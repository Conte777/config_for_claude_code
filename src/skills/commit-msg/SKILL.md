---
name: commit-msg
description: Use this skill when the user wants to generate a commit message. Contains workflow for branch checking, ticket ID extraction, and message formatting.
---

# Commit Workflow Skill

This skill defines the workflow for creating commits with proper validation, ticket ID extraction, and message formatting.

## When to Use

- User runs `/commit` command
- User asks to create a commit
- User needs help with commit message format
- User wants to commit staged changes

## Workflow Steps

### Step 1: Run Pre-commit Checks

Execute the helper script to gather git state information:

```powershell
pwsh -NoProfile -File "${SKILL_DIR}/scripts/commit-helper.ps1"
```

The script returns JSON with the following structure:

```json
{
  "stagedFiles": ["file1.ts", "file2.go"],
  "stagedCount": 2,
  "branchName": "CUS-1234/add-feature",
  "ticketId": "CUS-1234",
  "isProtectedBranch": false,
  "warnings": []
}
```

### Step 2: Handle Warnings

Process any warnings returned by the script:

#### EMPTY_STAGING
The staging area is empty. No files to commit.

**Action:** Use `AskUserQuestion` to ask the user:
- Question: "Staging area is empty. Add files?"
- Options:
  - "All files (-A)" — adds all files including untracked
  - "Tracked files only (-u)" — adds only tracked files
  - "Cancel" — abort the commit

After adding files, re-run the helper script to refresh the state.

#### PROTECTED_BRANCH
Attempting to commit directly to a protected branch (main, master, develop, stage).

**Action:** Use `AskUserQuestion` to confirm:
- Question: "You're about to commit to protected branch '{branchName}'. Continue?"
- Options:
  - "Да, продолжай" — proceed with commit
  - "Отмени" — abort the commit

#### NO_TICKET_ID
No ticket ID pattern (CUS-XXXX) found in branch name.

**Action:** Use `AskUserQuestion` to determine prefix:
- Question: "Нет номера задачи в ветке, Какой префикс использовать?"
- Options:
  - "feat/fix" — new feature or bug fix
  - "Ввести CUS-XXXX" — user provides ticket ID

### Step 3: Analyze Changes

Review the staged changes to understand the nature of the commit:

1. Run `git diff --staged` to see the actual changes
2. Identify the type of change (new feature or bug fix)
3. Note key files and components affected

### Step 4: Generate Commit Message

Create a commit message following the strict format:

#### Format Rules

**Prefix (one of):**
- `CUS-XXXX:` — when ticket ID is available
- `feat:` — new functionality (only when no ticket ID)
- `fix:` — bug fix (only when no ticket ID)

**Constraints:**
- Maximum 50 characters total
- Single line (header only, no body)
- Lowercase description
- No period at the end
- Use abbreviations when needed: `&`, `|`, `impl`, `auth`, `config`, `upd`, `del`

**Examples:**
```
CUS-1234: add user auth endpoint
CUS-5678: fix null check in payment service
feat: impl login & signup forms
fix: handle empty response in api client
```

### Step 5: Show commit message

Show commit message to user

## File References

- [Commit Helper Script](./scripts/commit-helper.ps1) — PowerShell validation script
- [Workflow Scenarios](./examples/workflow-scenarios.md) — Example scenarios
- [Message Format](./references/message-format.md) — Detailed format specification
- [Branch Conventions](./references/branch-conventions.md) — Branch naming rules

## Error Handling

- If git is not initialized, inform the user
- If there are merge conflicts, abort and notify
- If commit hook fails, show the error and suggest fixes
