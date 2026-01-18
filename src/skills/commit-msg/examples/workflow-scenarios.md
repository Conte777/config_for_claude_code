# Workflow Scenarios

This document describes common scenarios when using the commit workflow.

## Scenario A: Standard Commit with Ticket ID

**Conditions:**
- Branch: `CUS-1234/add-user-authentication`
- Staged files: 3 files
- No warnings

**Script Output:**
```json
{
  "stagedFiles": ["src/auth.ts", "src/user.ts", "tests/auth.test.ts"],
  "stagedCount": 3,
  "branchName": "CUS-1234/add-user-authentication",
  "ticketId": "CUS-1234",
  "isProtectedBranch": false,
  "warnings": []
}
```

**Workflow:**
1. Skip warning handling (no warnings)
2. Analyze staged changes
3. Generate message: `CUS-1234: add user auth endpoint`
4. Execute commit

---

## Scenario B: Commit to Protected Branch

**Conditions:**
- Branch: `main`
- Staged files: 1 file
- Warnings: `PROTECTED_BRANCH`, `NO_TICKET_ID`

**Script Output:**
```json
{
  "stagedFiles": ["hotfix.ts"],
  "stagedCount": 1,
  "branchName": "main",
  "ticketId": null,
  "isProtectedBranch": true,
  "warnings": ["PROTECTED_BRANCH", "NO_TICKET_ID"]
}
```

**Workflow:**
1. Handle `PROTECTED_BRANCH`:
   - Ask: "You're about to commit to protected branch 'main'. Continue?"
   - If "Cancel" → abort
2. Handle `NO_TICKET_ID`:
   - Ask: "No ticket ID found. Select commit type:"
   - Options: "feat" / "fix" / "Enter CUS-XXXX manually"
3. Generate message with selected prefix
4. Execute commit

---

## Scenario C: No Ticket ID in Branch

**Conditions:**
- Branch: `feature/new-login-form`
- Staged files: 2 files
- Warnings: `NO_TICKET_ID`

**Script Output:**
```json
{
  "stagedFiles": ["src/login.tsx", "src/login.css"],
  "stagedCount": 2,
  "branchName": "feature/new-login-form",
  "ticketId": null,
  "isProtectedBranch": false,
  "warnings": ["NO_TICKET_ID"]
}
```

**Workflow:**
1. Handle `NO_TICKET_ID`:
   - Ask: "No ticket ID found. Select commit type:"
   - User selects "feat"
2. Generate message: `feat: impl login form component`
3. Execute commit

---

## Scenario D: Empty Staging Area

**Conditions:**
- Branch: `CUS-5678/fix-bug`
- Staged files: 0
- Warnings: `EMPTY_STAGING`

**Script Output:**
```json
{
  "stagedFiles": [],
  "stagedCount": 0,
  "branchName": "CUS-5678/fix-bug",
  "ticketId": "CUS-5678",
  "isProtectedBranch": false,
  "warnings": ["EMPTY_STAGING"]
}
```

**Workflow:**
1. Handle `EMPTY_STAGING`:
   - Ask: "Staging area is empty. Add files?"
   - Options: "All files (-A)" / "Tracked only (-u)" / "Cancel"
   - If "Cancel" → abort
2. Run `git add -A` or `git add -u` based on selection
3. Re-run script to refresh state
4. Continue with normal workflow

---

## Scenario E: Detached HEAD State

**Conditions:**
- Branch: (detached at commit abc1234)
- Staged files: 1 file
- Warnings: `DETACHED_HEAD`, `NO_TICKET_ID`

**Script Output:**
```json
{
  "stagedFiles": ["fix.ts"],
  "stagedCount": 1,
  "branchName": "abc1234",
  "ticketId": null,
  "isProtectedBranch": false,
  "warnings": ["DETACHED_HEAD", "NO_TICKET_ID"]
}
```

**Workflow:**
1. Warn user about detached HEAD state
2. Handle `NO_TICKET_ID` as in Scenario C
3. Generate message and execute commit
4. Inform user the commit is not on any branch
