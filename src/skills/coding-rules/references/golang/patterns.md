# Go Patterns Reference

Паттерны и anti-patterns специфичные для Go.

**See also:**
- `uber-fx.md` — Uber FX lifecycle, DI, modules, graceful shutdown
- `clean-architecture.md` — DDD layers: entities, DTO, deps, repository, usecase, delivery, workers
- `grpc.md` — gRPC server, client, interceptors, error mapping, metadata
- `kafka.md` — Kafka consumer, producer, transactional event log, idempotency
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

### 5. Swallowed Errors via `Exists`-style Wrappers

**Проблема:** `Exists`-обёртка над `Get` возвращает `bool` и глотает любую ошибку, превращая её в "не существует". При лежащей БД, таймауте или сетевом сбое функция вернёт `false` — вызывающий код продолжит "корректно" работать как с отсутствующей записью, ставя данные в неконсистентное состояние. Реальная ошибка не доходит ни до логов, ни до метрик.

**Anti-pattern:**
```go
// BAD: любая ошибка трактуется как "нет записи"
func (r *Repository) Exists(ctx context.Context, id uuid.UUID) bool {
    _, err := r.Get(ctx, id)
    return err == nil
}

// в use case:
if !uc.repo.Exists(ctx, id) {
    return uc.repo.Create(ctx, &Entity{ID: id}) // race + БД лежит → дубликат
}
```

**Pattern:**
```go
// GOOD: явное разделение "нет записи" и "сбой"
func (r *Repository) Exists(ctx context.Context, id uuid.UUID) (bool, error) {
    _, err := r.Get(ctx, id)
    switch {
    case err == nil:
        return true, nil
    case errors.Is(err, ErrNotFound):
        return false, nil
    default:
        return false, fmt.Errorf("check exists: %w", err)
    }
}

// или вообще без обёртки — Get + errors.Is на месте
_, err := r.repo.Get(ctx, id)
switch {
case errors.Is(err, ErrNotFound):
    // создаём
case err != nil:
    return fmt.Errorf("get: %w", err)
default:
    // существует
}
```

**Признаки в коде:**
- Метод `Exists*`/`Has*`/`IsRegistered*` возвращает `bool` без `error`
- Внутри — `err == nil` или `err != nil` без различения `ErrNotFound`
- В тестах нет кейса "БД недоступна → ошибка пробрасывается"

**Severity:** 🔴 CRITICAL

### 6. Variable Shadowing Across Log/Error Sites

**Проблема:** Повторное использование одного имени переменной для строки и для распарсенного значения (`uuid.Parse`, `time.Parse`, `strconv.Atoi`) затеняет внешнее значение. Дальнейший лог при ошибке (`log.Error("...", "id", id)`) попадает уже на распарсенный объект — `uuid.Nil`/`time.Time{}`/`0` — и теряет исходную строку, по которой можно понять, что пришло на вход.

**Anti-pattern:**
```go
// BAD: id затеняет внешнюю строку; лог теряет исходное значение
func (w *Worker) handle(ctx context.Context, id string) error {
    id, err := uuid.Parse(id) // shadow: теперь id — uuid.UUID
    if err != nil {
        // в лог попадёт uuid.Nil, исходная строка потеряна
        w.log.ErrorwCtx(ctx, "parse id failed", "id", id, "err", err)
        return err
    }
    // ...
}
```

**Pattern:**
```go
// GOOD: разные имена для строки и распарсенного значения
func (w *Worker) handle(ctx context.Context, rawID string) error {
    id, err := uuid.Parse(rawID)
    if err != nil {
        w.log.ErrorwCtx(ctx, "parse id failed", "rawID", rawID, "err", err)
        return fmt.Errorf("parse id %q: %w", rawID, err)
    }
    // id — uuid.UUID, rawID — исходная строка
    return w.process(ctx, id)
}

// GOOD: или ранний return до тени
func (w *Worker) handle(ctx context.Context, id string) error {
    parsed, err := uuid.Parse(id)
    if err != nil {
        w.log.ErrorwCtx(ctx, "parse id failed", "id", id, "err", err)
        return err
    }
    return w.process(ctx, parsed)
}
```

**Защита через линтер:** включить `govet` с включённым проверкой `shadow` в `golangci-lint`:
```yaml
linters-settings:
  govet:
    enable:
      - shadow
linters:
  enable:
    - govet
```

**Признаки в коде:**
- В одной функции имя `id`/`t`/`n`/`amount` встречается до и после `Parse`/`Atoi`
- Лог "X failed" при ошибке не содержит исходную строку, по которой парсили
- Тест на ошибочный вход не проверяет содержимое лог-полей

**Severity:** 🟠 HIGH

## Configuration Types and Defaults

### 1. time.Duration vs Integer Seconds

**Проблема:** Поле `Timeout int` в конфиге заставляет в коде писать `time.Duration(cfg.Timeout) * time.Second` на каждом использовании. Юнит спрятан в имени переменной — `TimeoutMs`, `IntervalSec`, и при чтении легко перепутать. Defaults через `if cfg.X == 0 { cfg.X = 10 }` маскируют значение "не задано" под "явный ноль".

**Anti-pattern:**
```go
type Config struct {
    Timeout       int `env:"TIMEOUT"`        // секунды? миллисекунды? минуты?
    PollInterval  int `env:"POLL_INTERVAL"`  // непонятно, и нет дефолта
    SessionTTL    int `env:"SESSION_TTL"`
}

func (c *Config) Apply() {
    if c.Timeout == 0 {       // имитация дефолта if-блоком
        c.Timeout = 10
    }
    // ...
}

// в коде — ручной каст на каждом использовании
ctx, cancel := context.WithTimeout(ctx, time.Duration(cfg.Timeout)*time.Second)
```

**Pattern:**
```go
type Config struct {
    Timeout      time.Duration `env:"TIMEOUT"      envDefault:"10s"`
    PollInterval time.Duration `env:"POLL_INTERVAL" envDefault:"500ms"`
    SessionTTL   time.Duration `env:"SESSION_TTL"  envDefault:"24h"`
}

// в коде — без каста, единица очевидна
ctx, cancel := context.WithTimeout(ctx, cfg.Timeout)
```

`time.Duration` парсится напрямую большинством конфиг-библиотек (форматы `10s`, `500ms`, `1m30s`, `24h`):
- `caarlos0/env`: `env:"TIMEOUT" envDefault:"10s"`
- `kelseyhightower/envconfig`: `default:"10s"`
- `spf13/viper`: `viper.SetDefault("timeout", "10s")` + `viper.GetDuration("timeout")`

**Признаки в коде:**
- Поля `*Timeout`, `*Interval`, `*TTL`, `*Period` имеют тип `int`
- `time.Duration(cfg.X) * time.Second` встречается в коде
- Имя переменной несёт юнит (`TimeoutSec`, `IntervalMs`) вместо `time.Duration`
- Дефолты заданы блоком `if cfg.X == 0 { cfg.X = ... }` вместо struct-tag

**Severity:** 🟡 MEDIUM

## Magic Values

### 1. Magic Values → Named Constants

**Проблема:** Литералы `"pending"`, `0.05`, `30`, `"X-Trace-Id"` встроены прямо в выражения. Одно значение продублировано в нескольких местах — изменить статус "pending" → "PENDING" нужно везде, и опечатка не подсветится. Связь между значением и его смыслом не очевидна: что значит `30`?

**Anti-pattern:**
```go
// BAD: голые литералы, дубли, неясная семантика
if order.Status == "pending" {                    // смысл строки спрятан
    feeRate := 0.025                              // что за число?
    deadline := time.Now().Add(30 * time.Second)  // 30 чего?
    headers.Set("X-Trace-Id", traceID)            // ключ заголовка как литерал
}
// в другом файле:
if other.Status == "pending" { ... }              // дубль, легко разойдётся
```

**Pattern:**
```go
// GOOD: типизированные enum-ы, именованные const, конфиг для среды
type OrderStatus string

const (
    OrderStatusPending   OrderStatus = "pending"
    OrderStatusCompleted OrderStatus = "completed"
    OrderStatusCanceled  OrderStatus = "canceled"
)

const (
    DefaultFeeRate     = 0.025                // если не среда-зависимое
    OrderProcessingTimeout = 30 * time.Second // имя несёт смысл и юнит
    HeaderTraceID      = "X-Trace-Id"
)

if order.Status == OrderStatusPending {
    deadline := time.Now().Add(OrderProcessingTimeout)
    headers.Set(HeaderTraceID, traceID)
}
```

**Правила:**
- Статусы и enum-ы — typed constants (`type OrderStatus string` + набор `const`)
- Значения, меняющиеся между средами (timeouts, host-ы, лимиты) — в config, не в const
- HTTP-заголовки, Kafka-ключи, redis-keys, query-параметры — именованные const рядом с использующим кодом (или в общем `constants.go` пакета)
- Значения "из спеки" (комиссии, retry-числа, TTL по бизнес-правилу) — const с комментарием на источник

**Признаки в коде:**
- Одно строковое/числовое значение встречается в 2+ местах
- Статусы как голые строки (`"pending"`, `"completed"`)
- HTTP-заголовки/Kafka-keys/query-params как литералы по коду
- Числа без юнита/смысла (`30`, `0.05`, `1024`) в выражениях

**Severity:** 🟡 MEDIUM

## Boolean-Returning Validators

### 1. Inverted Condition on `bool`-Returning Validator

**Проблема:** `Validate*`-метод, возвращающий `bool` со значением "valid" (а не "invalid"), естественно ведёт к двусмысленным условиям. После рефакторинга легко перепутать `if v.Valid()` и `if !v.Valid()`: компилятор оба варианта пропустит, тип одинаковый, тестов на инвалидный кейс часто нет — баг уезжает в прод. Реальный кейс: `if !ticker.ValidateAmount(amount)` пропускал инвалидные значения, потому что под именем `ValidateAmount` ожидался "вернёт true если ОК", а возвращал он "true если **не** ок".

**Anti-pattern:**
```go
// BAD: bool-returning метод с неочевидной семантикой
func (t *Ticker) ValidateAmount(amount decimal.Decimal) bool {
    return amount.GreaterThan(t.MinAmount) && amount.LessThan(t.MaxAmount)
}

// в коде — легко инвертировать после рефактора
if !ticker.ValidateAmount(amount) { // пропустит инвалидные значения, если поменять знак
    return ErrInvalidAmount
}
```

**Pattern:**
```go
// GOOD: возвращаем error — нельзя перепутать направление
func (t *Ticker) ValidateAmount(amount decimal.Decimal) error {
    if !amount.GreaterThan(t.MinAmount) {
        return fmt.Errorf("%w: amount %s below min %s",
            ErrInvalidAmount, amount, t.MinAmount)
    }
    if !amount.LessThan(t.MaxAmount) {
        return fmt.Errorf("%w: amount %s above max %s",
            ErrInvalidAmount, amount, t.MaxAmount)
    }
    return nil
}

// в коде — компилятор и линтер ловят попытки инверсии
if err := ticker.ValidateAmount(amount); err != nil {
    return err
}
```

**Если `bool` всё-таки нужен** (оптимизация hot-path, predicate для filter):
- именовать через `Is*`/`Has*` — `IsValidAmount`, `HasMinBalance` (явно "true == ОК")
- возвращать `(ok bool, reason string)` или `(bool, error)` для отладочных сообщений
- обязательная пара тестов: один valid, один invalid с `require.False`/`require.True`

**Защита через тесты:** см. `testing.md → Validators must have at least one invalid test case`. Таблица из одних valid-кейсов компилятор пропустит — нужен явный invalid-кейс.

**Признаки в коде:**
- Метод имени `Validate*` возвращает `bool` (не `error`)
- В таблице тестов отсутствуют invalid-кейсы
- В вызывающем коде встречается `if !v.Validate*(...)` — потенциальная инверсия

**Severity:** 🟠 HIGH

## Slice Element Types

### 1. Slice of Pointers — Only When Justified

**Проблема:** `[]*T` по умолчанию плодит косвенность без выгоды: каждое чтение элемента — разыменование указателя, GC должен трекать каждый элемент, кэш-локальность хуже. Если `T` мал и не мутируется, `[]T` проще, быстрее и не требует nil-проверок.

**Anti-pattern:**
```go
// BAD: []*T по умолчанию для маленькой struct, элементы не мутируются
type Item struct {
    ID    uuid.UUID
    Code  string
}

func toItems(rows []row) []*Item {
    out := make([]*Item, 0, len(rows))
    for _, r := range rows {
        out = append(out, &Item{ID: r.ID, Code: r.Code}) // указатель без причины
    }
    return out
}

// потребители вынуждены проверять nil или делать разыменование
for _, it := range items {
    if it == nil { continue } // зачем nil в slice?
    fmt.Println(it.Code)
}
```

**Pattern:**
```go
// GOOD: []T для immutable элементов
func toItems(rows []row) []Item {
    out := make([]Item, 0, len(rows))
    for _, r := range rows {
        out = append(out, Item{ID: r.ID, Code: r.Code})
    }
    return out
}
```

**Когда `[]*T` оправдан:**
- нужна `nil`-семантика для optional element (sparse-slice, где `nil` означает "нет данных")
- элементы мутируются по индексу после создания, и эти мутации должны быть видны потребителям, держащим ссылку
- `T` крупная struct (≳ 64 байт) и копирование на каждом чтении заметно по профилю
- алгоритм требует nil-маркеров (graph traversal с visited-mask и т.п.)

**Признаки в коде:**
- `make([]*T, 0, n)` + `append(..., &T{...})`, после которого элементы только читаются
- `for i := range s { _ = s[i] }` без присвоения индексу `s[i] = ...`
- Потребители делают `if x == nil { continue }` без бизнес-смысла "пропустить"

**Severity:** 🔵 LOW

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

### 2. Slice Helpers (Map / Filter / Reduce)

**Проблема:** Одинаковая логика map / filter / paginate / chunk / unique реализуется для каждого типа отдельно через copy-paste — `func mapOrders(...)`, `func mapUsers(...)`, `func filterActive(...)`. Изменение поведения нужно повторять в N местах; легко получить расхождение.

**Anti-pattern:**
```go
// BAD: один и тот же шаблон map для разных типов
func ordersToIDs(orders []Order) []uuid.UUID {
    out := make([]uuid.UUID, len(orders))
    for i, o := range orders { out[i] = o.ID }
    return out
}

func usersToIDs(users []User) []uuid.UUID {
    out := make([]uuid.UUID, len(users))
    for i, u := range users { out[i] = u.ID }
    return out
}
// ...и так для каждого нового типа
```

**Pattern:**
```go
// GOOD: generic-функции в общем пакете (например, internal/pkg/slices)

func Map[T, U any](s []T, f func(T) U) []U {
    out := make([]U, len(s))
    for i, v := range s {
        out[i] = f(v)
    }
    return out
}

func Filter[T any](s []T, pred func(T) bool) []T {
    out := s[:0:0]
    for _, v := range s {
        if pred(v) {
            out = append(out, v)
        }
    }
    return out
}

func Reduce[T, A any](s []T, init A, f func(A, T) A) A {
    acc := init
    for _, v := range s {
        acc = f(acc, v)
    }
    return acc
}

// использование
ids := slices.Map(orders, func(o Order) uuid.UUID { return o.ID })
active := slices.Filter(users, func(u User) bool { return u.Active })
total := slices.Reduce(items, decimal.Zero, func(a decimal.Decimal, i Item) decimal.Decimal {
    return a.Add(i.Price)
})
```

**Эвристика, когда выносить:**
- одинаковый шаблон встречается **в 3+ местах** для разных типов → выносить в generic-helper
- встречается в **2 местах** → оставить inline; преждевременная абстракция
- если `Map` уже используется по проекту, новый "ещё один частный mapOrders" не нужен — переходим на generic

**Стандартная библиотека:** в Go 1.21+ есть `slices.Concat`, `slices.Contains`, `slices.Sort` и т.д.; собственные `Map/Filter/Reduce` дополняют их.

**Признаки в коде:**
- Идентичный `for _, x := range src { dst = append(dst, conv(x)) }` для разных типов
- Дублированный `Page[T]` / `Result[T]` — параметризация типа просится сама
- Имена `mapOrdersToIDs`, `mapUsersToIDs`, `mapItemsToIDs` рядом

**Severity:** 🔵 LOW

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
