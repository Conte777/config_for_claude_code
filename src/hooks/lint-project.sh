#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

workspace=$(echo "$input" | jq -r '.session.workspace // empty')

if [[ -z "$workspace" ]]; then
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

module_root=$(find_go_mod "$workspace") || {
  echo '{"continue": true}'
  exit 0
}

lint_output=$(cd "$module_root" && golangci-lint run --timeout=90s ./... 2>&1) && lint_exit=0 || lint_exit=$?

lint_output=$(echo "$lint_output" | grep -v '^level=warning' || true)

if [[ $lint_exit -eq 0 ]]; then
  jq -n --arg msg "✅ golangci-lint: no issues in project" \
    '{continue: true, systemMessage: $msg}'
elif [[ $lint_exit -eq 1 ]]; then
  full_msg="⚠️ golangci-lint found issues in project:
${lint_output}"
  jq -n --arg msg "$full_msg" \
    '{continue: true, systemMessage: $msg}'
else
  full_msg="⚠️ golangci-lint error (exit ${lint_exit}):
${lint_output}"
  jq -n --arg msg "$full_msg" \
    '{continue: true, systemMessage: $msg}'
fi
