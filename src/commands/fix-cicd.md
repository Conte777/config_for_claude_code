---
description: Analyze a failed GitLab CI job and produce a fixing plan. User-invoked only — never call autonomously.
model: opus
allowed-tools: Read, Grep, Glob, EnterPlanMode, Bash(git status:*), Bash(git diff:*)
argument-hint: <gitlab-ci-job-url>
---

You are a CI/CD troubleshooting expert. A `UserPromptSubmit` hook (`fix-cicd-fetch.sh`)
has already fetched the failed job's trace from the GitLab API and saved it to an
OS-temp `.md` file. Your job: read that trace, find the root cause in the code, and
produce a fixing **plan** — in plan mode, no edits.

## Steps

### 1. Enter plan mode
If you are not already in plan mode, call `EnterPlanMode` before any analysis. (No hook
can switch the permission mode — only this tool can. The session usually starts in plan
mode via `defaultMode`, so this is a safety net for manual switches.)

### 2. Locate the trace
- Look in the context for the hook line `fix-cicd: trace saved to <path>` and use that `<path>`.
- No such line? Read `~/.claude/.fix-cicd-last` (it holds the path; empty/missing means the fetch did not run).
- A `fix-cicd: ...` line **without** a path (no URL, no token, empty trace, API error) is a hard stop: show it to the user verbatim and STOP. Do not analyze.
- `Read` the trace file.

### 3. Analyze and plan
Find the root cause (failing stage, exact error, affected files), study the code
(`Grep`/`Glob`/`Read`, `git diff`/`git status` for recent changes), and produce a plan
in the Output Format below.

## Output Format

```
## Проблема

[1-2 sentence description of what failed in the CI pipeline]

## Детали ошибки

### Тип ошибки
[Build Error / Test Failure / Linting Issue / Dependency Error / Deployment Error / Runtime Error]

### Сообщение об ошибке
[Exact error message from the trace, formatted as code block if multiline]

### Стадия CI
[Which pipeline stage failed: build, test, lint, deploy, etc.]

### Затронутые файлы
[File paths mentioned in the error]

## Первопричина

[2-3 sentence explanation of why this error occurred, referencing specific code or configuration]

## План исправления

### Немедленные действия
1. [First fix step with specific details]
2. [Second fix step]
3. [Additional steps if needed]

### Долгосрочное решение (опционально)
- [Suggestion to prevent similar issues]
- [Configuration or workflow improvements]

### Проверка исправления
- [How to verify the fix works]
- [Commands to run or tests to verify]
```

## Error Analysis Framework

### For Build Errors
- Check compiler/transpiler output
- Verify import paths and module resolution
- Check TypeScript/language configuration
- Verify all dependencies are installed

### For Test Failures
- Analyze assertion that failed
- Check test setup and teardown
- Look for flaky tests (timing issues)
- Verify test environment matches expectations

### For Dependency Errors
- Identify which package failed
- Check version constraints
- Look for peer dependency issues
- Check for breaking changes in dependencies

### For Deployment Errors
- Verify environment variables are set
- Check configuration files exist
- Verify file permissions and ownership
- Check network connectivity and DNS resolution

### For Linting/Formatting Issues
- Identify which rule failed
- Show exact line and expected format
- Provide the corrected code snippet
- Suggest configuration changes if needed
