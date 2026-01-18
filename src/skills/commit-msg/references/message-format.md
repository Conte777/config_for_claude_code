# Commit Message Format

This document defines the strict format for commit messages in this workflow.

## Structure

```
{PREFIX}: {description}
```

A commit message consists of:
- **PREFIX**: Ticket ID or type indicator
- **Colon and space**: `: ` separator
- **description**: Lowercase description of the change

## Allowed Prefixes

Only these prefixes are allowed:

| Prefix | Usage | Example |
|--------|-------|---------|
| `CUS-XXXX:` | When ticket ID is available | `CUS-1234: add auth endpoint` |
| `feat:` | New functionality (no ticket) | `feat: impl user dashboard` |
| `fix:` | Bug fix (no ticket) | `fix: null check in handler` |

**Priority:** If ticket ID is available, always use `CUS-XXXX:` prefix.

## Constraints

| Rule | Value |
|------|-------|
| Maximum length | 50 characters |
| Line count | 1 (header only) |
| Description case | lowercase |
| Trailing period | none |
| Language | English |

## Abbreviations

Use these abbreviations to stay within 50 characters:

| Full | Abbreviation |
|------|--------------|
| `and` | `&` |
| `or` | `\|` |
| `implementation` | `impl` |
| `authentication` | `auth` |
| `configuration` | `config` |
| `update` | `upd` |
| `delete` | `del` |
| `function` | `fn` |
| `message` | `msg` |
| `request` | `req` |
| `response` | `res` |
| `database` | `db` |
| `repository` | `repo` |
| `parameters` | `params` |
| `initialization` | `init` |

## Examples

### Good Messages

```
CUS-1234: add user auth endpoint
CUS-5678: fix null check in payment service
CUS-9012: upd config for redis connection
feat: impl login & signup forms
feat: add user dashboard component
fix: handle empty response in api client
fix: resolve race condition in cache
```

### Bad Messages (and why)

```
CUS-1234: Add user authentication endpoint.
         ^ uppercase    ^ too long    ^ period

feat: This commit adds a new feature for users
      ^ uppercase  ^ too long

Fixed the bug
^ no prefix, past tense

CUS-1234
^ no description
```

## Character Counting

The 50-character limit includes:
- Prefix (`CUS-1234:` = 9 characters)
- Space after colon (1 character)
- Description (remaining characters)

**Example calculation:**
```
CUS-1234: add user auth endpoint
|---9---|1|-------17---------|
Total: 27 characters (within limit)
```

## Multi-word Descriptions

- Use spaces between words
- No special formatting (no dashes, underscores)
- Start with verb in imperative mood: add, fix, update, remove, refactor

## Scope (Optional)

If needed, scope can be added in parentheses:

```
CUS-1234: (api) add auth endpoint
feat: (ui) impl login form
```

However, prefer keeping messages simple without scope when possible.
