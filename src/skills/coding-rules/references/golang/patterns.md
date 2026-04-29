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

### 4. Dual Error Handling: Sentinel + Typed

**Проблема:** При обработке ошибок встречаются два сценария: (1) "проверить факт" (ошибка просто наступила — `not found`, `unauthorized`); (2) "извлечь данные" (ошибка содержит контекст — `field name`, `validation message`). Использование только sentinel-ошибок теряет контекст; только типизированных — раздувает API ради тривиальных проверок. Идиоматичный подход — комбинировать.

**Pattern:**
```go
// Sentinel — для безусловных фактов "случилось/не случилось"
var (
    ErrNotFound      = errors.New("not found")
    ErrAlreadyExists = errors.New("already exists")
    ErrUnauthorized  = errors.New("unauthorized")
)

// Typed — когда нужен контекст ошибки
type ValidationError struct {
    Field string
    Msg   string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed for %s: %s", e.Field, e.Msg)
}

type ConflictError struct {
    Resource string
    Reason   string
}

func (e *ConflictError) Error() string {
    return fmt.Sprintf("conflict on %s: %s", e.Resource, e.Reason)
}

// Использование:
// errors.Is — для sentinel
if errors.Is(err, ErrNotFound) {
    return status.Error(codes.NotFound, err.Error())
}

// errors.As — для typed (получаем доступ к полям)
var ve *ValidationError
if errors.As(err, &ve) {
    return fmt.Errorf("invalid %s: %s", ve.Field, ve.Msg)
}
```

**Правило выбора:**
- проверка факта без дополнительных данных (`is this NotFound?`) → sentinel + `errors.Is`
- нужен контекст ошибки (имя поля, ID ресурса, сообщение) → typed + `errors.As`
- НЕ выбирать sentinel ради "лёгкости" — если потребитель хочет показать сообщение пользователю, ему нужен typed

**Severity:** 🟡 MEDIUM

## Generics

### 1. Type-Safe Context Helpers

**Проблема:** Хранение значений в `context.Context` через `context.WithValue` требует ручного `type assertion` на каждом извлечении. Опечатка в типе → runtime panic; изменение типа значения → ничего не подскажет компилятор.

**Anti-pattern:**
```go
// BAD: ручной type assertion на каждом извлечении
type ctxKey string
const userKey ctxKey = "user"

func GetUser(ctx context.Context) *User {
    v := ctx.Value(userKey)
    if v == nil {
        return nil
    }
    return v.(*User) // panic если положили что-то другое
}
```

**Pattern:**
```go
// GOOD: generic helper, тип фиксируется на месте вызова
func ValueFromCtx[T any](ctx context.Context, key any) (T, bool) {
    v, ok := ctx.Value(key).(T)
    return v, ok
}

func MustValueFromCtx[T any](ctx context.Context, key any) T {
    v, ok := ctx.Value(key).(T)
    if !ok {
        var zero T
        panic(fmt.Sprintf("ctx key %v: expected %T, got %T", key, zero, ctx.Value(key)))
    }
    return v
}

// Использование:
type ctxKey struct{ name string }
var userKey = ctxKey{"user"}

ctx = context.WithValue(ctx, userKey, &User{ID: "42"})

user, ok := ValueFromCtx[*User](ctx, userKey)
if !ok {
    return ErrUnauthorized
}
```

**Преимущества:**
- тип проверяется компилятором при вызове `ValueFromCtx[*User]`
- нельзя случайно положить `string`, а извлекать `*User`
- ключи лучше делать пустой структурой `struct{ name string }` — это исключает коллизии с другими пакетами, использующими `string`-ключи

**Severity:** 🟡 MEDIUM

## Retry & Backoff

### Exponential Backoff with Jitter

**Проблема:** Линейный retry (`time.Sleep(retryDelay)`) перегружает downstream-сервис при массовых сбоях — все клиенты повторяют одновременно. Без jitter синхронизируются волны; без cap backoff растёт неограниченно; без max attempts retry бесконечный.

**Anti-pattern:**
```go
// BAD: фиксированная задержка, бесконечный retry
for {
    err := callService()
    if err == nil {
        return nil
    }
    time.Sleep(time.Second) // все клиенты бьют синхронно
}
```

**Pattern:**
```go
import (
    "math/rand/v2"
    "time"
)

const (
    baseDelay   = 100 * time.Millisecond
    maxBackoff  = 30 * time.Second
    maxAttempts = 5
)

func withBackoff(ctx context.Context, fn func() error) error {
    var err error
    for attempt := 0; attempt < maxAttempts; attempt++ {
        err = fn()
        if err == nil {
            return nil
        }
        if !isRetryable(err) {
            return err // не имеет смысла повторять
        }

        // exponential: 100ms, 200ms, 400ms, 800ms, ...
        backoff := baseDelay << attempt
        if backoff > maxBackoff {
            backoff = maxBackoff
        }
        // jitter ±25%, чтобы клиенты не синхронизировались
        jitter := time.Duration(rand.Int64N(int64(backoff / 4)))
        delay := backoff/2 + jitter + backoff/4

        select {
        case <-time.After(delay):
        case <-ctx.Done():
            return ctx.Err()
        }
    }
    return fmt.Errorf("after %d attempts: %w", maxAttempts, err)
}
```

**Правила:**
- ВСЕГДА cap на `maxBackoff` (30s — типичный потолок)
- ВСЕГДА jitter (хотя бы ±25%) — иначе rebalance/restart перезапустит всех одновременно
- Не повторять non-retryable ошибки (`InvalidArgument`, `Unauthorized`, `NotFound`)
- Учитывать `ctx.Done()` в `time.After`-ожидании, иначе shutdown будет ждать backoff
- Готовые библиотеки: `cenkalti/backoff/v4` — даёт `ExponentialBackoff` из коробки, плюс retry-helpers

**Severity:** 🟠 HIGH

## Graceful Shutdown

### Signal Handling with Timeout

**Проблема:** `os.Exit(0)` при SIGTERM обрывает in-flight запросы, открытые транзакции, неотправленные Kafka-сообщения. Без явного timeout shutdown может зависнуть навсегда (например, если БД не отвечает).

**Anti-pattern:**
```go
// BAD: жёсткое завершение
func main() {
    runApp()
    // SIGTERM → процесс убит, in-flight запросы оборваны
}

// BAD: ожидание без timeout
sig := make(chan os.Signal, 1)
signal.Notify(sig, syscall.SIGTERM)
<-sig
db.Close() // если зависнет — застрянем навсегда
```

**Pattern:**
```go
import (
    "context"
    "os/signal"
    "syscall"
    "time"
)

func main() {
    // signal.NotifyContext: отменяет ctx при SIGINT/SIGTERM
    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    app, err := newApp(ctx)
    if err != nil {
        log.Fatalf("init: %v", err)
    }

    if err := app.Run(ctx); err != nil {
        log.Printf("run: %v", err)
    }

    // явный timeout на shutdown — останавливаем всё, но не ждём дольше N секунд
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    if err := app.Shutdown(shutdownCtx); err != nil {
        log.Printf("shutdown: %v", err)
    }
}
```

**Правила:**
- `signal.NotifyContext` — Go 1.16+ идиома вместо ручного `signal.Notify` + select
- ВСЕГДА использовать **отдельный** контекст с timeout для shutdown — нельзя переиспользовать отменённый родительский ctx
- Типичный timeout: 5–30 секунд (зависит от тяжести fini-операций: HTTP graceful shutdown, Kafka flush, DB close)
- Если приложение под FX — `signal.NotifyContext` обычно не нужен, FX сам слушает сигналы; но shutdown timeout всё равно настраивается через `fx.StartTimeout`/`fx.StopTimeout`

**Severity:** 🟠 HIGH

## Null Handling

### Choosing Between Pointers and `null.*` Wrappers

**Проблема:** В Go нет встроенного `Optional[T]`. Для nullable полей используют либо указатели (`*string`, `*int64`), либо `database/sql.NullString`, либо `guregu/null/v6.String`. У каждого свой trade-off; типичная ошибка — выбрать указатель там, где нужен явный `null`-маркер при JSON-сериализации.

**Сравнение:**

| Тип                | JSON `null` vs `missing`     | DB-сериализация | Удобство в коде                |
|--------------------|------------------------------|-----------------|--------------------------------|
| `*string`          | `null` ↔ `nil`, missing ↔ `nil` (неразличимы при `omitempty`) | OK через `sql.Scanner` обёртки | разыменование требует nil-check |
| `sql.NullString`   | сериализуется как объект `{String:"x", Valid:true}` — некрасиво для API | нативная для `database/sql` | `.Valid`/`.String` поля |
| `null.String` ([guregu/null/v6](https://github.com/guregu/null)) | `null` ↔ Valid=false, отсутствие ↔ при `omitempty` пропускается | реализует `sql.Scanner`/`Valuer` | `.Valid`/`.String` + чистый JSON |

**Правила выбора:**
- API DTO, где важен `null` vs `missing` для PATCH-семантики → `null.String` / `null.Int`
- Внутренние структуры, не пересекающиеся с JSON → `*T` (короче синтаксис)
- Entity-структуры под `database/sql` без сложных JSON-выходов → `sql.NullString` приемлем
- Никогда не использовать `sql.NullString` в DTO — JSON-формат `{String, Valid}` ломает фронт

**Anti-pattern:**
```go
// BAD: указатель в API DTO теряет различие null vs missing при PATCH
type UpdateUserRequest struct {
    Bio *string `json:"bio,omitempty"` // null и отсутствие — одинаково
}
```

**Pattern:**
```go
import "github.com/guregu/null/v6"

// GOOD: null.String различает null (set bio = NULL) и missing (don't update)
type UpdateUserRequest struct {
    Bio null.String `json:"bio"` // .Valid=false → null; не пришло → zero-value
}

func (uc *UseCase) UpdateUser(ctx context.Context, req *UpdateUserRequest) error {
    if req.Bio.Valid {
        // явное обновление: либо строка, либо явный null
        // ...
    }
    return nil
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
