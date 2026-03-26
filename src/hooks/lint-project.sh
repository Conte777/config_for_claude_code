#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

workspace=$(echo "$input" | jq -r '
  .session.workspace // .session.cwd // .cwd // empty
')

if [[ -z "$workspace" ]]; then
  workspace="$PWD"
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

messages=()

# --- Go linting ---
go_module_root=$(find_project_root "$workspace" "go.mod") || true

if [[ -n "$go_module_root" ]]; then
  if ! command -v golangci-lint &>/dev/null; then
    messages+=("⚠️ golangci-lint not found in PATH. Install: https://golangci-lint.run/usage/install/")
  else
    go_output=$(cd "$go_module_root" && golangci-lint run --timeout=120s ./... 2>&1) && go_exit=0 || go_exit=$?
    go_output=$(echo "$go_output" | grep -v '^level=warning' || true)

    if [[ $go_exit -eq 0 ]]; then
      messages+=("✅ golangci-lint: no issues in project")
    elif [[ $go_exit -eq 1 ]]; then
      messages+=("⚠️ golangci-lint found issues in project:
${go_output}")
    else
      messages+=("⚠️ golangci-lint error (exit ${go_exit}):
${go_output}")
    fi
  fi
fi

# --- Python linting ---
py_project_root=$(find_project_root "$workspace" "pyproject.toml") || \
  py_project_root=$(find_project_root "$workspace" "ruff.toml") || true

if [[ -n "${py_project_root:-}" ]]; then
  if ! command -v uv &>/dev/null; then
    messages+=("⚠️ uv not found in PATH. Install: https://docs.astral.sh/uv/getting-started/installation/")
  else
    py_output=$(cd "$py_project_root" && uv run ruff check . 2>&1) && py_exit=0 || py_exit=$?

    if [[ $py_exit -eq 0 ]]; then
      messages+=("✅ ruff: no issues in project")
    elif [[ $py_exit -eq 1 ]]; then
      messages+=("⚠️ ruff found issues in project:
${py_output}")
    else
      messages+=("⚠️ ruff error (exit ${py_exit}):
${py_output}")
    fi
  fi
fi

# --- Output ---
if [[ ${#messages[@]} -eq 0 ]]; then
  echo '{"continue": true}'
else
  combined=$(printf '%s\n\n' "${messages[@]}")
  jq -n --arg msg "$combined" \
    '{continue: true, systemMessage: $msg}'
fi
