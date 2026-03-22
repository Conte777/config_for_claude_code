#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
user_prompt=$(echo "$input" | jq -r '.user_prompt // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

ticket_id=$(echo "$user_prompt" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)

if [[ -z "$ticket_id" ]]; then
  exit 0
fi

missing_vars=()
[[ -z "${JIRA_URL:-}" ]] && missing_vars+=("JIRA_URL")
[[ -z "${JIRA_PERSONAL_TOKEN:-}" ]] && missing_vars+=("JIRA_PERSONAL_TOKEN")
[[ -z "${GITLAB_API_URL:-}" ]] && missing_vars+=("GITLAB_API_URL")
[[ -z "${GITLAB_PERSONAL_ACCESS_TOKEN:-}" ]] && missing_vars+=("GITLAB_PERSONAL_ACCESS_TOKEN")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo "Error: missing env vars: ${missing_vars[*]}" >&2
  exit 2
fi

jira_headers=(-H "Authorization: Bearer $JIRA_PERSONAL_TOKEN" -H "Content-Type: application/json")

issue_json=$(curl -sf "${jira_headers[@]}" \
  "$JIRA_URL/rest/api/2/issue/$ticket_id?fields=summary,description,comment" 2>/dev/null || true)

if [[ -z "$issue_json" ]]; then
  echo "Error: failed to fetch Jira issue $ticket_id" >&2
  exit 2
fi

title=$(echo "$issue_json" | jq -r '.fields.summary // "N/A"')
description=$(echo "$issue_json" | jq -r '.fields.description // "N/A"')

comments_md=""
comment_count=$(echo "$issue_json" | jq '.fields.comment.comments | length')
if [[ "$comment_count" -gt 0 ]]; then
  comments_md=$(echo "$issue_json" | jq -r '
    .fields.comment.comments[] |
    "\(.id). [\(.author.displayName)] \(.body)"
  ')
fi

remote_links_json=$(curl -sf "${jira_headers[@]}" \
  "$JIRA_URL/rest/api/2/issue/$ticket_id/remotelink" 2>/dev/null || true)

mr_urls=()
if [[ -n "$remote_links_json" ]]; then
  while IFS= read -r url; do
    [[ -n "$url" ]] && mr_urls+=("$url")
  done < <(echo "$remote_links_json" | jq -r '.[].object.url // empty' | grep 'merge_requests')
fi

output="## Jira: $ticket_id
**Title:** $title
**Description:** $description"

if [[ -n "$comments_md" ]]; then
  output+="

### Comments
$comments_md"
fi

output+="

## Merge Requests
"

if [[ ${#mr_urls[@]} -eq 0 ]]; then
  output+="
No merge requests found in Jira remote links."
  echo "$output"
  exit 0
fi

gitlab_headers=(-H "PRIVATE-TOKEN: $GITLAB_PERSONAL_ACCESS_TOKEN")

for mr_url in "${mr_urls[@]}"; do
  project_path=$(echo "$mr_url" | sed -E 's|.*/(/[^/]+/[^/]+)/-/merge_requests/.*|\1|; s|^/||' || true)
  if [[ -z "$project_path" || "$project_path" == "$mr_url" ]]; then
    project_path=$(echo "$mr_url" | sed -E 's|https?://[^/]+/||; s|/-/merge_requests/.*||' || true)
  fi
  mr_iid=$(echo "$mr_url" | grep -oE 'merge_requests/[0-9]+' | grep -oE '[0-9]+' || true)

  if [[ -z "$project_path" || -z "$mr_iid" ]]; then
    output+="
### MR (failed to parse URL: $mr_url)"
    continue
  fi

  encoded_path=$(echo "$project_path" | jq -Rr @uri)

  mr_info=$(curl -sf "${gitlab_headers[@]}" \
    "$GITLAB_API_URL/api/v4/projects/$encoded_path/merge_requests/$mr_iid" 2>/dev/null || true)

  if [[ -z "$mr_info" ]]; then
    output+="
### MR !$mr_iid (failed to fetch from GitLab)
- **URL:** $mr_url"
    continue
  fi

  mr_title=$(echo "$mr_info" | jq -r '.title // "N/A"')
  source_branch=$(echo "$mr_info" | jq -r '.source_branch // "N/A"')
  target_branch=$(echo "$mr_info" | jq -r '.target_branch // "N/A"')

  mr_changes=$(curl -sf "${gitlab_headers[@]}" \
    "$GITLAB_API_URL/api/v4/projects/$encoded_path/merge_requests/$mr_iid/changes" 2>/dev/null || true)

  diff_file=""
  files_changed=0
  if [[ -n "$mr_changes" ]]; then
    files_changed=$(echo "$mr_changes" | jq '.changes | length')
    sanitized_title=$(echo "$mr_title" | tr ' /:' '---' | tr -cd 'a-zA-Z0-9-_')
    diff_file="/tmp/${sanitized_title}-${session_id}.txt"

    echo "$mr_changes" | jq -r '
      .changes[] |
      "--- a/\(.old_path)\n+++ b/\(.new_path)\n\(.diff)"
    ' > "$diff_file"
  fi

  output+="
### MR !$mr_iid: $mr_title
- **Branch:** $source_branch → $target_branch
- **URL:** $mr_url"

  if [[ -n "$diff_file" ]]; then
    output+="
- **Diff file:** $diff_file"
  fi

  output+="
- **Files changed:** $files_changed
"
done

echo "$output"
