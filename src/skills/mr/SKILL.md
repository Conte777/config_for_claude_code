---
name: mr
description: Create a GitLab merge request, put a branch up for review, or block one merge request on another. Every merge request in a GitLab repo goes through here, including one you decided to open yourself.
allowed-tools: AskUserQuestion, mcp__plugin_autogit_autogit__branch, mcp__plugin_autogit_autogit__commit, Bash(git fetch:*), Bash(git remote get-url:*), Bash(git ls-remote:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git push:*), Bash(glab api:*), Bash(glab mr create:*), Bash(glab mr list:*), Bash(glab mr update:*)
---

# Create a merge request

Ask every question in this skill with AskUserQuestion.

Values used throughout: `REPO` = `git rev-parse --show-toplevel`, `BRANCH` = `git rev-parse --abbrev-ref HEAD`, `PROJECT` = the URL-encoded project path (`group%2Fsub%2Fproject`) derived from `git remote get-url origin`, needed only by the `glab api` calls in step 7, `TICKET` = the ticket id for this work, sourced as step 2 describes.

## 1. Target branch

Run `git fetch origin`, then `git ls-remote --heads origin develop`. Output → `TARGET` is `develop`; empty output → `TARGET` is `main`.

Skipping the fetch makes `origin/<TARGET>` stale, which silently corrupts the commit range every later step reads.

## 2. Land on a feature branch

Take `TICKET` from the current branch name, or from the ticket the user named in this session. With neither, ask the user whether this work has a ticket; a "no" leaves `TICKET` empty. Never infer an id from commit messages, the diff, or file contents — a match there belongs to someone else's work and sends the branch and the merge request to the wrong ticket.

`BRANCH` is one of `main`, `master`, `develop`, `stage`, `staging`:

- `git status --porcelain` empty → stop and report that there is nothing to branch from. Create no branch.
- Otherwise call `mcp__plugin_autogit_autogit__branch` with `repoPath: REPO`, the ticket, and a short free-text description of the change. The server builds the branch name.

`BRANCH` is a feature branch and the user named a ticket whose id does not appear in `BRANCH` → ask whether to continue on this branch, and stop if the user declines. A missing ticket in the name usually means the branch was cut without one, or that you are standing on the wrong branch — either is worth catching before the push. Leave the branch name as it is.

## 3. Commit

- `git diff --cached --name-only` non-empty → `mcp__plugin_autogit_autogit__commit` with `stageMode: "staged"`.
- Nothing staged and `git status --porcelain` non-empty → ask which files to commit: all files (`stageMode: "all"`), tracked files only (`stageMode: "tracked"`), or nothing. Commit with the chosen mode.
- Clean worktree → skip this step.

`mcp__plugin_autogit_autogit__commit` generates the message server-side; pass no message.

## 4. Push

`git log --pretty=%s origin/<TARGET>..HEAD` empty → stop and report that there is nothing to merge. Create no merge request.

Otherwise `git push -u origin HEAD`.

## 5. Merge request

Bind `~/.claude/.env` in the same shell as every `glab mr` call of this step: `set -a; . ~/.claude/.env; set +a`. It carries `GITLAB_MR_REVIEWERS` (comma-separated GitLab usernames) and `JIRA_URL` (bare Jira host). Either one empty → carry on without the reviewers or the ticket link, and name the empty variable in the report.

### Merge request text

Write it from `git log origin/<TARGET>..HEAD` and `git diff origin/<TARGET>..HEAD` — the whole branch, not its latest commit.

- **Title** — one line in English. With `TICKET`: `<TICKET>: <summary>`, e.g. `CUS-1930: Add retries on notification send`. Without: a conventional-commit type with no scope, e.g. `feat: add retries on notification send` (`feat`, `fix`, `docs`, `refactor`, `chore`, …).
- **Description** — markdown: with `TICKET`, the line `Задача: [<TICKET>](https://<JIRA_URL>/browse/<TICKET>)` and a blank line; then 2–5 bullets in Russian, each a change in behaviour and its reason, never a file list.

Pipe the description to `--description-file -`, printing the link line from the shell variables so the Jira host stays out of the text you write:

```
{ printf 'Задача: [%s](https://%s/browse/%s)\n\n' "$TICKET" "$JIRA_URL" "$TICKET"; cat <<'EOF'
- <change and its reason>
EOF
} | glab mr <create|update> ... --description-file -
```

`TICKET` or `JIRA_URL` empty → drop the `printf` and pipe the bullets alone.

### Create or update

`glab mr list --source-branch BRANCH --output json` — with no state flag it lists open merge requests only. `glab` picks the project and the host from `git remote`, so no id and no token are needed here.

- The list is empty → create one:

  ```
  glab mr create --source-branch BRANCH --target-branch TARGET --title "<title>" --reviewer "$GITLAB_MR_REVIEWERS" --description-file - --yes
  ```

  `--yes` skips the confirmation prompt. If `glab` opens an editor anyway, re-run with `--no-editor`.

- A record comes back → carry its `iid` into step 6, then:
  1. Check the record's `title` and `description` against the branch. Either one states something the diff contradicts, or leaves out a change the branch makes → rewrite it to the format above with `glab mr update <iid> --title "<title>" --description-file -`. Keep lines that describe no code (deploy order, a note for the reviewer) as they are. Both match the branch → leave them untouched.
  2. `glab mr update <iid> --reviewer +<user> --reviewer +<user> …` — one `+<user>` per name in `GITLAB_MR_REVIEWERS`. A bare list replaces the reviewers and drops the ones assigned by hand; `+` adds to them.

## 6. Dependencies

Collect the blocking candidates from two signals:

- A pseudo-version (`v0.0.0-<date>-<sha>`) added to `go.mod` in this branch — `git diff origin/<TARGET>..HEAD -- go.mod`. It marks the case this step exists for: the service pins an unmerged library commit, and the library version must be bumped once the library merges.
- Merge requests this skill created earlier in the session, in other repositories.

- Candidates found → block on them without asking, and list them in the final report. A block that turns out to be unnecessary is visible there and cheap to remove by hand; a missing one is not.
- No candidates → ask whether this merge request depends on any other. The user answers with full merge request URLs.

Related changes across two services need no block — they merge together anyway; a pinned pseudo-version does.

## 7. Block

For each blocking merge request from step 6 — a candidate you found or a URL the user gave — in order:

1. Read the blocking project path and `iid` from the URL, then `glab api projects/<encoded blocking path>/merge_requests/<blocking iid>` and take the `id` field — the instance-global numeric id, which differs from the `iid` in the URL.
2. `glab api "projects/PROJECT/merge_requests/<iid>/blocks" -X POST -f "blocking_merge_request_id=<id>"` — undocumented endpoint, GitLab Premium.
3. Read every id from an API response. Ids are global across the instance, so a guessed one lands in a stranger's merge request.

Verify once at the end: `glab api projects/PROJECT/merge_requests/<iid>` reports `detailed_merge_status: merge_request_blocked`. The endpoint is undocumented, so this status is the only evidence that the blocks took effect.

A failing POST or a status other than `merge_request_blocked` is not a reason to stop — the merge request is already created and pushed. Carry on and say so in the report.

## Done

Report the merge request URL, whether the title and description were written, rewritten or left as they were, then the blocks that took effect and the ones that did not, as separate lists. With no confirming question left in the flow, this report is the only place a missing block becomes visible.
