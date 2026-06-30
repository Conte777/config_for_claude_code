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

# Extract direct GitLab MR URLs from the prompt (.../-/merge_requests/<iid>).
# Prints one URL per line, or nothing. ponytail: all MRs assumed on $GITLAB_HOST.
extract_mr_urls() { # <prompt>
  printf '%s' "$1" | grep -oE 'https?://[^[:space:]]+/-/merge_requests/[0-9]+' || true
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

# Jira issue JSON (stdin) -> markdown for the completeness agent: title, description,
# then a comments section. Server/DC api/2 shape: fields.{summary,description,comment.comments[]}.
issue_to_md() {
  jq -r '
    "# \(.key // ""): \(.fields.summary // "")",
    "",
    (.fields.description // ""),
    ( (.fields.comment.comments // []) as $c
      | if ($c | length) > 0
        then ("", "## Комментарии", "",
              ($c[] | "**\(.author.displayName // .author.name // "")** (\((.created // "")[:10])):",
                      (.body // ""), ""))
        else empty end )'
}

# heavy = n>=3 MR -> "-heavy" суффикс в имя WORK-папки, workflow читает его оттуда
# и гоняет читающих код агентов на 1M-окне. ponytail: n>=3 как прокси «агент
# прочитает много» (клоны по импортам); байты не тянем — известны только после цикла, YAGNI.
heavy_suffix() { [[ "$1" -ge 3 ]] && printf -- '-heavy'; }

# ponytail: self-check for the matching logic (non-trivial: direct map + fallback).
# Run: REVIEW_TASK_SELFTEST=1 bash src/hooks/review-task-fetch.sh
if [[ "${REVIEW_TASK_SELFTEST:-}" == 1 ]]; then
  [[ "$(extract_key '/review-task CUS-1776')" == CUS-1776 ]] || { echo "FAIL: bare key"; exit 1; }
  [[ "$(extract_key '/review-task https://jira.cp.itcrew.info/browse/CUS-1776')" == CUS-1776 ]] || { echo "FAIL: task url"; exit 1; }
  [[ -z "$(extract_key '/something-else CUS-1776')" ]] || { echo "FAIL: non-trigger"; exit 1; }
  one='https://git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/protos/safe-query-proto/-/merge_requests/7'
  [[ "$(extract_mr_urls "/review-task $one")" == "$one" ]] || { echo "FAIL: single mr url"; exit 1; }
  two=$(extract_mr_urls "/review-task $one https://git.itcrew.info/a/b/-/merge_requests/12")
  [[ "$two" == "$one"$'\n'"https://git.itcrew.info/a/b/-/merge_requests/12" ]] || { echo "FAIL: multi mr url"; exit 1; }
  [[ -z "$(extract_mr_urls '/review-task CUS-1776')" ]] || { echo "FAIL: key is not an mr url"; exit 1; }
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
  # discussions filter: system note dropped, inline note keeps file/line.
  disc_filter() { jq -c '[ .[].notes[]? | select(.system == false)
      | { author:(.author.username // ""), body:(.body // ""),
          file:(.position.new_path // .position.old_path // ""),
          line:(.position.new_line // .position.old_line // null),
          resolvable:(.resolvable // false), resolved:(.resolved // false) } ]'; }
  sample='[{"notes":[{"system":true,"body":"added 1 commit","author":{"username":"sys"}},
    {"system":false,"body":"nil deref here","author":{"username":"alice"},
     "position":{"new_path":"a/b.go","new_line":42},"resolvable":true,"resolved":false}]}]'
  out=$(printf '%s' "$sample" | disc_filter)
  [[ "$(printf '%s' "$out" | jq 'length')" == 1 ]] || { echo "FAIL: system note not dropped"; exit 1; }
  [[ "$(printf '%s' "$out" | jq -r '.[0].file')" == a/b.go ]] || { echo "FAIL: inline file lost"; exit 1; }
  [[ "$(printf '%s' "$out" | jq -r '.[0].line')" == 42 ]] || { echo "FAIL: inline line lost"; exit 1; }
  # issue_to_md: summary + comment body land in the rendered task.md.
  issue='{"key":"CUS-1","fields":{"summary":"Add retry","description":"Body",
    "comment":{"comments":[{"author":{"displayName":"Bob"},"created":"2024-05-01T10:00:00.000+0000",
      "body":"also handle timeout"}]}}}'
  md=$(printf '%s' "$issue" | issue_to_md)
  printf '%s' "$md" | grep -q 'CUS-1: Add retry' || { echo "FAIL: issue_to_md summary"; exit 1; }
  printf '%s' "$md" | grep -q 'also handle timeout' || { echo "FAIL: issue_to_md comment"; exit 1; }
  # .changes guard: an error payload has no .changes (skip), a real one does (keep).
  echo '{"message":"404"}' | jq -e '.changes' >/dev/null 2>&1 && { echo "FAIL: error payload must lack .changes"; exit 1; }
  echo '{"changes":[]}'   | jq -e '.changes' >/dev/null 2>&1 || { echo "FAIL: real payload must have .changes"; exit 1; }
  # heavy suffix: cross-file contract with the workflow (-heavy in dir name <-> 1M model).
  [[ "$(heavy_suffix 3)" == "-heavy" ]] || { echo "FAIL: heavy_suffix 3"; exit 1; }
  [[ -z "$(heavy_suffix 2)" ]] || { echo "FAIL: heavy_suffix 2"; exit 1; }
  rm -rf "$tmp"; echo "review-task selftest OK"; exit 0
fi

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
# trigger only on the slash command (pass-through for anything else)
[[ "$prompt" =~ ^/review-task([[:space:]]|$) ]] || exit 0

# Two input modes: direct GitLab MR URLs (priority) or a Jira key. URLs win.
KEY=""
MR_URLS=$(extract_mr_urls "$prompt")
if [[ -n "$MR_URLS" ]]; then
  MODE=mrs
else
  KEY=$(extract_key "$prompt") || true  # grep|tail returns 1 on no-key; -z handles it below
  [[ -n "$KEY" ]] || { echo "review-task: no Jira key or GitLab MR URL in the prompt. Do not run the workflow."; exit 0; }
  MODE=jira
fi

# Clear the stale-WORK fallback up front. If this run dies mid-flight (a jq/curl
# fault under `set -e`) before writing a fresh WORK, the command reads an empty
# file and honestly reports "fetch didn't run" instead of reviewing a PREVIOUS
# task's leftover WORK dir. Only a fully-completed run repopulates it (bottom).
: > "$HOME/.claude/.review-task-last" 2>/dev/null || true

GITLAB_HOST="${REVIEW_TASK_GITLAB_HOST:-git.itcrew.info}"

# password for a host from ~/.netrc; handles single-line and multi-line entries
netrc_token() { # <host>
  [[ -f "$HOME/.netrc" ]] || return 0
  awk -v host="$1" '
    { for (i=1;i<=NF;i++){
        if ($i=="machine"){ inhost=($(i+1)==host); i++ }
        else if (inhost && $i=="password"){ print $(i+1); exit } } }' "$HOME/.netrc"
}

# GitLab token is needed in both modes (clone + /changes API).
GL_TOKEN=$(netrc_token "$GITLAB_HOST")
[[ -z "$GL_TOKEN" ]] && { echo "review-task: no GitLab credentials in ~/.netrc (machine $GITLAB_HOST). Add 'machine $GITLAB_HOST login <user> password <token>' (chmod 600). Do not run the workflow."; exit 0; }

if [[ "$MODE" == jira ]]; then
  # Jira host stays out of this (version-controlled) file: env override, else the
  # ~/.netrc machine whose name contains "jira". netrc is the single source.
  JIRA_HOST="${REVIEW_TASK_JIRA_HOST:-}"
  [[ -z "$JIRA_HOST" ]] && JIRA_HOST=$(awk '$1=="machine" && $2 ~ /jira/ {print $2; exit}' "$HOME/.netrc" 2>/dev/null || true)
  JIRA_TOKEN=$(netrc_token "$JIRA_HOST")
  if [[ -z "$JIRA_HOST" || -z "$JIRA_TOKEN" ]]; then
    echo "review-task: no Jira credentials in ~/.netrc (jira machine: ${JIRA_HOST:-not found}). Add 'machine <host> login <user> password <token>' (chmod 600). Do not run the workflow."
    exit 0
  fi

  # 1. Jira gitplugin -> MR list
  gp=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "https://$JIRA_HOST/rest/gitplugin/1.0/issuegitdetails/issue/$KEY/pullRequest" 2>/dev/null || true)
  if [[ -z "$gp" ]]; then
    echo "review-task: Jira gitplugin did not respond for $KEY (auth/scope/host?). Do not run the workflow."
    exit 0
  fi

  # task text (summary+description+comments) -> task.md for the completeness agent.
  ISSUE_JSON=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "https://$JIRA_HOST/rest/api/2/issue/$KEY?fields=summary,description,comment" 2>/dev/null || true)

  # gitplugin shape: {mergeRequests:{items:[...]}, pullRequests:{items:[...]}};
  # item.url is the GitLab MR web url, .compareBranch=source, .baseBranch=target.
  mrs=$(printf '%s' "$gp" | jq -c '
    [ (.mergeRequests.items // []), (.pullRequests.items // []) | .[]
      | {url:(.url//""), source:(.compareBranch//""), target:(.baseBranch//""), title:(.title//"")} ]
    | map(select(.url | test("/-/merge_requests/[0-9]+")))' 2>/dev/null || echo '[]')
else
  # mrs mode: build the list straight from the prompt URLs. source/target stay
  # empty — GitLab /changes returns source_branch, and the loop already falls
  # back to the API answer when src_gp is empty.
  mrs=$(printf '%s\n' "$MR_URLS" | jq -R -s -c 'split("\n") | map(select(length>0)) | map({url:., source:"", target:"", title:""})')
fi

n=$(printf '%s' "$mrs" | jq 'length')
if [[ "$n" -eq 0 ]]; then
  echo "review-task: no MRs to review${KEY:+ for $KEY}. Do not run the workflow."
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/review-task-${KEY:-mrs}$(heavy_suffix "$n").XXXXXX")
mkdir -p "$WORK/repos" "$WORK/diffs" "$WORK/discussions"
export GIT_TERMINAL_PROMPT=0  # never block on a credential prompt

# jira-only: task.md is the requirements source for the completeness agent. Its
# absence in mrs-mode is the signal "no task" -> the agent is skipped downstream.
[[ -n "${ISSUE_JSON:-}" ]] && printf '%s' "$ISSUE_JSON" | issue_to_md > "$WORK/task.md"

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
  # A non-empty body without .changes is an error payload ({"message":"404..."}).
  # Skip it: `jq '.changes[]'` on null is exit 5, which under `set -e`+pipefail
  # would kill the whole hook mid-loop (no WORK= line -> stale-fallback review).
  printf '%s' "$changes" | jq -e '.changes' >/dev/null 2>&1 \
    || { echo "review-task: skipping $path!$iid (no .changes in GitLab response — 404/no access?)"; continue; }

  src=$(printf '%s' "$changes" | jq -r '.source_branch // empty'); [[ -z "$src" ]] && src="$src_gp"
  diff_path="$WORK/diffs/$slug.diff"
  printf '%s' "$changes" | jq -r '.changes[] | "--- a/\(.old_path)\n+++ b/\(.new_path)\n\(.diff)"' > "$diff_path"

  clone_path="$WORK/repos/$slug"
  cmd_present=false
  if git clone --depth 1 --branch "$src" "https://$GITLAB_HOST/$path.git" "$clone_path" >/dev/null 2>&1; then
    # `|| true`: find_local_claudemd ends in `[[…]] && printf`, so "not found"
    # returns exit 1 — which under `set -e` would kill the whole hook here for
    # any repo without a local CLAUDE.md. The empty stdout already means "none".
    cmd=$(find_local_claudemd "$path") || true
    if [[ -n "$cmd" ]]; then
      cp "$cmd" "$clone_path/CLAUDE.md"; cmd_present=true; cmd_copied=$((cmd_copied+1))
    else
      no_cmd=$((no_cmd+1))
    fi
  else
    failed_clones+="${failed_clones:+, }$path@$src"
    clone_path=""
  fi

  # human review comments (inline + general) — paginated; matcher correlates them
  # with findings so already-raised issues land in their own report section.
  disc='[]'; page=1
  while [[ $page -le 20 ]]; do   # ponytail: 20*100=2000 нот потолок, дальше не тянем
    pg=$(curl -fsS -H "PRIVATE-TOKEN: $GL_TOKEN" \
      "https://$GITLAB_HOST/api/v4/projects/$enc/merge_requests/$iid/discussions?per_page=100&page=$page" 2>/dev/null || true)
    cnt=$(printf '%s' "$pg" | jq 'length' 2>/dev/null || echo 0)
    [[ "$cnt" -eq 0 ]] && break
    disc=$(printf '%s\n%s' "$disc" "$pg" | jq -c -s 'add')   # concat страниц
    [[ "$cnt" -lt 100 ]] && break                            # последняя страница
    page=$((page+1))
  done
  notes_path="$WORK/discussions/$slug.json"
  printf '%s' "$disc" | jq -c '
    [ .[].notes[]?
      | select(.system == false)
      | { author:   (.author.username // ""),
          body:     (.body // ""),
          file:     (.position.new_path // .position.old_path // ""),
          line:     (.position.new_line // .position.old_line // null),
          resolvable:(.resolvable // false),
          resolved: (.resolved // false) } ]' > "$notes_path" 2>/dev/null \
    || printf '[]' > "$notes_path"

  manifest=$(printf '%s' "$manifest" | jq -c \
    --arg repo "$path" --arg iid "$iid" --arg cp "$clone_path" \
    --arg dp "$diff_path" --arg sb "$src" --arg url "$url" --argjson cmd "$cmd_present" \
    --arg disc "$notes_path" \
    '. + [{repo:$repo, iid:$iid, clonePath:$cp, diffPath:$dp, source_branch:$sb, web_url:$url, claudeMd:$cmd, discussionsPath:$disc}]')
done

printf '%s' "$manifest" > "$WORK/manifest.json"
got=$(printf '%s' "$manifest" | jq 'length')
if [[ "$got" -eq 0 ]]; then
  echo "review-task: could not assemble any MR${KEY:+ for $KEY}. Do not run the workflow."
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
echo "review-task: MRs ready ($got total)${KEY:+ for $KEY}. WORK=$WORK. Run the review-task workflow with this path."
exit 0
