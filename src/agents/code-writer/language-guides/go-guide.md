# Go Language Guide

Complete reference for writing idiomatic, production-ready Go code following official guidelines and community best practices.

## Style Guide & Formatting

### Automatic Formatting

**ALWAYS use gofmt** before completing any Go code:
```bash
gofmt -w filename.go
# Or for entire project:
go fmt ./...
```

**Key formatting rules** (enforced by gofmt):
- **Tabs for indentation** (not spaces)
- **Opening braces on same line** as statement
- **No line length limit** (but break long lines logically)
- **One statement per line** (except simple cases)

### Naming Conventions

#### Packages
- **Short, lowercase, single-word names** without underscores
- **Good**: `http`, `yaml`, `user`, `auth`
- **Bad**: `http_client`, `userService`, `authenticationModule`

#### Exported vs Unexported
- **First character determines visibility**:
  - `UserService` → exported (public)
  - `userService` → unexported (private)

#### Functions and Methods
- **Use MixedCaps**, not underscores
- **Getters**: Omit "Get" prefix → `Owner()` not `GetOwner()`
- **Setters**: Include "Set" prefix → `SetOwner()`

```go
// Good
func (c *Client) Owner() string { return c.owner }
func (c *Client) SetOwner(owner string) { c.owner = owner }

// Bad
func (c *Client) GetOwner() string { return c.owner }
func (c *Client) owner() string { return c.owner }  // unexported
```

#### Interfaces
- **Single-method interfaces**: Use agent noun with "-er" suffix
  - `Reader`, `Writer`, `Formatter`, `Closer`, `Logger`
- **Multi-method interfaces**: Descriptive name without suffix

```go
// Good
type Reader interface {
    Read(p []byte) (n int, err error)
}

type UserRepository interface {
    FindByID(id string) (*User, error)
    Save(user *User) error
    Delete(id string) error
}

// Bad
type ReadInterface interface { ... }
type IUserRepository interface { ... }
```

#### Variables
- **Short names for short scope**:
  - Loop variables: `i`, `j`, `k`
  - Common types: `b` for byte, `r` for reader, `w` for writer
- **Longer names for wider scope**:
  - Package-level variables: descriptive names
  - Struct fields: clear, complete names

```go
// Good
for i, v := range values {
    // i, v are fine for loop scope
}

var defaultTimeout = 30 * time.Second  // package level

// Bad
for index, value := range values {  // too verbose for loop
}
```

#### Avoid Repetition
- **Don't repeat package name in type names**:
  - `yaml.Marshaler` not `yaml.YAMLMarshaler`
  - `log.Logger` not `log.LogLogger`

```go
// Good
package user

type Service struct { ... }  // Used as user.Service

// Bad
package user

type UserService struct { ... }  // Redundant: user.UserService
```

## Idiomatic Patterns

### Error Handling

#### Multiple Return Values

**Standard pattern**: Return `(result, error)` pairs:

```go
// Good
func FindUser(id string) (*User, error) {
    user, err := db.Query("SELECT * FROM users WHERE id = ?", id)
    if err != nil {
        return nil, fmt.Errorf("finding user %s: %w", id, err)
    }
    return user, nil
}

// Usage
user, err := FindUser("123")
if err != nil {
    return err
}
// Use user
```

#### Guard Clauses

**Omit unnecessary else** when body ends with `return`, `break`, `continue`:

```go
// Good - guard clause style
func Divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, errors.New("division by zero")
    }
    return a / b, nil
}

// Bad - unnecessary else
func Divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, errors.New("division by zero")
    } else {
        return a / b, nil
    }
}
```

#### Error Wrapping

**Use `%w` for wrapping errors** (Go 1.13+):

```go
// Good - preserves error chain
func ProcessOrder(id string) error {
    order, err := fetchOrder(id)
    if err != nil {
        return fmt.Errorf("processing order %s: %w", id, err)
    }
    return nil
}

// Can unwrap later:
if errors.Is(err, ErrNotFound) { ... }

// Bad - loses error chain
return fmt.Errorf("processing order %s: %v", id, err)
```

#### Custom Error Types

**For errors that need programmatic inspection**:

```go
type ValidationError struct {
    Field string
    Value interface{}
    Err   error
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed for %s: %v", e.Field, e.Err)
}

func (e *ValidationError) Unwrap() error {
    return e.Err
}

// Usage
func Validate(user *User) error {
    if user.Email == "" {
        return &ValidationError{
            Field: "email",
            Value: user.Email,
            Err:   errors.New("required field"),
        }
    }
    return nil
}
```

### Concurrency Patterns

#### Goroutines and Channels

**Basic goroutine pattern**:

```go
// Launch goroutine
go func() {
    result := doWork()
    // Handle result
}()

// With channels for communication
func worker(jobs <-chan Job, results chan<- Result) {
    for job := range jobs {
        result := process(job)
        results <- result
    }
}

// Usage
jobs := make(chan Job, 100)
results := make(chan Result, 100)

go worker(jobs, results)
```

#### Context for Cancellation

**Always use context for timeout/cancellation**:

```go
func FetchData(ctx context.Context, url string) ([]byte, error) {
    req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
    if err != nil {
        return nil, err
    }

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    return io.ReadAll(resp.Body)
}

// Usage with timeout
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

data, err := FetchData(ctx, "https://api.example.com/data")
```

#### Error Group Pattern

**For parallel operations with error handling**:

```go
import "golang.org/x/sync/errgroup"

func ProcessBatch(items []Item) error {
    g, ctx := errgroup.WithContext(context.Background())

    for _, item := range items {
        item := item  // Capture loop variable
        g.Go(func() error {
            return processItem(ctx, item)
        })
    }

    // Wait for all goroutines, return first error
    return g.Wait()
}
```

#### Channel Patterns

**Fan-out, Fan-in**:

```go
// Fan-out: distribute work to multiple workers
func fanOut(input <-chan int, workers int) []<-chan int {
    channels := make([]<-chan int, workers)
    for i := 0; i < workers; i++ {
        channels[i] = worker(input)
    }
    return channels
}

// Fan-in: combine results from multiple channels
func fanIn(channels ...<-chan int) <-chan int {
    out := make(chan int)
    var wg sync.WaitGroup

    for _, ch := range channels {
        wg.Add(1)
        go func(c <-chan int) {
            defer wg.Done()
            for val := range c {
                out <- val
            }
        }(ch)
    }

    go func() {
        wg.Wait()
        close(out)
    }()

    return out
}
```

**Select with default** (non-blocking):

```go
select {
case msg := <-ch:
    // Received message
    handleMessage(msg)
case <-time.After(1 * time.Second):
    // Timeout
    return errors.New("timeout")
default:
    // No message available, don't block
}
```

## Project Structure

### Standard Layout

```
myproject/
├── cmd/                    # Main applications
│   └── myapp/
│       └── main.go
├── internal/               # Private application code
│   ├── handlers/          # HTTP handlers
│   ├── models/            # Data models
│   ├── services/          # Business logic
│   └── repository/        # Data access
├── pkg/                   # Public libraries (optional)
│   └── utils/
├── api/                   # API definitions (OpenAPI, Proto)
├── web/                   # Web assets
├── configs/               # Configuration files
├── scripts/               # Build, install scripts
├── test/                  # Additional test data
├── go.mod
├── go.sum
└── README.md
```

### Directory Guidelines

**`/cmd`**:
- Contains main applications for the project
- Directory name matches executable name
- Minimal code - mostly imports and invocations

```go
// cmd/myapp/main.go
package main

import (
    "myproject/internal/server"
)

func main() {
    srv := server.New()
    srv.Run()
}
```

**`/internal`**:
- **Private code** - enforced by Go compiler
- Cannot be imported by external projects
- Keep most application code here

**`/pkg`**:
- **Public libraries** that can be imported
- Only use if you actually want external use
- Many modern projects skip this and use `/internal`

**When to use `/cmd`**:
- Multiple binaries → Use `/cmd`
- Single binary → Can put `main.go` in root

### Package Organization

**Good package structure**:

```go
// internal/user/user.go
package user

type User struct { ... }

// internal/user/service.go
package user

type Service struct { ... }

func (s *Service) Create(u *User) error { ... }

// internal/user/repository.go
package user

type Repository struct { ... }

func (r *Repository) Save(u *User) error { ... }
```

**Anti-pattern** (too many packages):

```go
// Don't create packages for every file
// internal/user/user.go          → package user
// internal/userservice/service.go → package userservice
// internal/userrepo/repo.go      → package userrepo
```

## Code Templates

### HTTP Handler (with Gin)

```go
package handlers

import (
    "net/http"
    "github.com/gin-gonic/gin"
    "myproject/internal/services"
)

type UserHandler struct {
    userService *services.UserService
}

func NewUserHandler(us *services.UserService) *UserHandler {
    return &UserHandler{userService: us}
}

func (h *UserHandler) GetUser(c *gin.Context) {
    id := c.Param("id")

    user, err := h.userService.FindByID(c.Request.Context(), id)
    if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusOK, user)
}

func (h *UserHandler) CreateUser(c *gin.Context) {
    var req CreateUserRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    user, err := h.userService.Create(c.Request.Context(), &req)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    c.JSON(http.StatusCreated, user)
}

type CreateUserRequest struct {
    Name  string `json:"name" binding:"required"`
    Email string `json:"email" binding:"required,email"`
}
```

### Service Layer

```go
package services

import (
    "context"
    "fmt"
    "myproject/internal/models"
    "myproject/internal/repository"
)

type UserService struct {
    repo *repository.UserRepository
}

func NewUserService(repo *repository.UserRepository) *UserService {
    return &UserService{repo: repo}
}

func (s *UserService) FindByID(ctx context.Context, id string) (*models.User, error) {
    user, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("finding user %s: %w", id, err)
    }
    return user, nil
}

func (s *UserService) Create(ctx context.Context, req *CreateUserRequest) (*models.User, error) {
    user := &models.User{
        Name:  req.Name,
        Email: req.Email,
    }

    if err := s.validate(user); err != nil {
        return nil, fmt.Errorf("validation failed: %w", err)
    }

    if err := s.repo.Save(ctx, user); err != nil {
        return nil, fmt.Errorf("saving user: %w", err)
    }

    return user, nil
}

func (s *UserService) validate(user *models.User) error {
    if user.Email == "" {
        return fmt.Errorf("email is required")
    }
    return nil
}
```

### Repository/DAO (with GORM)

```go
package repository

import (
    "context"
    "myproject/internal/models"
    "gorm.io/gorm"
)

type UserRepository struct {
    db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
    return &UserRepository{db: db}
}

func (r *UserRepository) FindByID(ctx context.Context, id string) (*models.User, error) {
    var user models.User
    result := r.db.WithContext(ctx).First(&user, "id = ?", id)
    if result.Error != nil {
        return nil, result.Error
    }
    return &user, nil
}

func (r *UserRepository) Save(ctx context.Context, user *models.User) error {
    return r.db.WithContext(ctx).Create(user).Error
}

func (r *UserRepository) Update(ctx context.Context, user *models.User) error {
    return r.db.WithContext(ctx).Save(user).Error
}

func (r *UserRepository) Delete(ctx context.Context, id string) error {
    return r.db.WithContext(ctx).Delete(&models.User{}, "id = ?", id).Error
}
```

## Testing Patterns

### Table-Driven Tests

**Idiomatic Go testing pattern**:

```go
package user

import "testing"

func TestValidateEmail(t *testing.T) {
    tests := []struct {
        name    string
        email   string
        wantErr bool
    }{
        {
            name:    "valid email",
            email:   "user@example.com",
            wantErr: false,
        },
        {
            name:    "missing @",
            email:   "userexample.com",
            wantErr: true,
        },
        {
            name:    "empty email",
            email:   "",
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := ValidateEmail(tt.email)
            if (err != nil) != tt.wantErr {
                t.Errorf("ValidateEmail() error = %v, wantErr %v", err, tt.wantErr)
            }
        })
    }
}
```

### Test Helpers

```go
func TestUserService_Create(t *testing.T) {
    // Setup
    db := setupTestDB(t)
    defer teardownTestDB(t, db)

    repo := repository.NewUserRepository(db)
    service := NewUserService(repo)

    // Test
    user, err := service.Create(context.Background(), &CreateUserRequest{
        Name:  "Test User",
        Email: "test@example.com",
    })

    // Assertions
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    if user.Name != "Test User" {
        t.Errorf("got name %q, want %q", user.Name, "Test User")
    }
}

func setupTestDB(t *testing.T) *gorm.DB {
    t.Helper()
    // Setup test database
    return db
}

func teardownTestDB(t *testing.T, db *gorm.DB) {
    t.Helper()
    // Cleanup
}
```

## Common Anti-Patterns to Avoid

### 1. Ignoring Errors

```go
// Bad
value, _ := someFunction()

// Good
value, err := someFunction()
if err != nil {
    return fmt.Errorf("calling someFunction: %w", err)
}
```

### 2. Not Closing Resources

```go
// Bad
resp, _ := http.Get(url)
body, _ := io.ReadAll(resp.Body)

// Good
resp, err := http.Get(url)
if err != nil {
    return err
}
defer resp.Body.Close()

body, err := io.ReadAll(resp.Body)
if err != nil {
    return err
}
```

### 3. Goroutine Leaks

```go
// Bad - goroutine never exits
func Process() {
    go func() {
        for {
            doWork()
        }
    }()
}

// Good - explicit cancellation
func Process(ctx context.Context) {
    go func() {
        for {
            select {
            case <-ctx.Done():
                return
            default:
                doWork()
            }
        }
    }()
}
```

### 4. Premature Optimization

```go
// Bad - complex before necessary
func Sum(nums []int) int {
    var wg sync.WaitGroup
    result := 0
    mu := sync.Mutex{}

    for _, n := range nums {
        wg.Add(1)
        go func(num int) {
            defer wg.Done()
            mu.Lock()
            result += num
            mu.Unlock()
        }(n)
    }
    wg.Wait()
    return result
}

// Good - simple, clear
func Sum(nums []int) int {
    result := 0
    for _, n := range nums {
        result += n
    }
    return result
}
```

## Quick Reference

### Common Imports

```go
import (
    "context"           // Context for cancellation
    "errors"            // Error handling
    "fmt"               // Formatting
    "io"                // IO operations
    "net/http"          // HTTP client/server
    "time"              // Time operations

    "github.com/gin-gonic/gin"         // Web framework
    "gorm.io/gorm"                     // ORM
    "golang.org/x/sync/errgroup"       // Error groups
)
```

### Error Patterns Quick Reference

```go
// Simple error
return errors.New("something went wrong")

// Formatted error
return fmt.Errorf("processing item %d: failed", id)

// Wrapped error (preserves chain)
return fmt.Errorf("outer context: %w", err)

// Custom error type
type MyError struct { ... }
func (e *MyError) Error() string { ... }
```

### Context Patterns

```go
// With timeout
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()

// With cancellation
ctx, cancel := context.WithCancel(ctx)
defer cancel()

// With value (use sparingly)
ctx = context.WithValue(ctx, keyUserID, userID)
```
