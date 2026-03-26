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

### 3. Optional Dependencies

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
