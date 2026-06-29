# Personal instructions (all projects)

## Language
- Communication, explanations, and work commentary — in Russian.
- Code, identifiers, commits, branch names, and technical artifacts — in English.

## Workflow
- Before writing code against a library/framework, check current docs via
  context7, even for popular ones (your knowledge may be stale).
- Don't consider a task done until tests and linters have run. Report failures
  honestly, with the command output.
- `git push`, force-push, and any action on protected branches (main/master) —
  only after explicit confirmation.
- Commit/branch via `mcp__git__commit` / `mcp__git__branch` only when explicitly
  asked; the server generates the message — never pass your own. Protected
  branches need `allowProtectedBranch` (commit) only after the user agrees.
- Be extremely concise. Sacrifice grammar for the sake of concision.