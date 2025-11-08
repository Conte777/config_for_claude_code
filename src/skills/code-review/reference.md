# Code Review Reference Guide

## Table of Contents
- [Review Dimensions](#review-dimensions)
- [Analysis Checklists](#analysis-checklists)
- [Common Patterns to Flag](#common-patterns-to-flag)
- [Report Template](#report-template)

## Review Dimensions

### A. Code Quality

**Readability:**
- Clear, descriptive naming for variables, functions, classes
- Logical code structure that's easy to follow
- Comments only when code isn't self-explanatory
- Consistent formatting and style

**Maintainability:**
- Low cyclomatic complexity (< 10 per function)
- DRY principle (Don't Repeat Yourself)
- Clear separation of concerns
- Single Responsibility Principle
- Appropriate abstraction levels

**Organization:**
- Proper package/module structure
- Clear dependencies and imports
- Related code grouped together
- No circular dependencies

**Patterns:**
- Appropriate design patterns for the problem
- Idiomatic code for the language/framework
- No anti-patterns or code smells
- Consistent architecture across codebase

**Consistency:**
- Follows project conventions
- Adheres to style guide (PEP 8, ESLint rules, etc.)
- Naming conventions consistent
- Error handling patterns consistent

### B. Security

**Injection Vulnerabilities:**
- SQL Injection: Check for string concatenation in queries
- Command Injection: Validate user input in system commands
- XSS: Sanitize user input in HTML output
- Path Traversal: Validate file paths

**Authentication/Authorization:**
- Proper authentication mechanisms
- Session management
- Access control checks
- Password storage (hashed, salted)
- Token validation

**Sensitive Data:**
- No hardcoded passwords, API keys, secrets
- Sensitive data encrypted in transit (HTTPS/TLS)
- Sensitive data encrypted at rest
- No secrets in logs
- Proper data sanitization

**Input Validation:**
- All user input validated
- Whitelist validation preferred
- Type checking
- Length/range validation
- Sanitization before use

**Dependencies:**
- No known vulnerabilities in packages
- Dependencies up to date
- Minimal dependencies
- Trusted sources only

**OWASP Top 10:**
- Broken Access Control
- Cryptographic Failures
- Injection
- Insecure Design
- Security Misconfiguration
- Vulnerable Components
- Authentication Failures
- Software and Data Integrity Failures
- Security Logging Failures
- SSRF

### C. Performance

**Algorithms:**
- Appropriate time complexity (avoid O(n²) when O(n log n) or O(n) possible)
- Appropriate space complexity
- Efficient data structures chosen
- No unnecessary computations in loops

**Database:**
- No N+1 query problems
- Proper indexing
- Efficient queries
- Connection pooling
- Query result pagination

**Memory:**
- No memory leaks
- Unnecessary object creation avoided
- Large objects not kept in memory unnecessarily
- Proper garbage collection considerations
- Streaming for large data

**Concurrency:**
- No race conditions
- No deadlocks
- Proper synchronization
- Thread-safe code
- Appropriate use of async/await

**Caching:**
- Appropriate caching strategy
- Cache invalidation handled
- Cache hit/miss ratio considerations
- No caching of sensitive data

**Resource Management:**
- Connections closed properly
- File handles released
- Database transactions committed/rolled back
- Proper cleanup in finally blocks
- No resource exhaustion

### D. Error Handling

**Completeness:**
- All error cases handled
- No empty catch blocks
- No swallowed exceptions
- Appropriate error types caught

**Context:**
- Errors include helpful messages
- Stack traces preserved
- Error context logged
- User-friendly messages

**Propagation:**
- Errors properly propagated up stack
- Errors logged at appropriate level
- Don't re-throw same exception
- Wrap exceptions with context

**Recovery:**
- Graceful degradation when possible
- Fallback mechanisms
- Retry logic for transient failures
- Circuit breakers for cascading failures

**User Experience:**
- User-friendly error messages (not technical details)
- No sensitive information in error messages
- Clear actionable guidance
- Appropriate error codes/status

### E. Testing

**Coverage:**
- Critical paths have tests
- Business logic tested
- Edge cases covered
- Error cases tested
- Integration points tested

**Test Quality:**
- Tests are meaningful
- Not just testing for coverage numbers
- Tests verify behavior, not implementation
- Clear arrange-act-assert structure

**Edge Cases:**
- Boundary values tested
- Null/undefined/empty tested
- Large inputs tested
- Concurrent access tested

**Isolation:**
- Tests are independent
- No shared state between tests
- Can run in any order
- Mocks/stubs used appropriately
- External dependencies isolated

**Clarity:**
- Test names describe what's tested
- Clear given-when-then structure
- Easy to understand failures
- No complex logic in tests

### F. Best Practices

**Go:**
- Errors explicitly handled (never ignored)
- Interfaces used appropriately (small, focused)
- Goroutines have clear ownership and termination
- Context used for cancellation/timeouts
- defer used for cleanup
- No panic in library code

**TypeScript/JavaScript:**
- Proper type annotations (avoid `any`)
- Async/await used correctly
- Promises handled properly (no unhandled rejections)
- Event listeners cleaned up
- `===` used instead of `==`
- Modern ES6+ features used appropriately

**Python:**
- Type hints provided
- Context managers used for resources
- List comprehensions vs loops (appropriate choice)
- Exceptions vs error codes
- PEP 8 compliance
- Virtual environments used

**Docker:**
- Multi-stage builds
- Non-root user
- Minimal base images
- Specific version tags
- No secrets in images
- .dockerignore used

**Kubernetes:**
- Resource limits set
- Health checks configured
- Security context set
- Non-root user
- Read-only filesystem where possible
- Proper labels and selectors

## Analysis Checklists

### Security Checklist

- [ ] No hardcoded secrets or credentials
- [ ] Input validation on all user inputs
- [ ] SQL queries use parameterized queries (not string concatenation)
- [ ] Authentication/authorization properly implemented
- [ ] Sensitive data properly encrypted
- [ ] CORS configured correctly (if web app)
- [ ] Rate limiting implemented (if API)
- [ ] Dependencies scanned for vulnerabilities
- [ ] No eval() or similar dangerous functions
- [ ] File uploads validated and restricted
- [ ] CSRF protection (if web app)
- [ ] Secure headers set (CSP, HSTS, etc.)
- [ ] Logging doesn't expose sensitive data

### Performance Checklist

- [ ] No obvious N+1 query problems
- [ ] Efficient algorithms used (appropriate Big O)
- [ ] Proper database indexing
- [ ] Resource cleanup (connections, files, handles)
- [ ] Caching used where appropriate
- [ ] No unnecessary synchronous operations
- [ ] Concurrency handled correctly
- [ ] Large datasets paginated
- [ ] Memory usage reasonable
- [ ] No infinite loops or recursion without bounds

### Code Quality Checklist

- [ ] Functions are focused and single-purpose
- [ ] Naming is clear and descriptive
- [ ] Comments only where code isn't self-explanatory
- [ ] Error handling is comprehensive
- [ ] No code duplication (DRY)
- [ ] Proper abstraction levels
- [ ] Consistent code style
- [ ] Cyclomatic complexity reasonable (< 10)
- [ ] No "magic numbers" without explanation
- [ ] Proper separation of concerns

### Testing Checklist

- [ ] Critical paths have tests
- [ ] Edge cases covered
- [ ] Error cases tested
- [ ] Tests are isolated (no shared state)
- [ ] Test names are descriptive
- [ ] No flaky tests
- [ ] Integration tests for key workflows
- [ ] Mock/stub external dependencies
- [ ] Tests run fast
- [ ] Can run tests in any order

## Common Patterns to Flag

### Anti-Patterns

**God Object/Function:**
- Class or function doing too much
- Violates Single Responsibility Principle
- Hard to test and maintain

**Tight Coupling:**
- Classes/modules too dependent on each other
- Hard to change without breaking other code
- Difficult to test in isolation

**Magic Numbers:**
- Unnamed constants throughout code
- Meaning not clear
- Hard to update

**Overly Complex Conditionals:**
- Deeply nested if statements
- Long boolean expressions
- Hard to understand and test

**Deep Nesting:**
- More than 3 levels of nesting
- Hard to follow logic
- Consider extracting functions

**Long Functions:**
- Functions > 50 lines
- Doing multiple things
- Hard to understand and test

**Long Parameter Lists:**
- Functions with > 5 parameters
- Consider parameter objects
- Indicate function doing too much

**Premature Optimization:**
- Optimizing without profiling
- Sacrificing readability
- Focus on correctness first

**Copy-Paste Programming:**
- Duplicated code
- Violates DRY
- Hard to maintain

### Security Red Flags

**eval() Usage:**
```javascript
// Dangerous
eval(userInput)
```

**String Concatenation in SQL:**
```python
# Bad
query = f"SELECT * FROM users WHERE id = {user_id}"

# Good
query = "SELECT * FROM users WHERE id = %s"
cursor.execute(query, (user_id,))
```

**Unchecked File Uploads:**
```python
# Bad
file.save(request.files['file'].filename)

# Good
if file and allowed_file(file.filename):
    filename = secure_filename(file.filename)
    file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
```

**Missing CSRF Protection:**
```html
<!-- Bad: No CSRF token -->
<form method="POST">

<!-- Good -->
<form method="POST">
  <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
```

**Weak Cryptography:**
```python
# Bad
hashlib.md5(password.encode()).hexdigest()

# Good
bcrypt.hashpw(password.encode(), bcrypt.gensalt())
```

**Exposed Debug Information:**
```python
# Bad in production
app.run(debug=True)
```

**Insufficient Logging:**
- No logging of authentication attempts
- No logging of authorization failures
- No audit trail for sensitive operations

### Performance Red Flags

**N+1 Queries:**
```python
# Bad
users = User.all()
for user in users:
    orders = Order.where(user_id=user.id)  # Query in loop!

# Good
users = User.includes(:orders).all()
```

**Missing Indexes:**
```sql
-- Check queries on unindexed columns
SELECT * FROM users WHERE email = 'user@example.com';
-- Needs index on email column
```

**Synchronous in Async Context:**
```javascript
// Bad
async function processItems(items) {
  items.forEach(item => {
    await process(item);  // await in forEach doesn't work!
  });
}

// Good
async function processItems(items) {
  for (const item of items) {
    await process(item);
  }
  // Or parallel
  await Promise.all(items.map(item => process(item)));
}
```

**Large Objects in Memory:**
```python
# Bad
all_data = db.query("SELECT * FROM large_table")  # Millions of rows

# Good
for batch in db.query("SELECT * FROM large_table").batch(1000):
    process(batch)
```

**No Pagination:**
```javascript
// Bad
GET /api/users  // Returns all users

// Good
GET /api/users?page=1&limit=50
```

**Inefficient String Concatenation:**
```java
// Bad
String result = "";
for (int i = 0; i < 1000; i++) {
    result += i;  // Creates new string each iteration
}

// Good
StringBuilder result = new StringBuilder();
for (int i = 0; i < 1000; i++) {
    result.append(i);
}
```

## Report Template

### Code Review Report

**Executive Summary**
Brief overview of changes reviewed and overall assessment (2-3 sentences).

**Diagnostics Summary**
- **Errors**: X files, Y total errors
- **Warnings**: X files, Y total warnings
- **Info/Hints**: X files, Y total suggestions

**Critical Issues** (🔴 High Priority)
Issues that MUST be fixed before deployment:
1. **[file.go:45] SQL Injection Vulnerability**
   - Description: User input directly concatenated into SQL query
   - Impact: Allows arbitrary SQL execution, data breach risk
   - Recommendation: Use parameterized queries

**Warnings** (🟡 Medium Priority)
Issues that should be addressed soon:
1. **[handler.go:123] Missing Error Handling**
   - Error from database query not checked
   - Recommendation: Add error handling and logging

**Suggestions** (🟢 Low Priority)
Improvements for code quality:
1. **[service.go:78] Function Complexity**
   - Function has cyclomatic complexity of 12
   - Recommendation: Extract smaller functions

**Security Analysis**
- SQL injection vulnerability in user.go:45 (CRITICAL)
- Missing CSRF protection in forms
- No rate limiting on API endpoints
- Overall: **Needs Attention** - Critical issues present

**Performance Analysis**
- N+1 query in service.go:156
- Missing database index on users.email
- Large file loaded entirely into memory
- Overall: **Needs Improvement** - Multiple optimization opportunities

**Best Practices Compliance**
- ✅ Error handling generally good
- ✅ Tests present for critical paths
- ❌ Some functions too long (> 50 lines)
- ❌ Magic numbers without constants
- Overall: **Good** with room for improvement

**Test Coverage Assessment**
- Critical paths tested: Yes
- Edge cases covered: Partial
- Error cases tested: Yes
- Recommendations: Add tests for edge cases in payment processing

**Files Reviewed**
- `user.go` (234 lines)
- `handler.go` (456 lines)
- `service.go` (789 lines)
- Total: 3 files, 1479 lines

**Overall Assessment**
- Code Quality: **Good**
- Security: **Needs Attention**
- Performance: **Needs Improvement**
- Testing: **Good**

**Key Strengths:**
- Well-structured code organization
- Comprehensive error handling
- Good test coverage of critical paths

**Key Areas for Improvement:**
- Fix SQL injection vulnerability (CRITICAL)
- Optimize database queries (N+1 problem)
- Add CSRF protection

**Recommended Next Steps:**
1. Fix SQL injection vulnerability immediately
2. Add database index on users.email
3. Implement rate limiting on API
4. Refactor long functions in service.go

## Troubleshooting

### VSCode Diagnostics Issues

**No diagnostics returned**
```bash
# Check VSCode MCP server is running
# Verify workspace_path is absolute and correct

# For git modified files
mcp__vscode-mcp__get_diagnostics
  workspace_path: /absolute/path/to/workspace
  filePaths: []  # Empty for git modified

# For specific files
mcp__vscode-mcp__get_diagnostics
  workspace_path: /absolute/path/to/workspace
  filePaths: ["src/main.go", "src/handler.go"]
```

**"workspace not found"**
- Ensure workspace_path is absolute (not relative)
- Check path exists and is correct
- Verify VSCode is open with that workspace

**Diagnostics incomplete**
- Language server may still be initializing
- Wait a moment and retry
- Check file is saved
- Verify file extension is recognized

### LSP Tool Issues

**"symbol not found"**
```bash
# Provide code snippet to disambiguate
mcp__vscode-mcp__get_symbol_lsp_info
  workspace_path: <path>
  filePath: "handler.go"
  symbol: "UserHandler"
  codeSnippet: "type UserHandler struct"
```

**No type information**
- Symbol might not be indexed yet
- File may have syntax errors preventing analysis
- Check language server is running for file type

**References not showing**
- Verify symbol name is exact (case-sensitive)
- Check includeDeclaration parameter
- File might not be in workspace scope

### Analysis Challenges

**Large codebase overwhelming**
- Focus on modified files first (use git status)
- Review by module/component
- Prioritize high-risk areas (auth, payment, data handling)
- Use filePaths parameter to limit scope

**Conflicting diagnostics from different sources**
- Prioritize by source: TypeScript > ESLint > Prettier
- Security issues (ESLint security plugins) are critical
- Some warnings may be style preferences

**Too many low-priority issues**
- Filter by severity: focus on "error" and "warning" first
- Group similar issues
- Suggest bulk fixes (e.g., "add type annotations to all functions")

### Report Generation Issues

**Unclear what to prioritize**
Priority order:
1. Security vulnerabilities (SQL injection, XSS, etc.)
2. Errors preventing compilation/runtime
3. Performance issues causing user impact
4. Code quality issues affecting maintainability

**How to rate severity**
- 🔴 Critical: Security issues, data loss risk, crashes
- 🟡 Warning: Performance problems, code smells, missing tests
- 🟢 Suggestion: Style issues, minor optimizations, documentation

**Balancing detail vs brevity**
- Executive summary: 2-3 sentences
- List top 3-5 issues per category
- Link to detailed sections for comprehensive analysis
- Use code examples sparingly (only for critical issues)

### Language-Specific Challenges

**Go code review**
- Watch for: unhandled errors, goroutine leaks, race conditions
- Use: VSCode diagnostics + `go vet` output
- Check: defer usage, context propagation, interface design

**TypeScript/JavaScript**
- Watch for: `any` types, unhandled promises, unused variables
- Use: TypeScript errors + ESLint warnings
- Check: async/await patterns, type safety, null handling

**Python**
- Watch for: missing type hints, mutable defaults, exception handling
- Use: Pylint/Flake8 diagnostics
- Check: PEP 8 compliance, security (SQL injection), imports

### Common False Positives

**"Unused variable" but it's intentional**
- Used for side effects
- Required by interface
- Reserved for future use
- Note in report as acceptable with reason

**"Complex function" for legitimate business logic**
- Some domains are inherently complex
- Check if complexity can be reduced with better abstraction
- If not, suggest adding documentation instead

**"Missing tests" for generated code**
- Generated code often doesn't need tests
- Focus test coverage on hand-written business logic
- Note in report if applicable

### Performance Tips for Reviews

**Reviewing large changesets efficiently**
1. Start with diagnostics summary (get_diagnostics)
2. Read modified files in order of importance
3. Use symbol info for complex types
4. Use references before suggesting refactoring
5. Focus on high-impact issues first

**When to dive deeper**
- Security-sensitive code (auth, payments, data handling)
- Complex business logic
- Performance-critical paths
- Public APIs
- Database queries

**When to skip details**
- Auto-generated code
- Minor style inconsistencies
- Low-risk areas
- Well-tested utility functions

### Report Credibility

**Avoiding false negatives**
- Don't assume code is safe without checking
- Test SQL queries for injection
- Check all user input validation
- Verify error handling completeness
- Look for TODOs and FIXMEs

**Supporting claims with evidence**
- Reference specific line numbers
- Show code examples
- Explain WHY something is a problem
- Suggest concrete solutions
- Link to documentation/best practices

**Handling uncertainty**
- Mark uncertain findings as "Potential issue"
- Explain what additional info is needed
- Suggest further investigation steps
- Don't report something as critical if unsure
