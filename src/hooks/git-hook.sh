#!/usr/bin/env bash
# Hot-path straz for UserPromptSubmit: fires on EVERY prompt, so stay cheap.
# Non-trigger prompts exit in ~5ms; only a real /commit|/branch
# hands off to git_gen.py (Python + Claude Agent SDK), which owns ALL logic.
set -euo pipefail
for c in jq uv; do command -v "$c" >/dev/null 2>&1 || exit 0; done
[[ "${CLAUDE_COMMIT_GEN:-}" == "1" ]] && exit 0   # insurance vs. SDK recursion
input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
[[ "$prompt" =~ ^[[:space:]]*/(commit|branch)([[:space:]]|$) ]] || exit 0
printf '%s' "$input" | exec uv run "$HOME/.claude/hooks/git_gen.py" hook
