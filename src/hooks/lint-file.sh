#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" ]]; then
  echo '{"continue": true}'
  exit 0
fi

if [[ ! -f "$file_path" ]]; then
  echo '{"continue": true}'
  exit 0
fi

find_project_root() {
  local dir="$1"
  local marker="$2"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/$marker" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

output_result() {
  local emoji="$1"
  local msg="$2"
  jq -n --arg msg "${emoji} ${msg}" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
}

lint_go() {
  if ! command -v golangci-lint &>/dev/null; then
    echo '{"continue": true, "systemMessage": "⚠️ golangci-lint not found in PATH. Install: https://golangci-lint.run/usage/install/"}'
    exit 0
  fi

  local file_dir
  file_dir=$(dirname "$file_path")
  local module_root
  module_root=$(find_project_root "$file_dir" "go.mod") || {
    echo '{"continue": true}'
    exit 0
  }

  local package_path
  if [[ "$file_dir" == "$module_root" ]]; then
    package_path="."
  else
    package_path="${file_dir#"$module_root"/}"
  fi

  local lint_output lint_exit
  lint_output=$(cd "$module_root" && golangci-lint run --new-from-rev=HEAD --timeout=25s "./${package_path}/" 2>&1) && lint_exit=0 || lint_exit=$?

  lint_output=$(echo "$lint_output" | grep -v '^level=warning' || true)

  if [[ $lint_exit -eq 0 ]]; then
    output_result "✅" "golangci-lint: no issues in ${package_path}"
  elif [[ $lint_exit -eq 1 ]]; then
    output_result "⚠️" "golangci-lint found issues in ${package_path}:
${lint_output}"
  else
    output_result "⚠️" "golangci-lint error (exit ${lint_exit}) on ${package_path}:
${lint_output}"
  fi
}

lint_python() {
  if ! command -v uv &>/dev/null; then
    echo '{"continue": true, "systemMessage": "⚠️ uv not found in PATH. Install: https://docs.astral.sh/uv/getting-started/installation/"}'
    exit 0
  fi

  local file_dir
  file_dir=$(dirname "$file_path")
  local project_root
  project_root=$(find_project_root "$file_dir" "pyproject.toml") || \
    project_root=$(find_project_root "$file_dir" "ruff.toml") || {
    echo '{"continue": true}'
    exit 0
  }

  local lint_output lint_exit
  lint_output=$(cd "$project_root" && uv run ruff check "$file_path" 2>&1) && lint_exit=0 || lint_exit=$?

  if [[ $lint_exit -eq 0 ]]; then
    local rel_path="${file_path#"$project_root"/}"
    output_result "✅" "ruff: no issues in ${rel_path}"
  elif [[ $lint_exit -eq 1 ]]; then
    output_result "⚠️" "ruff found issues:
${lint_output}"
  else
    output_result "⚠️" "ruff error (exit ${lint_exit}):
${lint_output}"
  fi
}

case "$file_path" in
  *.go) lint_go ;;
  *.py) lint_python ;;
  *)    echo '{"continue": true}' ;;
esac
