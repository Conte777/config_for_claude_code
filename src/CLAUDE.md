# Global Instructions

## Language

Always respond in Russian language for all interactions, explanations, and documentation.

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

## VSCode Diagnostics

After editing or writing any code files (using Edit or Write tools):

1. Automatically run `mcp__vscode-mcp__get_diagnostics`
2. Provide the following parameters:
   - `workspace_path`: The absolute path to the workspace
   - `filePaths`: Array with the files that were just modified (or empty array for all git modified files)
   - `severities`: Include all severities by default ["error", "warning", "info", "hint"]
3. If any errors or warnings are found:
   - Analyze each diagnostic
   - Fix all errors and warnings automatically
   - Apply fixes immediately without asking for confirmation
4. Re-run diagnostics after fixes to ensure all issues are resolved

Do this proactively for all code edits without requiring explicit requests.

## Code Navigation

When searching for code elements, analyzing dependencies, or fixing type errors:

1. Use `mcp__vscode-mcp__get_symbol_lsp_info` to:
   - Get type definitions and documentation for symbols
   - Understand function signatures and parameters
   - Retrieve interface and type information
   - Analyze symbol declarations before making changes

2. Use `mcp__vscode-mcp__get_references` to:
   - Find all usages of a symbol before renaming or refactoring
   - Understand code dependencies and relationships
   - Identify impact scope of changes
   - Locate all places that need updates

3. Prefer these LSP tools over Grep/Glob when:
   - You need precise type information
   - Working with TypeScript/JavaScript symbols
   - Fixing type errors or doing refactoring
   - Analyzing code structure and dependencies

These tools provide IDE-quality intelligence and should be used whenever accurate code navigation is needed.

## Code Comments

Rules for writing comments:

- Write comments ONLY when a function is too complex and its purpose is not clear from its name
- Write comments ONLY when a variable's purpose is not clear from its name
- In all other cases, DO NOT write comments
