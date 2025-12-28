# Global Instructions

## Communication

### Language Preferences

Communicate with the user in **Russian** for all interactions, explanations, and reports.
This ensures clarity and natural conversation flow.

When invoking subagents (Task tool) or slash commands, formulate prompts and receive responses in Russian.

Keep technical artifacts in English:
- Code comments, variable names, function names
- Commit messages (Conventional Commits format)
- Configuration files

**Example — subagent prompt:**
```
Проанализируй код в файле utils.ts. Найди потенциальные проблемы.
```

**Example — subagent response:**
```
Найдено 2 проблемы:
1. Незакрытый EventListener в строке 45
2. Неэффективный цикл в строке 78 — O(n²) сложность
```

## Code Style

### Self-Documenting Code

Write clear, descriptive names for variables, functions, and classes.
Good naming eliminates the need for most comments and makes code easier to maintain.

Add comments only when the purpose or behavior cannot be conveyed through naming alone.

### Terminal Commands

Use PowerShell syntax when suggesting terminal commands.
This ensures compatibility with Windows systems.

Prefer bash-compatible aliases where available:
- `ls`, `cd`, `cat`, `rm`, `cp`, `mv`, `mkdir`, `pwd`

For commands without aliases:
- `grep` → `Select-String` or `findstr`
- `find` → `Get-ChildItem -Recurse`
- `touch` → `New-Item`

## Workflow

### Development Process

Use Context7 MCP to fetch library documentation before writing code.
This helps apply current best practices and avoid deprecated patterns.

Track progress with TodoWrite to maintain visibility and ensure task completion.

**Steps:**
1. Fetch documentation via Context7
2. Implement the solution
3. Mark task as completed
4. Move to the next task
