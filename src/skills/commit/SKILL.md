---
name: commit
description: >-
  This skill should be used when the user asks to "commit",
  "закоммитить", "сделать коммит", "create commit",
  "зафиксировать изменения"
version: 0.1.0
allowed-tools: AskUserQuestion, Skill, Bash(git add *), Bash(git diff --staged), Bash(git commit *)
---

# Commit Skill

This skill creates a git commit with proper validation, staging checks, protected branch guards, and message generation.

## Step 1: Parse Hook Context

The PreToolUse hook output contains git context collected by `collect-git-context.sh`. The output is visible to both user and Claude.

**Extract from hook output:**
- **Branch** — current branch name (or short hash if detached HEAD)
- **Protected** — whether the branch is protected (`true`/`false`)
- **Ticket ID** — extracted ticket ID or `none`
- **Staging empty** — whether staging area is empty (`true`/`false`)
- **Staged Files** — list of staged file names
- **Staged Diff** — full diff of staged changes

If hook output is missing, collect the data manually using allowed bash tools.

## Step 2: Handle Empty Staging

If staging is empty, ask the user via `AskUserQuestion`:
- Question: "Staging area пуст. Добавить файлы?"
- Options:
  - "Все файлы (-A)" — adds all files including untracked
  - "Только отслеживаемые (-u)" — adds only tracked files
  - "Отмена" — abort the commit

After selection:
- "Все файлы" → run `git add -A`
- "Только отслеживаемые" → run `git add -u`
- "Отмена" → abort and inform user

After adding files, run `git diff --staged` to get the updated diff for commit message generation.

## Step 3: Protected Branch Check

If the branch is protected (`main`, `master`, `develop`, `stage`, `staging`), ask the user via `AskUserQuestion`:
- Question: "Коммит в защищённую ветку '{branch}'. Продолжить?"
- Options:
  - "Да, продолжить" — proceed with commit
  - "Отмена" — abort the commit

## Step 4: Generate Commit Message

Invoke the `commit-msg` skill using the Skill tool.

The skill will read branch name, ticket ID, and diff from the conversation context (already present from Step 1).

## Step 5: Execute Commit

Run the commit:

```bash
git commit -m "MESSAGE"
```

Report success with the commit message used.

## File References

- [Message Format](./references/message-format.md) — Detailed format specification
- [Branch Conventions](./references/branch-conventions.md) — Branch naming rules
