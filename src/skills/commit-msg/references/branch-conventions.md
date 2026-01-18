# Branch Naming Conventions

This document describes branch naming patterns and ticket ID extraction rules.

## Ticket ID Pattern

The workflow searches for ticket IDs using the following pattern:

```regex
(?i)(CUS-\d+)
```

**Pattern breakdown:**
- `(?i)` — case insensitive matching
- `CUS-` — literal prefix "CUS-"
- `\d+` — one or more digits

**Examples of matching:**
- `CUS-1234/add-feature` → `CUS-1234`
- `cus-5678-fix-bug` → `CUS-5678`
- `feature/CUS-9012/new-component` → `CUS-9012`
- `CUS-42` → `CUS-42`

**Non-matching examples:**
- `feature/add-login` → no ticket ID
- `fix-null-pointer` → no ticket ID
- `main` → no ticket ID

## Recommended Branch Format

```
CUS-{number}/{short-description}
```

**Examples:**
```
CUS-1234/add-user-auth
CUS-5678/fix-payment-bug
CUS-9012/refactor-api-client
```

## Protected Branches

The following branches are considered protected:

| Branch | Purpose |
|--------|---------|
| `main` | Production branch |
| `master` | Production branch (legacy) |
| `develop` | Development integration branch |
| `stage` | Staging environment |
| `staging` | Staging environment (alternative) |

**Matching:** Case insensitive exact match.

When committing to a protected branch, the workflow will:
1. Display a warning
2. Ask for confirmation before proceeding

## Branch Types (Informational)

Common branch prefixes (not enforced, for reference):

| Prefix | Purpose |
|--------|---------|
| `feature/` | New features |
| `fix/` | Bug fixes |
| `hotfix/` | Urgent production fixes |
| `refactor/` | Code refactoring |
| `docs/` | Documentation changes |
| `test/` | Test additions or fixes |

## Ticket ID Extraction Priority

If multiple ticket IDs appear in a branch name, the first match is used:

```
CUS-1234/CUS-5678/feature → CUS-1234
```

## Detached HEAD State

When in detached HEAD state:
- Branch name will be the short commit hash (e.g., `abc1234`)
- No ticket ID will be extracted
- Warning `DETACHED_HEAD` will be issued

This typically occurs when:
- Checking out a specific commit
- During rebase operations
- After certain merge operations
