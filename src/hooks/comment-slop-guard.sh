#!/usr/bin/env bash
set -euo pipefail
for c in jq; do command -v "$c" >/dev/null 2>&1 || exit 0; done

input=$(cat)

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
  echo '{"continue": true}'
  exit 0
fi

case "$file_path" in
  *.go|*.py|*.java|*.kt|*.scala|*.rs|*.rb|*.php|*.swift|*.sh|*.bash|\
  *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|\
  *.c|*.h|*.cc|*.cpp|*.hpp|*.cxx) ;;
  *)
    echo '{"continue": true}'
    exit 0
    ;;
esac

output_result() {
  local msg="$1"
  jq -n --arg msg "$msg" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
}

# Only judge lines this session added, so pre-existing comments stay untouched.
# Untracked files have no diff to compare against, so the whole file is the diff.
collect_added() {
  local repo_root
  repo_root=$(cd "$(dirname "$file_path")" && git rev-parse --show-toplevel 2>/dev/null) || repo_root=""

  if [[ -n "$repo_root" ]] && git -C "$repo_root" ls-files --error-unmatch "$file_path" >/dev/null 2>&1; then
    git -C "$repo_root" diff -U0 HEAD -- "$file_path" 2>/dev/null | grep '^+' | grep -v '^+++' || true
  else
    sed 's/^/+/' "$file_path"
  fi
}

added=$(collect_added)

if [[ -z "$added" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Directives, shebangs and TODO/FIXME markers are not prose — never flag them.
KEEP='^\+[[:space:]]*(#!|//[[:space:]]*(go:|nolint|lint:|@ts-|eslint|prettier|biome)|#[[:space:]]*(noqa|type:|pylint|mypy|ruff:|fmt:)|#region|(//|#|--|\*)[[:space:]]*(TODO|FIXME|HACK|XXX|SAFETY|NOTE:))'

candidates=$(printf '%s\n' "$added" | grep -Ev "$KEEP" || true)

# Restating the code: narration, structural signposting, signature echo.
NARRATION='^\+[[:space:]]*(//+|#+|\*|--)[[:space:]]*((Step[[:space:]]+[0-9])|((Now|Then|First|Next|Finally)[[:space:],]+(we|create|check|set|get|call|do))|(This[[:space:]]+(function|method|class|file|module|struct|type|interface|variable|constant|field|block)[[:space:]])|((Loop|Loops|Iterate|Iterates)[[:space:]]+(through|over))|((Set|Sets|Get|Gets|Return|Returns|Create|Creates|Initialize|Initializes|Check|Checks|Handle|Handles|Update|Updates|Add|Adds|Remove|Removes|Call|Calls|Define|Defines|Declare|Declares|Parse|Parses|Convert|Converts|Store|Stores)[[:space:]]+(the|a|an)[[:space:]]))'

# Banner separators: `// ---- Helpers ----`, `# ====`, `/* **** */`.
BANNER='^\+[[:space:]]*(//+|#+|\*|--)[[:space:]]*[-=*_#~]{4,}'

narration_hits=$(printf '%s\n' "$candidates" | grep -Ei "$NARRATION" | head -8 || true)
banner_hits=$(printf '%s\n' "$candidates" | grep -E "$BANNER" | head -4 || true)

# Five consecutive comment lines is a wall of prose, not an explanation.
long_block=$(printf '%s\n' "$candidates" | awk '
  /^\+[[:space:]]*(\/\/|#|\*|--)/ { n++; if (n >= 5) found = 1; next }
  { n = 0 }
  END { if (found) print "yes" }')

messages=()

if [[ -n "$narration_hits" ]]; then
  messages+=("⚠️ Comments that restate the code in $(basename "$file_path") — delete them or replace with the reason:
${narration_hits}")
fi

if [[ -n "$banner_hits" ]]; then
  messages+=("⚠️ Section-divider banners in $(basename "$file_path") — remove them:
${banner_hits}")
fi

if [[ -n "$long_block" ]]; then
  messages+=("⚠️ A comment block of 5+ lines was added to $(basename "$file_path"). Keep it to one line unless the file already uses long blocks.")
fi

if [[ ${#messages[@]} -eq 0 ]]; then
  echo '{"continue": true}'
  exit 0
fi

combined=$(printf '%s\n' "${messages[@]}")
combined="${combined}

Comments must state why, not what. Fix the lines above before continuing."

output_result "$combined"
