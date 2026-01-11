---
description: Create a commit with ticket ID from branch name
allowed-tools: Bash(git status:*), Bash(git branch:*), Bash(git add:*), Bash(git diff:*), Bash(git commit:*), AskUserQuestion, Read
model: Haiku
---

# Commit Command

Create a git commit following the project conventions.

## Commit Message Format

**With ticket ID (from branch):**
- Format: `CUS-XXXX: brief description`
- Example: `CUS-1234: add user authentication`

**Without ticket ID:**
- Format: `feat: brief description` or `fix: brief description`
- Example: `feat: add login page`

**Constraints:**
- Maximum 50 characters total
- Lowercase description
- No trailing period

## Workflow

### Step 1: Get Current Branch

Run: `git branch --show-current`

### Step 2: Check Branch Type

If branch is `main`, `stage`, or `develop`:
- Use AskUserQuestion to confirm:
  - Question: "You are committing to [branch]. Continue?"
  - Header: "Confirm"
  - Options: "Yes, continue" / "No, cancel"
- If user cancels, abort the operation

### Step 3: Extract Ticket ID

Parse branch name for `CUS-XXXX` pattern (case-insensitive).
- Found: use `CUS-XXXX:` as prefix
- Not found: determine `feat:` or `fix:` based on changes

### Step 4: Check Staging Area

Run: `git diff --staged --name-only`

**If output is empty** (no staged files):
- Use AskUserQuestion:
  - Question: "No staged files. What to add?"
  - Header: "Stage"
  - Options: "All changes (git add -A)" / "Only tracked (git add -u)" / "Cancel"
- Execute chosen option or abort

**If output is NOT empty** (staged files exist):
- Do NOT ask any questions about staging
- Proceed directly to Step 5

### Step 5: Analyze Changes

Run: `git diff --staged`

Determine commit type (if no ticket):
- **feat**: new files, new functions, added functionality
- **fix**: bug fixes, code deletions, modifications to existing code

Generate brief description (max ~40 chars after prefix).

### Step 6: Execute Commit

Run: `git commit -m "PREFIX: description"`

Report success with the commit message used.
