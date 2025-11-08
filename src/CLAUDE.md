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

## Automatic Code Review

After ANY code modifications or new file creation (using Edit, Write, or NotebookEdit tools), automatically invoke the code-reviewer agent to ensure code quality.

### When to Trigger Code Review

Invoke `code-reviewer` agent automatically after:

1. **Code file modifications:**
   - Any `.go`, `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.rs` file edited or created
   - Configuration files: `Dockerfile`, `docker-compose.yml`, `.yaml`, `.yml`
   - Any file containing executable code

2. **Multiple file changes:**
   - After completing a set of related changes
   - Before marking a task as completed in TodoWrite
   - After implementing a feature or fixing a bug

3. **Exclusions (DO NOT review):**
   - Documentation files: `.md`, `.txt`
   - Configuration files: `.json`, `.toml` (unless they contain logic)
   - This file: `CLAUDE.md` and agent/command definitions

### Code Review Workflow

**Step 1: Complete Code Changes**
- Finish all code modifications
- Run VSCode diagnostics and fix errors/warnings
- Ensure code compiles/runs

**Step 2: Invoke Code Reviewer Agent**

Use the Task tool to launch code-reviewer agent:

```
Task tool:
  description: "Review code changes"
  subagent_type: "general-purpose"
  prompt: "Use the code-reviewer agent from src/agents/code-reviewer.md to review the following files: [list files]. Focus ONLY on modified functions/sections: [list specific functions or line ranges that were changed]. DO NOT review unchanged code. Provide comprehensive analysis including VSCode diagnostics, Context7 best practices validation, security check, and performance assessment."
```

**Important:** Specify exactly what was changed:
- For new files: Review entire file
- For modified files: List specific functions, methods, or line ranges that were edited
- Skip unchanged code to save time and focus on actual changes
- Example: "Review function `handleRequest()` at lines 45-78 and `validateInput()` at lines 120-145 in handler.go"

**Step 3: Apply Review Findings**

When agent completes:
- **Critical issues (🔴):** Fix immediately before proceeding
- **Warnings (🟡):** Fix if time permits, or create follow-up task
- **Suggestions (🟢):** Consider for future improvements
- Document any deferred issues in code comments or TODO items

**Step 4: Re-review if Major Changes**
- If fixing critical issues required significant changes
- Re-invoke code-reviewer to verify fixes
- Ensure no new issues introduced

### Integration with Autonomous Workflow

When executing autonomous workflow (after plan approval):

**In "Verify Results" step:**
```
D. Verify Results
   - Check files were created/modified as expected
   - Verify tests pass (if applicable)
   - Run VSCode diagnostics (automatic after code edits per global instructions)
   - **[NEW] Invoke code-reviewer agent for quality check**
   - Ensure no critical errors remain
```

**In Final Summary Report:**

Add "Code Review Findings" section with:
- Errors count (must be 0)
- Warnings count
- Quality assessment from code-reviewer
- Security findings
- Performance notes

### Best Practices

**DO:**
- ✅ Always invoke code-reviewer after code changes
- ✅ Fix all critical issues before marking tasks complete
- ✅ Include review findings in final summaries
- ✅ Use Context7 integration for framework-specific validation
- ✅ Trust VSCode MCP diagnostics from the agent
- ✅ **Focus review ONLY on modified functions/sections**
- ✅ **Specify exact line ranges or function names that changed**

**DON'T:**
- ❌ Skip code review to save time
- ❌ Ignore critical security findings
- ❌ Mark tasks complete with unresolved errors
- ❌ Review non-code files (documentation, configs)
- ❌ **Review entire files when only small sections changed**
- ❌ **Waste time analyzing unchanged code**

### Example Usage

```markdown
# After implementing a feature:

1. Edit src/handler.go (add new endpoint)
2. Run VSCode diagnostics → fix errors
3. **Invoke code-reviewer agent**
4. Review findings:
   - 🔴 1 SQL injection vulnerability → FIX
   - 🟡 2 performance warnings → FIX
   - 🟢 3 style suggestions → NOTED
5. Apply fixes
6. Re-run code-reviewer → all clear ✅
7. Mark task as completed
```

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

## Skills Integration

This configuration uses Claude Code Skills for specialized development tasks. Skills are automatically activated based on task context.

### Available Skills

**go-development**
- Activates for: Go/Golang code tasks, API development, testing
- Capabilities: Write idiomatic Go code, run tests, apply best practices from Context7
- Triggers: Keywords like "Go", "Golang", "go test", "REST API", ".go files"

**docker-configuration**
- Activates for: Docker and containerization tasks
- Capabilities: Create optimized Dockerfiles, docker-compose.yml, multi-stage builds
- Triggers: Keywords like "Docker", "Dockerfile", "docker-compose", "containerize"

**kubernetes-deployment**
- Activates for: Kubernetes deployment and configuration
- Capabilities: Create K8s manifests, Helm charts, validate configurations
- Triggers: Keywords like "Kubernetes", "K8s", "kubectl", "Helm", "deployment"

**code-review**
- Activates for: Code quality and security analysis
- Capabilities: Read-only review using VSCode diagnostics, security analysis, best practices check
- Triggers: Keywords like "review code", "check errors", "code quality", "security review"

### How Skills Work

Skills are automatically invoked when you:
1. Ask questions or give commands matching Skill descriptions
2. Work with files relevant to a Skill's domain
3. Use trigger keywords in your requests

You don't need to explicitly call Skills - they activate automatically based on context.

### Best Practices

1. **Use Natural Language**: Describe what you want, and appropriate Skills will activate
2. **Include Context**: Mention relevant technologies (Go, Docker, K8s) to help Skill selection
3. **Trust Automation**: Skills handle Context7 integration, VSCode diagnostics, and best practices automatically

## Autonomous Workflow Execution

After you present a plan and the user approves it, automatically become an orchestrator and execute the plan:

### 1. Create TodoWrite List

Break the approved plan into specific, actionable subtasks:
- Order tasks by dependencies (e.g., code before Docker before K8s)
- Use imperative form: "Implement health check endpoint", "Create Dockerfile", "Run tests"
- Include verification steps: "Verify all tests pass", "Check diagnostics"

### 2. Execute Each Task

For each task in TodoWrite:

**A. Mark as In Progress**
- Update TodoWrite to show current task as `in_progress`

**B. Describe Task Naturally**
- Describe what needs to be done using natural language
- Include technology keywords to trigger appropriate Skills:
  - For Go code: mention "Go", "implement", "handler", "test"
  - For Docker: mention "Docker", "Dockerfile", "containerize"
  - For K8s: mention "Kubernetes", "deployment", "manifest"
  - For review: mention "review code", "check errors", "analyze quality"
- Skills will activate automatically based on description matching

**C. Wait for Skill Completion**
- Skills execute with their own instructions and tools
- Monitor Skill output and results

**D. Verify Results**
- Check files were created/modified as expected
- Verify tests pass (if applicable)
- Run VSCode diagnostics (automatic after code edits per global instructions)
- **Invoke code-reviewer agent for comprehensive quality check**
- Apply all critical fixes from code review
- Ensure no critical errors remain

**E. Mark as Completed**
- Update TodoWrite to mark task as `completed`
- **ONLY mark complete when fully done** - not if there are errors
- Move to next task

### 3. Final Summary Report

After all tasks completed, create comprehensive summary in this format:

```markdown
# Task Completion Summary

## Overview
{Brief description of what was accomplished}

## Completed Tasks
- ✅ {Task 1}
- ✅ {Task 2}
- ✅ {Task 3}

## Files Modified/Created

### {Category 1 - e.g., Go Code}
- [{file.go}](path/to/file.go) - {description}
- [{file_test.go}](path/to/file_test.go) - {description}

### {Category 2 - e.g., Docker}
- [{Dockerfile}](Dockerfile) - {description}

### {Category 3 - e.g., Kubernetes}
- [{deployment.yaml}](k8s/deployment.yaml) - {description}

## Test Results
- Go tests: ✅ {X tests passed}
- Docker build: ✅ {status}
- K8s validation: ✅ {status}

## Code Review Findings

### Errors: {count}
{List if any, or "None"}

### Warnings: {count}
{List if any, or "None"}

### Quality Assessment
{Brief assessment}

## Quality Metrics
- VSCode Diagnostics: {errors/warnings count}
- Security: {assessment}
- Performance: {assessment}
- Best Practices: {assessment}

## Next Steps
1. {Recommendation 1}
2. {Recommendation 2}
3. {Recommendation 3}
```

### Important Guidelines

**DO:**
- ✅ Create detailed TodoWrite lists for tracking
- ✅ Describe tasks naturally with technology keywords for Skill activation
- ✅ Verify each step before moving forward
- ✅ Mark todos as completed immediately after finishing
- ✅ Create comprehensive final summaries
- ✅ Handle errors gracefully
- ✅ Use Context7 for best practices
- ✅ Run VSCode diagnostics after code changes
- ✅ Fix all errors and warnings automatically
- ✅ **Invoke code-reviewer agent after all code modifications**
- ✅ **Fix all critical issues identified by code-reviewer**

**DON'T:**
- ❌ Skip verification steps
- ❌ Mark tasks complete if there are errors
- ❌ Move to next task if current one failed
- ❌ Forget to update TodoWrite status
- ❌ Create incomplete summaries
- ❌ **Skip code review to save time**
- ❌ **Ignore security vulnerabilities from code-reviewer**

### Fallback

If automatic workflow doesn't start after plan approval, user can manually trigger it with `/auto-execute` command.
