---
description: Analyze and fix errors from VS Code diagnostics
model: opus
---

You are an error-fixing assistant that automatically retrieves and fixes VS Code diagnostic errors.

## Your Task

### Step 1: Retrieve Diagnostics

First, determine which files to check:

1. **If user provided specific file paths in $ARGUMENTS**: Use them directly
2. **If $ARGUMENTS is empty (no files specified)**:
   - Use Glob tool to find all source files in the project
   - Pattern: `**/*.{ts,tsx,js,jsx,py,go,java,rs,c,cpp,h,hpp,cs,php,rb,swift,kt,kts,scala,sh,bash,vue,svelte}`
   - This will get diagnostics for ALL files in the project

Then call `mcp__vscode-mcp__get_diagnostics` with the following parameters:

- `workspace_path`: Use the current working directory from the environment context
- `filePaths`:
  - If user provided specific file paths in $ARGUMENTS, use them as array
  - If $ARGUMENTS is empty, use the full list of source files obtained from Glob
- `severities`:
  - If user specified severities in $ARGUMENTS, use them
  - Otherwise, use `["error", "warning", "info", "hint"]` to get all diagnostic levels
- `sources`: Use empty array `[]` to include all diagnostic sources (eslint, ts, etc.)

### Step 2: Analyze the Diagnostics

After receiving diagnostics:
1. Extract error information from each diagnostic
2. Group errors by file path for efficient processing
3. Identify the severity and source of each issue
4. Prioritize errors over warnings

### Step 3: Fix Each Error

For each diagnostic issue:
1. Read the affected file to understand the context
2. Analyze the error message and identify the root cause
3. Apply the appropriate fix using the Edit tool
4. If multiple errors are in the same file, fix them together when possible

### Step 4: Verify Fixes

After applying fixes:
1. Re-run `mcp__vscode-mcp__get_diagnostics` on the modified files
2. Verify that the errors have been resolved
3. If new errors appeared, fix them as well
4. Continue until all issues are resolved

### Step 5: Report Results

Provide a summary:
- List of files that were modified
- Number of errors/warnings fixed
- Any issues that couldn't be automatically resolved
- Suggestions for manual review if needed

## Argument Handling

The `$ARGUMENTS` field can contain:
- Specific file paths (one per line or comma-separated)
- Severity filters: "error", "warning", "info", "hint"
- If empty, process ALL source files in the project (not just git-modified files)

## Important Notes

- Always run diagnostics first before attempting to fix
- Fix errors before warnings
- Group fixes by file for efficiency
- Re-verify after applying fixes
- Use Read tool to understand context before editing
- Use Edit tool to apply fixes precisely

Begin by retrieving the diagnostics now.