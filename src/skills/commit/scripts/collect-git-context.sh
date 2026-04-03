#!/usr/bin/env bash
set -euo pipefail

# Read JSON input from stdin (hook protocol)
input=$(cat)

# Determine context: PreToolUse (tool_input.skill) or UserPromptSubmit (prompt)
skill_name=$(echo "$input" | jq -r '.tool_input.skill // empty')
user_prompt=$(echo "$input" | jq -r '.prompt // empty')

if [[ -n "$skill_name" ]]; then
  # PreToolUse: only run for commit and commit-msg skills
  if [[ "$skill_name" != "commit" && "$skill_name" != "commit-msg" ]]; then
    echo '{"continue": true}'
    exit 0
  fi
elif [[ -n "$user_prompt" ]]; then
  # UserPromptSubmit: only run if prompt contains /commit or /commit-msg
  if ! echo "$user_prompt" | grep -qiE '/(commit-msg|commit)\b'; then
    exit 0
  fi
else
  echo '{"continue": true}'
  exit 0
fi

# Get branch name (handle detached HEAD)
branch=$(git branch --show-current 2>/dev/null || true)
detached_head=false
if [[ -z "$branch" ]]; then
  branch=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  detached_head=true
fi

# Check if branch is protected
protected=false
protected_branches="main master develop stage staging"
branch_lower=$(echo "$branch" | tr '[:upper:]' '[:lower:]')
for pb in $protected_branches; do
  if [[ "$branch_lower" == "$pb" ]]; then
    protected=true
    break
  fi
done

# Extract ticket ID (CUS-XXXX pattern, case insensitive)
ticket_id=$(echo "$branch" | grep -ioE 'CUS-[0-9]+' | head -1 || true)
if [[ -n "$ticket_id" ]]; then
  ticket_id=$(echo "$ticket_id" | tr '[:lower:]' '[:upper:]')
fi

# Check staging area
staged_files=$(git diff --cached --name-only 2>/dev/null || true)
staging_empty=true
if [[ -n "$staged_files" ]]; then
  staging_empty=false
fi

# Get staged diff (only if staging is not empty)
staged_diff=""
if [[ "$staging_empty" == "false" ]]; then
  staged_diff=$(git diff --cached 2>/dev/null || true)
fi

# Build markdown output
output="## Git Context

**Branch:** \`$branch\`"

if [[ "$detached_head" == "true" ]]; then
  output+=" (DETACHED HEAD)"
fi

output+="
**Protected:** $protected
**Ticket ID:** ${ticket_id:-none}
**Staging empty:** $staging_empty"

if [[ "$staging_empty" == "false" ]]; then
  output+="

### Staged Files
\`\`\`
$staged_files
\`\`\`

### Staged Diff
\`\`\`diff
$staged_diff
\`\`\`"
fi

# Output format depends on hook type
if [[ -n "$skill_name" ]]; then
  # PreToolUse: JSON format (visible to both user and Claude)
  jq -n --arg msg "$output" \
    '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $msg}}'
else
  # UserPromptSubmit: plain text → additionalContext
  echo "$output"
fi
