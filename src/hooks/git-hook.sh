#!/usr/bin/env bash
# Deterministic git helpers via UserPromptSubmit router — ports of the pi
# commit.ts / branch / commit-msg skills. On a ">" trigger the hook does all the
# work in bash (model only generates text via `claude -p haiku`), then BLOCKS the
# prompt so the main session model is never invoked and nothing enters context.
#
# Triggers (must start the prompt):
#   >commit [all] [force]   stage? -> haiku msg -> validate -> git commit
#   >commit-msg             haiku msg from staged diff, preview only (no commit)
#   >branch [CUS-N] [desc]  git switch -c PREFIX/slug
#                           ticket optional; without it the model picks feat/fix
set -euo pipefail

MAX_LEN=50
MAX_DIFF=14000
GEN_MODEL="haiku"   # alias -> latest haiku version, resolved by claude cli

# ---- validators (shared by runtime + self-check) ------------------------------
validate_msg() { # <message> <branch> -> prints errors, empty = valid
  local msg="$1" branch="$2" desc slug
  [[ "$msg" =~ ^(CUS-[0-9]+|feat|fix):\ .+ ]] || echo "must start with CUS-XXXX:, feat:, or fix:"
  (( ${#msg} <= MAX_LEN )) || echo "must be <= $MAX_LEN chars (got ${#msg})"
  [[ "$msg" != *. ]] || echo "must not end with a period"
  desc="${msg#*: }"
  [[ "$desc" == "$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')" ]] || echo "description must be lowercase"
  slug=$(printf '%s' "${branch##*/}" | tr '[:upper:]' '[:lower:]' | tr '-' ' ')
  [[ "$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')" != "$slug" ]] || echo "description copied from branch slug, not the diff"
}

validate_slug() { # <slug> -> prints errors, empty = valid
  local s="$1"
  [[ "$s" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || echo "slug must be lowercase kebab-case [a-z0-9-]"
  (( ${#s} <= 40 )) || echo "slug too long (max 40)"
}

slugify() { # free text -> kebab-case, max 4 words
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' \
    | cut -d- -f1-4
}

sanitize() { # model output -> clean single line
  sed -e 's/^```[a-z]*//' -e 's/```$//' \
    | grep -m1 . \
    | sed -e 's/^[[:space:]*`"'\''-]*//' -e 's/[[:space:]`"'\'']*$//' -e 's/[[:space:]]\{2,\}/ /g' -e 's/\.$//'
}

# assemble the correction block shown to the model on retry (pure, testable)
build_correction() { # <prev_candidate> <errors> -> correction block text
  printf '
Your previous output was: "%s"
It was REJECTED. Fix exactly these problems and return ONLY the corrected commit message: %s
' "$1" "$2"
}

# ---- self-check ----------------------------------------------------------------
if [[ "${1:-}" == "--self-check" ]]; then
  fail=0
  ck() { local got; got=$(validate_msg "$2" "$3")
    [[ "$1" == ok && -n "$got" ]] && { echo "FAIL want ok: '$2' -> $got"; fail=1; }
    [[ "$1" == bad && -z "$got" ]] && { echo "FAIL want bad: '$2'"; fail=1; }; return 0; }
  cks() { local got; got=$(validate_slug "$2")
    [[ "$1" == ok && -n "$got" ]] && { echo "FAIL slug want ok: '$2' -> $got"; fail=1; }
    [[ "$1" == bad && -z "$got" ]] && { echo "FAIL slug want bad: '$2'"; fail=1; }; return 0; }
  ck ok  "feat: add telegram notifier"            "feature/x"
  ck ok  "CUS-1234: add telegram notifier config" "CUS-1234/foo"
  ck bad "Feat: Add Thing"                        "x"
  ck bad "feat: add thing."                       "x"
  ck bad "chore: whatever"                        "x"
  ck bad "feat: $(printf 'x%.0s' {1..60})"        "x"
  ck bad "feat: add feature"                      "CUS-1/add-feature"
  cks ok  "add-user-auth"
  cks ok  "fix-login"
  cks bad "Add_User"
  cks bad "trailing-"
  [[ "$(slugify 'Add User Auth, now!')" == "add-user-auth-now" ]] || { echo "FAIL slugify"; fail=1; }
  [[ "$(slugify 'one two three four five')" == "one-two-three-four" ]] || { echo "FAIL slugify words"; fail=1; }
  cb=$(build_correction "feat: bad msg." "must not end with a period")
  [[ "$cb" == *"feat: bad msg."* && "$cb" == *"must not end with a period"* ]] || { echo "FAIL build_correction"; fail=1; }
  (( fail == 0 )) && echo "self-check: PASS" || { echo "self-check: FAIL"; exit 1; }
  exit 0
fi

# ---- output abstraction: hook (decision:block JSON) | cli (stdout + exit code) -
OUT_MODE=hook
emit() { # <ok|err> <text...>
  local kind="$1"; shift; local text="$*"
  if [[ "$OUT_MODE" == cli ]]; then
    printf '%s\n' "$text"
    [[ "$kind" == ok ]] && exit 0 || exit 1
  fi
  jq -n --arg r "$text" '{decision:"block", reason:$r, systemMessage:($r|split("\n")|.[0])}'
  exit 0
}

# ---- CLI mode: `git-hook.sh commit|branch|commit-msg --repo PATH …` (MCP front) -
# Subcommand as $1 switches to cli; flags map to the same internal words hook uses.
SUBCMD="" CLI_REPO="" CLI_STAGE="" CLI_REST=""
if [[ "${1:-}" =~ ^(commit|branch|commit-msg)$ ]]; then
  OUT_MODE=cli; SUBCMD="$1"; shift
  while (( $# )); do
    case "$1" in
      --repo)    CLI_REPO="${2:-}"; shift 2 ;;
      --repo=*)  CLI_REPO="${1#--repo=}"; shift ;;
      --all)     CLI_STAGE="$CLI_STAGE all";     shift ;;
      --tracked) CLI_STAGE="$CLI_STAGE tracked"; shift ;;
      --force)   CLI_STAGE="$CLI_STAGE force";   shift ;;
      --dry-run) CLI_STAGE="$CLI_STAGE dryrun";  shift ;;
      *)         CLI_REST="${CLI_REST:+$CLI_REST }$1"; shift ;;
    esac
  done
fi

# ---- recursion guard: the child `claude -p` re-fires this hook (hook mode only) -
[[ "$OUT_MODE" == hook && "${CLAUDE_COMMIT_GEN:-}" == "1" ]] && exit 0

# ---- input: hook mode reads stdin JSON; cli mode has no stdin -------------------
prompt=""
if [[ "$OUT_MODE" == hook ]]; then
  input=$(cat)
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty')
fi

gen() { # stdin = prompt -> raw model output
  CLAUDE_COMMIT_GEN=1 command claude -p --model "$GEN_MODEL" 2>/dev/null || true
}

gen_type() { # <context text> -> feat|fix decided by the model (defaults feat if it won't answer)
  local ctx="$1" raw t
  for attempt in 1 2; do
    raw=$(printf 'Reply with exactly one word: feat or fix.\n- feat = new functionality\n- fix = bug fix\nFor this change:\n%s' "$ctx" | gen)
    t=$(printf '%s' "$raw" | sanitize | awk '{print tolower($1)}')
    [[ "$t" == "feat" || "$t" == "fix" ]] && { printf '%s' "$t"; return 0; }
  done
  printf 'feat'
}

current_branch() {
  local b; b=$(git branch --show-current 2>/dev/null || true)
  [[ -z "$b" ]] && b=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
  printf '%s' "$b"
}

# build commit-message prompt; echoes a VALID message or nothing (4 attempts).
# on exhaustion stashes the last candidate + errors in GEN_LAST_CAND/GEN_LAST_ERR.
gen_message() { # <branch> <ticket> <staged_files> <diff>
  local branch="$1" ticket="$2" staged="$3" diff="$4" correction="" prev_cand="" cand raw verr
  for attempt in 1 2 3 4; do
    corr_block=""
    [[ -n "$correction" ]] && corr_block=$(build_correction "$prev_cand" "$correction")
    # printf with %s args is injection-safe: $staged/$diff are data, never evaluated
    raw=$(printf 'Generate exactly one git commit message for the staged changes.

Rules:
- Return ONLY the commit message: no quotes, no markdown, no explanation.
- Format: {PREFIX}: {description}
- If Ticket ID is present, PREFIX must be that ticket ID.
- If Ticket ID is absent, PREFIX must be feat: for new functionality or fix: for bug fixes.
- Maximum %s characters total. Single line. Description lowercase English. No period at the end.
- Imperative verbs: add, fix, update, remove, refactor.
- Describe the ACTUAL changed behavior/config/API from the diff. Do NOT copy the branch name.
- Abbreviations when needed: and=>&, implementation=>impl, authentication=>auth, configuration=>config, update=>upd, delete=>del, function=>fn, message=>msg, request=>req, response=>res, database=>db, repository=>repo, parameters=>params, initialization=>init.%s
Ticket ID: %s

Staged files:
%s

Staged diff:
```diff
%s
```
' "$MAX_LEN" "$corr_block" "${ticket:-none}" "$staged" "$diff" | gen)
    cand=$(printf '%s' "$raw" | sanitize)
    prev_cand="${cand:-(empty)}"
    [[ -z "$cand" ]] && { correction="model returned empty"; continue; }
    verr=$(validate_msg "$cand" "$branch")
    [[ -z "$verr" ]] && { GEN_MSG="$cand"; return 0; }
    correction=$(printf '%s' "$verr" | paste -sd';' -)
  done
  GEN_LAST_CAND="$prev_cand"; GEN_LAST_ERR="$correction"
  return 1
}

staged_context() { # echoes "files\n---DIFF---\ndiff", truncated; empty if nothing staged
  local files diff
  files=$(git diff --cached --name-only 2>/dev/null || true)
  [[ -z "$files" ]] && return 1
  diff=$(git diff --cached --no-ext-diff 2>/dev/null || true)
  (( ${#diff} > MAX_DIFF )) && diff="${diff:0:MAX_DIFF}

[diff truncated to $MAX_DIFF chars]"
  printf '%s\n---DIFF---\n%s' "$files" "$diff"
}

# ============================== commands =======================================
cmd_commit() { # <words: all|tracked|force|dryrun>
  local args=" $1 " mode_all=false mode_tracked=false force=false dryrun=false root branch protected ticket ctx files diff msg hash err
  [[ "$args" == *" all "* ]]     && mode_all=true
  [[ "$args" == *" tracked "* ]] && mode_tracked=true
  [[ "$args" == *" force "* ]]   && force=true
  [[ "$args" == *" dryrun "* ]]  && dryrun=true

  root=$(git rev-parse --show-toplevel 2>/dev/null) || emit err "✗ commit: not a git repository"
  cd "$root"
  $mode_all     && { git add -A || emit err "✗ commit: git add -A failed"; }
  $mode_tracked && { git add -u || emit err "✗ commit: git add -u failed"; }

  ctx=$(staged_context) || emit err "✗ commit: nothing staged. Stage files, or use --all / --tracked ('>commit all')."
  files="${ctx%%---DIFF---*}"; diff="${ctx#*---DIFF---$'\n'}"

  branch=$(current_branch)
  protected=false
  for pb in main master develop stage staging; do
    [[ "$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]')" == "$pb" ]] && protected=true && break
  done
  $protected && ! $force && emit err "✗ commit: '$branch' is protected. Use force / --force / allowProtectedBranch after review."

  ticket=$(printf '%s' "$branch" | grep -ioE 'CUS-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true)
  gen_message "$branch" "$ticket" "$files" "$diff" || emit err "$(printf '✗ commit: no valid message after 4 tries — re-run >commit to retry.
Last candidate: %s
Problems: %s' "${GEN_LAST_CAND:-(empty)}" "${GEN_LAST_ERR:-unknown}")"
  msg="$GEN_MSG"

  $dryrun && emit ok "📝 $msg"

  git commit -m "$msg" >/dev/null 2>git_err.tmp || { err=$(cat git_err.tmp); rm -f git_err.tmp; emit err "✗ commit failed: $err"; }
  rm -f git_err.tmp
  hash=$(git rev-parse --short HEAD 2>/dev/null || true)
  emit ok "✓ committed $hash: $msg"
}

cmd_commit_msg() {
  local root branch ticket ctx files diff msg
  root=$(git rev-parse --show-toplevel 2>/dev/null) || emit err "✗ commit-msg: not a git repository"
  cd "$root"
  ctx=$(staged_context) || emit err "✗ commit-msg: staging is empty. Stage files first."
  files="${ctx%%---DIFF---*}"; diff="${ctx#*---DIFF---$'\n'}"
  branch=$(current_branch)
  ticket=$(printf '%s' "$branch" | grep -ioE 'CUS-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true)
  gen_message "$branch" "$ticket" "$files" "$diff" || emit err "$(printf '✗ commit-msg: no valid message after 4 tries — re-run >commit-msg to retry.
Last candidate: %s
Problems: %s' "${GEN_LAST_CAND:-(empty)}" "${GEN_LAST_ERR:-unknown}")"
  emit ok "📝 $GEN_MSG"
}

cmd_branch() { # <args>
  local args="$1" first rest prefix="" desc slug root diff verr cand raw err ttype slug_try
  read -r first rest <<<"$args"
  # optional leading ticket (CUS-N) sets the prefix directly; otherwise the whole
  # input is the description and the model picks feat/fix.
  if [[ "$first" =~ ^[Cc][Uu][Ss]-[0-9]+$ ]]; then
    prefix=$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]'); desc="$rest"
  else
    desc="$args"
  fi

  root=$(git rev-parse --show-toplevel 2>/dev/null) || emit err "✗ branch: not a git repository"
  cd "$root"

  if [[ -n "${desc// /}" ]]; then
    slug=$(slugify "$desc")
    [[ -z "$prefix" ]] && prefix=$(gen_type "$desc")
  else
    diff=$(git diff HEAD 2>/dev/null || true)
    [[ -z "$diff" ]] && emit err "✗ branch: no description and no changes. Use '>branch [CUS-XXXX] <short description>'."
    (( ${#diff} > MAX_DIFF )) && diff="${diff:0:MAX_DIFF}"
    for attempt in 1 2; do
      if [[ -n "$prefix" ]]; then
        # type already known -> ask only for a slug
        raw=$(printf 'Return ONLY a 2-4 word kebab-case git branch slug (lowercase letters, digits, hyphens) describing these changes. No prefix, no quotes, no explanation.\n\nDiff:\n```diff\n%s\n```' "$diff" | gen)
        cand=$(printf '%s' "$raw" | sanitize | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
        verr=$(validate_slug "$cand"); [[ -z "$verr" ]] && { slug="$cand"; break; }
      else
        # no prefix -> let the model pick feat/fix and a slug in one call
        raw=$(printf 'Reply with exactly: <type> <slug>\n- type: feat (new functionality) or fix (bug fix)\n- slug: 2-4 word kebab-case (lowercase letters, digits, hyphens) describing the change\nExample: feat add-user-auth\nNo quotes, no explanation.\n\nDiff:\n```diff\n%s\n```' "$diff" | gen)
        cand=$(printf '%s' "$raw" | sanitize)
        ttype=$(printf '%s' "$cand" | awk '{print tolower($1)}')
        slug_try=$(printf '%s' "$cand" | sed -E 's/^[a-zA-Z]+[: ]+//' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
        if [[ "$ttype" == "feat" || "$ttype" == "fix" ]] && [[ -z "$(validate_slug "$slug_try")" ]]; then
          prefix="$ttype"; slug="$slug_try"; break
        fi
      fi
    done
    [[ -z "${slug:-}" ]] && emit err "✗ branch: model failed to produce a valid slug. Pass a description: '>branch [CUS-XXXX] <desc>'."
    [[ -z "$prefix" ]] && prefix="feat"
  fi

  [[ -z "$slug" ]] && emit err "✗ branch: empty description after slugify. Use '>branch [CUS-XXXX] <short description>'."
  local name="$prefix/$slug"
  git switch -c "$name" >/dev/null 2>git_err.tmp || { err=$(cat git_err.tmp); rm -f git_err.tmp; emit err "✗ branch failed: $err"; }
  rm -f git_err.tmp
  emit ok "✓ switched to new branch $name"
}

# ============================== routing ========================================
# cli mode: dispatch by subcommand (repo required); returns via emit (exit code).
if [[ "$OUT_MODE" == cli ]]; then
  [[ -z "$CLI_REPO" ]] && emit err "✗ $SUBCMD: --repo PATH is required"
  cd "$CLI_REPO" 2>/dev/null || emit err "✗ $SUBCMD: cannot enter repo '$CLI_REPO'"
  case "$SUBCMD" in
    commit)     cmd_commit "$CLI_STAGE" ;;
    commit-msg) cmd_commit_msg ;;
    branch)     cmd_branch "$CLI_REST" ;;
  esac
  exit 0
fi

# hook mode — order matters: >commit-msg before >commit (it is a prefix of it)
if   [[ "$prompt" =~ ^[[:space:]]*\>commit-msg([[:space:]]|$) ]]; then cmd_commit_msg
elif [[ "$prompt" =~ ^[[:space:]]*\>commit([[:space:]]|$) ]];     then cmd_commit "${prompt#*>commit}"
elif [[ "$prompt" =~ ^[[:space:]]*\>branch([[:space:]]|$) ]];     then
  b="${prompt#*>branch}"; cmd_branch "$(printf '%s' "$b" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
fi
exit 0  # not our trigger -> pass through to the model
