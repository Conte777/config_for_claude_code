#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
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
  local msg="$1"
  jq -n --arg msg "$msg" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
}

messages=()

# --- Go ---

format_go() {
  if ! command -v gofmt &>/dev/null; then
    return
  fi

  local fmt_output fmt_exit
  fmt_output=$(gofmt -l "$file_path" 2>&1) && fmt_exit=0 || fmt_exit=$?

  if [[ $fmt_exit -ne 0 ]]; then
    messages+=("⚠️ gofmt error: ${fmt_output}")
    return
  fi

  if [[ -n "$fmt_output" ]]; then
    gofmt -w "$file_path" 2>/dev/null
    messages+=("✅ gofmt: formatted $(basename "$file_path")")
  fi
}

lint_go() {
  if ! command -v golangci-lint &>/dev/null; then
    messages+=("⚠️ golangci-lint not found in PATH. Install: https://golangci-lint.run/usage/install/")
    return
  fi

  local file_dir module_root
  file_dir=$(dirname "$file_path")
  module_root=$(find_project_root "$file_dir" "go.mod") || return

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
    messages+=("✅ golangci-lint: no issues in ${package_path}")
  elif [[ $lint_exit -eq 1 ]]; then
    messages+=("⚠️ golangci-lint found issues in ${package_path}:
${lint_output}")
  else
    messages+=("⚠️ golangci-lint error (exit ${lint_exit}) on ${package_path}:
${lint_output}")
  fi
}

# --- Python ---

find_python_project_root() {
  local file_dir="$1"
  local root=""
  root=$(find_project_root "$file_dir" "pyproject.toml") || \
    root=$(find_project_root "$file_dir" "ruff.toml") || return 1
  echo "$root"
}

format_python() {
  if ! command -v uv &>/dev/null; then
    return
  fi

  local file_dir project_root
  file_dir=$(dirname "$file_path")
  project_root=$(find_python_project_root "$file_dir") || return

  local fmt_output fmt_exit
  fmt_output=$(cd "$project_root" && uv run ruff format "$file_path" 2>&1) && fmt_exit=0 || fmt_exit=$?

  if [[ $fmt_exit -ne 0 ]]; then
    messages+=("⚠️ ruff format error: ${fmt_output}")
    return
  fi

  if echo "$fmt_output" | grep -q "1 file reformatted"; then
    messages+=("✅ ruff format: formatted $(basename "$file_path")")
  fi
}

lint_python() {
  if ! command -v uv &>/dev/null; then
    messages+=("⚠️ uv not found in PATH. Install: https://docs.astral.sh/uv/getting-started/installation/")
    return
  fi

  local file_dir project_root
  file_dir=$(dirname "$file_path")
  project_root=$(find_python_project_root "$file_dir") || return

  local lint_output lint_exit
  lint_output=$(cd "$project_root" && uv run ruff check "$file_path" 2>&1) && lint_exit=0 || lint_exit=$?

  if [[ $lint_exit -eq 0 ]]; then
    local rel_path="${file_path#"$project_root"/}"
    messages+=("✅ ruff check: no issues in ${rel_path}")
  elif [[ $lint_exit -eq 1 ]]; then
    messages+=("⚠️ ruff found issues:
${lint_output}")
  else
    messages+=("⚠️ ruff error (exit ${lint_exit}):
${lint_output}")
  fi
}

# --- Java ---

format_java() {
  if ! command -v google-java-format &>/dev/null; then
    return
  fi

  local fmt_output fmt_exit
  fmt_output=$(google-java-format -i "$file_path" 2>&1) && fmt_exit=0 || fmt_exit=$?

  if [[ $fmt_exit -ne 0 ]]; then
    messages+=("⚠️ google-java-format error: ${fmt_output}")
  else
    messages+=("✅ google-java-format: formatted $(basename "$file_path")")
  fi
}

# --- Main ---

case "$file_path" in
  *.go)
    format_go
    lint_go
    ;;
  *.py)
    format_python
    lint_python
    ;;
  *.java)
    format_java
    ;;
  *)
    echo '{"continue": true}'
    exit 0
    ;;
esac

if [[ ${#messages[@]} -eq 0 ]]; then
  echo '{"continue": true}'
  exit 0
fi

combined=$(printf '%s\n' "${messages[@]}")
output_result "$combined"
