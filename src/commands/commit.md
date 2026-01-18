---
description: Create a commit with ticket ID from branch name
allowed-tools: AskUserQuestion, Skill, Bash(git *)
---

# Commit Command

Create a git commit with proper validation and message generation.

## Step 1: Pre-commit Checks

### Check staging area

```bash
git diff --cached --name-only
```

If empty, use `AskUserQuestion`:
- Question: "Staging area пуст. Добавить файлы?"
- Options:
  - "Все файлы (-A)" — adds all files including untracked
  - "Только отслеживаемые (-u)" — adds only tracked files
  - "Отмена" — abort the commit

After selection:
- "Все файлы" → run `git add -A`
- "Только отслеживаемые" → run `git add -u`
- "Отмена" → abort and inform user

Re-check staging after adding files.

### Check protected branch

```bash
git branch --show-current
```

Protected branches: `main`, `master`, `develop`, `stage`, `staging`

If on protected branch, use `AskUserQuestion`:
- Question: "Коммит в защищённую ветку '{branch}'. Продолжить?"
- Options:
  - "Да, продолжить" — proceed with commit
  - "Отмена" — abort the commit

## Step 2: Generate Commit Message

Invoke `commit-msg` skill using Skill tool to generate the commit message.

## Step 3: Execute Commit

```bash
git commit -m "MESSAGE"
```

Report success with the commit message used.
