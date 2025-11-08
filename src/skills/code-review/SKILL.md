---
name: code-review
description: Comprehensive read-only code review analyzing code quality, security vulnerabilities, performance issues, best practices compliance, and VSCode diagnostics. Use when user asks to review code, check for errors, analyze code quality, mentions security review, or wants feedback on their code.
allowed-tools: Read, Grep, Glob, mcp__vscode-mcp__get_diagnostics, mcp__vscode-mcp__get_symbol_lsp_info, mcp__vscode-mcp__get_references
---

# Code Review Skill

Comprehensive read-only code review with IDE-quality diagnostics from VSCode MCP, analyzing quality, security, performance, and best practices compliance.

**IMPORTANT**: This is a READ-ONLY Skill. Never modify files. Only analyze and report findings.

## Workflow

### 1. Determine Scope

If no specific scope provided:
- Ask user which files/directories to review
- Or review all recently modified files (git status)

### 2. Gather Diagnostics

Use VSCode MCP for comprehensive diagnostics:

```
mcp__vscode-mcp__get_diagnostics
  workspace_path: <absolute path>
  filePaths: []  # Empty for all git modified files
  severities: ["error", "warning", "info", "hint"]
  sources: []  # All sources (eslint, ts, etc.)
```

**Diagnostic severity levels:**
- **Errors** (0): Critical issues preventing compilation/execution
- **Warnings** (1): Potential problems to address
- **Info** (2): Suggestions for improvement
- **Hints** (3): Minor style/convention suggestions

### 3. Read and Analyze Code

Read all files in scope to understand:
- Code structure and organization
- Logic implementation
- Error handling patterns
- Testing coverage
- Documentation quality

### 4. Perform Multi-Dimensional Analysis

Analyze code across these dimensions:

**Code Quality:**
- Readability, maintainability, organization
- Design patterns, idiomatic code
- Consistency with project conventions

**Security:**
- Injection vulnerabilities (SQL, XSS, Command)
- Authentication/authorization
- Hardcoded secrets
- Input validation
- OWASP Top 10 vulnerabilities

**Performance:**
- Algorithm efficiency
- Database queries (N+1 problems)
- Memory usage
- Concurrency issues
- Caching opportunities

**Error Handling:**
- Completeness of error handling
- Error context and propagation
- Graceful degradation
- User-friendly messages

**Testing:**
- Coverage of critical paths
- Edge cases and error cases
- Test quality and isolation
- Clear test descriptions

**Best Practices:**
- Language-specific patterns (Go, TypeScript, Python, etc.)
- Framework conventions
- Container best practices (Docker, Kubernetes)

For detailed checklists and criteria, see [reference.md](reference.md)

### 5. Use LSP Tools

For type errors or unclear code:

**Get symbol information:**
```
mcp__vscode-mcp__get_symbol_lsp_info
  workspace_path: <path>
  filePath: <file>
  symbol: <symbol name>
  infoType: "all"
```

**Find symbol usage:**
```
mcp__vscode-mcp__get_references
  workspace_path: <path>
  filePath: <file>
  symbol: <symbol name>
  includeDeclaration: true
```

### 6. Generate Structured Report

Create comprehensive but concise report with:

**Executive Summary:**
Brief overview (2-3 sentences) of changes and overall assessment

**Diagnostics Summary:**
Count of errors, warnings, info, hints

**Issues by Priority:**
- 🔴 Critical (MUST fix before deployment)
- 🟡 Warnings (should address soon)
- 🟢 Suggestions (code quality improvements)

**Analysis Sections:**
- Security Analysis (vulnerabilities, overall rating)
- Performance Analysis (bottlenecks, optimizations)
- Best Practices Compliance (what's good, what needs work)
- Test Coverage Assessment

**Overall Assessment:**
- Code quality rating (Excellent / Good / Needs Improvement / Poor)
- Key strengths
- Key areas for improvement
- Recommended next steps

For complete report template and examples, see [reference.md](reference.md#report-template)

## Common Issues to Flag

**Anti-Patterns:**
- God objects/functions (doing too much)
- Tight coupling
- Magic numbers
- Deep nesting (> 3 levels)
- Long functions (> 50 lines)
- Long parameter lists (> 5 params)

**Security Red Flags:**
- `eval()` usage
- String concatenation in SQL
- Unchecked file uploads
- Missing CSRF protection
- Weak cryptography (MD5, SHA1 for passwords)
- Exposed debug information

**Performance Red Flags:**
- N+1 queries
- Missing database indexes
- Synchronous in async context
- Large objects in memory
- No pagination
- Inefficient string concatenation in loops

For detailed patterns and examples, see [reference.md](reference.md#common-patterns-to-flag)

## Output Guidelines

**Format:**
- Use markdown with clear headings
- Priority indicators: 🔴 🟡 🟢
- File references with line numbers: `file.go:123`
- Code blocks for examples

**Tone:**
- Professional and objective
- Focus on facts, not opinions
- Explain "why" not just "what"
- Suggest solutions, not just problems

**Prioritization:**
- Security issues first
- Then errors preventing functionality
- Then performance issues
- Then code quality improvements

## Quality Checklist

Before completing review:
- [ ] VSCode diagnostics analyzed
- [ ] All files in scope read
- [ ] Security vulnerabilities checked
- [ ] Performance issues identified
- [ ] Error handling reviewed
- [ ] Test coverage assessed
- [ ] Best practices verified
- [ ] Report is structured and clear
- [ ] Recommendations are actionable
- [ ] Priority clearly indicated

## Reference Materials

- [reference.md](reference.md) - Comprehensive review guide
  - Review dimensions (Quality, Security, Performance, Error Handling, Testing)
  - Analysis checklists (Security, Performance, Code Quality, Testing)
  - Common anti-patterns and red flags
  - Complete report template with examples

## Dependencies

- VSCode MCP server configured (for diagnostics and LSP)
- Access to workspace files for analysis
