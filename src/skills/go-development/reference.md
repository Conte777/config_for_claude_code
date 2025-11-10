# Go Development Reference Guide

## Table of Contents
- [Error Handling Best Practices](#error-handling-best-practices)
- [Testing Patterns](#testing-patterns)
- [REST API Development](#rest-api-development)
- [Concurrency Patterns](#concurrency-patterns)
- [Package Organization](#package-organization)
- [VSCode Integration](#vscode-integration)
- [Performance Tips](#performance-tips)

## Error Handling Best Practices

### Basic Principles

1. **Never ignore errors**
```go
// Bad
data, _ := os.ReadFile("file.txt")

// Good
data, err := os.ReadFile("file.txt")
if err != nil {
    return fmt.Errorf("reading file: %w", err)
}
```

2. **Wrap errors with context**
```go
if err := processData(data); err != nil {
    return fmt.Errorf("processing data for user %s: %w", userID, err)
}
```

3. **Use error wrapping (%w) for error chain**
```go
// Allows errors.Is() and errors.As()
return fmt.Errorf("database query failed: %w", err)
```

### Custom Error Types

```go
type ValidationError struct {
    Field string
    Value interface{}
    Msg   string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation error: %s - %s (value: %v)", e.Field, e.Msg, e.Value)
}

// Usage
if age < 0 {
    return &ValidationError{
        Field: "age",
        Value: age,
        Msg:   "must be non-negative",
    }
}
```

### Error Checking

```go
// Check for specific error
if errors.Is(err, sql.ErrNoRows) {
    // Handle not found
}

// Check error type
var valErr *ValidationError
if errors.As(err, &valErr) {
    // Handle validation error
}
```

### Panic vs Error

```go
// Use errors for expected failure modes
func validateInput(input string) error {
    if input == "" {
        return errors.New("input cannot be empty")
    }
    return nil
}

// Panic only for programmer errors or truly exceptional conditions
func mustConnect(url string) *sql.DB {
    db, err := sql.Open("postgres", url)
    if err != nil {
        panic(err)  // Only in init() or main()
    }
    return db
}
```

## Testing Patterns

### Table-Driven Tests

```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive numbers", 2, 3, 5},
        {"negative numbers", -2, -3, -5},
        {"mixed numbers", 2, -3, -1},
        {"zero", 0, 0, 0},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := Add(tt.a, tt.b)
            if result != tt.expected {
                t.Errorf("Add(%d, %d) = %d; want %d", tt.a, tt.b, result, tt.expected)
            }
        })
    }
}
```

### Subtests

```go
func TestUser(t *testing.T) {
    t.Run("Create", func(t *testing.T) {
        user := NewUser("John")
        if user.Name != "John" {
            t.Errorf("expected John, got %s", user.Name)
        }
    })

    t.Run("Update", func(t *testing.T) {
        user := NewUser("John")
        user.Update("Jane")
        if user.Name != "Jane" {
            t.Errorf("expected Jane, got %s", user.Name)
        }
    })
}
```

### Mocking

```go
// Interface for dependency
type UserStore interface {
    Get(id string) (*User, error)
    Save(user *User) error
}

// Mock implementation
type MockUserStore struct {
    users map[string]*User
}

func (m *MockUserStore) Get(id string) (*User, error) {
    user, ok := m.users[id]
    if !ok {
        return nil, errors.New("user not found")
    }
    return user, nil
}

// Test using mock
func TestUserService(t *testing.T) {
    store := &MockUserStore{
        users: map[string]*User{
            "1": {ID: "1", Name: "John"},
        },
    }

    service := NewUserService(store)
    user, err := service.GetUser("1")
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    if user.Name != "John" {
        t.Errorf("expected John, got %s", user.Name)
    }
}
```

### Test Fixtures

```go
func setupTest(t *testing.T) (*sql.DB, func()) {
    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        t.Fatalf("failed to open db: %v", err)
    }

    // Setup schema
    if err := db.Exec(schema); err != nil {
        t.Fatalf("failed to create schema: %v", err)
    }

    // Return cleanup function
    return db, func() {
        db.Close()
    }
}

func TestDatabase(t *testing.T) {
    db, cleanup := setupTest(t)
    defer cleanup()

    // Use db for testing
}
```

### Testing HTTP Handlers

```go
func TestHandler(t *testing.T) {
    req := httptest.NewRequest("GET", "/users/123", nil)
    w := httptest.NewRecorder()

    handler := UserHandler()
    handler.ServeHTTP(w, req)

    if w.Code != http.StatusOK {
        t.Errorf("expected status 200, got %d", w.Code)
    }

    var user User
    if err := json.Unmarshal(w.Body.Bytes(), &user); err != nil {
        t.Fatalf("failed to unmarshal response: %v", err)
    }

    if user.ID != "123" {
        t.Errorf("expected ID 123, got %s", user.ID)
    }
}
```

## REST API Development

### Basic Handler Pattern

```go
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
    id := chi.URLParam(r, "id")

    user, err := h.userService.Get(r.Context(), id)
    if err != nil {
        if errors.Is(err, ErrNotFound) {
            http.Error(w, "user not found", http.StatusNotFound)
            return
        }
        http.Error(w, "internal error", http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(user)
}
```

### Middleware

```go
// Logging middleware
func LoggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()

        // Wrap ResponseWriter to capture status code
        wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

        next.ServeHTTP(wrapped, r)

        log.Printf("%s %s %d %v", r.Method, r.URL.Path, wrapped.statusCode, time.Since(start))
    })
}

// Recovery middleware
func RecoveryMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        defer func() {
            if err := recover(); err != nil {
                log.Printf("panic: %v\n%s", err, debug.Stack())
                http.Error(w, "internal server error", http.StatusInternalServerError)
            }
        }()
        next.ServeHTTP(w, r)
    })
}
```

### Request/Response Types

```go
type CreateUserRequest struct {
    Name  string `json:"name" validate:"required,min=2"`
    Email string `json:"email" validate:"required,email"`
    Age   int    `json:"age" validate:"required,min=0,max=150"`
}

type UserResponse struct {
    ID        string    `json:"id"`
    Name      string    `json:"name"`
    Email     string    `json:"email"`
    CreatedAt time.Time `json:"created_at"`
}

func (h *Handler) CreateUser(w http.ResponseWriter, r *http.Request) {
    var req CreateUserRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "invalid request body", http.StatusBadRequest)
        return
    }

    if err := h.validator.Struct(req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    user, err := h.userService.Create(r.Context(), req)
    if err != nil {
        http.Error(w, "failed to create user", http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(UserResponse{
        ID:        user.ID,
        Name:      user.Name,
        Email:     user.Email,
        CreatedAt: user.CreatedAt,
    })
}
```

### Router Setup

```go
func NewRouter(userHandler *UserHandler) http.Handler {
    r := chi.NewRouter()

    // Middleware
    r.Use(middleware.Logger)
    r.Use(middleware.Recoverer)
    r.Use(middleware.RequestID)
    r.Use(middleware.Timeout(60 * time.Second))

    // Routes
    r.Route("/api/v1", func(r chi.Router) {
        r.Route("/users", func(r chi.Router) {
            r.Get("/", userHandler.List)
            r.Post("/", userHandler.Create)
            r.Route("/{id}", func(r chi.Router) {
                r.Get("/", userHandler.Get)
                r.Put("/", userHandler.Update)
                r.Delete("/", userHandler.Delete)
            })
        })
    })

    return r
}
```

## Concurrency Patterns

### Goroutine Patterns

```go
// Worker pool
func processItems(items []Item) {
    const numWorkers = 10
    jobs := make(chan Item, len(items))
    results := make(chan Result, len(items))

    // Start workers
    for w := 0; w < numWorkers; w++ {
        go worker(jobs, results)
    }

    // Send jobs
    for _, item := range items {
        jobs <- item
    }
    close(jobs)

    // Collect results
    for i := 0; i < len(items); i++ {
        result := <-results
        // Process result
    }
}

func worker(jobs <-chan Item, results chan<- Result) {
    for item := range jobs {
        results <- process(item)
    }
}
```

### Context Usage

```go
func (s *Service) FetchData(ctx context.Context, id string) (*Data, error) {
    // Create timeout context
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()

    // Make request with context
    req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
    if err != nil {
        return nil, err
    }

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    // Process response
    var data Data
    if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
        return nil, err
    }

    return &data, nil
}
```

### Select with Context

```go
func (s *Service) DoWork(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case work := <-s.workChan:
            if err := s.process(work); err != nil {
                return err
            }
        }
    }
}
```

## Package Organization

### Standard Layout

```
myproject/
├── cmd/
│   └── myapp/
│       └── main.go          # Application entrypoint
├── internal/
│   ├── handler/             # HTTP handlers
│   ├── service/             # Business logic
│   ├── store/               # Data access
│   └── model/               # Domain models
├── pkg/                     # Public libraries
├── api/                     # API definitions (OpenAPI, protobuf)
├── migrations/              # Database migrations
├── scripts/                 # Build/deploy scripts
├── go.mod
├── go.sum
└── README.md
```

### Package Guidelines

1. **One package, one purpose**
2. **internal/ for private code**
3. **pkg/ for reusable libraries**
4. **Avoid circular dependencies**
5. **Keep packages small and focused**

## VSCode Integration

### Get Diagnostics

```go
// Run after code changes
mcp__vscode-mcp__get_diagnostics
  workspace_path: <absolute path>
  filePaths: ["main.go", "handler.go"]
  severities: ["error", "warning"]
```

### Get Symbol Info

```go
// Understand type definitions
mcp__vscode-mcp__get_symbol_lsp_info
  workspace_path: <path>
  filePath: "handler.go"
  symbol: "UserHandler"
  infoType: "all"
```

### Find References

```go
// Before refactoring
mcp__vscode-mcp__get_references
  workspace_path: <path>
  filePath: "service.go"
  symbol: "GetUser"
  includeDeclaration: true
```

## Performance Tips

### Avoid Allocations in Hot Paths

```go
// Bad - creates new slice each time
func process(items []int) []int {
    result := []int{}
    for _, item := range items {
        result = append(result, item*2)
    }
    return result
}

// Good - preallocate
func process(items []int) []int {
    result := make([]int, 0, len(items))
    for _, item := range items {
        result = append(result, item*2)
    }
    return result
}
```

### Use sync.Pool for Reusable Objects

```go
var bufferPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func processData(data []byte) []byte {
    buf := bufferPool.Get().(*bytes.Buffer)
    defer bufferPool.Put(buf)

    buf.Reset()
    buf.Write(data)
    // Process buffer
    return buf.Bytes()
}
```

### Benchmark Tests

```go
func BenchmarkProcess(b *testing.B) {
    data := generateTestData()

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        process(data)
    }
}

// Run with: go test -bench=. -benchmem
```

## Dependency Management

### Common Commands

```bash
# Initialize module
go mod init github.com/user/project

# Add dependency
go get github.com/gin-gonic/gin@latest

# Update dependencies
go get -u ./...

# Tidy (remove unused, add missing)
go mod tidy

# Vendor dependencies
go mod vendor

# Why is package needed
go mod why github.com/some/package

# Graph of dependencies
go mod graph
```

### go.mod Best Practices

```go
module github.com/user/project

go 1.21

require (
    github.com/gin-gonic/gin v1.9.1
    github.com/lib/pq v1.10.9
)

// Pin specific version
replace github.com/old/package => github.com/new/package v1.2.3

// Use local version for development
// replace github.com/my/package => ../my/package
```

## Troubleshooting

### Build Errors

**"cannot find package"**
```bash
# Solution: Download missing dependencies
go mod download
go mod tidy
```

**"imported but not used"**
- Remove unused imports or use blank import `_ "package"` if needed for side effects
- Use `goimports` to auto-manage imports

**"undefined: X"**
- Check package is imported
- Verify capitalization (exported names start with uppercase)
- Run `go mod tidy` to sync dependencies

### Test Failures

**"race condition detected"**
```bash
# Run with race detector to find issues
go test -race ./...

# Fix by using proper synchronization
sync.Mutex, sync.RWMutex, channels, atomic operations
```

**"timeout exceeded"**
- Increase timeout: `go test -timeout 5m`
- Check for infinite loops or blocking operations
- Use context.WithTimeout in tests

**"connection refused" in tests**
- Use httptest.Server for HTTP tests
- Use mocks for external dependencies
- Check port availability

### Module Issues

**"go.sum mismatch"**
```bash
# Regenerate go.sum
rm go.sum
go mod tidy
```

**"incompatible version"**
- Check for breaking changes in dependency
- Pin to compatible version: `go get package@v1.2.3`
- Use replace directive if needed

**"ambiguous import"**
- Use import alias: `import alias "package/path"`
- Avoid conflicting package names

### Performance Issues

**High memory usage**
- Profile with: `go test -memprofile mem.prof`
- Check for memory leaks (unclosed connections, goroutine leaks)
- Use `sync.Pool` for reusable objects
- Preallocate slices with make([]T, 0, capacity)

**Slow performance**
- Profile with: `go test -cpuprofile cpu.prof`
- Analyze with: `go tool pprof cpu.prof`
- Check for inefficient algorithms (O(n²))
- Avoid unnecessary allocations in hot paths

**Goroutine leaks**
```bash
# Check goroutine count
runtime.NumGoroutine()

# Profile goroutines
go tool pprof http://localhost:6060/debug/pprof/goroutine
```
- Always provide exit conditions for goroutines
- Use context for cancellation
- Close channels when done

### VSCode Integration Issues

**"diagnostics not showing"**
- Verify VSCode MCP server running
- Check workspace_path is correct
- Run `go mod tidy` to sync dependencies
- Restart Go language server

**"symbol not found"**
- Run `gopls` language server: `gopls check path/to/file.go`
- Clear gopls cache: delete `~/.cache/gopls`
- Verify file is in module

### Common Runtime Errors

**panic: nil pointer dereference**
- Check for nil before dereferencing
- Use safe navigation patterns
- Add nil checks in critical paths

**deadlock**
- Avoid circular channel dependencies
- Don't hold locks while blocking
- Use buffered channels or select with timeout

**context deadline exceeded**
- Increase timeout if operation legitimately slow
- Check for blocking operations
- Verify network connectivity
