#!/usr/bin/env bash
# PreToolUse for Edit|Write|MultiEdit: auto-approve writes whose target file
# lives OUTSIDE the current project (cross-repo config/migration edits). Only
# in acceptEdits mode — default (cautious) and plan (writes blocked) keep the
# normal prompt. In-project writes fall through to the usual acceptEdits flow.
set -euo pipefail

is_sensitive() { # <file> -> 0 if in a credential/config location that must keep the prompt
  local f="$1" h="${HOME:-/nonexistent}"
  # ponytail: literal-path match; symlink-through-innocent-name unhandled, add realpath if it ever bites
  case "$f" in
    "$h"/.ssh/*|"$h"/.aws/*|"$h"/.gnupg/*|"$h"/.kube/*|"$h"/.docker/*|"$h"/.config/*|"$h"/.claude/*|"$h"/.claude|"$h"/.claude.json*) return 0 ;;
    "$h"/.bashrc|"$h"/.zshrc|"$h"/.bash_profile|"$h"/.zprofile|"$h"/.profile|"$h"/.netrc|"$h"/.npmrc|"$h"/.pypirc) return 0 ;;
    /etc/*|/private/etc/*|/var/spool/cron/*|/var/at/*) return 0 ;;
  esac
  return 1
}

decide() { # <mode> <file> <cwd> -> prints allow JSON or nothing
  local mode="$1" file="$2" cwd="$3"
  # ponytail: only extend acceptEdits to cross-repo; default/plan keep normal flow
  [[ "$mode" == "acceptEdits" ]] || return 0
  [[ -n "$file" && -n "$cwd" ]] || return 0
  # ponytail: relative file_path (no leading /) treated as in-project -> normal flow
  # trailing-slash guard so /proj doesn't match /proj-other
  case "$file" in "$cwd"/*|"$cwd") return 0 ;; esac
  is_sensitive "$file" && return 0  # credential/config path -> keep manual prompt
  jq -n --arg f "$file" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:("Auto-approved edit outside project: "+$f)}}'
}

if [[ "${EDIT_APPROVE_SELFTEST:-}" == "1" ]]; then
  cwd=/a/proj
  [[ -n "$(decide acceptEdits /a/other/cfg.yaml "$cwd")" ]] || { echo "FAIL: outside should allow"; exit 1; }
  [[ -z "$(decide acceptEdits "$cwd/sub/x.go" "$cwd")" ]] || { echo "FAIL: inside should be silent"; exit 1; }
  [[ -z "$(decide acceptEdits "$cwd" "$cwd")" ]] || { echo "FAIL: cwd itself should be silent"; exit 1; }
  [[ -n "$(decide acceptEdits "${cwd}-other/x" "$cwd")" ]] || { echo "FAIL: sibling dir should allow"; exit 1; }
  [[ -z "$(decide default /a/other/cfg.yaml "$cwd")" ]] || { echo "FAIL: default should be silent"; exit 1; }
  [[ -z "$(decide plan /a/other/cfg.yaml "$cwd")" ]] || { echo "FAIL: plan should be silent"; exit 1; }
  [[ -z "$(decide acceptEdits "$HOME/.ssh/config" "$cwd")" ]] || { echo "FAIL: ~/.ssh should stay prompt"; exit 1; }
  [[ -z "$(decide acceptEdits "$HOME/.claude/settings.json" "$cwd")" ]] || { echo "FAIL: ~/.claude should stay prompt"; exit 1; }
  [[ -z "$(decide acceptEdits /etc/hosts "$cwd")" ]] || { echo "FAIL: /etc should stay prompt"; exit 1; }
  echo "edit-write-autoapprove selftest OK"; exit 0
fi

input=$(cat)
mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty')
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
decide "$mode" "$file" "$cwd"
exit 0
