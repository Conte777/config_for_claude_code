#!/usr/bin/env bash
set -euo pipefail

SOURCE_BRANCH="$1"
TARGET_BRANCH="${2:-main}"
WORKTREE_PATH="/tmp/review-wt-$(echo "$SOURCE_BRANCH" | tr '/' '-')-$$"

git fetch origin "$SOURCE_BRANCH" "$TARGET_BRANCH" 2>/dev/null
git worktree add "$WORKTREE_PATH" "origin/$SOURCE_BRANCH" 2>/dev/null

echo "$WORKTREE_PATH"
