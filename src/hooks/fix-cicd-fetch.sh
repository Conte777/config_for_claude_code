#!/usr/bin/env bash
# UserPromptSubmit hook for `/fix-cicd <gitlab-ci-job-url>` — deterministic, no LLM.
# Fetches the failed job's trace from the GitLab API (token from ~/.netrc), strips
# ANSI, writes it to an OS-temp .md file and prints the path to stdout (-> session
# context) so the /fix-cicd command can Read it. Any other prompt: exit 0 (pass-through).
set -euo pipefail

# password for a host from ~/.netrc; handles single-line and multi-line entries
netrc_token() { # <host>
  [[ -f "$HOME/.netrc" ]] || return 0
  awk -v host="$1" '
    { for (i=1;i<=NF;i++){
        if ($i=="machine"){ inhost=($(i+1)==host); i++ }
        else if (inhost && $i=="password"){ print $(i+1); exit } } }' "$HOME/.netrc"
}

# ponytail: self-check for URL parsing (the non-trivial part).
# Run: FIX_CICD_SELFTEST=1 bash src/hooks/fix-cicd-fetch.sh
if [[ "${FIX_CICD_SELFTEST:-}" == 1 ]]; then
  u='https://git.itcrew.info/Fri_releases/cryptoprocessing/backend-core/auth-gateway/-/jobs/222943'
  url=$(printf '%s' "/fix-cicd $u" | grep -oE 'https?://[^[:space:]]+/-/jobs/[0-9]+' | head -1)
  [[ "$url" == "$u" ]] || { echo "FAIL: job url extract"; exit 1; }
  host=$(printf '%s' "$url" | sed -E 's|https?://([^/]+)/.*|\1|')
  [[ "$host" == git.itcrew.info ]] || { echo "FAIL: host parse ($host)"; exit 1; }
  path=$(printf '%s' "$url" | sed -E 's|https?://[^/]+/||; s|/-/jobs/.*||')
  [[ "$path" == Fri_releases/cryptoprocessing/backend-core/auth-gateway ]] || { echo "FAIL: path parse ($path)"; exit 1; }
  jobid=$(printf '%s' "$url" | grep -oE 'jobs/[0-9]+' | grep -oE '[0-9]+')
  [[ "$jobid" == 222943 ]] || { echo "FAIL: job id parse ($jobid)"; exit 1; }
  [[ -z "$(printf '%s' '/fix-cicd no url here' | grep -oE 'https?://[^[:space:]]+/-/jobs/[0-9]+' | head -1)" ]] \
    || { echo "FAIL: no-url should be empty"; exit 1; }
  echo "fix-cicd selftest OK"; exit 0
fi

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
# trigger only on the slash command (pass-through for anything else — hot path)
[[ "$prompt" =~ ^[[:space:]]*/fix-cicd([[:space:]]|$) ]] || exit 0

# Clear the stale fallback up front: if this run dies mid-flight under `set -e`
# before writing a fresh trace, the command reads an empty file and honestly
# reports "fetch didn't run" instead of analyzing a PREVIOUS job's leftover.
: > "$HOME/.claude/.fix-cicd-last" 2>/dev/null || true

url=$(printf '%s' "$prompt" | grep -oE 'https?://[^[:space:]]+/-/jobs/[0-9]+' | head -1 || true)
[[ -z "$url" ]] && { echo "fix-cicd: no GitLab CI job URL (.../-/jobs/<id>) in the prompt. Do not analyze."; exit 0; }

host=$(printf '%s' "$url" | sed -E 's|https?://([^/]+)/.*|\1|')
path=$(printf '%s' "$url" | sed -E 's|https?://[^/]+/||; s|/-/jobs/.*||')
jobid=$(printf '%s' "$url" | grep -oE 'jobs/[0-9]+' | grep -oE '[0-9]+' || true)
[[ -z "$host" || -z "$path" || -z "$jobid" ]] && { echo "fix-cicd: could not parse the job URL: $url. Do not analyze."; exit 0; }
enc=$(printf '%s' "$path" | jq -Rr @uri)

GL_TOKEN=$(netrc_token "$host")
[[ -z "$GL_TOKEN" ]] && { echo "fix-cicd: no GitLab credentials in ~/.netrc (machine $host). Add 'machine $host login <user> password <token>' (chmod 600). Do not analyze."; exit 0; }

# job metadata (for the trace header) + the raw trace log
meta=$(curl -fsS -H "PRIVATE-TOKEN: $GL_TOKEN" "https://$host/api/v4/projects/$enc/jobs/$jobid" 2>/dev/null || true)
[[ -z "$meta" ]] && { echo "fix-cicd: GitLab job API did not respond for $path job $jobid (auth/host/access?). Do not analyze."; exit 0; }
read -r name stage status ref < <(printf '%s' "$meta" | jq -r '[.name, .stage, .status, .ref] | @tsv' 2>/dev/null || true)

trace=$(curl -fsS -H "PRIVATE-TOKEN: $GL_TOKEN" "https://$host/api/v4/projects/$enc/jobs/$jobid/trace" 2>/dev/null || true)
[[ -z "$trace" ]] && { echo "fix-cicd: empty trace for $path job $jobid (job too old/erased, or no access). Do not analyze."; exit 0; }

# CI logs are full of ANSI escape codes — strip them for a readable .md.
trace=$(printf '%s' "$trace" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')

# BSD mktemp wants the Xs at the very end (no suffix) — create, then add .md.
f=$(mktemp "${TMPDIR:-/tmp}/fix-cicd-${jobid}.XXXXXX") && mv "$f" "$f.md" && f="$f.md"
{
  printf '# CI job %s (%s) — %s\n\n' "${name:-?}" "${stage:-?}" "${status:-?}"
  printf -- '- URL: %s\n- ref: %s\n\n' "$url" "${ref:-?}"
  printf '## Trace\n\n```\n%s\n```\n' "$trace"
} > "$f"

# fallback delivery: fixed file in case stdout->context is unreliable
echo "$f" > "$HOME/.claude/.fix-cicd-last" 2>/dev/null || true
echo "fix-cicd: trace saved to $f"
exit 0
