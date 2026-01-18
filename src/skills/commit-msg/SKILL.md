---
name: commit-msg
description: Use this skill when the user wants to generate a commit message. Contains workflow for branch checking, ticket ID extraction, and message formatting.
allowed-tools: Bash(git branch *), Bash(git diff *), Read
---

# Commit Message Generator

This skill generates commit messages with proper ticket ID extraction and formatting.

## When to Use

- User runs `/commit` command (called by commit command)
- User asks to generate a commit message
- User needs help with commit message format

## Workflow Steps

### Step 1: Get Branch Name

```bash
git branch --show-current
```

### Step 2: Extract Ticket ID

Extract ticket ID from branch name using pattern `CUS-\d+` (case insensitive).

Examples:
- `CUS-1234/add-feature` → `CUS-1234`
- `feature/CUS-5678-fix-bug` → `CUS-5678`
- `cus-9999-update-docs` → `CUS-9999`

### Step 3: Analyze Changes

Review the staged changes:

```bash
git diff --staged
```

Identify:
1. Type of change (new feature or bug fix)
2. Key files and components affected
3. Main purpose of the changes

### Step 4: Determine Prefix

**If ticket ID found** → use `CUS-XXXX:`

**If no ticket ID** → determine prefix from diff analysis:

| Prefix | Use when changes... |
|--------|---------------------|
| `fix:` | Fix bugs, errors, null checks, edge cases, error handling, typos, broken logic |
| `feat:` | Add new functionality, files, endpoints, components, capabilities |

Analyze the nature of changes — don't ask the user.

### Step 5: Generate Commit Message

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

### Step 6: Return Message

Return the generated commit message to the caller.

## File References

- [Message Format](./references/message-format.md) — Detailed format specification
- [Branch Conventions](./references/branch-conventions.md) — Branch naming rules

## Error Handling

- If git is not initialized, inform the user
- If detached HEAD state, use short commit hash as reference
