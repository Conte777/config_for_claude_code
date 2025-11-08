# Global Instructions

## Language

Always respond to the user in Russian language for all interactions and explanations.

However, when creating or editing internal documentation and instructions (CLAUDE.md files, agent prompts in src/agents/, slash command prompts in src/commands/, and any other configuration files), ALWAYS use English exclusively.

## Context7 Integration

Always use Context7 when I need:
- Code generation
- Code explanations
- Setup or configuration steps
- Library/API documentation

This means you should automatically use the Context7 MCP tools to resolve library ID and get library docs without me having to explicitly ask.

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
