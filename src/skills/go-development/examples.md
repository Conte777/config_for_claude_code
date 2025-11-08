# Go Code Examples

## REST API Example

Complete example of a REST API with proper structure:

### main.go
```go
package main

import (
    "context"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/user/project/internal/handler"
    "github.com/user/project/internal/service"
    "github.com/user/project/internal/store"
)

func main() {
    // Initialize dependencies
    db, err := store.NewPostgresDB(os.Getenv("DATABASE_URL"))
    if err != nil {
        log.Fatalf("failed to connect to database: %v", err)
    }
    defer db.Close()

    userStore := store.NewUserStore(db)
    userService := service.NewUserService(userStore)
    userHandler := handler.NewUserHandler(userService)

    // Setup router
    router := handler.NewRouter(userHandler)

    // Create server
    srv := &http.Server{
        Addr:         ":8080",
        Handler:      router,
        ReadTimeout:  15 * time.Second,
        WriteTimeout: 15 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    // Start server in goroutine
    go func() {
        log.Printf("Server starting on %s", srv.Addr)
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("server failed: %v", err)
        }
    }()

    // Graceful shutdown
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    log.Println("Server shutting down...")

    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }

    log.Println("Server exited")
}
```

### handler/user.go
```go
package handler

import (
    "encoding/json"
    "errors"
    "net/http"

    "github.com/go-chi/chi/v5"
    "github.com/user/project/internal/model"
    "github.com/user/project/internal/service"
)

type UserHandler struct {
    userService *service.UserService
}

func NewUserHandler(userService *service.UserService) *UserHandler {
    return &UserHandler{
        userService: userService,
    }
}

func (h *UserHandler) List(w http.ResponseWriter, r *http.Request) {
    users, err := h.userService.List(r.Context())
    if err != nil {
        respondError(w, http.StatusInternalServerError, "failed to list users")
        return
    }

    respondJSON(w, http.StatusOK, users)
}

func (h *UserHandler) Get(w http.ResponseWriter, r *http.Request) {
    id := chi.URLParam(r, "id")

    user, err := h.userService.Get(r.Context(), id)
    if err != nil {
        if errors.Is(err, service.ErrNotFound) {
            respondError(w, http.StatusNotFound, "user not found")
            return
        }
        respondError(w, http.StatusInternalServerError, "failed to get user")
        return
    }

    respondJSON(w, http.StatusOK, user)
}

func (h *UserHandler) Create(w http.ResponseWriter, r *http.Request) {
    var req model.CreateUserRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondError(w, http.StatusBadRequest, "invalid request body")
        return
    }

    if err := req.Validate(); err != nil {
        respondError(w, http.StatusBadRequest, err.Error())
        return
    }

    user, err := h.userService.Create(r.Context(), &req)
    if err != nil {
        respondError(w, http.StatusInternalServerError, "failed to create user")
        return
    }

    respondJSON(w, http.StatusCreated, user)
}

func (h *UserHandler) Update(w http.ResponseWriter, r *http.Request) {
    id := chi.URLParam(r, "id")

    var req model.UpdateUserRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondError(w, http.StatusBadRequest, "invalid request body")
        return
    }

    user, err := h.userService.Update(r.Context(), id, &req)
    if err != nil {
        if errors.Is(err, service.ErrNotFound) {
            respondError(w, http.StatusNotFound, "user not found")
            return
        }
        respondError(w, http.StatusInternalServerError, "failed to update user")
        return
    }

    respondJSON(w, http.StatusOK, user)
}

func (h *UserHandler) Delete(w http.ResponseWriter, r *http.Request) {
    id := chi.URLParam(r, "id")

    if err := h.userService.Delete(r.Context(), id); err != nil {
        if errors.Is(err, service.ErrNotFound) {
            respondError(w, http.StatusNotFound, "user not found")
            return
        }
        respondError(w, http.StatusInternalServerError, "failed to delete user")
        return
    }

    w.WriteHeader(http.StatusNoContent)
}

// Helper functions
func respondJSON(w http.ResponseWriter, status int, data interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteStatus(status)
    json.NewEncoder(w).Encode(data)
}

func respondError(w http.ResponseWriter, status int, message string) {
    respondJSON(w, status, map[string]string{"error": message})
}
```

### service/user.go
```go
package service

import (
    "context"
    "errors"
    "fmt"

    "github.com/user/project/internal/model"
    "github.com/user/project/internal/store"
)

var (
    ErrNotFound = errors.New("user not found")
)

type UserService struct {
    userStore *store.UserStore
}

func NewUserService(userStore *store.UserStore) *UserService {
    return &UserService{
        userStore: userStore,
    }
}

func (s *UserService) List(ctx context.Context) ([]*model.User, error) {
    users, err := s.userStore.List(ctx)
    if err != nil {
        return nil, fmt.Errorf("listing users: %w", err)
    }
    return users, nil
}

func (s *UserService) Get(ctx context.Context, id string) (*model.User, error) {
    user, err := s.userStore.Get(ctx, id)
    if err != nil {
        if errors.Is(err, store.ErrNotFound) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("getting user %s: %w", id, err)
    }
    return user, nil
}

func (s *UserService) Create(ctx context.Context, req *model.CreateUserRequest) (*model.User, error) {
    user := &model.User{
        Name:  req.Name,
        Email: req.Email,
        Age:   req.Age,
    }

    if err := s.userStore.Create(ctx, user); err != nil {
        return nil, fmt.Errorf("creating user: %w", err)
    }

    return user, nil
}

func (s *UserService) Update(ctx context.Context, id string, req *model.UpdateUserRequest) (*model.User, error) {
    user, err := s.userStore.Get(ctx, id)
    if err != nil {
        if errors.Is(err, store.ErrNotFound) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("getting user for update: %w", err)
    }

    if req.Name != nil {
        user.Name = *req.Name
    }
    if req.Email != nil {
        user.Email = *req.Email
    }

    if err := s.userStore.Update(ctx, user); err != nil {
        return nil, fmt.Errorf("updating user: %w", err)
    }

    return user, nil
}

func (s *UserService) Delete(ctx context.Context, id string) error {
    if err := s.userStore.Delete(ctx, id); err != nil {
        if errors.Is(err, store.ErrNotFound) {
            return ErrNotFound
        }
        return fmt.Errorf("deleting user: %w", err)
    }
    return nil
}
```

### model/user.go
```go
package model

import (
    "errors"
    "regexp"
    "time"
)

type User struct {
    ID        string    `json:"id"`
    Name      string    `json:"name"`
    Email     string    `json:"email"`
    Age       int       `json:"age"`
    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
}

type CreateUserRequest struct {
    Name  string `json:"name"`
    Email string `json:"email"`
    Age   int    `json:"age"`
}

func (r *CreateUserRequest) Validate() error {
    if r.Name == "" {
        return errors.New("name is required")
    }
    if len(r.Name) < 2 {
        return errors.New("name must be at least 2 characters")
    }
    if r.Email == "" {
        return errors.New("email is required")
    }
    if !isValidEmail(r.Email) {
        return errors.New("invalid email format")
    }
    if r.Age < 0 || r.Age > 150 {
        return errors.New("age must be between 0 and 150")
    }
    return nil
}

type UpdateUserRequest struct {
    Name  *string `json:"name,omitempty"`
    Email *string `json:"email,omitempty"`
}

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)

func isValidEmail(email string) bool {
    return emailRegex.MatchString(email)
}
```

## Table-Driven Test Example

```go
package calculator_test

import (
    "testing"

    "github.com/user/project/calculator"
)

func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive numbers", 2, 3, 5},
        {"negative numbers", -2, -3, -5},
        {"mixed signs", 10, -5, 5},
        {"zero with positive", 0, 5, 5},
        {"zero with zero", 0, 0, 0},
        {"large numbers", 1000000, 2000000, 3000000},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := calculator.Add(tt.a, tt.b)
            if result != tt.expected {
                t.Errorf("Add(%d, %d) = %d; want %d",
                    tt.a, tt.b, result, tt.expected)
            }
        })
    }
}

func TestDivide(t *testing.T) {
    tests := []struct {
        name      string
        a, b      float64
        expected  float64
        expectErr bool
    }{
        {"normal division", 10, 2, 5, false},
        {"division by zero", 10, 0, 0, true},
        {"negative numbers", -10, 2, -5, false},
        {"result is fraction", 5, 2, 2.5, false},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result, err := calculator.Divide(tt.a, tt.b)

            if tt.expectErr {
                if err == nil {
                    t.Error("expected error, got nil")
                }
                return
            }

            if err != nil {
                t.Errorf("unexpected error: %v", err)
                return
            }

            if result != tt.expected {
                t.Errorf("Divide(%f, %f) = %f; want %f",
                    tt.a, tt.b, result, tt.expected)
            }
        })
    }
}
```

## Error Handling Example

```go
package main

import (
    "database/sql"
    "errors"
    "fmt"
)

// Custom error types
type ValidationError struct {
    Field string
    Msg   string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("%s: %s", e.Field, e.Msg)
}

type NotFoundError struct {
    Resource string
    ID       string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("%s with ID %s not found", e.Resource, e.ID)
}

// Service example
func GetUser(db *sql.DB, id string) (*User, error) {
    if id == "" {
        return nil, &ValidationError{
            Field: "id",
            Msg:   "cannot be empty",
        }
    }

    user, err := queryUser(db, id)
    if err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, &NotFoundError{
                Resource: "User",
                ID:       id,
            }
        }
        return nil, fmt.Errorf("querying user %s: %w", id, err)
    }

    return user, nil
}

// Using errors.Is and errors.As
func HandleError(err error) {
    if err == nil {
        return
    }

    // Check for specific error
    if errors.Is(err, sql.ErrNoRows) {
        fmt.Println("No rows found")
        return
    }

    // Check for error type
    var valErr *ValidationError
    if errors.As(err, &valErr) {
        fmt.Printf("Validation error in field %s: %s\n", valErr.Field, valErr.Msg)
        return
    }

    var notFoundErr *NotFoundError
    if errors.As(err, &notFoundErr) {
        fmt.Printf("Resource %s with ID %s not found\n", notFoundErr.Resource, notFoundErr.ID)
        return
    }

    fmt.Printf("Unexpected error: %v\n", err)
}
```

## Concurrency Example

```go
package main

import (
    "context"
    "fmt"
    "sync"
    "time"
)

// Worker pool pattern
func ProcessItems(items []string) []Result {
    const numWorkers = 5

    jobs := make(chan string, len(items))
    results := make(chan Result, len(items))

    // Start workers
    var wg sync.WaitGroup
    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            worker(jobs, results)
        }()
    }

    // Send jobs
    for _, item := range items {
        jobs <- item
    }
    close(jobs)

    // Close results channel when all workers done
    go func() {
        wg.Wait()
        close(results)
    }()

    // Collect results
    var collected []Result
    for result := range results {
        collected = append(collected, result)
    }

    return collected
}

func worker(jobs <-chan string, results chan<- Result) {
    for job := range jobs {
        results <- processJob(job)
    }
}

// Context with timeout
func FetchWithTimeout(ctx context.Context, url string) (string, error) {
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()

    resultChan := make(chan string, 1)
    errChan := make(chan error, 1)

    go func() {
        data, err := fetch(url)
        if err != nil {
            errChan <- err
            return
        }
        resultChan <- data
    }()

    select {
    case <-ctx.Done():
        return "", fmt.Errorf("request cancelled: %w", ctx.Err())
    case err := <-errChan:
        return "", err
    case data := <-resultChan:
        return data, nil
    }
}

// Pipeline pattern
func Pipeline(ctx context.Context, input <-chan int) <-chan int {
    // Stage 1: multiply by 2
    stage1 := make(chan int)
    go func() {
        defer close(stage1)
        for n := range input {
            select {
            case <-ctx.Done():
                return
            case stage1 <- n * 2:
            }
        }
    }()

    // Stage 2: add 1
    stage2 := make(chan int)
    go func() {
        defer close(stage2)
        for n := range stage1 {
            select {
            case <-ctx.Done():
                return
            case stage2 <- n + 1:
            }
        }
    }()

    return stage2
}
```

## Middleware Example

```go
package middleware

import (
    "log"
    "net/http"
    "runtime/debug"
    "time"
)

// Logging middleware
func Logging(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()

        wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
        next.ServeHTTP(wrapped, r)

        log.Printf("[%s] %s %s %d %v",
            r.Method,
            r.URL.Path,
            r.RemoteAddr,
            wrapped.statusCode,
            time.Since(start),
        )
    })
}

// Recovery middleware
func Recovery(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        defer func() {
            if err := recover(); err != nil {
                log.Printf("panic recovered: %v\n%s", err, debug.Stack())
                http.Error(w, "Internal Server Error", http.StatusInternalServerError)
            }
        }()
        next.ServeHTTP(w, r)
    })
}

// Response writer wrapper
type responseWriter struct {
    http.ResponseWriter
    statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
    rw.statusCode = code
    rw.ResponseWriter.WriteHeader(code)
}

// Auth middleware
func Auth(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        token := r.Header.Get("Authorization")
        if token == "" {
            http.Error(w, "Unauthorized", http.StatusUnauthorized)
            return
        }

        // Validate token
        userID, err := validateToken(token)
        if err != nil {
            http.Error(w, "Invalid token", http.StatusUnauthorized)
            return
        }

        // Add user to context
        ctx := context.WithValue(r.Context(), "userID", userID)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```
