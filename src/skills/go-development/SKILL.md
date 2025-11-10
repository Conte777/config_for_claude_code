---
name: go-development
description: Expert Go/Golang development: writing idiomatic code, REST APIs, gRPC services, microservices, CLI tools, HTTP handlers, middleware, routers, concurrency with goroutines, channels, context, sync primitives, error handling, interfaces, structs, pointers, defer, panic, recover, testing with go test, table-driven tests, benchmarking, mocking, test coverage, go mod, go mod tidy, go get, go fmt, go vet, delve debugging, pprof profiling, net/http, database/sql, JSON/XML/YAML encoding, HTTP clients, WebSocket, logging (zap, zerolog, logrus), metrics (Prometheus), tracing (OpenTelemetry), graceful shutdown, signal handling, generics, reflection, build tags, cross-compilation. Use when user asks to write, modify, refactor, debug, test, optimize Go code, mentions Golang, Go modules, go test, go build, go run, go install, GraphQL, Gin, Echo, Chi, Fiber, GORM, sqlc, sqlx, Cobra, Viper, select, waitgroups, mutexes, dependency injection, clean architecture, hexagonal architecture, .go files. (project, gitignored)
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(go test:*), Bash(go build:*), Bash(go mod:*), Bash(go run:*), Bash(go fmt:*), Bash(go vet:*), mcp__context7__resolve-library-id, mcp__context7__get-library-docs, mcp__vscode-mcp__get_diagnostics, mcp__vscode-mcp__get_symbol_lsp_info, mcp__vscode-mcp__get_references
---

# Go Development Skill

Expert-level Go development with best practices from Context7, VSCode diagnostics integration, and comprehensive testing.

## Workflow

### 1. Research Best Practices

Use Context7 for up-to-date Go best practices:
- Resolve library ID for relevant packages (`/golang/go`, `/gin-gonic/gin`, `/gorilla/mux`)
- Get documentation for API patterns, error handling, testing, performance

### 2. Write Idiomatic Go Code

Follow Go conventions and best practices:

**Error Handling:**
- Always handle errors explicitly (never ignore with `_`)
- Wrap errors with context: `fmt.Errorf("context: %w", err)`
- Return errors, don't panic (except truly exceptional cases)

**Code Structure:**
- Organize by domain/functionality
- Clear, descriptive names following Go conventions
- Comments only when code purpose isn't clear from names
- Small, focused interfaces
- Write tests alongside code

**Key Principles:**
- Keep functions small and focused
- Avoid deep nesting (> 3 levels)
- Use table-driven tests
- Handle concurrency with channels and context

For detailed best practices and patterns, see [reference.md](reference.md)

For complete code examples (REST API, testing, concurrency), see [examples.md](examples.md)

### 3. Testing

Run tests after writing code:

```bash
# Run all tests
go test ./...

# Verbose output
go test -v ./path/to/package

# Race detection (for concurrency)
go test -race ./...

# Coverage
go test -cover ./...
```

**If tests fail:**
- Analyze failure output
- Fix the issue
- Re-run tests
- Repeat until all pass

**Test patterns:**
- Table-driven tests for multiple scenarios
- Use `t.Run()` for subtests
- Mock external dependencies
- Test error cases, not just happy paths

For testing examples, see [reference.md](reference.md#testing-patterns) and [examples.md](examples.md#table-driven-test-example)

### 4. Code Validation

Use VSCode diagnostics to catch issues:

**Get diagnostics:**
```
mcp__vscode-mcp__get_diagnostics
  workspace_path: <absolute path>
  filePaths: ["main.go", "handler.go"]
  severities: ["error", "warning"]
```

**For type errors:**
```
mcp__vscode-mcp__get_symbol_lsp_info
  workspace_path: <path>
  filePath: "handler.go"
  symbol: "UserHandler"
```

**Before refactoring:**
```
mcp__vscode-mcp__get_references
  workspace_path: <path>
  filePath: "service.go"
  symbol: "GetUser"
```

**Fix all errors and warnings** before marking task complete.

### 5. Code Formatting

Always format and vet code:

```bash
# Format code
go fmt ./...

# Lint and check for issues
go vet ./...
```

## Common Patterns

**REST API Development:**
- Standard library `net/http` or frameworks (Gin, Echo, Chi)
- Middleware for logging, recovery, auth
- Clean handler → service → store separation
- Use `context.Context` for request-scoped values

**Error Handling:**
- Wrap errors with context
- Custom error types when needed
- Use `errors.Is()` and `errors.As()`

**Concurrency:**
- Worker pools for parallel processing
- Context for cancellation and timeouts
- Channels for communication
- `sync` package for synchronization

**Testing:**
- Table-driven tests
- Subtests with `t.Run()`
- Mocks for external dependencies
- Test fixtures for setup/teardown

For detailed patterns and examples, see [reference.md](reference.md) and [examples.md](examples.md)

## Dependency Management

```bash
# Initialize module
go mod init github.com/user/project

# Add dependency
go get github.com/gin-gonic/gin@latest

# Update dependencies
go get -u ./...

# Clean up unused, add missing
go mod tidy

# Vendor dependencies
go mod vendor
```

## Quality Checklist

Before marking task complete:
- [ ] All tests pass (`go test ./...`)
- [ ] No compilation errors
- [ ] No linter warnings (`go vet ./...`)
- [ ] Code formatted (`go fmt ./...`)
- [ ] VSCode diagnostics show no errors
- [ ] Error handling is comprehensive
- [ ] Follows Go conventions and idioms
- [ ] Tests cover critical paths and edge cases

## Reference Materials

- [reference.md](reference.md) - Comprehensive Go guide
  - Error handling best practices
  - Testing patterns (table-driven, mocks, fixtures)
  - REST API development
  - Concurrency patterns
  - Package organization
  - VSCode integration
  - Performance tips
  - Dependency management

- [examples.md](examples.md) - Complete code examples
  - Full REST API implementation (handlers, services, models)
  - Table-driven test examples
  - Error handling examples
  - Concurrency patterns (worker pools, context, pipelines)
  - Middleware examples (logging, recovery, auth)

## Dependencies

- Go toolchain installed
- Context7 MCP server configured (for best practices)
- VSCode MCP server configured (for diagnostics and LSP)
