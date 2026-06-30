#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["claude-agent-sdk"]
# ///
"""Deterministic git helpers (commit / commit-msg / branch).

Port of git-hook.sh: validators, git plumbing, and haiku text generation — but
the generation engine is now the Claude Agent SDK with a STATEFUL session.
Instead of re-running `claude -p` from scratch each attempt, a single
ClaudeSDKClient keeps the dialog open: an invalid candidate is answered with a
short correction follow-up in the SAME session, so the model sees its own
rejected turn as conversation context.

setting_sources is left unset -> the SDK-spawned `claude` does NOT load user
settings/hooks, so it never re-fires UserPromptSubmit (the bash straz keeps a
CLAUDE_COMMIT_GEN env guard as cheap insurance regardless).

Modes (argv[0]):
  commit|commit-msg|branch  -> cli (needs --repo; flags --all/--tracked/--force/--dry-run)
  hook                      -> read stdin JSON, route by .prompt, emit decision:block
  --self-check              -> run pure-function asserts (no network)
"""

import json
import os
import re
import subprocess
import sys

MAX_LEN = 50
MAX_DIFF = 14000
GEN_MODEL = "haiku"  # alias -> latest haiku, resolved by claude cli

MODE = "hook"  # "hook" | "cli"


# ---- pure functions (validators / text shaping; shared by runtime + self-check)

def validate_msg(msg: str, branch: str) -> list[str]:
    """Return list of problems with a commit message; empty list = valid."""
    errs = []
    if not re.match(r"^(CUS-[0-9]+|feat|fix): .+", msg):
        errs.append("must start with CUS-XXXX:, feat:, or fix:")
    if len(msg) > MAX_LEN:
        errs.append(f"must be <= {MAX_LEN} chars (got {len(msg)})")
    if msg.endswith("."):
        errs.append("must not end with a period")
    desc = msg.split(": ", 1)[1] if ": " in msg else msg
    if desc != desc.lower():
        errs.append("description must be lowercase")
    slug = branch.rsplit("/", 1)[-1].lower().replace("-", " ")
    if desc.lower() == slug:
        errs.append("description copied from branch slug, not the diff")
    return errs


def validate_slug(s: str) -> list[str]:
    errs = []
    if not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", s):
        errs.append("slug must be lowercase kebab-case [a-z0-9-]")
    if len(s) > 40:
        errs.append("slug too long (max 40)")
    return errs


def slugify(text: str) -> str:
    """Free text -> kebab-case, max 4 words."""
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return "-".join(s.split("-")[:4])


def sanitize(raw: str) -> str:
    """Model output -> clean single line (strip code fences, quotes, trailing dot)."""
    cleaned = []
    for ln in raw.split("\n"):
        ln = re.sub(r"^```[a-z]*", "", ln)
        ln = re.sub(r"```$", "", ln)
        cleaned.append(ln)
    line = next((l for l in cleaned if len(l) > 0), "")  # first non-empty line
    line = re.sub(r"^[\s*`\"'-]+", "", line)
    line = re.sub(r"[\s`\"']+$", "", line)
    line = re.sub(r"\s{2,}", " ", line)
    line = re.sub(r"\.$", "", line)
    return line


def correction_text(errs: str) -> str:
    """Follow-up sent in the SAME session after a rejected candidate."""
    return (
        f"Your previous message was rejected: {errs}. "
        "Return ONLY the corrected output, no quotes, no markdown, no explanation."
    )


def extract_ticket(branch: str) -> str:
    m = re.search(r"CUS-[0-9]+", branch, re.I)
    return m.group(0).upper() if m else ""


# ---- prompts (rules -> system_prompt, dynamic data -> turn 1) ------------------

COMMIT_SYSTEM = f"""You generate exactly one git commit message for the staged changes.

Rules:
- Return ONLY the commit message: no quotes, no markdown, no explanation.
- Format: {{PREFIX}}: {{description}}
- If Ticket ID is present, PREFIX must be that ticket ID.
- If Ticket ID is absent, PREFIX must be feat: for new functionality or fix: for bug fixes.
- Maximum {MAX_LEN} characters total. Single line. Description lowercase English. No period at the end.
- Imperative verbs: add, fix, update, remove, refactor.
- Describe the ACTUAL changed behavior/config/API from the diff. Do NOT copy the branch name.
- Abbreviations when needed: and=>&, implementation=>impl, authentication=>auth, configuration=>config, update=>upd, delete=>del, function=>fn, message=>msg, request=>req, response=>res, database=>db, repository=>repo, parameters=>params, initialization=>init."""

COMMIT_TURN = "Ticket ID: {ticket}\n\nStaged files:\n{files}\n\nStaged diff:\n```diff\n{diff}\n```"

SLUG_SYSTEM = (
    "Return ONLY a 2-4 word kebab-case git branch slug (lowercase letters, digits, "
    "hyphens) describing the changes. No prefix, no quotes, no explanation."
)
TYPESLUG_SYSTEM = (
    "Reply with exactly: <type> <slug>\n"
    "- type: feat (new functionality) or fix (bug fix)\n"
    "- slug: 2-4 word kebab-case (lowercase letters, digits, hyphens) describing the change\n"
    "Example: feat add-user-auth\nNo quotes, no explanation."
)
DIFF_TURN = "Diff:\n```diff\n{diff}\n```"

TYPE_SYSTEM = "Reply with exactly one word: feat or fix.\n- feat = new functionality\n- fix = bug fix"
TYPE_TURN = "For this change:\n{ctx}"


# ---- SDK generation engine: stateful multi-turn until valid -------------------

def _dbg(turn: int, what: str) -> None:
    if os.environ.get("GIT_GEN_DEBUG"):
        print(f"[git_gen turn {turn}] {what}", file=sys.stderr)


async def _collect_text(client) -> str:
    from claude_agent_sdk import AssistantMessage, TextBlock

    parts = []
    async for msg in client.receive_response():
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    parts.append(block.text)
    return "".join(parts)


async def converse_until_valid(system_prompt, first_prompt, check, attempts):
    """Run one stateful dialog; retry via correction follow-ups until `check` passes.

    `check(raw) -> (value, errors)`: value is the usable result (str or tuple),
    errors a list ([] = valid). Returns (value | None, last_repr, last_err).
    """
    from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient

    options = ClaudeAgentOptions(
        model=GEN_MODEL,
        system_prompt=system_prompt,
        allowed_tools=[],
        max_turns=attempts,
    )
    last_repr, last_err = "(empty)", "unknown"
    async with ClaudeSDKClient(options=options) as client:
        await client.query(first_prompt)
        for turn in range(attempts):
            raw = await _collect_text(client)
            value, errs = check(raw)
            last_repr = str(value) if value else "(empty)"
            _dbg(turn + 1, f"cand={last_repr!r} errs={errs}")
            if value and not errs:
                return value, last_repr, ""
            last_err = ";".join(errs) if errs else "unknown"
            if turn + 1 < attempts:
                await client.query(correction_text(last_err))
    return None, last_repr, last_err


# check closures: (raw) -> (value, errors)
def _check_msg(branch):
    def check(raw):
        cand = sanitize(raw)
        if not cand:
            return "", ["model returned empty"]
        return cand, validate_msg(cand, branch)
    return check


def _check_slug(raw):
    cand = sanitize(raw).replace(" ", "-").lower()
    return cand, validate_slug(cand)


def _check_type_slug(raw):
    cand = sanitize(raw)
    words = cand.split()
    ttype = words[0].lower() if words else ""
    slug_try = re.sub(r"^[a-zA-Z]+[: ]+", "", cand).replace(" ", "-").lower()
    if ttype in ("feat", "fix") and not validate_slug(slug_try):
        return (ttype, slug_try), []
    return cand, ["expected exactly '<feat|fix> <kebab-slug>'"]


def _check_type(raw):
    words = sanitize(raw).split()
    t = words[0].lower() if words else ""
    if t in ("feat", "fix"):
        return t, []
    return t, ["reply exactly 'feat' or 'fix'"]


def _run_async(coro_fn, *args):
    import anyio

    return anyio.run(coro_fn, *args)


# ---- git plumbing -------------------------------------------------------------

def git(*args):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def current_branch() -> str:
    _, out, _ = git("branch", "--show-current")
    b = out.strip()
    if not b:
        _, out, _ = git("rev-parse", "--short", "HEAD")
        b = out.strip() or "unknown"
    return b


def staged_context():
    """Return (files, diff) truncated, or None if nothing staged."""
    _, files, _ = git("diff", "--cached", "--name-only")
    files = files.rstrip("\n")
    if not files:
        return None
    _, diff, _ = git("diff", "--cached", "--no-ext-diff")
    if len(diff) > MAX_DIFF:
        diff = diff[:MAX_DIFF] + f"\n\n[diff truncated to {MAX_DIFF} chars]"
    return files, diff


# ---- output: hook (decision:block JSON) | cli (stdout + exit code) ------------

def emit(kind: str, text: str):
    if MODE == "cli":
        print(text)
        sys.exit(0 if kind == "ok" else 1)
    first = text.split("\n", 1)[0]
    print(json.dumps({"decision": "block", "reason": text, "systemMessage": first}))
    sys.exit(0)


# ---- commands -----------------------------------------------------------------

def cmd_commit(words: str):
    toks = set(words.split())
    rc, root, _ = git("rev-parse", "--show-toplevel")
    if rc != 0:
        emit("err", "✗ commit: not a git repository")
    os.chdir(root.strip())
    if "all" in toks:
        rc, _, _ = git("add", "-A")
        if rc != 0:
            emit("err", "✗ commit: git add -A failed")
    if "tracked" in toks:
        rc, _, _ = git("add", "-u")
        if rc != 0:
            emit("err", "✗ commit: git add -u failed")

    ctx = staged_context()
    if ctx is None:
        emit("err", "✗ commit: nothing staged. Stage files, or use --all / --tracked ('/commit all').")
    files, diff = ctx

    branch = current_branch()
    if branch.lower() in ("main", "master", "develop", "stage", "staging") and "force" not in toks:
        emit("err", f"✗ commit: '{branch}' is protected. Use force / --force / allowProtectedBranch after review.")

    ticket = extract_ticket(branch)
    msg, last_cand, last_err = _run_async(
        converse_until_valid, COMMIT_SYSTEM,
        COMMIT_TURN.format(ticket=ticket or "none", files=files, diff=diff),
        _check_msg(branch), 4,
    )
    if msg is None:
        emit("err", "✗ commit: no valid message after 4 tries — re-run /commit to retry.\n"
                    f"Last candidate: {last_cand}\nProblems: {last_err}")

    if "dryrun" in toks:
        emit("ok", f"📝 {msg}")

    rc, _, err = git("commit", "-m", msg)
    if rc != 0:
        emit("err", f"✗ commit failed: {err.strip()}")
    _, h, _ = git("rev-parse", "--short", "HEAD")
    emit("ok", f"✓ committed {h.strip()}: {msg}")


def cmd_commit_msg():
    rc, root, _ = git("rev-parse", "--show-toplevel")
    if rc != 0:
        emit("err", "✗ commit-msg: not a git repository")
    os.chdir(root.strip())
    ctx = staged_context()
    if ctx is None:
        emit("err", "✗ commit-msg: staging is empty. Stage files first.")
    files, diff = ctx
    branch = current_branch()
    ticket = extract_ticket(branch)
    msg, last_cand, last_err = _run_async(
        converse_until_valid, COMMIT_SYSTEM,
        COMMIT_TURN.format(ticket=ticket or "none", files=files, diff=diff),
        _check_msg(branch), 4,
    )
    if msg is None:
        emit("err", "✗ commit-msg: no valid message after 4 tries — re-run /commit-msg to retry.\n"
                    f"Last candidate: {last_cand}\nProblems: {last_err}")
    emit("ok", f"📝 {msg}")


def cmd_branch(args: str):
    parts = args.split(None, 1)
    first = parts[0] if parts else ""
    rest = parts[1] if len(parts) > 1 else ""
    prefix = ""
    if re.match(r"^[Cc][Uu][Ss]-[0-9]+$", first):
        prefix = first.upper()
        desc = rest
    else:
        desc = args

    rc, root, _ = git("rev-parse", "--show-toplevel")
    if rc != 0:
        emit("err", "✗ branch: not a git repository")
    os.chdir(root.strip())

    if desc.strip():
        slug = slugify(desc)
        if not prefix:
            t, _, _ = _run_async(converse_until_valid, TYPE_SYSTEM,
                                 TYPE_TURN.format(ctx=desc), _check_type, 2)
            prefix = t or "feat"
    else:
        _, diff, _ = git("diff", "HEAD")
        if not diff.strip():
            emit("err", "✗ branch: no description and no changes. Use '/branch [CUS-XXXX] <short description>'.")
        if len(diff) > MAX_DIFF:
            diff = diff[:MAX_DIFF]
        if prefix:
            slug, _, _ = _run_async(converse_until_valid, SLUG_SYSTEM,
                                    DIFF_TURN.format(diff=diff), _check_slug, 2)
        else:
            res, _, _ = _run_async(converse_until_valid, TYPESLUG_SYSTEM,
                                   DIFF_TURN.format(diff=diff), _check_type_slug, 2)
            if res is None:
                emit("err", "✗ branch: model failed to produce a valid slug. Pass a description: '/branch [CUS-XXXX] <desc>'.")
            prefix, slug = res
        if not slug:
            emit("err", "✗ branch: model failed to produce a valid slug. Pass a description: '/branch [CUS-XXXX] <desc>'.")
        if not prefix:
            prefix = "feat"

    if not slug:
        emit("err", "✗ branch: empty description after slugify. Use '/branch [CUS-XXXX] <short description>'.")
    name = f"{prefix}/{slug}"
    rc, _, err = git("switch", "-c", name)
    if rc != 0:
        emit("err", f"✗ branch failed: {err.strip()}")
    emit("ok", f"✓ switched to new branch {name}")


# ---- self-check (pure functions only) ----------------------------------------

def self_check():
    assert validate_msg("feat: add telegram notifier", "feature/x") == []
    assert validate_msg("CUS-1234: add telegram notifier config", "CUS-1234/foo") == []
    assert validate_msg("Feat: Add Thing", "x")
    assert validate_msg("feat: add thing.", "x")
    assert validate_msg("chore: whatever", "x")
    assert validate_msg("feat: " + "x" * 60, "x")
    assert validate_msg("feat: add feature", "CUS-1/add-feature")
    assert validate_slug("add-user-auth") == []
    assert validate_slug("fix-login") == []
    assert validate_slug("Add_User")
    assert validate_slug("trailing-")
    assert slugify("Add User Auth, now!") == "add-user-auth-now"
    assert slugify("one two three four five") == "one-two-three-four"
    assert "must not end with a period" in correction_text("must not end with a period")
    assert sanitize("```\nfeat: add thing.\n```") == "feat: add thing"
    assert sanitize('  "feat: do x"  ') == "feat: do x"
    # check closures
    assert _check_msg("x")("feat: add thing") == ("feat: add thing", [])
    assert _check_slug("Add User") == ("add-user", [])
    assert _check_type_slug("feat add-user-auth") == (("feat", "add-user-auth"), [])
    assert _check_type("fix") == ("fix", [])
    print("self-check: PASS")


# ---- routing ------------------------------------------------------------------

def main():
    global MODE
    argv = sys.argv[1:]
    if not argv:
        sys.exit(0)

    if argv[0] == "--self-check":
        self_check()
        return

    if argv[0] in ("commit", "commit-msg", "branch"):
        MODE = "cli"
        sub, rest = argv[0], argv[1:]
        repo, stage, free = "", [], []
        i = 0
        while i < len(rest):
            a = rest[i]
            if a == "--repo":
                repo = rest[i + 1] if i + 1 < len(rest) else ""
                i += 2
            elif a.startswith("--repo="):
                repo = a[len("--repo="):]
                i += 1
            elif a == "--all":
                stage.append("all"); i += 1
            elif a == "--tracked":
                stage.append("tracked"); i += 1
            elif a == "--force":
                stage.append("force"); i += 1
            elif a == "--dry-run":
                stage.append("dryrun"); i += 1
            else:
                free.append(a); i += 1
        if not repo:
            emit("err", f"✗ {sub}: --repo PATH is required")
        try:
            os.chdir(repo)
        except OSError:
            emit("err", f"✗ {sub}: cannot enter repo '{repo}'")
        if sub == "commit":
            cmd_commit(" ".join(stage))
        elif sub == "commit-msg":
            cmd_commit_msg()
        else:
            cmd_branch(" ".join(free))
        return

    if argv[0] == "hook":
        MODE = "hook"
        if os.environ.get("CLAUDE_COMMIT_GEN") == "1":
            sys.exit(0)
        try:
            prompt = json.loads(sys.stdin.read()).get("prompt", "") or ""
        except Exception:
            prompt = ""
        # order matters: /commit-msg before /commit (it is a prefix of it)
        if re.match(r"^\s*/commit-msg(\s|$)", prompt):
            cmd_commit_msg()
        elif re.match(r"^\s*/commit(\s|$)", prompt):
            cmd_commit(prompt.split("/commit", 1)[1])
        elif re.match(r"^\s*/branch(\s|$)", prompt):
            cmd_branch(prompt.split("/branch", 1)[1].strip())
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    main()
