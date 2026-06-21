# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.2"]
# ///
"""Git MCP — deterministic commit/branch for the main model.

Thin adapter: maps tool args to argv and shells out to git-hook.sh, which owns
ALL logic (staging, haiku message generation, validation, retry, git). Nothing
is duplicated here — the server only parses tool calls and returns stdout.
"""

import os
import subprocess

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("git")

HOOK = os.path.expanduser("~/.claude/hooks/git-hook.sh")


def _run(argv: list[str]) -> str:
    try:
        p = subprocess.run(
            ["bash", HOOK, *argv],
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        return "✗ git-hook timed out (120s)"
    out = (p.stdout or "").strip()
    if p.returncode != 0:
        return out or (p.stderr or "").strip() or f"✗ git-hook exited {p.returncode}"
    return out or "(no output)"


@mcp.tool()
def commit(
    repoPath: str,
    stageMode: str = "staged",
    allowProtectedBranch: bool = False,
    dryRun: bool = False,
) -> str:
    """Commit staged changes in a git repo with an auto-generated message.

    Use ONLY when the user explicitly asks to commit. Do NOT commit proactively.
    The commit message is generated and validated server-side from the staged
    diff (haiku + bash validators) — you do NOT write or pass a message.

    Protected branches (main/master/develop/stage/staging) are blocked unless
    allowProtectedBranch=True, which you set ONLY after the user explicitly
    agrees to commit on that branch.

    Args:
        repoPath: Absolute path to the repository (or any dir inside it).
        stageMode: "staged" (default, commit what's already staged), "all"
            (git add -A first), or "tracked" (git add -u first).
        allowProtectedBranch: Permit committing on a protected branch. Requires
            explicit user consent — never set this on your own initiative.
        dryRun: Generate and return the message WITHOUT committing. Useful to
            preview the message before the real commit.

    Returns:
        Result line, e.g. "✓ committed <hash>: <msg>", "📝 <msg>" (dry run), or
        a "✗ …" error explaining why nothing was committed.
    """
    argv = ["commit", "--repo", repoPath]
    if stageMode == "all":
        argv.append("--all")
    elif stageMode == "tracked":
        argv.append("--tracked")
    if allowProtectedBranch:
        argv.append("--force")
    if dryRun:
        argv.append("--dry-run")
    return _run(argv)


@mcp.tool()
def branch(
    repoPath: str,
    ticket: str | None = None,
    description: str | None = None,
) -> str:
    """Create and switch to a new git branch named <prefix>/<slug>.

    Use ONLY when the user explicitly asks to create/switch to a new branch.

    The prefix is the ticket (e.g. CUS-1234) when given, otherwise feat/fix
    decided server-side from the description or diff. The slug is a kebab-case
    summary generated server-side — pass a short human description, not a slug.

    Args:
        repoPath: Absolute path to the repository (or any dir inside it).
        ticket: Optional ticket id like "CUS-1234"; becomes the branch prefix.
        description: Short free-text description of the change. If omitted, the
            server infers a slug from the current diff (requires uncommitted
            changes).

    Returns:
        "✓ switched to new branch <name>" or a "✗ …" error.
    """
    argv = ["branch", "--repo", repoPath]
    if ticket:
        argv.append(ticket)
    if description:
        argv.append(description)
    return _run(argv)


if __name__ == "__main__":
    mcp.run()
