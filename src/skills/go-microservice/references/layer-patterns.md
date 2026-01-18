# Layer Patterns Reference

Detailed rules and code examples for each architectural layer.

---

## Entities Layer

**Location:** `internal/domain/{name}/entities/entities.go`

### Rules

| Rule | Description |
|------|-------------|
| ALWAYS use `db` tags | For sqlx mapping: `db:"column_name"` |
| ALWAYS use `json` tags | For API serialization: `json:"fieldName"` |
| PREFER `timetools.FrontendTime` | For date fields |
| PREFER typed constants | For status/enum fields |
| NO business logic | Pure data structures |

### Example

```go
package entities

import (
    "database/sql"

    "github.com/google/uuid"
    "github.com/shopspring/decimal"

    "service/pkg/timetools"
)

// Entity with all common patterns
type Order struct {
    ID          uuid.UUID              `db:"id" json:"id"`
    UserID      uuid.UUID              `db:"user_id" json:"userId"`
    Status      OrderStatus            `db:"status" json:"status"`
    Amount      decimal.Decimal        `db:"amount" json:"amount"`
    Currency    string                 `db:"currency" json:"currency"`
    Description sql.NullString         `db:"description" json:"description,omitempty"`
    CreatedAt   timetools.FrontendTime `db:"created_at" json:"createdAt"`
    UpdatedAt   timetools.FrontendTime `db:"updated_at" json:"updatedAt"`
    DeletedAt   sql.NullTime           `db:"deleted_at" json:"-"`
}

// Typed enum with constants
type OrderStatus string

const (
    OrderStatusPending   OrderStatus = "pending"
    OrderStatusProcessed OrderStatus = "processed"
    OrderStatusCompleted OrderStatus = "completed"
    OrderStatusCancelled OrderStatus = "cancelled"
    OrderStatusFailed    OrderStatus = "failed"
)

// Validation method on entity
func (s OrderStatus) IsValid() bool {
    switch s {
    case OrderStatusPending, OrderStatusProcessed, OrderStatusCompleted,
         OrderStatusCancelled, OrderStatusFailed:
        return true
    }
    return false
}

// Entity with composite key
type OrderItem struct {
    OrderID   uuid.UUID       `db:"order_id" json:"orderId"`
    ProductID uuid.UUID       `db:"product_id" json:"productId"`
    Quantity  int             `db:"quantity" json:"quantity"`
    Price     decimal.Decimal `db:"price" json:"price"`
}
```

### Nullable Fields

```go
import (
    "database/sql"
    "github.com/guregu/null/v6"
)

type User struct {
    // Standard library - use for simple cases
    DeletedAt sql.NullTime   `db:"deleted_at" json:"-"`
    Bio       sql.NullString `db:"bio" json:"bio,omitempty"`

    // guregu/null - better JSON marshaling
    MiddleName null.String `db:"middle_name" json:"middleName"`
    Age        null.Int    `db:"age" json:"age"`
}
```

---

## DTO Layer

**Location:** `internal/domain/{name}/dto/dto.go`

### Rules

| Rule | Description |
|------|-------------|
| ALWAYS separate Request/Response | Never mix in one struct |
| ALWAYS use `validate` tags | For request validation |
| PREFER `query` tags | For query parameters |
| NEVER expose entities | Always map to/from DTOs |
| USE camelCase in JSON | Match frontend conventions |

### Example

```go
package dto

import (
    "github.com/google/uuid"
    "github.com/shopspring/decimal"
)

// === CREATE ===

type CreateOrderRequest struct {
    UserID      uuid.UUID       `json:"userId" validate:"required"`
    Amount      decimal.Decimal `json:"amount" validate:"required,gt=0"`
    Currency    string          `json:"currency" validate:"required,len=3"`
    Description string          `json:"description" validate:"max=500"`
    Items       []CreateItemDTO `json:"items" validate:"required,min=1,dive"`
}

type CreateItemDTO struct {
    ProductID uuid.UUID       `json:"productId" validate:"required"`
    Quantity  int             `json:"quantity" validate:"required,min=1"`
    Price     decimal.Decimal `json:"price" validate:"required,gt=0"`
}

type CreateOrderResponse struct {
    ID uuid.UUID `json:"id"`
}

// === GET ONE ===

type GetOrderResponse struct {
    ID          uuid.UUID         `json:"id"`
    UserID      uuid.UUID         `json:"userId"`
    Status      string            `json:"status"`
    Amount      string            `json:"amount"`
    Currency    string            `json:"currency"`
    Description *string           `json:"description,omitempty"`
    Items       []OrderItemDTO    `json:"items"`
    CreatedAt   string            `json:"createdAt"`
    UpdatedAt   string            `json:"updatedAt"`
}

type OrderItemDTO struct {
    ProductID uuid.UUID `json:"productId"`
    Quantity  int       `json:"quantity"`
    Price     string    `json:"price"`
}

// === LIST ===

type ListOrdersRequest struct {
    UserID   *uuid.UUID `query:"userId"`
    Status   *string    `query:"status" validate:"omitempty,oneof=pending processed completed"`
    Limit    int        `query:"limit" validate:"min=1,max=100"`
    Offset   int        `query:"offset" validate:"min=0"`
    SortBy   string     `query:"sortBy" validate:"omitempty,oneof=created_at amount"`
    SortDir  string     `query:"sortDir" validate:"omitempty,oneof=asc desc"`
}

type ListOrdersResponse struct {
    Orders []GetOrderResponse `json:"orders"`
    Total  int                `json:"total"`
}

// === UPDATE ===

type UpdateOrderRequest struct {
    Status      *string `json:"status" validate:"omitempty,oneof=processed completed cancelled"`
    Description *string `json:"description" validate:"omitempty,max=500"`
}

// === FILTERS ===

type OrderFilter struct {
    UserID     *uuid.UUID
    Status     *string
    MinAmount  *decimal.Decimal
    MaxAmount  *decimal.Decimal
    CreatedFrom *time.Time
    CreatedTo   *time.Time
}
```

### Validation Tags Reference

```go
// Required
`validate:"required"`

// String length
`validate:"min=3,max=100"`
`validate:"len=3"`

// Numbers
`validate:"gt=0"`           // Greater than
`validate:"gte=0"`          // Greater than or equal
`validate:"lt=100"`         // Less than
`validate:"lte=100"`        // Less than or equal

// Enum
`validate:"oneof=pending completed failed"`

// Email, URL
`validate:"email"`
`validate:"url"`

// UUID
`validate:"uuid"`

// Nested validation
`validate:"dive"`           // Validate slice elements
`validate:"required,dive"`  // Required slice with validated elements

// Conditional
`validate:"omitempty,min=3"` // Only validate if not empty
```

---

## Deps Layer (Interfaces)

**Location:** `internal/domain/{name}/deps/dep.go`

### Rules

| Rule | Description |
|------|-------------|
| ONLY interfaces | No implementations |
| ALWAYS `context.Context` first | First argument in all methods |
| ONE file | All domain interfaces in `dep.go` |
| RETURN domain types | Entities or errors |
| CLEAR naming | `Repository`, `Client`, `Service` suffixes |

### Example

```go
package deps

import (
    "context"

    "github.com/google/uuid"

    "service/internal/domain/order/dto"
    "service/internal/domain/order/entities"
)

// Repository interface - data access
type OrderRepository interface {
    Create(ctx context.Context, order *entities.Order) error
    GetByID(ctx context.Context, id uuid.UUID) (*entities.Order, error)
    GetByFilter(ctx context.Context, filter *dto.OrderFilter, limit, offset int) ([]entities.Order, int, error)
    Update(ctx context.Context, order *entities.Order) error
    Delete(ctx context.Context, id uuid.UUID) error
}

// Cache interface - caching
type OrderCache interface {
    Get(ctx context.Context, id uuid.UUID) (*entities.Order, bool)
    Set(ctx context.Context, order *entities.Order) error
    Invalidate(ctx context.Context, id uuid.UUID) error
}

// External service client
type PaymentClient interface {
    ProcessPayment(ctx context.Context, orderID uuid.UUID, amount string, currency string) (*PaymentResult, error)
    RefundPayment(ctx context.Context, paymentID uuid.UUID) error
    GetPaymentStatus(ctx context.Context, paymentID uuid.UUID) (string, error)
}

type PaymentResult struct {
    PaymentID uuid.UUID
    Status    string
    Message   string
}

// Another external service
type NotificationClient interface {
    SendOrderCreated(ctx context.Context, order *entities.Order) error
    SendOrderCompleted(ctx context.Context, order *entities.Order) error
    SendOrderFailed(ctx context.Context, order *entities.Order, reason string) error
}

// Message producer
type EventProducer interface {
    PublishOrderCreated(ctx context.Context, order *entities.Order) error
    PublishOrderStatusChanged(ctx context.Context, order *entities.Order, oldStatus, newStatus string) error
}
```

---

## Repository Layer

**Location:** `internal/domain/{name}/repository/postgres/repo.go`

### Rules

| Rule | Description |
|------|-------------|
| RETURN interface | `func New(db) deps.Repository` |
| USE `NamedExecContext` | For INSERT/UPDATE with named params |
| USE `GetContext` | For SELECT single row |
| USE `SelectContext` | For SELECT multiple rows |
| MAP errors | Convert DB errors to domain errors |
| WRAP errors | `fmt.Errorf("context: %w", err)` |

### Example

```go
package postgres

import (
    "context"
    "database/sql"
    "fmt"

    "github.com/google/uuid"
    "github.com/jmoiron/sqlx"

    "service/internal/domain/order/deps"
    "service/internal/domain/order/dto"
    "service/internal/domain/order/entities"
    pkgerrors "service/pkg/errors"
    "service/pkg/pgconnector"
)

type Repository struct {
    db pgconnector.IDB
}

func NewRepository(db pgconnector.IDB) deps.OrderRepository {
    return &Repository{db: db}
}

// CREATE
func (r *Repository) Create(ctx context.Context, order *entities.Order) error {
    query := `
        INSERT INTO orders (id, user_id, status, amount, currency, description, created_at, updated_at)
        VALUES (:id, :user_id, :status, :amount, :currency, :description, :created_at, :updated_at)
    `
    _, err := r.db.Do(ctx).NamedExecContext(ctx, query, order)
    if err != nil {
        return fmt.Errorf("create order: %w", err)
    }
    return nil
}

// READ ONE
func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*entities.Order, error) {
    var order entities.Order
    query := `SELECT * FROM orders WHERE id = $1 AND deleted_at IS NULL`

    err := r.db.Do(ctx).GetContext(ctx, &order, query, id)
    if err != nil {
        if err == sql.ErrNoRows {
            return nil, pkgerrors.NewNotFoundError("order not found")
        }
        return nil, fmt.Errorf("get order by id: %w", err)
    }

    return &order, nil
}

// READ MANY with filter
func (r *Repository) GetByFilter(ctx context.Context, filter *dto.OrderFilter, limit, offset int) ([]entities.Order, int, error) {
    var orders []entities.Order

    // Build query dynamically
    query := `SELECT * FROM orders WHERE deleted_at IS NULL`
    countQuery := `SELECT COUNT(*) FROM orders WHERE deleted_at IS NULL`
    args := []interface{}{}
    argNum := 1

    if filter.UserID != nil {
        query += fmt.Sprintf(" AND user_id = $%d", argNum)
        countQuery += fmt.Sprintf(" AND user_id = $%d", argNum)
        args = append(args, *filter.UserID)
        argNum++
    }

    if filter.Status != nil {
        query += fmt.Sprintf(" AND status = $%d", argNum)
        countQuery += fmt.Sprintf(" AND status = $%d", argNum)
        args = append(args, *filter.Status)
        argNum++
    }

    // Get total count
    var total int
    if err := r.db.Do(ctx).GetContext(ctx, &total, countQuery, args...); err != nil {
        return nil, 0, fmt.Errorf("count orders: %w", err)
    }

    // Add pagination
    query += fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", argNum, argNum+1)
    args = append(args, limit, offset)

    if err := r.db.Do(ctx).SelectContext(ctx, &orders, query, args...); err != nil {
        return nil, 0, fmt.Errorf("select orders: %w", err)
    }

    return orders, total, nil
}

// UPDATE
func (r *Repository) Update(ctx context.Context, order *entities.Order) error {
    query := `
        UPDATE orders
        SET status = :status, amount = :amount, description = :description, updated_at = :updated_at
        WHERE id = :id AND deleted_at IS NULL
    `
    result, err := r.db.Do(ctx).NamedExecContext(ctx, query, order)
    if err != nil {
        return fmt.Errorf("update order: %w", err)
    }

    rows, _ := result.RowsAffected()
    if rows == 0 {
        return pkgerrors.NewNotFoundError("order not found")
    }

    return nil
}

// DELETE (soft delete)
func (r *Repository) Delete(ctx context.Context, id uuid.UUID) error {
    query := `UPDATE orders SET deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL`

    result, err := r.db.Do(ctx).ExecContext(ctx, query, id)
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

### Transaction Example

```go
func (r *Repository) CreateWithItems(ctx context.Context, order *entities.Order, items []entities.OrderItem) error {
    return r.db.WithTx(ctx, func(ctx context.Context) error {
        // Insert order
        orderQuery := `INSERT INTO orders (...) VALUES (...)`
        _, err := r.db.Do(ctx).NamedExecContext(ctx, orderQuery, order)
        if err != nil {
            return fmt.Errorf("insert order: %w", err)
        }

        // Insert items
        itemQuery := `INSERT INTO order_items (...) VALUES (...)`
        for _, item := range items {
            _, err := r.db.Do(ctx).NamedExecContext(ctx, itemQuery, item)
            if err != nil {
                return fmt.Errorf("insert order item: %w", err)
            }
        }

        return nil
    })
}
```

---

## Usecase Layer

**Location:** `internal/domain/{name}/usecase/buissines/uc.go`

### Rules

| Rule | Description |
|------|-------------|
| INJECT via interfaces | From `deps` package |
| RETURN DTOs | Never return entities |
| VALIDATE inputs | Check required fields |
| USE domain errors | From domain `errors` package |
| ORCHESTRATE | Coordinate between repo, cache, clients |

### Example

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
    "service/pkg/logger"
    "service/pkg/timetools"
)

type UseCase struct {
    log      logger.ILogger
    repo     deps.OrderRepository
    cache    deps.OrderCache
    payment  deps.PaymentClient
    notifier deps.NotificationClient
    producer deps.EventProducer
}

type Params struct {
    fx.In

    Logger   logger.ILogger
    Repo     deps.OrderRepository
    Cache    deps.OrderCache
    Payment  deps.PaymentClient
    Notifier deps.NotificationClient
    Producer deps.EventProducer
}

func NewUseCase(p Params) *UseCase {
    return &UseCase{
        log:      p.Logger,
        repo:     p.Repo,
        cache:    p.Cache,
        payment:  p.Payment,
        notifier: p.Notifier,
        producer: p.Producer,
    }
}

// CREATE
func (uc *UseCase) CreateOrder(ctx context.Context, req *dto.CreateOrderRequest) (*dto.CreateOrderResponse, error) {
    // Validation
    if req.Amount.IsNegative() || req.Amount.IsZero() {
        return nil, domainerrors.InvalidAmount
    }

    now := timetools.FrontendTime(time.Now())
    order := &entities.Order{
        ID:          uuid.New(),
        UserID:      req.UserID,
        Status:      entities.OrderStatusPending,
        Amount:      req.Amount,
        Currency:    req.Currency,
        Description: sql.NullString{String: req.Description, Valid: req.Description != ""},
        CreatedAt:   now,
        UpdatedAt:   now,
    }

    if err := uc.repo.Create(ctx, order); err != nil {
        return nil, err
    }

    // Async operations (fire and forget)
    go func() {
        bgCtx := context.Background()
        _ = uc.notifier.SendOrderCreated(bgCtx, order)
        _ = uc.producer.PublishOrderCreated(bgCtx, order)
    }()

    uc.log.InfowCtx(ctx, "order created", "orderId", order.ID)

    return &dto.CreateOrderResponse{ID: order.ID}, nil
}

// READ
func (uc *UseCase) GetOrder(ctx context.Context, id uuid.UUID) (*dto.GetOrderResponse, error) {
    // Try cache first
    if order, ok := uc.cache.Get(ctx, id); ok {
        return uc.mapOrderToDTO(order), nil
    }

    order, err := uc.repo.GetByID(ctx, id)
    if err != nil {
        return nil, err
    }

    // Cache for future requests
    _ = uc.cache.Set(ctx, order)

    return uc.mapOrderToDTO(order), nil
}

// LIST
func (uc *UseCase) ListOrders(ctx context.Context, req *dto.ListOrdersRequest) (*dto.ListOrdersResponse, error) {
    filter := &dto.OrderFilter{
        UserID: req.UserID,
        Status: req.Status,
    }

    orders, total, err := uc.repo.GetByFilter(ctx, filter, req.Limit, req.Offset)
    if err != nil {
        return nil, err
    }

    dtos := make([]dto.GetOrderResponse, len(orders))
    for i, order := range orders {
        dtos[i] = *uc.mapOrderToDTO(&order)
    }

    return &dto.ListOrdersResponse{
        Orders: dtos,
        Total:  total,
    }, nil
}

// BUSINESS OPERATION
func (uc *UseCase) CompleteOrder(ctx context.Context, id uuid.UUID) error {
    order, err := uc.repo.GetByID(ctx, id)
    if err != nil {
        return err
    }

    // Business rule validation
    if order.Status != entities.OrderStatusPending {
        return domainerrors.OrderNotPending
    }

    // External service call
    result, err := uc.payment.ProcessPayment(ctx, id, order.Amount.String(), order.Currency)
    if err != nil {
        uc.log.ErrorwCtx(ctx, "payment failed", "orderId", id, "error", err)
        return domainerrors.PaymentFailed
    }

    if result.Status != "success" {
        return domainerrors.PaymentDeclined
    }

    // Update state
    oldStatus := order.Status
    order.Status = entities.OrderStatusCompleted
    order.UpdatedAt = timetools.FrontendTime(time.Now())

    if err := uc.repo.Update(ctx, order); err != nil {
        return err
    }

    // Invalidate cache
    _ = uc.cache.Invalidate(ctx, id)

    // Publish events
    _ = uc.producer.PublishOrderStatusChanged(ctx, order, string(oldStatus), string(order.Status))
    _ = uc.notifier.SendOrderCompleted(ctx, order)

    uc.log.InfowCtx(ctx, "order completed", "orderId", id)

    return nil
}

// Mapping helper
func (uc *UseCase) mapOrderToDTO(order *entities.Order) *dto.GetOrderResponse {
    resp := &dto.GetOrderResponse{
        ID:        order.ID,
        UserID:    order.UserID,
        Status:    string(order.Status),
        Amount:    order.Amount.String(),
        Currency:  order.Currency,
        CreatedAt: time.Time(order.CreatedAt).Format(time.RFC3339),
        UpdatedAt: time.Time(order.UpdatedAt).Format(time.RFC3339),
    }

    if order.Description.Valid {
        resp.Description = &order.Description.String
    }

    return resp
}
```

---

## Delivery Layer (HTTP)

**Location:** `internal/domain/{name}/delivery/http/`

### handlers.go

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

    // TODO: Add validation with go-playground/validator

    resp, err := h.uc.CreateOrder(ctx, &req)
    if err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    ctx.SetStatusCode(fasthttp.StatusCreated)
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

func (h *Handlers) ListOrders(ctx *fasthttp.RequestCtx) {
    req := &dto.ListOrdersRequest{
        Limit:  10,
        Offset: 0,
    }

    // Parse query params
    if v := ctx.QueryArgs().Peek("limit"); len(v) > 0 {
        req.Limit, _ = strconv.Atoi(string(v))
    }
    if v := ctx.QueryArgs().Peek("offset"); len(v) > 0 {
        req.Offset, _ = strconv.Atoi(string(v))
    }
    if v := ctx.QueryArgs().Peek("status"); len(v) > 0 {
        s := string(v)
        req.Status = &s
    }

    resp, err := h.uc.ListOrders(ctx, req)
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

### router.go

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
    orders.GET("", r.handlers.ListOrders)
    orders.GET("/{id}", r.handlers.GetOrder)
    orders.POST("/{id}/complete", r.handlers.CompleteOrder)
}
```

---

## Delivery Layer (gRPC)

**Location:** `internal/domain/{name}/delivery/grpc/`

```go
package grpc

import (
    "context"
    "fmt"
    "net"

    "google.golang.org/grpc"
    "google.golang.org/grpc/metadata"

    "service/internal/domain/order/usecase/buissines"
    proto "service/proto/order/v1"
    "service/pkg/logger"
)

type Server struct {
    log        logger.ILogger
    port       int
    grpcServer *grpc.Server
    uc         *buissines.UseCase

    proto.UnimplementedOrderServiceServer
}

func NewServer(log logger.ILogger, port int, uc *buissines.UseCase) *Server {
    return &Server{
        log:  log,
        port: port,
        uc:   uc,
    }
}

func (s *Server) OnStart(ctx context.Context) error {
    lis, err := net.Listen("tcp", fmt.Sprintf(":%d", s.port))
    if err != nil {
        return fmt.Errorf("failed to listen: %w", err)
    }

    s.grpcServer = grpc.NewServer()
    proto.RegisterOrderServiceServer(s.grpcServer, s)

    go func() {
        s.log.Infof("gRPC server listening on port %d", s.port)
        if err := s.grpcServer.Serve(lis); err != nil {
            s.log.Errorf("gRPC server error: %v", err)
        }
    }()

    return nil
}

func (s *Server) OnStop(ctx context.Context) error {
    if s.grpcServer != nil {
        s.grpcServer.GracefulStop()
    }
    return nil
}

// RPC implementation
func (s *Server) GetOrder(ctx context.Context, req *proto.GetOrderRequest) (*proto.GetOrderResponse, error) {
    // Extract metadata
    md, _ := metadata.FromIncomingContext(ctx)
    _ = md.Get("authorization")

    id, err := uuid.Parse(req.GetId())
    if err != nil {
        return nil, status.Error(codes.InvalidArgument, "invalid order id")
    }

    order, err := s.uc.GetOrder(ctx, id)
    if err != nil {
        return nil, s.mapError(err)
    }

    return &proto.GetOrderResponse{
        Id:        order.ID.String(),
        Status:    order.Status,
        Amount:    order.Amount,
        CreatedAt: order.CreatedAt,
    }, nil
}

func (s *Server) mapError(err error) error {
    switch err.(type) {
    case pkgerrors.NotFoundError:
        return status.Error(codes.NotFound, err.Error())
    case pkgerrors.ValidationError:
        return status.Error(codes.InvalidArgument, err.Error())
    default:
        return status.Error(codes.Internal, "internal error")
    }
}
```

---

## Workers Layer

**Location:** `internal/domain/{name}/workers/`

### worker.go

```go
package workers

import (
    "context"
    "time"

    "service/internal/domain/order/usecase/buissines"
    "service/pkg/logger"
)

type ExpiredOrdersWorker struct {
    log      logger.ILogger
    uc       *buissines.UseCase
    interval time.Duration
    ticker   *time.Ticker
    done     chan bool
}

func NewExpiredOrdersWorker(log logger.ILogger, uc *buissines.UseCase, interval time.Duration) *ExpiredOrdersWorker {
    return &ExpiredOrdersWorker{
        log:      log,
        uc:       uc,
        interval: interval,
        done:     make(chan bool),
    }
}

func (w *ExpiredOrdersWorker) Start(ctx context.Context) {
    w.ticker = time.NewTicker(w.interval)

    go func() {
        w.log.Info("ExpiredOrdersWorker started")

        // Run immediately on start
        w.process(ctx)

        for {
            select {
            case <-w.done:
                w.log.Info("ExpiredOrdersWorker stopped")
                return
            case <-w.ticker.C:
                w.process(ctx)
            }
        }
    }()
}

func (w *ExpiredOrdersWorker) Stop() {
    if w.ticker != nil {
        w.ticker.Stop()
    }
    w.done <- true
}

func (w *ExpiredOrdersWorker) process(ctx context.Context) {
    w.log.Debug("processing expired orders")

    count, err := w.uc.CancelExpiredOrders(ctx)
    if err != nil {
        w.log.Errorw("failed to cancel expired orders", "error", err)
        return
    }

    if count > 0 {
        w.log.Infow("cancelled expired orders", "count", count)
    }
}
```

### fx.go

```go
package workers

import (
    "context"
    "time"

    "go.uber.org/fx"

    "service/internal/domain/order/usecase/buissines"
    "service/pkg/logger"
)

var Module = fx.Module(
    "order-workers",
    fx.Provide(func(log logger.ILogger, uc *buissines.UseCase) *ExpiredOrdersWorker {
        return NewExpiredOrdersWorker(log, uc, 5*time.Minute)
    }),
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

## Domain Errors

**Location:** `internal/domain/{name}/errors/errors.go`

```go
package errors

import pkgerrors "service/pkg/errors"

var (
    // Not found
    OrderNotFound = pkgerrors.NewNotFoundError("order not found")
    ItemNotFound  = pkgerrors.NewNotFoundError("order item not found")

    // Validation
    InvalidAmount   = pkgerrors.NewValidationError("invalid order amount")
    InvalidCurrency = pkgerrors.NewValidationError("invalid currency")
    InvalidStatus   = pkgerrors.NewValidationError("invalid order status")

    // Business rules
    OrderNotPending  = pkgerrors.NewConflictError("order is not in pending status")
    OrderAlreadyPaid = pkgerrors.NewConflictError("order already paid")
    OrderExpired     = pkgerrors.NewConflictError("order has expired")

    // External services
    PaymentFailed   = pkgerrors.NewValidationError("payment processing failed")
    PaymentDeclined = pkgerrors.NewValidationError("payment was declined")
)
```
