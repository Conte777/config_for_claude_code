#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" || "$file_path" != *.go ]]; then
  echo '{"continue": true}'
  exit 0
fi

if [[ ! -f "$file_path" ]]; then
  echo '{"continue": true}'
  exit 0
fi

if ! command -v golangci-lint &>/dev/null; then
  echo '{"continue": true, "systemMessage": "⚠️ golangci-lint not found in PATH. Install: https://golangci-lint.run/usage/install/"}'
  exit 0
fi

find_go_mod() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/go.mod" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

file_dir=$(dirname "$file_path")
module_root=$(find_go_mod "$file_dir") || {
  echo '{"continue": true}'
  exit 0
}

relative_path="${file_path#"$module_root"/}"

lint_output=$(cd "$module_root" && golangci-lint run --timeout=25s "./${relative_path}" 2>&1) && lint_exit=0 || lint_exit=$?

lint_output=$(echo "$lint_output" | grep -v '^level=warning' || true)

if [[ $lint_exit -eq 0 ]]; then
  jq -n --arg msg "✅ golangci-lint: no issues in ${relative_path}" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
elif [[ $lint_exit -eq 1 ]]; then
  full_msg="⚠️ golangci-lint found issues in ${relative_path}:
${lint_output}"
  jq -n --arg msg "$full_msg" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
else
  full_msg="⚠️ golangci-lint error (exit ${lint_exit}) on ${relative_path}:
${lint_output}"
  jq -n --arg msg "$full_msg" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
fi
