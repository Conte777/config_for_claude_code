# Global Instructions

## Context7 Integration

Always use Context7 when I need:
- Code generation
- Code explanations
- Setup or configuration steps
- Library/API documentation

This means you should automatically use the Context7 MCP tools to resolve library ID and get library docs without me having to explicitly ask.

## Sequential Thinking

Always use the MCP sequential-thinking tool for:
- Breaking down complex tasks into smaller, manageable steps
- Planning implementation before writing code
- Analyzing multi-step problems
- Tasks that require careful step-by-step reasoning

When I provide a task request:
1. First use `mcp__sequential-thinking__sequentialthinking` to decompose and plan the approach
2. Use the tool to think through:
   - What needs to be done
   - The logical sequence of steps
   - Potential challenges or edge cases
   - Alternative approaches if needed
3. After completing the sequential thinking process, proceed with implementation

Do this proactively for any non-trivial task without requiring explicit requests. Use sequential thinking before starting work on complex features, refactoring, or problem-solving tasks.

## Go Code Review

After writing, editing, or generating any Go code (.go files):

1. Complete the code changes
2. Automatically launch the Task tool with `subagent_type="go-reviewer"`
3. Apply any critical feedback from the review

Do this proactively for all Go code without requiring explicit requests.

## Automatic Error Fixing

When any Bash command fails, encounters errors, or produces unexpected output:

1. Automatically launch the Task tool with `subagent_type="error-fixer"`
2. Provide the error-fixer agent with:
   - The command that failed
   - The error output
   - Any relevant context about what you were trying to achieve
3. Apply the fixes suggested by the agent

Do this proactively for all failed commands without requiring explicit requests.

## Code Comments

Rules for writing comments:

- Write comments ONLY when a function is too complex and its purpose is not clear from its name
- Write comments ONLY when a variable's purpose is not clear from its name
- In all other cases, DO NOT write comments
