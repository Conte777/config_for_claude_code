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

## Coding Rules (Mandatory)

Before planning, writing, modifying, or reviewing any Go, Java, or Python code, you
MUST load the `coding-rules` skill. This is non-negotiable — it applies to design
discussions, implementation plans, one-line changes, typo fixes in code, or quick
experiments alike.

This includes any planning activity that produces concrete code-shape decisions:
sketching APIs/signatures, choosing patterns or libraries, drafting implementation
plans (including in plan mode), or proposing refactors — load the rules before
making such recommendations, not after.

Order of loading:
1. `coding-rules/references/common.md` (always)
2. Language-specific `patterns.md` (Go/Java/Python — based on the file you touch
   or the language being planned for)
3. Framework/library references that match the project (fx, gRPC, kafka, redis,
   http, postgres, observability, migrations, validation, testing, etc.)

If you find yourself planning or writing code without having loaded coding-rules
first, stop and load them.

## Commits (Mandatory)

All commits MUST be created through the `commit` skill (full pre-commit workflow:
staging checks, protected branch validation, message generation) or, when only a
commit message is needed, through the `commit-msg` skill.

Never craft commit messages manually or run `git commit` directly without invoking
one of these skills — they ensure ticket ID extraction, Conventional Commits format,
and project-specific validation.

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
