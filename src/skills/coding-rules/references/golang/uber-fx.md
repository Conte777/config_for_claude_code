# Go + Uber FX Patterns Reference

Паттерны и anti-patterns для приложений на Uber FX.

## Lifecycle Hooks

### 1. OnStart/OnStop Correctness

**Anti-pattern:**
```go
// BAD: Blocking OnStart
func NewServer(lc fx.Lifecycle) *Server {
    srv := &Server{}
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return srv.ListenAndServe() // Blocks forever!
        },
        OnStop: func(ctx context.Context) error {
            return srv.Shutdown(ctx)
        },
    })
    return srv
}
```

**Pattern:**
```go
// GOOD: Non-blocking OnStart
func NewServer(lc fx.Lifecycle) *Server {
    srv := &Server{}
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            go func() {
                if err := srv.ListenAndServe(); err != http.ErrServerClosed {
                    log.Printf("Server error: %v", err)
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error {
            return srv.Shutdown(ctx)
        },
    })
    return srv
}
```

**Severity:** 🔴 CRITICAL

### 2. Context Timeout in Hooks

**Anti-pattern:**
```go
// BAD: Ignoring context deadline
func NewDB(lc fx.Lifecycle, cfg *Config) *sql.DB {
    db, _ := sql.Open("postgres", cfg.DSN)
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            // Long operation without respecting context
            return db.Ping()
        },
    })
    return db
}
```

**Pattern:**
```go
// GOOD: Respect context deadline
func NewDB(lc fx.Lifecycle, cfg *Config) *sql.DB {
    db, _ := sql.Open("postgres", cfg.DSN)
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return db.PingContext(ctx)
        },
    })
    return db
}
```

**Severity:** 🟠 HIGH

### 3. fx.Invoke for One-Shot Side Effects, Not Long-Running Components

**Проблема:** `fx.Invoke` выполняется один раз при старте контейнера и подходит для side effects, выполнимых "под занавес" сборки графа: warm-up cache, регистрация router-ов, валидация графа, запуск миграций. Если в `fx.Invoke` стартует **долгоживущий** компонент (HTTP/gRPC-сервер, consumer, ticker, scheduler) без регистрации в `fx.Lifecycle`, FX не знает о его существовании — graceful shutdown такой компонент не остановит, ресурсы утекут, in-flight запросы оборвутся.

**Anti-pattern:**
```go
// BAD: fx.Invoke запускает фоновый процесс без lifecycle hook
fx.Invoke(func(s *Server) {
    go s.Run() // FX ничего не знает; SIGTERM → горутина продолжает работать
})

// BAD: запуск consumer без OnStop
fx.Invoke(func(c *Consumer) {
    go c.Consume(context.Background()) // shutdown не отменит этот ctx
})
```

**Pattern:**
```go
// GOOD: long-running компонент регистрируется через lc.Append
fx.Invoke(func(lc fx.Lifecycle, s *Server) {
    lc.Append(fx.Hook{
        OnStart: s.OnStart,   // не блокирует — старт в горутине внутри
        OnStop:  s.OnStop,    // GracefulStop / cancel + Wait
    })
})

// GOOD: fx.Invoke для one-shot side effects
fx.Invoke(func(r *router.Router, h *Handlers) {
    h.RegisterRoutes(r) // одноразовый side effect, никаких goroutine
})

fx.Invoke(func(cache *Cache) error {
    return cache.WarmUp(context.Background()) // одноразовая инициализация
})

fx.Invoke(func(m *Migrator) error {
    return m.RunPendingMigrations(context.Background()) // одноразово на старте
})
```

**Признаки в коде:**
- `fx.Invoke(...)` запускает горутины, серверы, consumer-ы, тикеры
- В `fx.Invoke` присутствует `go ...`/`for {}`/`time.NewTicker`/`Serve`
- При SIGTERM в логах компонент не сообщает об остановке (нет `OnStop`-хендлера)
- `OnStop` для компонента отсутствует или находится в другом месте графа

**Правило:** если функция запускает что-то, что должно жить пока живёт приложение — она обязана зарегистрировать `fx.Hook{OnStart, OnStop}`. `fx.Invoke` без `lc.Append` допустим только для строго одноразовой работы.

**Severity:** 🟠 HIGH

### 4. Methods on Type for Stateful Components

**Проблема:** Когда компонент имеет состояние (listener, ticker, базовый сервер, handler-registry), вынос lifecycle в inline-замыкание внутри FX-конструктора раздувает код, заставляет тащить замыкания над `var listener net.Listener`/`var cancel context.CancelFunc`, плодит boilerplate и затрудняет тесты — состояние живёт в захваченных переменных, а не в полях типа.

Этот паттерн — обобщение `grpc.md → 3. Stateful Server: Methods on Type vs Lifecycle Functions` на любые long-running компоненты (workers, consumer-pools, scheduler-ы, HTTP-серверы, kafka-консьюмеры).

**Anti-pattern:**
```go
// BAD: state в захваченных переменных, lifecycle в одном большом замыкании
func NewWorker(lc fx.Lifecycle, log Logger, svc Service) {
    var (
        cancel context.CancelFunc
        ticker *time.Ticker
        wg     sync.WaitGroup
    )
    lc.Append(fx.Hook{
        OnStart: func(_ context.Context) error {
            var runCtx context.Context
            runCtx, cancel = context.WithCancel(context.Background())
            ticker = time.NewTicker(30 * time.Second)
            wg.Add(1)
            go func() {
                defer wg.Done()
                for {
                    select {
                    case <-runCtx.Done():
                        return
                    case <-ticker.C:
                        if err := svc.DoWork(runCtx); err != nil {
                            log.Errorw("iteration failed", "err", err)
                        }
                    }
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error {
            cancel()
            ticker.Stop()
            done := make(chan struct{})
            go func() { wg.Wait(); close(done) }()
            select {
            case <-done:
                return nil
            case <-ctx.Done():
                return ctx.Err()
            }
        },
    })
}
```

**Pattern:**
```go
// GOOD: state — поля типа, OnStart/OnStop — методы; FX-wiring в одну строку
type Worker struct {
    log    Logger
    svc    Service
    period time.Duration

    cancel context.CancelFunc
    ticker *time.Ticker
    wg     sync.WaitGroup
}

func NewWorker(log Logger, svc Service, cfg *Config) *Worker {
    return &Worker{log: log, svc: svc, period: cfg.Period}
}

func (w *Worker) OnStart(_ context.Context) error {
    runCtx, cancel := context.WithCancel(context.Background())
    w.cancel = cancel
    w.ticker = time.NewTicker(w.period)
    w.wg.Add(1)
    go w.loop(runCtx)
    return nil
}

func (w *Worker) loop(ctx context.Context) {
    defer w.wg.Done()
    for {
        select {
        case <-ctx.Done():
            return
        case <-w.ticker.C:
            if err := w.svc.DoWork(ctx); err != nil {
                w.log.Errorw("iteration failed", "err", err)
            }
        }
    }
}

func (w *Worker) OnStop(ctx context.Context) error {
    w.cancel()
    w.ticker.Stop()
    done := make(chan struct{})
    go func() { w.wg.Wait(); close(done) }()
    select {
    case <-done:
        return nil
    case <-ctx.Done():
        return ctx.Err()
    }
}

// FX-wiring — одна строка
var Module = fx.Module("worker",
    fx.Provide(NewWorker),
    fx.Invoke(func(lc fx.Lifecycle, w *Worker) {
        lc.Append(fx.Hook{OnStart: w.OnStart, OnStop: w.OnStop})
    }),
)
```

**Преимущества:**
- состояние явно живёт в полях, а не в захваченных переменных
- `Worker.OnStart`/`OnStop` тестируются напрямую без поднятия FX-контейнера
- логика цикла вынесена в `(w *Worker).loop` — короче и читаемее
- inline-bootstrap не дублируется между конструкторами разных компонентов

**Признаки в коде:**
- FX-конструктор > 30 строк, большая часть — тело `OnStart`-замыкания
- `var listener net.Listener` / `var cancel context.CancelFunc` объявлены в lifecycle-замыкании
- Похожий inline-bootstrap дублируется в 2+ конструкторах
- В тестах нельзя вызвать lifecycle компонента без `fxtest.New`

**Severity:** 🟡 MEDIUM (читаемость + тестируемость)

## Dependency Injection

### 1. Circular Dependencies

**Anti-pattern:**
```go
// BAD: Circular dependency
func NewServiceA(b *ServiceB) *ServiceA {
    return &ServiceA{b: b}
}

func NewServiceB(a *ServiceA) *ServiceB {
    return &ServiceB{a: a} // Cycle: A -> B -> A
}
```

**Pattern:**
```go
// GOOD: Interface to break cycle
type ServiceAInterface interface {
    DoA()
}

func NewServiceA(b *ServiceB) *ServiceA {
    return &ServiceA{b: b}
}

func NewServiceB(a ServiceAInterface) *ServiceB {
    return &ServiceB{a: a}
}

// GOOD: Lazy initialization
func NewServiceB(a func() *ServiceA) *ServiceB {
    return &ServiceB{getA: a}
}
```

**Severity:** 🟠 HIGH

### 2. Missing Providers

**Anti-pattern:**
```go
// BAD: Dependency not provided
fx.New(
    fx.Provide(NewServer), // Needs *Config, not provided
    fx.Invoke(StartServer),
)
```

**Pattern:**
```go
// GOOD: All dependencies provided
fx.New(
    fx.Provide(
        NewConfig,  // Provides *Config
        NewServer,  // Uses *Config
    ),
    fx.Invoke(StartServer),
)
```

**Severity:** 🔴 CRITICAL (app won't start)

### 3. No Redundant Nil-Checks for FX-Injected Deps

**Проблема:** В FX-конструкторе для обязательной зависимости (`Logger`, `*Config`, `Repository`) пишется `if log == nil { return nil, errors.New("log is nil") }`. Это шум: если зависимость не предоставлена, FX упадёт на этапе сборки графа с понятным сообщением "missing type *zap.Logger" — раньше, чем выполнится конструктор. Nil-check ловит то, что граф уже ловит, и засоряет код.

**Anti-pattern:**
```go
// BAD: defensive nil-checks для обязательных deps
func NewGeneratorWorker(log *zap.Logger, repo deps.Repository, cfg *Config) (*Worker, error) {
    if log == nil {
        return nil, errors.New("log is nil")
    }
    if repo == nil {
        return nil, errors.New("repo is nil")
    }
    if cfg == nil {
        return nil, errors.New("cfg is nil")
    }
    return &Worker{log: log, repo: repo, cfg: cfg}, nil
}
```

**Pattern:**
```go
// GOOD: полагаемся на FX-валидацию графа
func NewGeneratorWorker(log *zap.Logger, repo deps.Repository, cfg *Config) *Worker {
    return &Worker{log: log, repo: repo, cfg: cfg}
}
```

**Когда nil-check нужен:**
- зависимость объявлена `optional:"true"` — FX вернёт `nil`, и обработать это надо явно (см. секцию `3. Optional Dependencies → Optional Dependencies`)
- конструктор используется и вне FX (тесты передают зависимости вручную, есть путь без DI) — но даже там лучше падать с `panic`, чем городить ветви ошибок

**Признаки в коде:**
- В FX-конструкторе с обязательными аргументами есть `if x == nil` без `optional:"true"`
- Конструктор возвращает `(T, error)` только ради `errors.New("X is nil")`
- В тестах нет кейса `X == nil`, но nil-check всё равно есть

**Severity:** 🟡 MEDIUM (засоряет код и ловит то, что граф ловит на старте)

### 4. Optional Dependencies

**Anti-pattern:**
```go
// BAD: Nil check everywhere
func NewService(logger *Logger) *Service {
    s := &Service{logger: logger}
    if s.logger == nil {
        // What to do?
    }
    return s
}
```

**Pattern:**
```go
// GOOD: Use fx.In with optional tag
type ServiceParams struct {
    fx.In
    Logger *Logger `optional:"true"`
}

func NewService(p ServiceParams) *Service {
    s := &Service{}
    if p.Logger != nil {
        s.logger = p.Logger
    } else {
        s.logger = NewNopLogger()
    }
    return s
}
```

**Severity:** 🟡 MEDIUM

## Module Structure

### 1. Module Organization

**Anti-pattern:**
```go
// BAD: Everything in one module
var Module = fx.Module("app",
    fx.Provide(
        NewConfig,
        NewDB,
        NewCache,
        NewUserService,
        NewOrderService,
        NewPaymentService,
        // ... 50 more providers
    ),
)
```

**Pattern:**
```go
// GOOD: Domain-based modules
var Module = fx.Module("app",
    ConfigModule,
    InfraModule,
    UserModule,
    OrderModule,
    PaymentModule,
)

var UserModule = fx.Module("user",
    fx.Provide(
        NewUserRepository,
        NewUserService,
    ),
)

var InfraModule = fx.Module("infra",
    fx.Provide(
        NewDB,
        NewCache,
    ),
)
```

**Severity:** 🟡 MEDIUM

### 2. fx.Provide vs fx.Supply

**Anti-pattern:**
```go
// BAD: Using Provide for static values
fx.Provide(func() *Config {
    return &Config{Port: 8080}
})
```

**Pattern:**
```go
// GOOD: Use Supply for static values
fx.Supply(&Config{Port: 8080})

// GOOD: Provide for computed values
fx.Provide(LoadConfigFromEnv)
```

**Severity:** 💡 INFO

### 3. No `fx.Module` for Stateless Utilities

**Проблема:** `fx.Module` — обёртка для логически связанной группы провайдеров и lifecycle-хуков. Если пакет содержит чистые функции/парсер/билдер запроса без `Lifecycle`, без shared state и без зависимостей друг от друга, оборачивать его в `fx.Module("name", fx.Provide(NewParser))` бессмысленно: модуль ничего не агрегирует, импортирующему сервису всё равно нужно решать, как этим пользоваться. Получается слой косвенности без выгоды — в `app.go` появляется `pagination.Module`, но из самого пакета нельзя вызвать функцию иначе, как через FX.

**Anti-pattern:**
```go
// BAD: модуль для чистых функций
package pagination

import "go.uber.org/fx"

type Parser struct{}

func NewParser() *Parser { return &Parser{} }

func (p *Parser) Parse(r *http.Request) (Request, error) { /* pure */ }

var Module = fx.Module("pagination", fx.Provide(NewParser))
```

```go
// в app.go — каждый импортёр обязан подключать модуль
fx.New(pagination.Module, ...)
```

**Pattern:**
```go
// GOOD: экспортируем чистые функции/struct, без FX-обёртки
package pagination

type Parser struct{}

func NewParser() *Parser { return &Parser{} }

func (p *Parser) Parse(r *http.Request) (Request, error) { /* pure */ }
```

```go
// импортирующий сервис сам решает, нужно ли заворачивать
package order

var Module = fx.Module("order",
    fx.Provide(pagination.NewParser),
    fx.Provide(NewUseCase),
    // ...
)
```

**Когда `fx.Module` оправдан:**
- пакет регистрирует `lc.Append` (Lifecycle-зависимый компонент)
- несколько провайдеров логически связаны (репозиторий + use case + handler)
- есть `fx.Invoke` для side effects на старте
- пакет экспортирует interface bindings через `fx.Annotate` + `fx.As`

**Признаки в коде:**
- `fx.Module` содержит ровно один `fx.Provide` без `Lifecycle`/`Invoke`
- Пакет — чистые helper-функции, никакого shared state
- В тестах функцию приходится вызывать вручную, FX-граф не используется
- `Module`-переменная импортируется только в `app.go`, нигде больше

**Severity:** 🟡 MEDIUM

## Graceful Shutdown

### 1. Shutdown Ordering

**Anti-pattern:**
```go
// BAD: Order not guaranteed
lc.Append(fx.Hook{
    OnStop: func(ctx context.Context) error {
        db.Close() // May close before server stops using it
        return nil
    },
})
```

**Pattern:**
```go
// GOOD: FX handles order automatically (LIFO)
// Dependencies are stopped in reverse order of startup

// If explicit ordering needed:
var ServerModule = fx.Module("server",
    fx.Provide(NewServer),
    fx.Decorate(func(srv *Server, lc fx.Lifecycle) *Server {
        lc.Append(fx.Hook{
            OnStop: func(ctx context.Context) error {
                // Server stops before its dependencies
                return srv.Shutdown(ctx)
            },
        })
        return srv
    }),
)
```

**Severity:** 🟡 MEDIUM

### 2. Context Cancellation

**Anti-pattern:**
```go
// BAD: Not respecting shutdown context
func NewWorker(lc fx.Lifecycle) *Worker {
    w := &Worker{}
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            go w.Run() // No way to stop!
            return nil
        },
    })
    return w
}
```

**Pattern:**
```go
// GOOD: Use context for graceful shutdown
func NewWorker(lc fx.Lifecycle) *Worker {
    w := &Worker{}
    var cancel context.CancelFunc

    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            var runCtx context.Context
            runCtx, cancel = context.WithCancel(context.Background())
            go w.Run(runCtx)
            return nil
        },
        OnStop: func(ctx context.Context) error {
            cancel()
            return w.Wait(ctx)
        },
    })
    return w
}
```

**Severity:** 🟠 HIGH

## fx.Annotate & fx.As

### 1. Interface Binding with fx.As

**Проблема:** Конструктор возвращает конкретный тип, но потребителям нужен интерфейс. Без `fx.As` приходится менять сигнатуру конструктора.

**Anti-pattern:**
```go
// BAD: Constructor returns interface — hides implementation details
func NewRepository(db *sql.DB) deps.Repository {
    return &repository{db: db}
}
```

**Pattern:**
```go
// GOOD: Constructor returns concrete type, fx.As binds to interface
func NewRepository(db *sql.DB) *Repository {
    return &Repository{db: db}
}

var Module = fx.Module("order",
    fx.Provide(
        fx.Annotate(
            NewRepository,
            fx.As(new(deps.Repository)),
        ),
    ),
)
```

**Severity:** 🟡 MEDIUM

### 2. Named Dependencies with ResultTags/ParamTags

**Проблема:** Несколько реализаций одного интерфейса — FX не может различить.

**Anti-pattern:**
```go
// BAD: Two *redis.Client in container — ambiguous
fx.Provide(NewCacheRedis, NewSessionRedis)

func NewService(cache *redis.Client, session *redis.Client) *Service {
    // Which is which?
}
```

**Pattern:**
```go
// GOOD: Named dependencies via tags
fx.Provide(
    fx.Annotate(NewCacheRedis, fx.ResultTags(`name:"cache"`)),
    fx.Annotate(NewSessionRedis, fx.ResultTags(`name:"session"`)),
),

type ServiceParams struct {
    fx.In
    Cache   *redis.Client `name:"cache"`
    Session *redis.Client `name:"session"`
}

func NewService(p ServiceParams) *Service {
    return &Service{cache: p.Cache, session: p.Session}
}
```

**Severity:** 🟡 MEDIUM

### 2.1 Typed Config Wrappers vs Named Tags

**Проблема:** Когда нужно различать **несколько инстансов конфига одного типа** (например, `*config.GRPCClientConfig` для ledger, balance, autowithdraw), соблазн использовать `name:"..."`-теги. Но строковые имена не проверяются компилятором: опечатка в `name:"balanceServiceConfig"` → паника на старте FX, а не ошибка билда. Для конфигов лучше типизированные обёртки — каждый клиент получает свой конкретный тип.

**Anti-pattern:**
```go
// BAD: строковые имена для разных gRPC-клиентов одного типа конфига
type Config struct {
    Ledger          *GRPCClientConfig `name:"ledgerServiceConfig"`
    Balance         *GRPCClientConfig `name:"balanceServiceConfig"`
    Autowithdraw    *GRPCClientConfig `name:"autowithdrawServiceConfig"`
}

// в пакете balance:
type Params struct {
    fx.In
    Config *config.GRPCClientConfig `name:"balanceServiceConfig"` // опечатка → runtime panic
    Logger *zap.Logger
}

// в провайдере конфига:
fx.Provide(
    fx.Annotate(loadBalanceCfg, fx.ResultTags(`name:"balanceServiceConfig"`)),
    fx.Annotate(loadLedgerCfg,  fx.ResultTags(`name:"ledgerServiceConfig"`)),
)
```

**Pattern:**
```go
// GOOD: типизированная обёртка на каждый клиент
package balance

type Config struct {
    *config.GRPCClientConfig // inline
    // можно добавить специфичные поля при необходимости
}

type Params struct {
    fx.In
    Config *Config            // компилятор проверит тип
    Logger *zap.Logger
}

// в config.go:
type Config struct {
    Ledger       LedgerClientConfig
    Balance      BalanceClientConfig
    Autowithdraw AutowithdrawClientConfig
}

type BalanceClientConfig struct {
    GRPCClientConfig // env tags наследуются
}

// в провайдере: разные типы → FX автоматически роутит по типу,
// никаких ResultTags/ParamTags не нужно.
fx.Provide(
    func(c *Config) *BalanceClientConfig { return &c.Balance },
    func(c *Config) *LedgerClientConfig  { return &c.Ledger },
)
```

**Когда `name:"..."` всё-таки уместен:**
- разные инстансы внешней библиотеки одного типа, который нельзя обернуть (`*redis.Client`, `*sql.DB` для двух разных БД) — там типизированная обёртка добавляет лишнюю прослойку без смысла
- конфиги команды разделены по доменам и типы уже отдельные → `name` не нужен

**Правило:** если ты пишешь `name:"<x>ServiceConfig"` несколько раз на разные клиенты — заменяй на типизированные обёртки. Для случайных коллизий *чужих* типов — оставляй теги.

**Severity:** 🟡 MEDIUM (надёжность + проверка компилятором)

### 3. Parameter Objects with fx.In/fx.Out

**Проблема:** Конструктор с 5+ аргументами — сложно читать и поддерживать.

**Anti-pattern:**
```go
// BAD: Too many constructor arguments
func NewService(
    db *sql.DB,
    cache *redis.Client,
    logger *zap.Logger,
    tracer trace.Tracer,
    meter metric.Meter,
    cfg *Config,
) *Service {
    // ...
}
```

**Pattern:**
```go
// GOOD: Parameter object with fx.In
type ServiceParams struct {
    fx.In
    DB     *sql.DB
    Cache  *redis.Client
    Logger *zap.Logger
    Tracer trace.Tracer
    Meter  metric.Meter
    Cfg    *Config
}

func NewService(p ServiceParams) *Service {
    return &Service{
        db:     p.DB,
        cache:  p.Cache,
        logger: p.Logger,
    }
}

// GOOD: Result object with fx.Out
type ServiceResult struct {
    fx.Out
    Service    *Service
    HealthCheck health.Checker `group:"health"`
}

func NewService(p ServiceParams) ServiceResult {
    svc := &Service{db: p.DB}
    return ServiceResult{
        Service:     svc,
        HealthCheck: svc, // implements health.Checker
    }
}
```

**Severity:** 🟡 MEDIUM

## Testing

### 1. fx.Test Usage

**Anti-pattern:**
```go
// BAD: Testing with full app
func TestService(t *testing.T) {
    app := fx.New(FullAppModule)
    app.Start(context.Background())
    // ... tests
}
```

**Pattern:**
```go
// GOOD: Use fxtest for isolated testing
func TestService(t *testing.T) {
    var svc *Service

    app := fxtest.New(t,
        fx.Provide(
            NewMockDB,
            NewMockCache,
            NewService,
        ),
        fx.Populate(&svc),
    )
    app.RequireStart()
    defer app.RequireStop()

    // Test svc...
}
```

**Severity:** 🟡 MEDIUM

### 2. Replace Modules for Testing

**Anti-pattern:**
```go
// BAD: Can't mock real dependencies
var DBModule = fx.Module("db",
    fx.Provide(NewRealDB),
)
```

**Pattern:**
```go
// GOOD: Interface-based for easy mocking
type DBInterface interface {
    Query(ctx context.Context, sql string) (*Result, error)
}

var DBModule = fx.Module("db",
    fx.Provide(
        fx.Annotate(
            NewRealDB,
            fx.As(new(DBInterface)),
        ),
    ),
)

// In tests:
var MockDBModule = fx.Module("db",
    fx.Provide(
        fx.Annotate(
            NewMockDB,
            fx.As(new(DBInterface)),
        ),
    ),
)
```

**Severity:** 🟡 MEDIUM

### 3. Mock Providers

**Pattern:**
```go
// Using fx.Replace for testing
func TestWithMocks(t *testing.T) {
    app := fxtest.New(t,
        AppModule,
        fx.Replace(&MockConfig{Port: 0}),
        fx.Decorate(func() DBInterface {
            return &MockDB{}
        }),
    )
}
```

**Severity:** 💡 INFO

## Multiple Interface Bindings

### Single Constructor → Several Interfaces

**Проблема:** Одна реализация удовлетворяет нескольким узким интерфейсам (например, кэш реализует и `OrderCache`, и `UserCache`, и `health.Checker`). Без `fx.As` приходится либо плодить отдельные конструкторы, либо менять сигнатуру `New` так, чтобы возвращался самый "широкий" интерфейс — тогда теряется доступ к остальным методам типа.

**Pattern:**
```go
// Конструктор остаётся возвращающим конкретный тип
type RedisCache struct { /* ... */ }

func NewRedisCache(cfg *Config) *RedisCache { /* ... */ }

func (c *RedisCache) GetOrder(ctx context.Context, id string) (*Order, error) { /* ... */ }
func (c *RedisCache) GetUser(ctx context.Context, id string) (*User, error)   { /* ... */ }
func (c *RedisCache) Check(ctx context.Context) error                          { /* ... */ }

// fx.Annotate с несколькими fx.As — один провайдер регистрирует несколько интерфейсов
var Module = fx.Module("cache",
    fx.Provide(
        fx.Annotate(
            NewRedisCache,
            fx.As(new(deps.OrderCache)),
            fx.As(new(deps.UserCache)),
            fx.As(new(health.Checker)),
        ),
    ),
)
```

**Когда применять:**
- инфраструктурный компонент (БД, кэш, MQ-коннектор) удовлетворяет 2+ узким интерфейсам разных доменов
- хочется избежать дублирования провайдера (`NewOrderCache`, `NewUserCache` поверх одного `*RedisCache`)
- альтернатива через возврат интерфейса теряет доступ к специфичным методам типа

**Severity:** 🟡 MEDIUM

## Config Decomposition

### Splitting a Monolithic Config into Domain-Scoped Sub-Configs

**Проблема:** Большое приложение часто заводит один `*Config` со всеми полями (DB, Redis, Kafka, gRPC-клиенты, фичи). Любой провайдер, которому нужна одна строка из конфига, начинает зависеть от всего `*Config` — тестам приходится конструировать монолит, изменения в `Config` каскадом ломают сигнатуры провайдеров.

**Anti-pattern:**
```go
// BAD: каждый провайдер берёт *Config целиком
type Config struct {
    DB    DBConfig
    Redis RedisConfig
    Kafka KafkaConfig
}

func NewDB(cfg *Config) *sql.DB     { /* uses cfg.DB */ }
func NewRedis(cfg *Config) *redis.Client { /* uses cfg.Redis */ }
// каждый знает про весь Config — тестировать сложно
```

**Pattern:**
```go
import "github.com/caarlos0/env/v10" // или sethvargo/go-envconfig

// Корневой конфиг с env-prefix-ами
type Config struct {
    DB    DBConfig    `envPrefix:"DB_"`
    Redis RedisConfig `envPrefix:"REDIS_"`
    Kafka KafkaConfig `envPrefix:"KAFKA_"`
}

type DBConfig struct {
    DSN          string        `env:"DSN,required"`
    MaxConns     int32         `env:"MAX_CONNS"     envDefault:"10"`
    MaxConnLifetime time.Duration `env:"MAX_CONN_LIFETIME" envDefault:"30m"`
}

func LoadConfig() (*Config, error) {
    cfg := &Config{}
    return cfg, env.Parse(cfg)
}

// Распаковка sub-конфигов в отдельные провайдеры
var ConfigModule = fx.Module("config",
    fx.Provide(
        LoadConfig,
        func(c *Config) *DBConfig    { return &c.DB },
        func(c *Config) *RedisConfig { return &c.Redis },
        func(c *Config) *KafkaConfig { return &c.Kafka },
    ),
)

// Провайдеры зависят только от своего sub-конфига
func NewDB(cfg *DBConfig) (*sql.DB, error)        { /* ... */ }
func NewRedis(cfg *RedisConfig) (*redis.Client, error) { /* ... */ }
```

**Преимущества:**
- `NewDB` тестируется без знания про `RedisConfig`/`KafkaConfig`
- изменение `RedisConfig.MaxIdleConns` не трогает сигнатуру провайдера БД
- env-теги наследуются через `envPrefix` — единообразный формат `DB_DSN`, `REDIS_ADDR`

**Когда стоит:** домен > 3–4 sub-конфигов, или когда тестирование одного провайдера тянет загрузку всего `Config`. Для маленьких приложений монолит приемлем.

**Severity:** 🟡 MEDIUM

## Module Composition by Domains

### Per-Domain `fx.Module` Files

**Проблема:** Сборка контейнера в одном файле `internal/app/app.go` со всеми `fx.Provide` приводит к гигантскому списку и слабой инкапсуляции — добавление нового домена требует правки центрального файла, а не только домена.

**Pattern:**
```
internal/
├── app/
│   └── app.go              // root: fx.New(ConfigModule, InfraModule, OrderModule, ...)
├── infrastructure/
│   ├── db/fx.go            // DBModule
│   ├── redis/fx.go         // RedisModule
│   └── kafka/fx.go         // KafkaModule
└── domain/
    ├── order/
    │   ├── fx.go           // OrderModule = fx.Module("order", repo + uc + handler)
    │   ├── repository/postgres/repository.go
    │   ├── usecase/usecase.go
    │   └── delivery/grpc/handler.go
    └── user/
        ├── fx.go           // UserModule
        └── ...
```

```go
// internal/domain/order/fx.go
package order

import (
    "go.uber.org/fx"
    "project/internal/domain/order/delivery/grpc"
    "project/internal/domain/order/deps"
    "project/internal/domain/order/repository/postgres"
    "project/internal/domain/order/usecase"
)

var Module = fx.Module("order",
    fx.Provide(
        fx.Annotate(postgres.NewRepository, fx.As(new(deps.OrderRepository))),
        usecase.NewUseCase,
        grpc.NewHandler,
    ),
)
```

```go
// internal/app/app.go
package app

import (
    "go.uber.org/fx"
    "project/internal/domain/order"
    "project/internal/domain/user"
    "project/internal/infrastructure/db"
    "project/internal/infrastructure/redis"
)

var Module = fx.Module("app",
    db.Module,
    redis.Module,
    order.Module,
    user.Module,
)
```

**Преимущества:**
- добавить домен — добавить одну строку в `app.go`, остальное в `domain/<X>/fx.go`
- `Module`-переменная домена импортируется и тестируется как единое целое
- root-файл остаётся коротким и читаемым

**Severity:** 🟡 MEDIUM
