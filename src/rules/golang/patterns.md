# Go Patterns Reference

Паттерны и anti-patterns специфичные для Go.

**See also:**
- `uber-fx.md` — Uber FX lifecycle, DI, modules, graceful shutdown
- `clean-architecture.md` — DDD layers: entities, DTO, deps, repository, usecase, delivery, workers
- `grpc.md` — gRPC server, client, interceptors, error mapping, metadata
- `kafka.md` — Kafka consumer, producer, outbox pattern, idempotency
- `redis.md` — Redis caching, distributed locks, pipelines
- `testing.md` — Mockery, testify, table tests, integration tests

## Goroutine Leaks

### 1. Unbuffered Channel Without Receiver

**Anti-pattern:**
```go
// BAD: Goroutine blocked forever
func process() {
    ch := make(chan int)
    go func() {
        result := compute()
        ch <- result // Blocked if no receiver!
    }()
    // No receive from ch - goroutine leaks
}
```

**Pattern:**
```go
// GOOD: Buffered channel or guaranteed receiver
func process() {
    ch := make(chan int, 1) // Buffered
    go func() {
        ch <- compute()
    }()
    // Can receive later or let channel be GC'd
}

// GOOD: Context for cancellation
func process(ctx context.Context) {
    ch := make(chan int)
    go func() {
        select {
        case ch <- compute():
        case <-ctx.Done():
            return
        }
    }()
}
```

**Severity:** 🟠 HIGH

### 2. Missing Done Channel

**Anti-pattern:**
```go
// BAD: No way to stop worker
func startWorker() {
    go func() {
        for {
            processItem(<-workQueue)
        }
    }()
}
```

**Pattern:**
```go
// GOOD: Done channel for graceful shutdown
func startWorker(ctx context.Context) {
    go func() {
        for {
            select {
            case item := <-workQueue:
                processItem(item)
            case <-ctx.Done():
                return
            }
        }
    }()
}
```

**Severity:** 🟠 HIGH

### 3. WaitGroup Misuse

**Anti-pattern:**
```go
// BAD: Add inside goroutine - race condition
func process(items []Item) {
    var wg sync.WaitGroup
    for _, item := range items {
        go func(item Item) {
            wg.Add(1) // Race: might not happen before Wait()
            defer wg.Done()
            processItem(item)
        }(item)
    }
    wg.Wait()
}
```

**Pattern:**
```go
// GOOD: Add before starting goroutine
func process(items []Item) {
    var wg sync.WaitGroup
    for _, item := range items {
        wg.Add(1)
        go func(item Item) {
            defer wg.Done()
            processItem(item)
        }(item)
    }
    wg.Wait()
}
```

**Severity:** 🟠 HIGH

## Defer Patterns

### 1. Defer in Loop

**Anti-pattern:**
```go
// BAD: Defers pile up until function returns
func processFiles(paths []string) error {
    for _, path := range paths {
        f, err := os.Open(path)
        if err != nil {
            return err
        }
        defer f.Close() // All deferred until function exits!
        process(f)
    }
    return nil
}
```

**Pattern:**
```go
// GOOD: Wrap in function to scope defer
func processFiles(paths []string) error {
    for _, path := range paths {
        if err := processFile(path); err != nil {
            return err
        }
    }
    return nil
}

func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close()
    return process(f)
}
```

**Severity:** 🟠 HIGH

### 2. Defer Order

**Anti-pattern:**
```go
// BAD: Wrong cleanup order
func setup() (*DB, error) {
    db, err := openDB()
    if err != nil {
        return nil, err
    }
    defer db.Close() // Will close before returning!

    return db, nil
}
```

**Pattern:**
```go
// GOOD: Caller is responsible for cleanup
func setup() (*DB, func(), error) {
    db, err := openDB()
    if err != nil {
        return nil, nil, err
    }

    cleanup := func() {
        db.Close()
    }

    return db, cleanup, nil
}
```

**Severity:** 🟡 MEDIUM

## Error Handling

### 1. Error Wrapping

**Anti-pattern:**
```go
// BAD: Context lost
func loadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, err // Original error, no context
    }
}
```

**Pattern:**
```go
// GOOD: Wrap with context using %w
func loadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("loading config %s: %w", path, err)
    }
}
```

**Severity:** 🟡 MEDIUM

### 2. Unchecked Errors

**Anti-pattern:**
```go
// BAD: Error ignored
func save(data []byte) {
    os.WriteFile("data.txt", data, 0644)
}

// BAD: Deferred error ignored
func process(path string) error {
    f, err := os.Create(path)
    if err != nil {
        return err
    }
    defer f.Close() // Close error ignored!

    _, err = f.Write(data)
    return err
}
```

**Pattern:**
```go
// GOOD: Check all errors
func save(data []byte) error {
    return os.WriteFile("data.txt", data, 0644)
}

// GOOD: Check deferred close errors
func process(path string) (err error) {
    f, err := os.Create(path)
    if err != nil {
        return err
    }
    defer func() {
        if closeErr := f.Close(); closeErr != nil && err == nil {
            err = closeErr
        }
    }()

    _, err = f.Write(data)
    return err
}
```

**Severity:** 🟡 MEDIUM

### 3. Sentinel Errors

**Anti-pattern:**
```go
// BAD: String comparison
if err.Error() == "not found" {
    // Fragile!
}
```

**Pattern:**
```go
// GOOD: Sentinel errors or error types
var ErrNotFound = errors.New("not found")

if errors.Is(err, ErrNotFound) {
    // Robust
}

// GOOD: Error types for additional context
type NotFoundError struct {
    Resource string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("%s not found", e.Resource)
}

var target *NotFoundError
if errors.As(err, &target) {
    log.Printf("Missing: %s", target.Resource)
}
```

**Severity:** 🟡 MEDIUM

## Context Patterns

### 1. Missing Context

**Anti-pattern:**
```go
// BAD: No cancellation support
func fetchData() ([]byte, error) {
    resp, err := http.Get(url)
    // ...
}
```

**Pattern:**
```go
// GOOD: Accept and use context
func fetchData(ctx context.Context) ([]byte, error) {
    req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
    if err != nil {
        return nil, err
    }
    resp, err := http.DefaultClient.Do(req)
    // ...
}
```

**Severity:** 🟡 MEDIUM

### 2. Context Propagation

**Anti-pattern:**
```go
// BAD: Dropping context
func handler(ctx context.Context, req *Request) {
    go processAsync(req) // Context not passed!
}
```

**Pattern:**
```go
// GOOD: Pass context through
func handler(ctx context.Context, req *Request) {
    go processAsync(ctx, req)
}

// GOOD: Background task with new context
func handler(ctx context.Context, req *Request) {
    // Create new context for background task if needed
    bgCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    go func() {
        defer cancel()
        processAsync(bgCtx, req)
    }()
}
```

**Severity:** 🟡 MEDIUM

## Concurrency Patterns

### 1. Data Race on Map

**Anti-pattern:**
```go
// BAD: Concurrent map access panics
var cache = make(map[string]string)

func get(key string) string { return cache[key] }
func set(key, val string)   { cache[key] = val }
```

**Pattern:**
```go
// GOOD: sync.Map for concurrent access
var cache sync.Map

func get(key string) (string, bool) {
    v, ok := cache.Load(key)
    if !ok {
        return "", false
    }
    return v.(string), true
}

func set(key, val string) {
    cache.Store(key, val)
}

// GOOD: Or RWMutex for more control
type SafeCache struct {
    mu   sync.RWMutex
    data map[string]string
}

func (c *SafeCache) Get(key string) string {
    c.mu.RLock()
    defer c.mu.RUnlock()
    return c.data[key]
}

func (c *SafeCache) Set(key, val string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.data[key] = val
}
```

**Severity:** 🔴 CRITICAL

### 2. Mutex Misuse

**Anti-pattern:**
```go
// BAD: Forgetting to unlock
func process() {
    mu.Lock()
    if condition {
        return // Mutex never unlocked!
    }
    // ...
    mu.Unlock()
}
```

**Pattern:**
```go
// GOOD: Use defer
func process() {
    mu.Lock()
    defer mu.Unlock()

    if condition {
        return // Defer handles unlock
    }
    // ...
}
```

**Severity:** 🟠 HIGH

### 3. Channel Deadlock

**Anti-pattern:**
```go
// BAD: Deadlock - reading from closed channel works,
// but this pattern can cause issues
func process() {
    ch := make(chan int)
    close(ch)
    ch <- 1 // Panic: send on closed channel
}

// BAD: Deadlock - both goroutines waiting
func deadlock() {
    ch1 := make(chan int)
    ch2 := make(chan int)

    go func() {
        <-ch1
        ch2 <- 1
    }()

    go func() {
        <-ch2
        ch1 <- 1
    }()
    // Both waiting forever
}
```

**Pattern:**
```go
// GOOD: Clear channel ownership and closing
func process(ctx context.Context) <-chan int {
    ch := make(chan int)
    go func() {
        defer close(ch) // Producer closes
        for {
            select {
            case ch <- compute():
            case <-ctx.Done():
                return
            }
        }
    }()
    return ch
}
```

**Severity:** 🟠 HIGH

## Worker Patterns

### Worker Pattern (Ticker-Based Background Loop)

**Проблема:** `time.Sleep` в горутине без graceful shutdown — воркер не останавливается при завершении приложения, sleep не прерывается контекстом.

**Anti-pattern:**
```go
// BAD: time.Sleep — no graceful shutdown, goroutine leaks
func startWorker() {
    go func() {
        for {
            doWork()
            time.Sleep(30 * time.Second) // Can't interrupt, leaks on shutdown
        }
    }()
}
```

**Pattern:**
```go
// GOOD: Ticker + context + lifecycle hooks
func NewWorker(lc fx.Lifecycle, logger *zap.Logger, svc *Service) {
    var cancel context.CancelFunc

    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            var runCtx context.Context
            runCtx, cancel = context.WithCancel(context.Background())

            go func() {
                ticker := time.NewTicker(30 * time.Second)
                defer ticker.Stop()

                // Run immediately on start
                if err := svc.DoWork(runCtx); err != nil {
                    logger.Error("worker iteration failed", zap.Error(err))
                }

                for {
                    select {
                    case <-ticker.C:
                        if err := svc.DoWork(runCtx); err != nil {
                            logger.Error("worker iteration failed", zap.Error(err))
                        }
                    case <-runCtx.Done():
                        logger.Info("worker stopped")
                        return
                    }
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error {
            cancel()
            return nil
        },
    })
}
```

**Severity:** 🟠 HIGH
