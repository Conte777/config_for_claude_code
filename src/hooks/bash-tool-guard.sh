#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks plain single cat/head/tail/grep/find/ls
# calls in favor of Read/Grep/Glob (leaner context + keeps the harness's
# "file has been read" tracking intact for Edit/Write). Anything compound —
# pipes, &&, ;, &, redirects, substitutions, multiline — passes through.
set -euo pipefail

is_simple_read() { # <command> -> 0 if it should be blocked
  local c="$1"
  case "$c" in
    *'|'*|*'&'*|*';'*|*'>'*|*'<'*|*'$('*|*'`'*|*$'\n'*) return 1 ;;
  esac
  # ponytail: tail -f follows a live file — Read can't; let it through
  [[ "$c" =~ ^[[:space:]]*tail[[:space:]].*-[A-Za-z]*f ]] && return 1
  [[ "$c" =~ ^[[:space:]]*(cat|head|tail|grep|egrep|fgrep|find|ls)([[:space:]]|$) ]]
}

# ponytail: self-check for the classifier (the non-trivial part).
# Run: BASH_GUARD_SELFTEST=1 bash src/hooks/bash-tool-guard.sh
if [[ "${BASH_GUARD_SELFTEST:-}" == 1 ]]; then
  blocked=(
    'cat README.md'
    '  head -20 src/main.go'
    'tail -n 50 app.log'
    'grep -rn TODO src'
    'find . -name "*.ts"'
    'ls -la src/hooks'
    'ls'
  )
  passed=(
    'cat x | grep y'
    'ls -la && pwd'
    'grep foo bar > out.txt'
    'find . -name "*.pyc" -exec rm {} \;'
    'tail -f app.log'
    'echo cat'
    'cat <<EOF
hi
EOF'
    'files=$(ls src)'
    ''
  )
  for c in "${blocked[@]}"; do
    is_simple_read "$c" || { echo "FAIL: should block: $c"; exit 1; }
  done
  for c in "${passed[@]}"; do
    is_simple_read "$c" && { echo "FAIL: should pass: $c"; exit 1; }
  done
  echo "bash-tool-guard selftest OK"; exit 0
fi

cmd=$(cat | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Raw git commit / branch creation -> route to mcp__git__ (server generates the msg).
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+(commit([[:space:]]|$)|checkout[[:space:]]+-b|switch[[:space:]]+-[cC]([[:space:]]|$)|branch[[:space:]]+[^-[:space:]])'; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Raw git commit / branch creation is blocked. Use mcp__git__commit / mcp__git__branch instead (the server generates the commit message — never pass your own)."}}'
  exit 0
fi

if is_simple_read "$cmd"; then
  first=$(printf '%s' "$cmd" | awk '{print $1}')
  case "$first" in
    cat|head|tail)   hint="Read (supports offset/limit)" ;;
    grep|egrep|fgrep) hint="Grep" ;;
    find|ls)         hint="Glob" ;;
  esac
  echo "Plain '$first' via Bash is blocked: use the $hint tool instead — it keeps context lean and marks files as read for Edit/Write." >&2
  exit 2
fi
exit 0
