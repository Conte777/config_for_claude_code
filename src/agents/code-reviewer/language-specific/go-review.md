# Go Code Review Guide

This guide provides Go-specific patterns, idioms, anti-patterns, and best practices for code review.

## Go Idioms and Best Practices

### Error Handling

**✅ Good Practices:**
```go
// Return errors, don't panic
func readConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("failed to read config: %w", err)
    }
    // ...
}

// Wrap errors with context using %w
if err := saveData(data); err != nil {
    return fmt.Errorf("saving user %d: %w", userID, err)
}
```

**❌ Anti-Patterns:**
```go
// DON'T: Panic for regular errors
func readConfig(path string) *Config {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(err) // ❌ Don't panic
    }
    // ...
}

// DON'T: Ignore errors
data, _ := os.ReadFile(path) // ❌ Error ignored

// DON'T: Lose error context
if err != nil {
    return fmt.Errorf("failed: %v", err) // ❌ Use %w, not %v
}
```

### Goroutines and Concurrency

**✅ Good Practices:**
```go
// Use sync.WaitGroup for goroutine coordination
var wg sync.WaitGroup
for _, item := range items {
    wg.Add(1)
    go func(i Item) {
        defer wg.Done()
        process(i)
    }(item) // Pass item as argument to avoid closure issues
}
wg.Wait()

// Use context for cancellation
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

// Check context in long-running operations
select {
case <-ctx.Done():
    return ctx.Err()
case result := <-resultChan:
    return result
}
```

**❌ Anti-Patterns:**
```go
// DON'T: Forget to pass loop variable
for _, item := range items {
    go func() {
        process(item) // ❌ Closure captures loop variable
    }()
}

// DON'T: Ignore goroutine leaks
go func() {
    for {
        // ❌ No way to stop this goroutine
        doWork()
    }
}()

// DON'T: Share memory without synchronization
// Multiple goroutines modifying shared variable
counter++ // ❌ Race condition
```

### Interface Usage

**✅ Good Practices:**
```go
// Accept interfaces, return structs
func ProcessData(r io.Reader) (*Result, error) {
    // ...
}

// Small, focused interfaces
type Saver interface {
    Save(data []byte) error
}

// Interface defined by consumer, not provider
type UserService interface {
    GetUser(id int) (*User, error)
}
```

**❌ Anti-Patterns:**
```go
// DON'T: Interface pollution (too many methods)
type Database interface {
    Connect() error
    Disconnect() error
    Query() error
    Insert() error
    Update() error
    Delete() error
    // ❌ Too many methods
}

// DON'T: Return interfaces from functions
func NewService() UserService { // ❌ Return concrete type instead
    return &service{}
}
```

### Nil Checks and Pointers

**✅ Good Practices:**
```go
// Check for nil before dereferencing
if user != nil && user.Address != nil {
    fmt.Println(user.Address.City)
}

// Use pointers for large structs or when nil is meaningful
type Config struct {
    Timeout *time.Duration // nil means "use default"
}
```

**❌ Anti-Patterns:**
```go
// DON'T: Dereference without nil check
city := user.Address.City // ❌ Panic if user or Address is nil

// DON'T: Unnecessary pointers for small types
func setFlag(flag *bool) { // ❌ Use bool, not *bool
    *flag = true
}
```

### Defer Usage

**✅ Good Practices:**
```go
// Defer cleanup operations
func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close() // ✅ Always closed, even on error

    // Process file
}

// Defer in loops: be careful
func processFiles(paths []string) error {
    for _, path := range paths {
        func() error {
            f, err := os.Open(path)
            if err != nil {
                return err
            }
            defer f.Close() // ✅ Deferred per iteration
            // Process
        }()
    }
}
```

**❌ Anti-Patterns:**
```go
// DON'T: Defer in loops without function wrapper
for _, path := range paths {
    f, err := os.Open(path)
    if err != nil {
        continue
    }
    defer f.Close() // ❌ All defers execute at end of function
    // This causes resource leaks
}

// DON'T: Defer Close() before checking error
f, err := os.Open(path)
defer f.Close() // ❌ Panic if f is nil
if err != nil {
    return err
}
```

## Go Security Patterns

### Input Validation

**✅ Good Practices:**
```go
// Validate and sanitize user input
func validateEmail(email string) error {
    if len(email) > 255 {
        return errors.New("email too long")
    }
    matched, _ := regexp.MatchString(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`, email)
    if !matched {
        return errors.New("invalid email format")
    }
    return nil
}

// Use whitelisting, not blacklisting
func isValidAction(action string) bool {
    validActions := map[string]bool{
        "read": true, "write": true, "delete": true,
    }
    return validActions[action]
}
```

### SQL Injection Prevention

**✅ Good Practices:**
```go
// ALWAYS use parameterized queries
rows, err := db.Query("SELECT * FROM users WHERE id = ?", userID)

// With named parameters
rows, err := db.Query(
    "SELECT * FROM users WHERE email = :email",
    sql.Named("email", email),
)
```

**❌ Anti-Patterns:**
```go
// DON'T: String concatenation in SQL
query := "SELECT * FROM users WHERE id = " + userID // ❌ SQL injection
rows, err := db.Query(query)

// DON'T: fmt.Sprintf for SQL
query := fmt.Sprintf("SELECT * FROM users WHERE email = '%s'", email) // ❌
```

### Authentication/Authorization

**✅ Good Practices:**
```go
// Use crypto/rand for tokens, not math/rand
import "crypto/rand"

func generateToken() (string, error) {
    b := make([]byte, 32)
    if _, err := rand.Read(b); err != nil {
        return "", err
    }
    return base64.URLEncoding.EncodeToString(b), nil
}

// Hash passwords with bcrypt
import "golang.org/x/crypto/bcrypt"

func hashPassword(password string) (string, error) {
    hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
    if err != nil {
        return "", err
    }
    return string(hash), nil
}
```

## Go Performance Patterns

### Avoid Allocations

**✅ Good Practices:**
```go
// Preallocate slices when size is known
users := make([]User, 0, expectedCount)

// Reuse buffers
var buf bytes.Buffer
buf.Reset() // Reuse instead of creating new buffer

// Use sync.Pool for frequently allocated objects
var bufferPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}
```

**❌ Anti-Patterns:**
```go
// DON'T: Grow slices repeatedly
var users []User
for _, id := range ids {
    users = append(users, getUser(id)) // ❌ Reallocations
}

// DON'T: String concatenation in loops
var result string
for _, s := range strings {
    result += s // ❌ Creates new string each iteration
}
// Use strings.Builder or bytes.Buffer instead
```

### Channel and Select Patterns

**✅ Good Practices:**
```go
// Buffered channels for known capacity
ch := make(chan int, 100)

// Non-blocking send
select {
case ch <- value:
    // Sent
default:
    // Channel full, handle
}

// Timeout pattern
select {
case result := <-ch:
    // Got result
case <-time.After(5 * time.Second):
    return errors.New("timeout")
}
```

## Code Organization

### Package Structure

**✅ Good Practices:**
- Use flat structure, avoid deep nesting
- Package names: lowercase, single word, no underscores
- Exported names start with uppercase
- Unexported helpers start with lowercase

**❌ Anti-Patterns:**
```go
// DON'T: Generic package names
package utils    // ❌ Too generic
package helpers  // ❌ Too generic
package common   // ❌ Too generic

// DON'T: Stutter in names
user.UserService // ❌ Use user.Service instead
```

### Testing Patterns

**✅ Good Practices:**
```go
// Table-driven tests
func TestValidateEmail(t *testing.T) {
    tests := []struct {
        name    string
        email   string
        wantErr bool
    }{
        {"valid", "user@example.com", false},
        {"invalid", "invalid", true},
        {"empty", "", true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := validateEmail(tt.email)
            if (err != nil) != tt.wantErr {
                t.Errorf("validateEmail() error = %v, wantErr %v", err, tt.wantErr)
            }
        })
    }
}
```

## Common Review Checklist

When reviewing Go code, check for:

- [ ] Errors are checked and properly wrapped (%w)
- [ ] No goroutine leaks (goroutines can be stopped)
- [ ] Mutexes are unlocked (defer mu.Unlock())
- [ ] Resources are cleaned up (defer Close())
- [ ] No race conditions (use go run -race)
- [ ] SQL queries use parameters, not concatenation
- [ ] crypto/rand used for security tokens, not math/rand
- [ ] Passwords are hashed, not stored plaintext
- [ ] Slices preallocated when size is known
- [ ] Interfaces are small and focused
- [ ] Exported names have documentation comments
- [ ] Test coverage for critical paths
