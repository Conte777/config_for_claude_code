---
description: Create and switch to a new branch from ticket ID
allowed-tools: Bash(git switch:*), Bash(git diff:*), Bash(git status:*)
argument-hint: <ticket-id>
---

## Task

Create a new git branch using the provided ticket ID and switch to it.

**Branch naming format:** `{ticket-id}/{brief-description}`

## Instructions

1. **Validate input:**
   - Ticket ID: `$ARGUMENTS`
   - If no ticket ID provided, ask the user

2. **Analyze changes:**
   - Run `git diff` and `git diff --staged` to understand current work
   - If no changes exist, use conversation context or ask user for description

3. **Generate description:**
   - Create 2-4 word description in kebab-case
   - Examples: `add-user-auth`, `fix-login-bug`, `update-api-docs`
   - Keep it concise and descriptive

4. **Create branch:**
   - Execute: `git switch -c {ticket-id}/{description}`
   - Example: `git switch -c CUS-123/add-user-auth`

5. **Report result:**
   - Confirm branch creation
   - Show the full branch name
