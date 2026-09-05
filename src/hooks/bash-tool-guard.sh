#!/usr/bin/env bash
# PreToolUse guard for Bash: routes raw git commit/branch creation to mcp__git__
# (the server generates the commit message).
set -euo pipefail
for c in jq; do command -v "$c" >/dev/null 2>&1 || exit 0; done

cmd=$(cat | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+(commit([[:space:]]|$)|checkout[[:space:]]+-b|switch[[:space:]]+-[cC]([[:space:]]|$)|branch[[:space:]]+[^-[:space:]])'; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Raw git commit / branch creation is blocked. Use mcp__git__commit / mcp__git__branch instead (the server generates the commit message — never pass your own)."}}'
  exit 0
fi

exit 0
