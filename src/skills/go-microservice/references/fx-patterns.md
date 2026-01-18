# Uber FX Patterns Reference

Advanced dependency injection patterns with Uber FX.

---

## Module Definition

### Basic Module

```go
package order

import "go.uber.org/fx"

var Module = fx.Module(
    "order",  // Module name for debugging
    fx.Provide(
        NewRepository,
        NewUseCase,
        NewHandlers,
        NewRouter,
    ),
)
```

### Module with Annotations

```go
var Module = fx.Module(
    "order",
    fx.Provide(
        // Return interface instead of concrete type
        fx.Annotate(
            postgres.NewRepository,
            fx.As(new(deps.OrderRepository)),
        ),

        // Named dependencies
        fx.Annotate(
            NewCryptoAdapter,
            fx.ResultTags(`name:"cryptoAdapter"`),
        ),
        fx.Annotate(
            NewFiatAdapter,
            fx.ResultTags(`name:"fiatAdapter"`),
        ),

        NewUseCase,
    ),
)
```

---

## fx.Provide Patterns

### Simple Provider

```go
// Constructor returns concrete type
func NewRepository(db *sqlx.DB) *Repository {
    return &Repository{db: db}
}

// Registration
fx.Provide(NewRepository)
```

### Interface Provider with fx.As

```go
// Constructor returns concrete type
func NewRepository(db *sqlx.DB) *Repository {
    return &Repository{db: db}
}

// Registration - provide as interface
fx.Provide(
    fx.Annotate(
        NewRepository,
        fx.As(new(deps.Repository)),
    ),
)
```

### Multiple Interfaces from One Constructor

```go
// Constructor returns concrete type implementing multiple interfaces
func NewStorage(db *sqlx.DB) *Storage {
    return &Storage{db: db}
}

// Provide as multiple interfaces
fx.Provide(
    fx.Annotate(
        NewStorage,
        fx.As(new(deps.OrderRepository)),
        fx.As(new(deps.UserRepository)),
    ),
)
```

### Named Dependencies

```go
// Producer: Tag the result
fx.Provide(
    fx.Annotate(
        NewPrimaryDB,
        fx.ResultTags(`name:"primary"`),
    ),
    fx.Annotate(
        NewReplicaDB,
        fx.ResultTags(`name:"replica"`),
    ),
)

// Consumer: Tag the parameter
type Params struct {
    fx.In
    PrimaryDB *sqlx.DB `name:"primary"`
    ReplicaDB *sqlx.DB `name:"replica"`
}

func NewRepository(p Params) *Repository {
    return &Repository{
        write: p.PrimaryDB,
        read:  p.ReplicaDB,
    }
}
```

### Group Dependencies

```go
// Producer: Add to group
fx.Provide(
    fx.Annotate(
        NewOrderHandler,
        fx.ResultTags(`group:"handlers"`),
    ),
    fx.Annotate(
        NewUserHandler,
        fx.ResultTags(`group:"handlers"`),
    ),
)

// Consumer: Receive all group members
type Params struct {
    fx.In
    Handlers []Handler `group:"handlers"`
}

func NewRouter(p Params) *Router {
    r := &Router{}
    for _, h := range p.Handlers {
        r.Register(h)
    }
    return r
}
```

---

## fx.In and fx.Out

### fx.In - Multiple Dependencies

```go
type Params struct {
    fx.In

    Logger    logger.ILogger
    DB        pgconnector.IDB
    Redis     redisconnector.IRedis
    Config    *config.BusinessConfig

    // Optional dependency
    Tracer    tracer.ITracer `optional:"true"`

    // Named dependency
    Primary   *sqlx.DB `name:"primary"`
}

func NewUseCase(p Params) *UseCase {
    return &UseCase{
        log:   p.Logger,
        db:    p.DB,
        redis: p.Redis,
        cfg:   p.Config,
    }
}
```

### fx.Out - Multiple Results

```go
type Result struct {
    fx.Out

    Config      *Config
    Logger      *loggerconfig.LoggerConfig
    DB          *pgconfig.PGConnectorConfig
    Redis       *redisconfig.RedisConfig
    Business    *BusinessConfig
}

func Out() (Result, error) {
    cfg, err := loadConfig()
    if err != nil {
        return Result{}, err
    }

    return Result{
        Config:   &cfg,
        Logger:   &cfg.Logger,
        DB:       &cfg.DB,
        Redis:    &cfg.Redis,
        Business: &cfg.Business,
    }, nil
}
```

---

## fx.Invoke

### Side Effects

```go
// Register routes - side effect, no return value
fx.Invoke(func(router *Router, handlers *Handlers) {
    router.Register("/orders", handlers.CreateOrder)
    router.Register("/orders/{id}", handlers.GetOrder)
})
```

### Lifecycle Registration

```go
fx.Invoke(func(lc fx.Lifecycle, server *Server) {
    lc.Append(fx.Hook{
        OnStart: server.Start,
        OnStop:  server.Stop,
    })
})
```

---

## Lifecycle Hooks

### Basic OnStart/OnStop

```go
type Server struct {
    httpServer *http.Server
}

func (s *Server) OnStart(ctx context.Context) error {
    go func() {
        if err := s.httpServer.ListenAndServe(); err != http.ErrServerClosed {
            log.Fatalf("HTTP server error: %v", err)
        }
    }()
    return nil
}

func (s *Server) OnStop(ctx context.Context) error {
    return s.httpServer.Shutdown(ctx)
}

// Registration
fx.Invoke(func(lc fx.Lifecycle, s *Server) {
    lc.Append(fx.Hook{
        OnStart: s.OnStart,
        OnStop:  s.OnStop,
    })
})
```

### Worker with Graceful Shutdown

```go
type Worker struct {
    ticker *time.Ticker
    done   chan bool
}

func NewWorker() *Worker {
    return &Worker{
        ticker: time.NewTicker(5 * time.Minute),
        done:   make(chan bool),
    }
}

func (w *Worker) Start(ctx context.Context) error {
    go func() {
        for {
            select {
            case <-w.done:
                return
            case <-w.ticker.C:
                w.process(ctx)
            }
        }
    }()
    return nil
}

func (w *Worker) Stop(ctx context.Context) error {
    w.ticker.Stop()
    w.done <- true
    return nil
}

// Worker module
var WorkerModule = fx.Module(
    "worker",
    fx.Provide(NewWorker),
    fx.Invoke(func(lc fx.Lifecycle, w *Worker) {
        lc.Append(fx.Hook{
            OnStart: w.Start,
            OnStop:  w.Stop,
        })
    }),
)
```

### Consumer with Blocking Loop

```go
type KafkaConsumer struct {
    consumer kafkaconnector.IConsumer
    cancel   context.CancelFunc
}

func (c *KafkaConsumer) OnStart(ctx context.Context) error {
    consumerCtx, cancel := context.WithCancel(context.Background())
    c.cancel = cancel

    go func() {
        c.consumer.Consume() // Blocking
    }()

    return nil
}

func (c *KafkaConsumer) OnStop(ctx context.Context) error {
    if c.cancel != nil {
        c.cancel()
    }
    return nil
}
```

---

## Module Aggregation

### Domain Module

```go
// internal/domain/fx.go
package domain

import (
    "go.uber.org/fx"

    "service/internal/domain/order"
    "service/internal/domain/user"
    "service/internal/domain/product"
)

var Module = fx.Module(
    "domain",
    order.Module,
    user.Module,
    product.Module,
)
```

### Infrastructure Module

```go
// internal/infrastructure/fx.go
package infrastructure

import (
    "go.uber.org/fx"

    "service/internal/infrastructure/grpc"
    "service/internal/infrastructure/http"
)

var Module = fx.Module(
    "infrastructure",
    http.ServerModule,
    grpc.ServerModule,
)
```

### Application Composition

```go
// internal/app/app.go
func CreateApp() fx.Option {
    return fx.Options(
        // External packages (order matters for dependencies)
        loggerfx.LoggerFx,
        healthfx.HealthCheckFx,
        pgconnectorfx.PGConnectorFx,
        redisfx.RedisFx,

        // Internal modules
        domain.Module,
        infrastructure.Module,

        // Configuration
        fx.Provide(
            config.Out,
            context.Background,
        ),

        // Final setup
        healthfx.ReadinessProbeFX,
    )
}
```

---

## Testing

### Graph Validation

```go
// internal/app/app_test.go
func Test__CreateApp(t *testing.T) {
    err := fx.ValidateApp(CreateApp())
    require.NoError(t, err)
}
```

### Module Testing

```go
func TestOrderModule(t *testing.T) {
    err := fx.ValidateApp(
        fx.Options(
            // Mock dependencies
            fx.Provide(func() *sqlx.DB { return nil }),
            fx.Provide(func() logger.ILogger { return nil }),

            // Module under test
            order.Module,
        ),
    )
    require.NoError(t, err)
}
```

### Integration Test with fx.Populate

```go
func TestIntegration(t *testing.T) {
    var uc *UseCase

    app := fx.New(
        CreateApp(),
        fx.Populate(&uc), // Extract dependency for testing
    )

    ctx := context.Background()
    require.NoError(t, app.Start(ctx))
    defer app.Stop(ctx)

    // Test using uc
    result, err := uc.Process(ctx, testInput)
    require.NoError(t, err)
}
```

---

## Common Patterns

### Conditional Providers

```go
func CreateApp(env string) fx.Option {
    options := []fx.Option{
        loggerfx.LoggerFx,
        domain.Module,
    }

    if env == "production" {
        options = append(options, fx.Provide(NewProductionDB))
    } else {
        options = append(options, fx.Provide(NewTestDB))
    }

    return fx.Options(options...)
}
```

### Decorator Pattern

```go
// Original provider
fx.Provide(NewRepository)

// Decorator that wraps original
fx.Decorate(func(repo *Repository, tracer tracer.ITracer) *Repository {
    return &TracingRepository{
        inner:  repo,
        tracer: tracer,
    }
})
```

### Replace for Testing

```go
// In tests, replace real implementation with mock
fx.Replace(func() deps.Repository {
    return &MockRepository{}
})
```

---

## Error Handling

### Constructor Errors

```go
func NewRepository(cfg *Config) (*Repository, error) {
    if cfg.DSN == "" {
        return nil, fmt.Errorf("database DSN is required")
    }

    db, err := sqlx.Connect("postgres", cfg.DSN)
    if err != nil {
        return nil, fmt.Errorf("connect to database: %w", err)
    }

    return &Repository{db: db}, nil
}
```

### OnStart Errors

```go
func (s *Server) OnStart(ctx context.Context) error {
    if err := s.validate(); err != nil {
        return fmt.Errorf("server validation failed: %w", err)
    }

    if err := s.listen(); err != nil {
        return fmt.Errorf("server listen failed: %w", err)
    }

    return nil
}
```

If OnStart returns error, fx.App.Start() will fail and all previously started hooks will receive OnStop.

---

## Best Practices

1. **Use interfaces in deps package** - Define what you need, not what you have
2. **Use fx.As for interface binding** - Return concrete, bind to interface
3. **Keep modules focused** - One domain = one module
4. **Use fx.In/fx.Out for multiple deps** - Cleaner than many constructor params
5. **Always implement OnStop** - Clean shutdown prevents resource leaks
6. **Validate graph in tests** - `fx.ValidateApp()` catches wiring errors early
7. **Use named deps sparingly** - Prefer interfaces over names
8. **Log in OnStart/OnStop** - Helps debug startup issues
