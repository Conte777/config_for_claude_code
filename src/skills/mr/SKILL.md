---
name: mr
description: Create a GitLab merge request for the current work and block it on the merge requests it depends on.
disable-model-invocation: true
allowed-tools: AskUserQuestion, mcp__git__branch, mcp__git__commit, mcp__gitlab__create_merge_request, mcp__gitlab__list_merge_requests, Bash(git fetch:*), Bash(git remote get-url:*), Bash(git ls-remote:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git push:*), Bash(glab api:*)
---

# Create a merge request

Invoked as `/mr` or `/mr CUS-1234`. Ask every question in this skill with AskUserQuestion.

Values used throughout: `REPO` = `git rev-parse --show-toplevel`, `BRANCH` = `git rev-parse --abbrev-ref HEAD`, `PROJECT` = the URL-encoded project path (`group%2Fsub%2Fproject`) derived from `git remote get-url origin`.

## 1. Target branch

Run `git fetch origin`, then `git ls-remote --heads origin develop`. Output → `TARGET` is `develop`; empty output → `TARGET` is `main`.

Skipping the fetch makes `origin/<TARGET>` stale, which silently corrupts the commit range every later step reads.

## 2. Land on a feature branch

`BRANCH` is one of `main`, `master`, `develop`, `stage`, `staging`:

- `git status --porcelain` empty → stop and report that there is nothing to branch from. Create no branch.
- Otherwise take the ticket from the invocation argument; with no argument, ask the user whether this work has a ticket. Then call `mcp__git__branch` with `repoPath: REPO`, the ticket, and a short free-text description of the change. The server builds the branch name.

`BRANCH` is a feature branch and a ticket argument was passed whose id does not appear in `BRANCH` → ask whether to continue on this branch, and stop if the user declines. A missing ticket in the name usually means the branch was cut without one, or that you are standing on the wrong branch — either is worth catching before the push. Leave the branch name as it is.

## 3. Commit

- `git diff --cached --name-only` non-empty → `mcp__git__commit` with `stageMode: "staged"`.
- Nothing staged and `git status --porcelain` non-empty → ask which files to commit: all files (`stageMode: "all"`), tracked files only (`stageMode: "tracked"`), or nothing. Commit with the chosen mode.
- Clean worktree → skip this step.

`mcp__git__commit` generates the message server-side; pass no message.

## 4. Push

`git log --pretty=%s origin/<TARGET>..HEAD` empty → stop and report that there is nothing to merge. Create no merge request.

Otherwise `git push -u origin HEAD`.

## 5. Merge request

`mcp__gitlab__list_merge_requests` with `project_id: PROJECT`, `source_branch: BRANCH`, `state: "opened"`.

- A merge request exists → keep it exactly as it is, title and description included, and carry its `iid` into step 6.
- None exists → `mcp__gitlab__create_merge_request` with `project_id: PROJECT`, `source_branch: BRANCH`, `target_branch: TARGET`, and `title` = the **first** commit of the branch, i.e. the last line of `git log --pretty=%s origin/<TARGET>..HEAD`. Omit `description` so it stays empty.

## 6. Dependencies

Collect the blocking candidates from two signals:

- A pseudo-version (`v0.0.0-<date>-<sha>`) added to `go.mod` in this branch — `git diff origin/<TARGET>..HEAD -- go.mod`. It marks the case this step exists for: the service pins an unmerged library commit, and the library version must be bumped once the library merges.
- Merge requests this skill created earlier in the session, in other repositories.

Then ask the user, always:

- Candidates found → list them and ask whether that is all the dependencies.
- No candidates → ask whether this merge request depends on any other.

The user answers with full merge request URLs. Related changes across two services need no block — they merge together anyway; a pinned pseudo-version does.

## 7. Block

For each URL the user gave, in order:

1. Read the blocking project path and `iid` from the URL, then `glab api projects/<encoded blocking path>/merge_requests/<blocking iid>` and take the `id` field — the instance-global numeric id, which differs from the `iid` in the URL.
2. `glab api "projects/PROJECT/merge_requests/<iid>/blocks" -X POST -f "blocking_merge_request_id=<id>"` — undocumented endpoint, GitLab Premium.
3. Read every id from an API response. Ids are global across the instance, so a guessed one lands in a stranger's merge request.

Verify once at the end: `glab api projects/PROJECT/merge_requests/<iid>` reports `detailed_merge_status: merge_request_blocked`. The endpoint is undocumented, so this status is the only evidence that the blocks took effect.

## Done

Report the merge request URL and each blocking merge request that was attached.
