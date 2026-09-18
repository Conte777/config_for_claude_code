#!/usr/bin/env bash
set -euo pipefail
command -v jq >/dev/null 2>&1 || exit 0

MAX_BLOCKS=3

input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')

if [[ -z "$session_id" ]]; then
  exit 0
fi

session_file="$HOME/.claude/.lint-sessions/$session_id"
blocks_file="$session_file.blocks"

if [[ ! -f "$session_file" ]]; then
  exit 0
fi

find_project_root() {
  local dir="$1" marker="$2"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/$marker" ]] && { echo "$dir"; return 0; }
    dir=$(dirname "$dir")
  done
  return 1
}

lint_go() {
  local file="$1" dir module_root relative target
  command -v golangci-lint >/dev/null 2>&1 || return 0
  dir=$(dirname "$file")
  module_root=$(find_project_root "$dir" "go.mod") || return 0
  if [[ "$dir" == "$module_root" ]]; then
    target="./"
  else
    target="./${dir#"$module_root"/}/"
  fi
  (cd "$module_root" && golangci-lint run --timeout=60s "$target" 2>/dev/null) \
    | grep -E '^[^[:space:]]+:[0-9]+:[0-9]+:' || true
}

lint_python() {
  local file="$1"
  if command -v ruff >/dev/null 2>&1; then
    ruff check --output-format concise "$file" 2>/dev/null | grep -E ':[0-9]+:[0-9]+: ' || true
  elif command -v uvx >/dev/null 2>&1; then
    uvx ruff check --output-format concise "$file" 2>/dev/null | grep -E ':[0-9]+:[0-9]+: ' || true
  fi
}

findings=""
seen_packages=""

while IFS= read -r file; do
  [[ -n "$file" && -f "$file" ]] || continue
  case "$file" in
    *.go)
      package_dir=$(dirname "$file")
      case "$seen_packages" in
        *"|$package_dir|"*) continue ;;
      esac
      seen_packages="$seen_packages|$package_dir|"
      out=$(lint_go "$file")
      ;;
    *.py) out=$(lint_python "$file") ;;
    *) continue ;;
  esac
  [[ -n "$out" ]] && findings="${findings}${out}"$'\n'
done < "$session_file"

findings=$(printf '%s' "$findings" | sed '/^$/d')

if [[ -z "$findings" ]]; then
  rm -f "$blocks_file"
  exit 0
fi

blocks=0
[[ -f "$blocks_file" ]] && blocks=$(cat "$blocks_file" 2>/dev/null || echo 0)

if [[ "$blocks" -ge "$MAX_BLOCKS" ]]; then
  jq -n --arg msg "⚠️ Lint still failing after $MAX_BLOCKS attempts — letting the turn end. Outstanding:
$findings" '{systemMessage: $msg}'
  rm -f "$blocks_file"
  exit 0
fi

echo $((blocks + 1)) > "$blocks_file"

jq -n --arg reason "The files you changed this session still fail the linter. Fix these before finishing:
$findings" '{decision: "block", reason: $reason}'
