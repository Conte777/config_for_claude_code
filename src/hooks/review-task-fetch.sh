#!/usr/bin/env bash
# UserPromptSubmit hook for `/review-task <KEY>` — deterministic, no LLM.
# Fetches the task's MRs from Jira gitplugin, pulls each MR's GitLab diff,
# shallow-clones the source branch, writes a manifest, and prints the WORK dir
# to stdout (-> session context) so the /review-task command can hand it to the
# review Workflow. Any other prompt: exit 0 immediately (pass-through).
set -euo pipefail

# Extract the Jira KEY from a /review-task prompt — accepts a bare key
# (/review-task CUS-1776) or a task URL (.../browse/CUS-1776). Prints the key, or
# nothing if the prompt isn't a /review-task trigger.
extract_key() { # <prompt>
  [[ "$1" =~ ^/review-task([[:space:]]|$) ]] || return 0
  printf '%s' "$1" | grep -oE '[A-Z]+-[0-9]+' | tail -1
}

# Local workspace where per-repo (gitignored) CLAUDE.md files live. We copy the
# leaf repo's CLAUDE.md into its clone so the lenses see project conventions.
LOCAL_ROOT="${REVIEW_TASK_LOCAL_ROOT:-$HOME/Work/friday-releases}"

# Map a GitLab path (e.g. Fri_releases/cryptoprocessing/backend-core/order-service)
# to a local CLAUDE.md. Prints the abs path, or nothing if not found/ambiguous.
find_local_claudemd() { # <gitlab_path>
  local gl="$1"
  # direct map: drop the top GitLab group, the rest mirrors the on-disk layout
  local cand="$LOCAL_ROOT/${gl#*/}"
  [[ -f "$cand/CLAUDE.md" ]] && { printf '%s\n' "$cand/CLAUDE.md"; return; }
  # fallback by basename: accept only a single unambiguous hit (0 or >1 -> nothing)
  local hits
  hits=$(find "$LOCAL_ROOT" -maxdepth 5 -type d -name "$(basename "$gl")" 2>/dev/null \
    | while read -r d; do [[ -f "$d/CLAUDE.md" ]] && printf '%s\n' "$d/CLAUDE.md"; done)
  [[ $(printf '%s' "$hits" | grep -c .) -eq 1 ]] && printf '%s\n' "$hits"
}

# ponytail: self-check for the matching logic (non-trivial: direct map + fallback).
# Run: REVIEW_TASK_SELFTEST=1 bash src/hooks/review-task-fetch.sh
if [[ "${REVIEW_TASK_SELFTEST:-}" == 1 ]]; then
  [[ "$(extract_key '/review-task CUS-1776')" == CUS-1776 ]] || { echo "FAIL: bare key"; exit 1; }
  [[ "$(extract_key '/review-task https://jira.cp.itcrew.info/browse/CUS-1776')" == CUS-1776 ]] || { echo "FAIL: task url"; exit 1; }
  [[ -z "$(extract_key '/something-else CUS-1776')" ]] || { echo "FAIL: non-trigger"; exit 1; }
  tmp=$(mktemp -d); LOCAL_ROOT="$tmp"
  mkdir -p "$tmp/processing/api_go" "$tmp/cryptoprocessing/backend-core/order-service" \
           "$tmp/cryptoprocessing/shared/logger" "$tmp/dup-a/svc" "$tmp/dup-b/svc"
  : > "$tmp/processing/api_go/CLAUDE.md"
  : > "$tmp/cryptoprocessing/backend-core/order-service/CLAUDE.md"
  : > "$tmp/dup-a/svc/CLAUDE.md"; : > "$tmp/dup-b/svc/CLAUDE.md"
  [[ "$(find_local_claudemd Fri_releases/processing/api_go)" == "$tmp/processing/api_go/CLAUDE.md" ]] \
    || { echo "FAIL: direct map"; exit 1; }
  [[ "$(find_local_claudemd Fri_releases/cryptoprocessing/backend-core/order-service)" == "$tmp/cryptoprocessing/backend-core/order-service/CLAUDE.md" ]] \
    || { echo "FAIL: nested direct map"; exit 1; }
  [[ -z "$(find_local_claudemd Fri_releases/cryptoprocessing/shared/logger)" ]] \
    || { echo "FAIL: missing CLAUDE.md should be empty"; exit 1; }
  [[ "$(find_local_claudemd other/wrong/order-service)" == "$tmp/cryptoprocessing/backend-core/order-service/CLAUDE.md" ]] \
    || { echo "FAIL: basename fallback"; exit 1; }
  [[ -z "$(find_local_claudemd grp/x/svc)" ]] \
    || { echo "FAIL: ambiguous basename should be empty"; exit 1; }
  rm -rf "$tmp"; echo "review-task selftest OK"; exit 0
fi

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
# trigger only on the slash command; KEY from a bare arg or a task URL
KEY=$(extract_key "$prompt")
[[ -n "$KEY" ]] || exit 0

GITLAB_HOST="${REVIEW_TASK_GITLAB_HOST:-git.itcrew.info}"
# Jira host stays out of this (version-controlled) file: env override, else the
# ~/.netrc machine whose name contains "jira". netrc is the single source.
JIRA_HOST="${REVIEW_TASK_JIRA_HOST:-}"
[[ -z "$JIRA_HOST" ]] && JIRA_HOST=$(awk '$1=="machine" && $2 ~ /jira/ {print $2; exit}' "$HOME/.netrc" 2>/dev/null || true)

# password for a host from ~/.netrc; handles single-line and multi-line entries
netrc_token() { # <host>
  [[ -f "$HOME/.netrc" ]] || return 0
  awk -v host="$1" '
    { for (i=1;i<=NF;i++){
        if ($i=="machine"){ inhost=($(i+1)==host); i++ }
        else if (inhost && $i=="password"){ print $(i+1); exit } } }' "$HOME/.netrc"
}

JIRA_TOKEN=$(netrc_token "$JIRA_HOST")
GL_TOKEN=$(netrc_token "$GITLAB_HOST")
if [[ -z "$JIRA_HOST" || -z "$JIRA_TOKEN" || -z "$GL_TOKEN" ]]; then
  echo "review-task: no credentials in ~/.netrc (jira machine: ${JIRA_HOST:-not found}, gitlab: $GITLAB_HOST). Add 'machine <host> login <user> password <token>' (chmod 600). Do not run the workflow."
  exit 0
fi

# 1. Jira gitplugin -> MR list
gp=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
  "https://$JIRA_HOST/rest/gitplugin/1.0/issuegitdetails/issue/$KEY/pullRequest" 2>/dev/null || true)
if [[ -z "$gp" ]]; then
  echo "review-task: Jira gitplugin did not respond for $KEY (auth/scope/host?). Do not run the workflow."
  exit 0
fi

# gitplugin shape: {mergeRequests:{items:[...]}, pullRequests:{items:[...]}};
# item.url is the GitLab MR web url, .compareBranch=source, .baseBranch=target.
mrs=$(printf '%s' "$gp" | jq -c '
  [ (.mergeRequests.items // []), (.pullRequests.items // []) | .[]
    | {url:(.url//""), source:(.compareBranch//""), target:(.baseBranch//""), title:(.title//"")} ]
  | map(select(.url | test("/-/merge_requests/[0-9]+")))' 2>/dev/null || echo '[]')

n=$(printf '%s' "$mrs" | jq 'length')
if [[ "$n" -eq 0 ]]; then
  echo "review-task: no MRs found for $KEY in Jira gitplugin. Do not run the workflow."
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/review-task-$KEY.XXXXXX")
mkdir -p "$WORK/repos" "$WORK/diffs"
export GIT_TERMINAL_PROMPT=0  # never block on a credential prompt

manifest='[]'
i=0
cmd_copied=0; no_cmd=0; failed_clones=""  # rolled up into one summary line at the end
while [[ $i -lt $n ]]; do
  url=$(printf '%s' "$mrs" | jq -r ".[$i].url")
  src_gp=$(printf '%s' "$mrs" | jq -r ".[$i].source")
  i=$((i+1))

  path=$(printf '%s' "$url" | sed -E 's|https?://[^/]+/||; s|/-/merge_requests/.*||')
  iid=$(printf '%s' "$url" | grep -oE 'merge_requests/[0-9]+' | grep -oE '[0-9]+' || true)
  [[ -z "$path" || -z "$iid" ]] && { echo "review-task: skipping MR (could not parse url: $url)"; continue; }
  enc=$(printf '%s' "$path" | jq -Rr @uri)
  slug="$(printf '%s' "$path" | tr '/' '_')__mr$iid"

  changes=$(curl -fsS -H "PRIVATE-TOKEN: $GL_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$enc/merge_requests/$iid/changes" 2>/dev/null || true)
  [[ -z "$changes" ]] && { echo "review-task: skipping $path!$iid (GitLab /changes did not respond)"; continue; }

  src=$(printf '%s' "$changes" | jq -r '.source_branch // empty'); [[ -z "$src" ]] && src="$src_gp"
  diff_path="$WORK/diffs/$slug.diff"
  printf '%s' "$changes" | jq -r '.changes[] | "--- a/\(.old_path)\n+++ b/\(.new_path)\n\(.diff)"' > "$diff_path"

  clone_path="$WORK/repos/$slug"
  cmd_present=false
  if git clone --depth 1 --branch "$src" "https://$GITLAB_HOST/$path.git" "$clone_path" >/dev/null 2>&1; then
    cmd=$(find_local_claudemd "$path")
    if [[ -n "$cmd" ]]; then
      cp "$cmd" "$clone_path/CLAUDE.md"; cmd_present=true; cmd_copied=$((cmd_copied+1))
    else
      no_cmd=$((no_cmd+1))
    fi
  else
    failed_clones+="${failed_clones:+, }$path@$src"
    clone_path=""
  fi

  manifest=$(printf '%s' "$manifest" | jq -c \
    --arg repo "$path" --arg iid "$iid" --arg cp "$clone_path" \
    --arg dp "$diff_path" --arg sb "$src" --arg url "$url" --argjson cmd "$cmd_present" \
    '. + [{repo:$repo, iid:$iid, clonePath:$cp, diffPath:$dp, source_branch:$sb, web_url:$url, claudeMd:$cmd}]')
done

printf '%s' "$manifest" > "$WORK/manifest.json"
got=$(printf '%s' "$manifest" | jq 'length')
if [[ "$got" -eq 0 ]]; then
  echo "review-task: could not assemble any MR for $KEY. Do not run the workflow."
  exit 0
fi

# one rolled-up diagnostics line (instead of one per MR) so the WORK= line below
# stays visible and isn't lost to context compaction
diag="review-task: CLAUDE.md injected into $cmd_copied repo(s)"
[[ $no_cmd -gt 0 ]] && diag+=", without local conventions: $no_cmd"
[[ -n "$failed_clones" ]] && diag+="; clones failed: $failed_clones"
echo "$diag."

# fallback delivery: fixed file in case stdout->context is unreliable
echo "$WORK" > "$HOME/.claude/.review-task-last" 2>/dev/null || true
echo "review-task: MRs for $KEY ready ($got total). WORK=$WORK. Run the review-task workflow with this path."
exit 0
