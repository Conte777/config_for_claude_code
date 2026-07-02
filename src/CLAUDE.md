# Personal instructions (all projects)

## Language
- Communication, explanations, and work commentary — in Russian.
- Code, identifiers, commits, branch names, and technical artifacts — in English.
- Be extremely concise. Sacrifice grammar for the sake of concision.

## Workflow
- Before writing code against a library/framework, check current docs via context7, even for popular ones (your knowledge may be stale).
- Don't consider a task done until tests and linters have run. Report failures honestly, with the command output.
- Commit/branch only when explicitly asked, via `mcp__git__commit` / `mcp__git__branch` (a hook blocks raw git for these). `allowProtectedBranch` only after the user agrees.

## Code style
- No obvious comments. Comment only non-obvious constraints or the "why" the code can't express — never narrate what the next line does.