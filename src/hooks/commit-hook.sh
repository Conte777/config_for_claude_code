#!/usr/bin/env bash
# Deterministic ">commit" — port of the pi commit.ts extension.
# A UserPromptSubmit router: on trigger it generates the commit message with a
# cheap model (claude -p haiku), validates it in bash, runs git commit, and
# BLOCKS the prompt so the main session model is never invoked and nothing
# enters its context. Generation = the only model call; everything else is bash.
set -euo pipefail

MAX_LEN=50
MAX_DIFF=14000
GEN_MODEL="claude-haiku-4-5"

# ---- validator (shared by runtime + self-check) -------------------------------
# validate_msg <message> <branch>  -> prints errors (one per line), empty = valid
validate_msg() {
  local msg="$1" branch="$2" desc slug
  [[ "$msg" =~ ^(CUS-[0-9]+|feat|fix):\ .+ ]] || echo "must start with CUS-XXXX:, feat:, or fix:"
  (( ${#msg} <= MAX_LEN )) || echo "must be <= $MAX_LEN chars (got ${#msg})"
  [[ "$msg" != *. ]] || echo "must not end with a period"
  desc="${msg#*: }"
  [[ "$desc" == "$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')" ]] || echo "description must be lowercase"
  # not a verbatim copy of the branch slug
  slug=$(printf '%s' "${branch##*/}" | tr '[:upper:]' '[:lower:]' | tr '-' ' ')
  [[ "$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')" != "$slug" ]] || echo "description copied from branch slug, not the diff"
}

# ---- self-check: bash assertions, no model/git ---------------------------------
if [[ "${1:-}" == "--self-check" ]]; then
  fail=0
  check() { # check <expect: ok|bad> <msg> <branch>
    local got; got=$(validate_msg "$2" "$3")
    if [[ "$1" == "ok" && -n "$got" ]]; then echo "FAIL want ok: '$2' -> $got"; fail=1; fi
    if [[ "$1" == "bad" && -z "$got" ]]; then echo "FAIL want bad: '$2'"; fail=1; fi
  }
  check ok  "feat: add telegram notifier"          "feature/x"
  check ok  "CUS-1234: add telegram notifier config" "CUS-1234/foo"
  check ok  "fix: remove unused imports"            "main"
  check bad "Feat: Add Thing"                       "x"           # uppercase
  check bad "feat: add thing."                      "x"           # trailing period
  check bad "chore: whatever"                       "x"           # bad prefix
  check bad "feat: $(printf 'x%.0s' {1..60})"       "x"           # too long
  check bad "feat: add feature"                     "CUS-1/add-feature"  # branch slug copy
  (( fail == 0 )) && echo "self-check: PASS" || { echo "self-check: FAIL"; exit 1; }
  exit 0
fi

# ---- recursion guard: the child `claude -p` below re-fires this hook -----------
[[ "${CLAUDE_COMMIT_GEN:-}" == "1" ]] && exit 0

# ---- trigger match -------------------------------------------------------------
input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
[[ "$prompt" =~ ^[[:space:]]*\>commit([[:space:]]|$) ]] || exit 0  # not our trigger -> pass through

args=" ${prompt#*>commit} "          # remainder, space-padded for word match
mode_all=false; force=false
[[ "$args" == *" all "* ]]   && mode_all=true
[[ "$args" == *" force "* ]] && force=true

block() { jq -n --arg r "$1" '{decision:"block", reason:$r, systemMessage:($r|split("\n")|.[0])}'; exit 0; }

# ---- repo + context ------------------------------------------------------------
root=$(git rev-parse --show-toplevel 2>/dev/null) || block "✗ commit: not a git repository"
cd "$root"

$mode_all && { git add -A || block "✗ commit: git add -A failed"; }

branch=$(git branch --show-current 2>/dev/null || true)
[[ -z "$branch" ]] && branch=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)

staged=$(git diff --cached --name-only 2>/dev/null || true)
[[ -z "$staged" ]] && block "✗ commit: staging is empty. Stage files or use '>commit all'."

protected=false
for pb in main master develop stage staging; do
  [[ "$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]')" == "$pb" ]] && protected=true && break
done
$protected && ! $force && block "✗ commit: '$branch' is protected. Use '>commit force' after review."

ticket=$(printf '%s' "$branch" | grep -ioE 'CUS-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true)
diff=$(git diff --cached --no-ext-diff 2>/dev/null || true)
(( ${#diff} > MAX_DIFF )) && diff="${diff:0:MAX_DIFF}

[diff truncated to $MAX_DIFF chars]"

# ---- generation prompt (port of buildGenerationPrompt) -------------------------
gen_prompt() { # gen_prompt [correction]
  cat <<EOF
Generate exactly one git commit message for the staged changes.

Rules:
- Return ONLY the commit message: no quotes, no markdown, no explanation.
- Format: {PREFIX}: {description}
- If Ticket ID is present, PREFIX must be that ticket ID.
- If Ticket ID is absent, PREFIX must be feat: for new functionality or fix: for bug fixes.
- Maximum $MAX_LEN characters total. Single line. Description lowercase English. No period at the end.
- Imperative verbs: add, fix, update, remove, refactor.
- Describe the ACTUAL changed behavior/config/API from the diff. Do NOT copy the branch name.
- Prefer specific changed components over generic service names.
- Abbreviations when needed: and=>&, implementation=>impl, authentication=>auth, configuration=>config, update=>upd, delete=>del, function=>fn, message=>msg, request=>req, response=>res, database=>db, repository=>repo, parameters=>params, initialization=>init.
${1:+
Previous attempt was invalid. Fix it. Validation errors: $1
}
Ticket ID: ${ticket:-none}

Staged files:
$staged

Staged diff:
\`\`\`diff
$diff
\`\`\`
EOF
}

# ---- generate + validate, up to 2 attempts ------------------------------------
sanitize() { # strip fences/quotes/bullets, first non-empty line, collapse, drop trailing dot
  sed -e 's/^```[a-z]*//; s/```$//' \
    | grep -m1 . \
    | sed -e 's/^[[:space:]*`"'\''-]*//' -e 's/[[:space:]`"'\'']*$//' -e 's/[[:space:]]\{2,\}/ /g' -e 's/\.$//'
}

correction=""; errors=""; msg=""
for attempt in 1 2; do
  raw=$(CLAUDE_COMMIT_GEN=1 gen_prompt "$correction" | command claude -p --model "$GEN_MODEL" 2>/dev/null || true)
  cand=$(printf '%s' "$raw" | sanitize)
  if [[ -z "$cand" ]]; then correction="model returned empty"; errors+="attempt $attempt: empty; "; continue; fi
  verr=$(validate_msg "$cand" "$branch")
  if [[ -z "$verr" ]]; then msg="$cand"; break; fi
  correction=$(printf '%s' "$verr" | paste -sd';' -)
  errors+="attempt $attempt ('$cand'): $correction; "
done
[[ -z "$msg" ]] && block "✗ commit: model failed to produce a valid message. $errors"

# ---- commit --------------------------------------------------------------------
git commit -m "$msg" >/dev/null 2>git_err.tmp || { err=$(cat git_err.tmp); rm -f git_err.tmp; block "✗ commit failed: $err"; }
rm -f git_err.tmp
hash=$(git rev-parse --short HEAD 2>/dev/null || true)
block "✓ committed $hash: $msg"
