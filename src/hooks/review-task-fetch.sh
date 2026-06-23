#!/usr/bin/env bash
# UserPromptSubmit hook for `/review-task <KEY>` — deterministic, no LLM.
# Fetches the task's MRs from Jira gitplugin, pulls each MR's GitLab diff,
# shallow-clones the source branch, writes a manifest, and prints the WORK dir
# to stdout (-> session context) so the /review-task command can hand it to the
# review Workflow. Any other prompt: exit 0 immediately (pass-through).
set -euo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
# trigger only on the slash command; KEY = ABC-123
[[ "$prompt" =~ ^/review-task[[:space:]]+([A-Z]+-[0-9]+) ]] || exit 0
KEY="${BASH_REMATCH[1]}"

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
  echo "review-task: нет учёток в ~/.netrc (jira-машина: ${JIRA_HOST:-не найдена}, gitlab: $GITLAB_HOST). Добавь 'machine <host> login <user> password <token>' (chmod 600). Workflow не запускай."
  exit 0
fi

# 1. Jira gitplugin -> MR list
gp=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
  "https://$JIRA_HOST/rest/gitplugin/1.0/issuegitdetails/issue/$KEY/pullRequest" 2>/dev/null || true)
if [[ -z "$gp" ]]; then
  echo "review-task: Jira gitplugin не ответил для $KEY (auth/scope/host?). Workflow не запускай."
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
  echo "review-task: для $KEY не найдено MR в Jira gitplugin. Workflow не запускай."
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/review-task-$KEY.XXXXXX")
mkdir -p "$WORK/repos" "$WORK/diffs"
export GIT_TERMINAL_PROMPT=0  # never block on a credential prompt

manifest='[]'
i=0
while [[ $i -lt $n ]]; do
  url=$(printf '%s' "$mrs" | jq -r ".[$i].url")
  src_gp=$(printf '%s' "$mrs" | jq -r ".[$i].source")
  i=$((i+1))

  path=$(printf '%s' "$url" | sed -E 's|https?://[^/]+/||; s|/-/merge_requests/.*||')
  iid=$(printf '%s' "$url" | grep -oE 'merge_requests/[0-9]+' | grep -oE '[0-9]+' || true)
  [[ -z "$path" || -z "$iid" ]] && { echo "review-task: пропуск MR (url не разобран: $url)"; continue; }
  enc=$(printf '%s' "$path" | jq -Rr @uri)
  slug="$(printf '%s' "$path" | tr '/' '_')__mr$iid"

  changes=$(curl -fsS -H "PRIVATE-TOKEN: $GL_TOKEN" \
    "https://$GITLAB_HOST/api/v4/projects/$enc/merge_requests/$iid/changes" 2>/dev/null || true)
  [[ -z "$changes" ]] && { echo "review-task: пропуск $path!$iid (GitLab /changes не ответил)"; continue; }

  src=$(printf '%s' "$changes" | jq -r '.source_branch // empty'); [[ -z "$src" ]] && src="$src_gp"
  diff_path="$WORK/diffs/$slug.diff"
  printf '%s' "$changes" | jq -r '.changes[] | "--- a/\(.old_path)\n+++ b/\(.new_path)\n\(.diff)"' > "$diff_path"

  clone_path="$WORK/repos/$slug"
  if ! git clone --depth 1 --branch "$src" "https://$GITLAB_HOST/$path.git" "$clone_path" >/dev/null 2>&1; then
    echo "review-task: клон $path@$src не удался — линза пойдёт по diff без полного кода"
    clone_path=""
  fi

  manifest=$(printf '%s' "$manifest" | jq -c \
    --arg repo "$path" --arg iid "$iid" --arg cp "$clone_path" \
    --arg dp "$diff_path" --arg sb "$src" --arg url "$url" \
    '. + [{repo:$repo, iid:$iid, clonePath:$cp, diffPath:$dp, source_branch:$sb, web_url:$url}]')
done

printf '%s' "$manifest" > "$WORK/manifest.json"
got=$(printf '%s' "$manifest" | jq 'length')
if [[ "$got" -eq 0 ]]; then
  echo "review-task: для $KEY ни один MR собрать не удалось. Workflow не запускай."
  exit 0
fi

# fallback delivery: fixed file in case stdout->context is unreliable
echo "$WORK" > "$HOME/.claude/.review-task-last" 2>/dev/null || true
echo "review-task: MR для $KEY готовы ($got шт.). WORK=$WORK. Запусти workflow review-task с этим путём."
exit 0
