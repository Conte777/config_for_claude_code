# Template Structure Reference

Complete description of each file and directory in the microservice template.

**Template Location:** `D:\Work\friday_releases\cryptoprocessing\shared\service_template`

---

## Entry Point

### cmd/app/main.go

Entry point with signal handling and graceful shutdown.

```go
func main() {
    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    application := fx.New(app.CreateApp())
    if err := application.Start(ctx); err != nil {
        panic(fmt.Errorf("failed to start: %w", err))
    }

    <-ctx.Done()

    stopCtx, stopCancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer stopCancel()

    if err := application.Stop(stopCtx); err != nil {
        panic(fmt.Errorf("failed to stop: %w", err))
    }
}
```

**Key Points:**
- Use `signal.NotifyContext` for graceful shutdown on SIGINT/SIGTERM
- Create fx application with `app.CreateApp()`
- Wait for context cancellation
- Use timeout context for shutdown

---

## Configuration

### config/config.go

Configuration struct with fx.Out pattern for dependency injection.

```go
type Config struct {
    containers.AppConfig
    HTTPServer   containers.HttpServerConfig    `envPrefix:"HTTP_SERVER_" yaml:"HttpServer" validate:"required"`
    HealthCheck  healthconfig.HealthCheckConfig `envPrefix:"HEALTHCHECK_" yaml:"HealthCheck" validate:"required"`
    Logger       loggerconfig.LoggerConfig      `envPrefix:"LOGGER_" yaml:"Logger" validate:"required"`
    Redis        redisconfig.RedisConfig        `envPrefix:"REDIS_" yaml:"Redis" validate:"required"`
    DB           config.PGConnectorConfig       `envPrefix:"DB_" yaml:"Db" validate:"required"`
    Business     BusinessConfig                 `envPrefix:"BUSINESS_" yaml:"Business" validate:"required"`
    GRPCServer   containers.GRPCServerConfig    `envPrefix:"GRPC_" yaml:"GRPC" validate:"required"`
}

type BusinessConfig struct {
    Attr string `env:"ATTR" yaml:"ATTR" validate:"required"`
}

// fx.Out pattern - returns multiple dependencies
type Result struct {
    fx.Out
    App         *containers.AppConfig
    Config      *Config
    HealthCheck *healthconfig.HealthCheckConfig
    Logger      *loggerconfig.LoggerConfig
    Redis       *redisconfig.RedisConfig
    Business    *BusinessConfig
    HTTPServ    *containers.HttpServerConfig
    DB          *config.PGConnectorConfig
}

func Out() (Result, error) {
    cfg, err := configurator.NewConfigurator[Config](constants.ENV).GetConfig()
    if err != nil {
        return Result{}, err
    }
    return Result{
        App:         &cfg.AppConfig,
        Config:      &cfg,
        HealthCheck: &cfg.HealthCheck,
        Logger:      &cfg.Logger,
        Redis:       &cfg.Redis,
        Business:    &cfg.Business,
        HTTPServ:    &cfg.HTTPServer,
        DB:          &cfg.DB,
    }, nil
}
```

**Tag Format:**
- `envPrefix:"PREFIX_"` - Environment variable prefix
- `yaml:"FieldName"` - YAML field name
- `validate:"required"` - Validation rule

**Common Environment Variables:**
```
APP_NAME, APP_VERSION, STAND
HEALTHCHECK_PORT, HEALTHCHECK_PATH
LOGGER_SERVICE_NAME, LOGGER_DEVELOPMENT, LOGGER_ENCODING, LOGGER_LEVEL
HTTP_SERVER_HOST, HTTP_SERVER_PORT
REDIS_DSN, REDIS_DB, REDIS_PASSWORD
DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_DATABASE, DB_SSL_MODE
```

---

## Application Bootstrap

### internal/app/app.go

fx module composition.

```go
func CreateApp() fx.Option {
    return fx.Options(
        // Infrastructure
        loggerfx.LoggerFx,
        healthfx.HealthCheckFx,
        pgconnectorfx.PGConnectorFx,
        redisfx.RedisFx,

        // Domain logic
        domain.Module,

        // Infrastructure servers
        infrastructure.Module,

        // Configuration
        fx.Provide(
            config.Out,
            context.Background,
        ),

        // Health probes
        healthfx.ReadinessProbeFX,
    )
}
```

### internal/app/app_test.go

fx graph validation test.

```go
func Test__CreateApp(t *testing.T) {
    require.NoError(t, fx.ValidateApp(CreateApp()))
}
```

Run with: `go test -run Test__CreateApp ./internal/app`

---

## Domain Structure

### internal/domain/fx.go

Aggregation of all domain modules.

```go
var Module = fx.Module(
    "domain",
    order.Module,
    user.Module,
    product.Module,
    // Add new domain modules here
)
```

### internal/domain/{name}/

Complete domain directory structure:

```
internal/domain/{name}/
├── fx.go                         # fx.Module registration
├── consts/
│   └── permission_scope.go       # Scope constants
├── delivery/
│   ├── http/
│   │   ├── handlers.go           # HTTP handlers
│   │   └── router.go             # Route registration
│   ├── grpc/
│   │   └── handlers.go           # gRPC handlers
│   ├── kafka/
│   │   └── handlers.go           # Kafka consumers
│   └── rabbit/
│       └── handlers.go           # RabbitMQ consumers
├── deps/
│   └── dep.go                    # Interface definitions
├── dto/
│   └── dto.go                    # Request/Response structs
├── entities/
│   └── entities.go               # Domain entities
├── errors/
│   └── errors.go                 # Domain errors
├── repository/
│   ├── postgres/
│   │   └── repo.go               # PostgreSQL implementation
│   └── http_clients/
│       └── {service}/client.go   # External HTTP client
├── usecase/
│   └── buissines/
│       └── uc.go                 # Business logic
└── workers/
    ├── fx.go                     # Workers fx.Module
    └── worker.go                 # Worker implementation
```

---

## Domain Files Detail

### fx.go (Domain Module)

```go
package order

import (
    "go.uber.org/fx"

    "service/internal/domain/order/delivery/http"
    "service/internal/domain/order/repository/postgres"
    "service/internal/domain/order/usecase/buissines"
)

var Module = fx.Module(
    "order",
    fx.Provide(
        postgres.NewRepository,
        buissines.NewUseCase,
        http.NewHandlers,
        http.NewRouter,
    ),
)
```

### consts/permission_scope.go

```go
package consts

const (
    ScopeOrderRead   = "order:read"
    ScopeOrderWrite  = "order:write"
    ScopeOrderDelete = "order:delete"
)
```

### entities/entities.go

```go
package entities

import (
    "github.com/google/uuid"
    "service/pkg/timetools"
)

type Order struct {
    ID        uuid.UUID              `db:"id" json:"id"`
    UserID    uuid.UUID              `db:"user_id" json:"userId"`
    Status    OrderStatus            `db:"status" json:"status"`
    Amount    string                 `db:"amount" json:"amount"`
    CreatedAt timetools.FrontendTime `db:"created_at" json:"createdAt"`
    UpdatedAt timetools.FrontendTime `db:"updated_at" json:"updatedAt"`
}

type OrderStatus string

const (
    OrderStatusPending   OrderStatus = "pending"
    OrderStatusCompleted OrderStatus = "completed"
    OrderStatusCancelled OrderStatus = "cancelled"
)
```

### dto/dto.go

```go
package dto

import "github.com/google/uuid"

// Request structs
type CreateOrderRequest struct {
    UserID uuid.UUID `json:"userId" validate:"required"`
    Amount string    `json:"amount" validate:"required,numeric"`
}

type GetOrdersRequest struct {
    Limit  int `query:"limit" validate:"min=1,max=100"`
    Offset int `query:"offset" validate:"min=0"`
}

type UpdateOrderRequest struct {
    Status string `json:"status" validate:"required,oneof=pending completed cancelled"`
}

// Response structs
type CreateOrderResponse struct {
    ID uuid.UUID `json:"id"`
}

type OrderResponse struct {
    ID        uuid.UUID `json:"id"`
    UserID    uuid.UUID `json:"userId"`
    Status    string    `json:"status"`
    Amount    string    `json:"amount"`
    CreatedAt string    `json:"createdAt"`
}

type OrdersListResponse struct {
    Orders []OrderResponse `json:"orders"`
    Total  int             `json:"total"`
}
```

### deps/dep.go

```go
package deps

import (
    "context"

    "github.com/google/uuid"
    "service/internal/domain/order/entities"
)

type OrderRepository interface {
    Create(ctx context.Context, order *entities.Order) error
    GetByID(ctx context.Context, id uuid.UUID) (*entities.Order, error)
    GetByUserID(ctx context.Context, userID uuid.UUID, limit, offset int) ([]entities.Order, int, error)
    Update(ctx context.Context, order *entities.Order) error
    Delete(ctx context.Context, id uuid.UUID) error
}

type PaymentClient interface {
    ProcessPayment(ctx context.Context, orderID uuid.UUID, amount string) error
    RefundPayment(ctx context.Context, orderID uuid.UUID) error
}

type NotificationClient interface {
    SendOrderCreated(ctx context.Context, order *entities.Order) error
    SendOrderCompleted(ctx context.Context, order *entities.Order) error
}
```

### repository/postgres/repo.go

```go
package postgres

import (
    "context"
    "fmt"

    "github.com/google/uuid"
    "github.com/jmoiron/sqlx"

    "service/internal/domain/order/deps"
    "service/internal/domain/order/entities"
    pkgerrors "service/pkg/errors"
)

type Repository struct {
    db *sqlx.DB
}

func NewRepository(db *sqlx.DB) deps.OrderRepository {
    return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, order *entities.Order) error {
    query := `
        INSERT INTO orders (id, user_id, status, amount, created_at, updated_at)
        VALUES (:id, :user_id, :status, :amount, :created_at, :updated_at)
    `
    _, err := r.db.NamedExecContext(ctx, query, order)
    if err != nil {
        return fmt.Errorf("create order: %w", err)
    }
    return nil
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*entities.Order, error) {
    var order entities.Order
    query := `SELECT * FROM orders WHERE id = $1`
    err := r.db.GetContext(ctx, &order, query, id)
    if err != nil {
        return nil, pkgerrors.NewNotFoundError("order not found")
    }
    return &order, nil
}

func (r *Repository) GetByUserID(ctx context.Context, userID uuid.UUID, limit, offset int) ([]entities.Order, int, error) {
    var orders []entities.Order
    query := `SELECT * FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`
    err := r.db.SelectContext(ctx, &orders, query, userID, limit, offset)
    if err != nil {
        return nil, 0, fmt.Errorf("get orders: %w", err)
    }

    var total int
    countQuery := `SELECT COUNT(*) FROM orders WHERE user_id = $1`
    err = r.db.GetContext(ctx, &total, countQuery, userID)
    if err != nil {
        return nil, 0, fmt.Errorf("count orders: %w", err)
    }

    return orders, total, nil
}

func (r *Repository) Update(ctx context.Context, order *entities.Order) error {
    query := `
        UPDATE orders SET status = :status, amount = :amount, updated_at = :updated_at
        WHERE id = :id
    `
    result, err := r.db.NamedExecContext(ctx, query, order)
    if err != nil {
        return fmt.Errorf("update order: %w", err)
    }

    rows, _ := result.RowsAffected()
    if rows == 0 {
        return pkgerrors.NewNotFoundError("order not found")
    }
    return nil
}

func (r *Repository) Delete(ctx context.Context, id uuid.UUID) error {
    query := `DELETE FROM orders WHERE id = $1`
    result, err := r.db.ExecContext(ctx, query, id)
    if err != nil {
        return fmt.Errorf("delete order: %w", err)
    }

    rows, _ := result.RowsAffected()
    if rows == 0 {
        return pkgerrors.NewNotFoundError("order not found")
    }
    return nil
}
```

### usecase/buissines/uc.go

```go
package buissines

import (
    "context"
    "time"

    "github.com/google/uuid"

    "service/internal/domain/order/deps"
    "service/internal/domain/order/dto"
    "service/internal/domain/order/entities"
    domainerrors "service/internal/domain/order/errors"
    pkgerrors "service/pkg/errors"
    "service/pkg/timetools"
)

type UseCase struct {
    repo    deps.OrderRepository
    payment deps.PaymentClient
}

func NewUseCase(repo deps.OrderRepository, payment deps.PaymentClient) *UseCase {
    return &UseCase{
        repo:    repo,
        payment: payment,
    }
}

func (uc *UseCase) CreateOrder(ctx context.Context, req *dto.CreateOrderRequest) (*dto.CreateOrderResponse, error) {
    if req.Amount == "" {
        return nil, pkgerrors.NewValidationError("amount is required")
    }

    now := timetools.FrontendTime(time.Now())
    order := &entities.Order{
        ID:        uuid.New(),
        UserID:    req.UserID,
        Status:    entities.OrderStatusPending,
        Amount:    req.Amount,
        CreatedAt: now,
        UpdatedAt: now,
    }

    if err := uc.repo.Create(ctx, order); err != nil {
        return nil, err
    }

    return &dto.CreateOrderResponse{ID: order.ID}, nil
}

func (uc *UseCase) GetOrder(ctx context.Context, id uuid.UUID) (*dto.OrderResponse, error) {
    order, err := uc.repo.GetByID(ctx, id)
    if err != nil {
        return nil, err
    }

    return &dto.OrderResponse{
        ID:        order.ID,
        UserID:    order.UserID,
        Status:    string(order.Status),
        Amount:    order.Amount,
        CreatedAt: time.Time(order.CreatedAt).Format(time.RFC3339),
    }, nil
}

func (uc *UseCase) CompleteOrder(ctx context.Context, id uuid.UUID) error {
    order, err := uc.repo.GetByID(ctx, id)
    if err != nil {
        return err
    }

    if order.Status != entities.OrderStatusPending {
        return domainerrors.OrderNotPending
    }

    if err := uc.payment.ProcessPayment(ctx, id, order.Amount); err != nil {
        return err
    }

    order.Status = entities.OrderStatusCompleted
    order.UpdatedAt = timetools.FrontendTime(time.Now())

    return uc.repo.Update(ctx, order)
}
```

### delivery/http/handlers.go

```go
package http

import (
    "encoding/json"

    "github.com/google/uuid"
    "github.com/valyala/fasthttp"

    "service/internal/domain/order/dto"
    "service/internal/domain/order/usecase/buissines"
    pkgerrors "service/pkg/errors"
    "service/pkg/httputil"
)

type Handlers struct {
    uc     *buissines.UseCase
    mapper *pkgerrors.Mapper
}

func NewHandlers(uc *buissines.UseCase, mapper *pkgerrors.Mapper) *Handlers {
    return &Handlers{uc: uc, mapper: mapper}
}

func (h *Handlers) CreateOrder(ctx *fasthttp.RequestCtx) {
    var req dto.CreateOrderRequest
    if err := json.Unmarshal(ctx.PostBody(), &req); err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    resp, err := h.uc.CreateOrder(ctx, &req)
    if err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    httputil.WriteResponse(ctx, resp)
}

func (h *Handlers) GetOrder(ctx *fasthttp.RequestCtx) {
    idStr := ctx.UserValue("id").(string)
    id, err := uuid.Parse(idStr)
    if err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    resp, err := h.uc.GetOrder(ctx, id)
    if err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    httputil.WriteResponse(ctx, resp)
}

func (h *Handlers) CompleteOrder(ctx *fasthttp.RequestCtx) {
    idStr := ctx.UserValue("id").(string)
    id, err := uuid.Parse(idStr)
    if err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    if err := h.uc.CompleteOrder(ctx, id); err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    httputil.WriteResponse(ctx, map[string]string{"status": "completed"})
}
```

### delivery/http/router.go

```go
package http

import (
    "github.com/fasthttp/router"

    "service/pkg/httputil"
    "service/pkg/logger"
)

type Router struct {
    log      logger.ILogger
    handlers *Handlers
}

func NewRouter(handlers *Handlers, log logger.ILogger) *Router {
    return &Router{handlers: handlers, log: log}
}

func (r *Router) RegisterRoutes(rt *router.Router) {
    api := httputil.NewMiddlewareGroup(rt.Group("/api/v1"))

    orders := api.Group("/orders")
    orders.POST("", r.handlers.CreateOrder)
    orders.GET("/{id}", r.handlers.GetOrder)
    orders.POST("/{id}/complete", r.handlers.CompleteOrder)
}
```

### errors/errors.go

```go
package errors

import pkgerrors "service/pkg/errors"

var (
    OrderNotFound    = pkgerrors.NewNotFoundError("order not found")
    OrderNotPending  = pkgerrors.NewConflictError("order is not in pending status")
    OrderAlreadyPaid = pkgerrors.NewConflictError("order already paid")
    InvalidAmount    = pkgerrors.NewValidationError("invalid order amount")
)
```

### workers/worker.go

```go
package workers

import (
    "context"
    "time"

    "service/internal/domain/order/usecase/buissines"
    "service/pkg/logger"
)

type ExpiredOrdersWorker struct {
    log    logger.ILogger
    uc     *buissines.UseCase
    ticker *time.Ticker
    done   chan bool
}

func NewExpiredOrdersWorker(log logger.ILogger, uc *buissines.UseCase) *ExpiredOrdersWorker {
    return &ExpiredOrdersWorker{
        log:    log,
        uc:     uc,
        ticker: time.NewTicker(5 * time.Minute),
        done:   make(chan bool),
    }
}

func (w *ExpiredOrdersWorker) Start(ctx context.Context) {
    go func() {
        w.log.Info("ExpiredOrdersWorker started")
        for {
            select {
            case <-w.done:
                w.log.Info("ExpiredOrdersWorker stopped")
                return
            case <-w.ticker.C:
                if err := w.uc.CancelExpiredOrders(ctx); err != nil {
                    w.log.Errorw("failed to cancel expired orders", "error", err)
                }
            }
        }
    }()
}

func (w *ExpiredOrdersWorker) Stop() {
    w.ticker.Stop()
    w.done <- true
}
```

### workers/fx.go

```go
package workers

import (
    "context"

    "go.uber.org/fx"
)

var Module = fx.Module(
    "order-workers",
    fx.Provide(NewExpiredOrdersWorker),
    fx.Invoke(registerLifecycle),
)

func registerLifecycle(lc fx.Lifecycle, w *ExpiredOrdersWorker) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            w.Start(ctx)
            return nil
        },
        OnStop: func(ctx context.Context) error {
            w.Stop()
            return nil
        },
    })
}
```

---

## Infrastructure

### internal/infrastructure/fx.go

```go
var Module = fx.Module(
    "infrastructure",
    httpserver.Module,
    grpcserver.Module,
)
```

### internal/infrastructure/http/server/server.go

```go
package server

import (
    "context"
    "fmt"

    "github.com/fasthttp/router"
    "github.com/valyala/fasthttp"
    "go.uber.org/fx"

    "service/config"
)

type Server struct {
    cfg    *config.HttpServerConfig
    router *router.Router
    server *fasthttp.Server
}

func New(cfg *config.HttpServerConfig) *Server {
    return &Server{
        cfg:    cfg,
        router: router.New(),
    }
}

func (s *Server) Router() *router.Router {
    return s.router
}

func (s *Server) OnStart(ctx context.Context) error {
    s.server = &fasthttp.Server{
        Handler: s.router.Handler,
    }

    go func() {
        addr := fmt.Sprintf("%s:%d", s.cfg.Host, s.cfg.Port)
        if err := s.server.ListenAndServe(addr); err != nil {
            panic(err)
        }
    }()

    return nil
}

func (s *Server) OnStop(ctx context.Context) error {
    if s.server != nil {
        return s.server.Shutdown()
    }
    return nil
}

var Module = fx.Module(
    "http-server",
    fx.Provide(New),
    fx.Invoke(func(lc fx.Lifecycle, s *Server) {
        lc.Append(fx.Hook{
            OnStart: s.OnStart,
            OnStop:  s.OnStop,
        })
    }),
)
```

---

## Local Utilities (pkg/)

### pkg/errors/errors.go

```go
package errors

type ValidationError struct{ msg string }
func (e ValidationError) Error() string { return e.msg }
func NewValidationError(msg string) error { return ValidationError{msg: msg} }

type NotFoundError struct{ msg string }
func (e NotFoundError) Error() string { return e.msg }
func NewNotFoundError(msg string) error { return NotFoundError{msg: msg} }

type UnauthorizedError struct{ msg string }
func (e UnauthorizedError) Error() string { return e.msg }
func NewUnauthorizedError(msg string) error { return UnauthorizedError{msg: msg} }

type PermissionError struct{ msg string }
func (e PermissionError) Error() string { return e.msg }
func NewPermissionError(msg string) error { return PermissionError{msg: msg} }

type ConflictError struct{ msg string }
func (e ConflictError) Error() string { return e.msg }
func NewConflictError(msg string) error { return ConflictError{msg: msg} }
```

### pkg/errors/mappers.go

```go
package errors

import "net/http"

type Mapper struct{}

func NewMapper() *Mapper { return &Mapper{} }

func (m *Mapper) MapErrorToHttp(err error) (int, string) {
    switch err.(type) {
    case ValidationError:
        return http.StatusBadRequest, err.Error()
    case NotFoundError:
        return http.StatusNotFound, err.Error()
    case UnauthorizedError:
        return http.StatusUnauthorized, err.Error()
    case PermissionError:
        return http.StatusForbidden, err.Error()
    case ConflictError:
        return http.StatusConflict, err.Error()
    default:
        return http.StatusInternalServerError, "internal server error"
    }
}
```

### pkg/httputil/response.go

```go
package httputil

import (
    "encoding/json"

    "github.com/valyala/fasthttp"
)

func WriteResponse(ctx *fasthttp.RequestCtx, data interface{}) {
    ctx.SetContentType("application/json")
    ctx.SetStatusCode(fasthttp.StatusOK)
    json.NewEncoder(ctx).Encode(data)
}

func WriteError(ctx *fasthttp.RequestCtx, err error, status, code int) {
    ctx.SetContentType("application/json")
    ctx.SetStatusCode(status)
    json.NewEncoder(ctx).Encode(map[string]interface{}{
        "error": err.Error(),
        "code":  code,
    })
}

func WriteErrorResponse(ctx *fasthttp.RequestCtx, msg string, status int, err error) {
    ctx.SetContentType("application/json")
    ctx.SetStatusCode(status)
    json.NewEncoder(ctx).Encode(map[string]string{
        "error": msg,
    })
}
```

### pkg/ctxutil/value.go

```go
package ctxutil

import "context"

func FromCtx[T any](ctx context.Context, key string) (T, bool) {
    val := ctx.Value(key)
    if val == nil {
        var zero T
        return zero, false
    }
    typed, ok := val.(T)
    return typed, ok
}

func HasInCtx(ctx context.Context, key string) bool {
    return ctx.Value(key) != nil
}
```

### pkg/timetools/frontendtime.go

```go
package timetools

import (
    "time"
)

const FrontendTimeFormat = "2006-01-02 15:04:05.000000 -07:00"

type FrontendTime time.Time

func (t FrontendTime) MarshalJSON() ([]byte, error) {
    return []byte(`"` + time.Time(t).Format(FrontendTimeFormat) + `"`), nil
}

func (t *FrontendTime) UnmarshalJSON(data []byte) error {
    s := string(data)
    if len(s) >= 2 {
        s = s[1 : len(s)-1]
    }
    parsed, err := time.Parse(FrontendTimeFormat, s)
    if err != nil {
        return err
    }
    *t = FrontendTime(parsed)
    return nil
}
```

---

## Infrastructure Constants

### internal/infrastructure/constants/constants.go

```go
package constants

const (
    IpAddressContextKey   = "ip_address"
    FingerprintContextKey = "fingerprint"
    SessionInfoContextKey = "session_info"
    ApiKeyInfoContextKey  = "api_key_info"
    OtpCodeContextKey     = "otp_code"
    MerchantIDContextKey  = "merchant_id"
    UserIDContextKey      = "user_id"
    ProductIDContextKey   = "product_id"

    AccessTokenCookieName  = "access_token"
    RefreshTokenCookieName = "refresh_token"
)
```
