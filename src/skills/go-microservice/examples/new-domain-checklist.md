# New Domain Creation Checklist

Step-by-step guide with copy-paste code for creating a new domain.

---

## Quick Checklist

```
1. [ ] Create directory structure
2. [ ] Define entities
3. [ ] Define DTOs
4. [ ] Define interfaces (deps)
5. [ ] Define domain errors
6. [ ] Implement repository
7. [ ] Implement usecase
8. [ ] Implement HTTP handlers
9. [ ] Implement router
10. [ ] Create fx.Module
11. [ ] Register in domain/fx.go
12. [ ] Validate: go test -run Test__CreateApp ./internal/app
```

---

## Step 1: Create Directory Structure

```powershell
$domain = "product"  # Change to your domain name
$base = "internal/domain/$domain"

mkdir -Force "$base/entities"
mkdir -Force "$base/dto"
mkdir -Force "$base/deps"
mkdir -Force "$base/errors"
mkdir -Force "$base/repository/postgres"
mkdir -Force "$base/usecase/buissines"
mkdir -Force "$base/delivery/http"

New-Item -Force "$base/fx.go"
New-Item -Force "$base/entities/entities.go"
New-Item -Force "$base/dto/dto.go"
New-Item -Force "$base/deps/dep.go"
New-Item -Force "$base/errors/errors.go"
New-Item -Force "$base/repository/postgres/repo.go"
New-Item -Force "$base/usecase/buissines/uc.go"
New-Item -Force "$base/delivery/http/handlers.go"
New-Item -Force "$base/delivery/http/router.go"
```

---

## Step 2: Define Entities

**File:** `internal/domain/{name}/entities/entities.go`

```go
package entities

import (
    "database/sql"

    "github.com/google/uuid"
    "github.com/shopspring/decimal"

    "service/pkg/timetools"
)

type Product struct {
    ID          uuid.UUID              `db:"id" json:"id"`
    Name        string                 `db:"name" json:"name"`
    Description sql.NullString         `db:"description" json:"description,omitempty"`
    Price       decimal.Decimal        `db:"price" json:"price"`
    Status      ProductStatus          `db:"status" json:"status"`
    CreatedAt   timetools.FrontendTime `db:"created_at" json:"createdAt"`
    UpdatedAt   timetools.FrontendTime `db:"updated_at" json:"updatedAt"`
}

type ProductStatus string

const (
    ProductStatusActive   ProductStatus = "active"
    ProductStatusInactive ProductStatus = "inactive"
)
```

---

## Step 3: Define DTOs

**File:** `internal/domain/{name}/dto/dto.go`

```go
package dto

import (
    "github.com/google/uuid"
    "github.com/shopspring/decimal"
)

// Create
type CreateProductRequest struct {
    Name        string          `json:"name" validate:"required,min=1,max=255"`
    Description string          `json:"description" validate:"max=1000"`
    Price       decimal.Decimal `json:"price" validate:"required,gt=0"`
}

type CreateProductResponse struct {
    ID uuid.UUID `json:"id"`
}

// Get
type GetProductResponse struct {
    ID          uuid.UUID `json:"id"`
    Name        string    `json:"name"`
    Description *string   `json:"description,omitempty"`
    Price       string    `json:"price"`
    Status      string    `json:"status"`
    CreatedAt   string    `json:"createdAt"`
}

// List
type ListProductsRequest struct {
    Status *string `query:"status" validate:"omitempty,oneof=active inactive"`
    Limit  int     `query:"limit" validate:"min=1,max=100"`
    Offset int     `query:"offset" validate:"min=0"`
}

type ListProductsResponse struct {
    Products []GetProductResponse `json:"products"`
    Total    int                  `json:"total"`
}

// Update
type UpdateProductRequest struct {
    Name        *string          `json:"name" validate:"omitempty,min=1,max=255"`
    Description *string          `json:"description" validate:"omitempty,max=1000"`
    Price       *decimal.Decimal `json:"price" validate:"omitempty,gt=0"`
    Status      *string          `json:"status" validate:"omitempty,oneof=active inactive"`
}
```

---

## Step 4: Define Interfaces

**File:** `internal/domain/{name}/deps/dep.go`

```go
package deps

import (
    "context"

    "github.com/google/uuid"

    "service/internal/domain/product/dto"
    "service/internal/domain/product/entities"
)

type ProductRepository interface {
    Create(ctx context.Context, product *entities.Product) error
    GetByID(ctx context.Context, id uuid.UUID) (*entities.Product, error)
    GetByFilter(ctx context.Context, status *string, limit, offset int) ([]entities.Product, int, error)
    Update(ctx context.Context, product *entities.Product) error
    Delete(ctx context.Context, id uuid.UUID) error
}
```

---

## Step 5: Define Domain Errors

**File:** `internal/domain/{name}/errors/errors.go`

```go
package errors

import pkgerrors "service/pkg/errors"

var (
    ProductNotFound = pkgerrors.NewNotFoundError("product not found")
    InvalidPrice    = pkgerrors.NewValidationError("invalid product price")
    InvalidName     = pkgerrors.NewValidationError("invalid product name")
)
```

---

## Step 6: Implement Repository

**File:** `internal/domain/{name}/repository/postgres/repo.go`

```go
package postgres

import (
    "context"
    "database/sql"
    "fmt"

    "github.com/google/uuid"

    "service/internal/domain/product/deps"
    "service/internal/domain/product/entities"
    domainerrors "service/internal/domain/product/errors"
    "service/pkg/pgconnector"
)

type Repository struct {
    db pgconnector.IDB
}

func NewRepository(db pgconnector.IDB) deps.ProductRepository {
    return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, product *entities.Product) error {
    query := `
        INSERT INTO products (id, name, description, price, status, created_at, updated_at)
        VALUES (:id, :name, :description, :price, :status, :created_at, :updated_at)
    `
    _, err := r.db.Do(ctx).NamedExecContext(ctx, query, product)
    if err != nil {
        return fmt.Errorf("create product: %w", err)
    }
    return nil
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*entities.Product, error) {
    var product entities.Product
    query := `SELECT * FROM products WHERE id = $1`

    err := r.db.Do(ctx).GetContext(ctx, &product, query, id)
    if err != nil {
        if err == sql.ErrNoRows {
            return nil, domainerrors.ProductNotFound
        }
        return nil, fmt.Errorf("get product: %w", err)
    }

    return &product, nil
}

func (r *Repository) GetByFilter(ctx context.Context, status *string, limit, offset int) ([]entities.Product, int, error) {
    var products []entities.Product

    query := `SELECT * FROM products WHERE 1=1`
    countQuery := `SELECT COUNT(*) FROM products WHERE 1=1`
    args := []interface{}{}
    argNum := 1

    if status != nil {
        query += fmt.Sprintf(" AND status = $%d", argNum)
        countQuery += fmt.Sprintf(" AND status = $%d", argNum)
        args = append(args, *status)
        argNum++
    }

    var total int
    if err := r.db.Do(ctx).GetContext(ctx, &total, countQuery, args...); err != nil {
        return nil, 0, fmt.Errorf("count products: %w", err)
    }

    query += fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", argNum, argNum+1)
    args = append(args, limit, offset)

    if err := r.db.Do(ctx).SelectContext(ctx, &products, query, args...); err != nil {
        return nil, 0, fmt.Errorf("select products: %w", err)
    }

    return products, total, nil
}

func (r *Repository) Update(ctx context.Context, product *entities.Product) error {
    query := `
        UPDATE products
        SET name = :name, description = :description, price = :price, status = :status, updated_at = :updated_at
        WHERE id = :id
    `
    result, err := r.db.Do(ctx).NamedExecContext(ctx, query, product)
    if err != nil {
        return fmt.Errorf("update product: %w", err)
    }

    rows, _ := result.RowsAffected()
    if rows == 0 {
        return domainerrors.ProductNotFound
    }

    return nil
}

func (r *Repository) Delete(ctx context.Context, id uuid.UUID) error {
    query := `DELETE FROM products WHERE id = $1`

    result, err := r.db.Do(ctx).ExecContext(ctx, query, id)
    if err != nil {
        return fmt.Errorf("delete product: %w", err)
    }

    rows, _ := result.RowsAffected()
    if rows == 0 {
        return domainerrors.ProductNotFound
    }

    return nil
}
```

---

## Step 7: Implement Usecase

**File:** `internal/domain/{name}/usecase/buissines/uc.go`

```go
package buissines

import (
    "context"
    "database/sql"
    "time"

    "github.com/google/uuid"

    "service/internal/domain/product/deps"
    "service/internal/domain/product/dto"
    "service/internal/domain/product/entities"
    "service/pkg/logger"
    "service/pkg/timetools"
)

type UseCase struct {
    log  logger.ILogger
    repo deps.ProductRepository
}

func NewUseCase(log logger.ILogger, repo deps.ProductRepository) *UseCase {
    return &UseCase{
        log:  log,
        repo: repo,
    }
}

func (uc *UseCase) CreateProduct(ctx context.Context, req *dto.CreateProductRequest) (*dto.CreateProductResponse, error) {
    now := timetools.FrontendTime(time.Now())
    product := &entities.Product{
        ID:          uuid.New(),
        Name:        req.Name,
        Description: sql.NullString{String: req.Description, Valid: req.Description != ""},
        Price:       req.Price,
        Status:      entities.ProductStatusActive,
        CreatedAt:   now,
        UpdatedAt:   now,
    }

    if err := uc.repo.Create(ctx, product); err != nil {
        return nil, err
    }

    uc.log.InfowCtx(ctx, "product created", "productId", product.ID)

    return &dto.CreateProductResponse{ID: product.ID}, nil
}

func (uc *UseCase) GetProduct(ctx context.Context, id uuid.UUID) (*dto.GetProductResponse, error) {
    product, err := uc.repo.GetByID(ctx, id)
    if err != nil {
        return nil, err
    }

    return uc.mapToDTO(product), nil
}

func (uc *UseCase) ListProducts(ctx context.Context, req *dto.ListProductsRequest) (*dto.ListProductsResponse, error) {
    products, total, err := uc.repo.GetByFilter(ctx, req.Status, req.Limit, req.Offset)
    if err != nil {
        return nil, err
    }

    dtos := make([]dto.GetProductResponse, len(products))
    for i, p := range products {
        dtos[i] = *uc.mapToDTO(&p)
    }

    return &dto.ListProductsResponse{
        Products: dtos,
        Total:    total,
    }, nil
}

func (uc *UseCase) UpdateProduct(ctx context.Context, id uuid.UUID, req *dto.UpdateProductRequest) error {
    product, err := uc.repo.GetByID(ctx, id)
    if err != nil {
        return err
    }

    if req.Name != nil {
        product.Name = *req.Name
    }
    if req.Description != nil {
        product.Description = sql.NullString{String: *req.Description, Valid: *req.Description != ""}
    }
    if req.Price != nil {
        product.Price = *req.Price
    }
    if req.Status != nil {
        product.Status = entities.ProductStatus(*req.Status)
    }
    product.UpdatedAt = timetools.FrontendTime(time.Now())

    return uc.repo.Update(ctx, product)
}

func (uc *UseCase) DeleteProduct(ctx context.Context, id uuid.UUID) error {
    return uc.repo.Delete(ctx, id)
}

func (uc *UseCase) mapToDTO(p *entities.Product) *dto.GetProductResponse {
    resp := &dto.GetProductResponse{
        ID:        p.ID,
        Name:      p.Name,
        Price:     p.Price.String(),
        Status:    string(p.Status),
        CreatedAt: time.Time(p.CreatedAt).Format(time.RFC3339),
    }
    if p.Description.Valid {
        resp.Description = &p.Description.String
    }
    return resp
}
```

---

## Step 8: Implement HTTP Handlers

**File:** `internal/domain/{name}/delivery/http/handlers.go`

```go
package http

import (
    "encoding/json"
    "strconv"

    "github.com/google/uuid"
    "github.com/valyala/fasthttp"

    "service/internal/domain/product/dto"
    "service/internal/domain/product/usecase/buissines"
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

func (h *Handlers) Create(ctx *fasthttp.RequestCtx) {
    var req dto.CreateProductRequest
    if err := json.Unmarshal(ctx.PostBody(), &req); err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    resp, err := h.uc.CreateProduct(ctx, &req)
    if err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    ctx.SetStatusCode(fasthttp.StatusCreated)
    httputil.WriteResponse(ctx, resp)
}

func (h *Handlers) Get(ctx *fasthttp.RequestCtx) {
    id, err := uuid.Parse(ctx.UserValue("id").(string))
    if err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    resp, err := h.uc.GetProduct(ctx, id)
    if err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    httputil.WriteResponse(ctx, resp)
}

func (h *Handlers) List(ctx *fasthttp.RequestCtx) {
    req := &dto.ListProductsRequest{
        Limit:  10,
        Offset: 0,
    }

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

    resp, err := h.uc.ListProducts(ctx, req)
    if err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    httputil.WriteResponse(ctx, resp)
}

func (h *Handlers) Update(ctx *fasthttp.RequestCtx) {
    id, err := uuid.Parse(ctx.UserValue("id").(string))
    if err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    var req dto.UpdateProductRequest
    if err := json.Unmarshal(ctx.PostBody(), &req); err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    if err := h.uc.UpdateProduct(ctx, id, &req); err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    httputil.WriteResponse(ctx, map[string]string{"status": "updated"})
}

func (h *Handlers) Delete(ctx *fasthttp.RequestCtx) {
    id, err := uuid.Parse(ctx.UserValue("id").(string))
    if err != nil {
        httputil.WriteError(ctx, err, fasthttp.StatusBadRequest, 0)
        return
    }

    if err := h.uc.DeleteProduct(ctx, id); err != nil {
        status, msg := h.mapper.MapErrorToHttp(err)
        httputil.WriteErrorResponse(ctx, msg, status, err)
        return
    }

    ctx.SetStatusCode(fasthttp.StatusNoContent)
}
```

---

## Step 9: Implement Router

**File:** `internal/domain/{name}/delivery/http/router.go`

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

    products := api.Group("/products")
    products.POST("", r.handlers.Create)
    products.GET("", r.handlers.List)
    products.GET("/{id}", r.handlers.Get)
    products.PUT("/{id}", r.handlers.Update)
    products.DELETE("/{id}", r.handlers.Delete)
}
```

---

## Step 10: Create fx.Module

**File:** `internal/domain/{name}/fx.go`

```go
package product

import (
    "go.uber.org/fx"

    "service/internal/domain/product/delivery/http"
    "service/internal/domain/product/repository/postgres"
    "service/internal/domain/product/usecase/buissines"
)

var Module = fx.Module(
    "product",
    fx.Provide(
        postgres.NewRepository,
        buissines.NewUseCase,
        http.NewHandlers,
        http.NewRouter,
    ),
)
```

---

## Step 11: Register in Domain

**File:** `internal/domain/fx.go`

```go
package domain

import (
    "go.uber.org/fx"

    "service/internal/domain/order"
    "service/internal/domain/user"
    "service/internal/domain/product"  // Add new import
)

var Module = fx.Module(
    "domain",
    order.Module,
    user.Module,
    product.Module,  // Add new module
)
```

---

## Step 12: Validate

```powershell
go test -run Test__CreateApp ./internal/app
```

If validation passes, the domain is correctly wired.

---

## Database Migration

Create migration file `migrations/V{version}__create_products_table.sql`:

```sql
CREATE TABLE products (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(18, 8) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_status ON products(status);
CREATE INDEX idx_products_created_at ON products(created_at);
```

---

## Import Template

Standard imports for each file type:

### entities/entities.go

```go
import (
    "database/sql"

    "github.com/google/uuid"
    "github.com/shopspring/decimal"

    "service/pkg/timetools"
)
```

### dto/dto.go

```go
import (
    "github.com/google/uuid"
    "github.com/shopspring/decimal"
)
```

### deps/dep.go

```go
import (
    "context"

    "github.com/google/uuid"

    "service/internal/domain/{name}/entities"
)
```

### repository/postgres/repo.go

```go
import (
    "context"
    "database/sql"
    "fmt"

    "github.com/google/uuid"

    "service/internal/domain/{name}/deps"
    "service/internal/domain/{name}/entities"
    domainerrors "service/internal/domain/{name}/errors"
    "service/pkg/pgconnector"
)
```

### usecase/buissines/uc.go

```go
import (
    "context"
    "database/sql"
    "time"

    "github.com/google/uuid"

    "service/internal/domain/{name}/deps"
    "service/internal/domain/{name}/dto"
    "service/internal/domain/{name}/entities"
    "service/pkg/logger"
    "service/pkg/timetools"
)
```

### delivery/http/handlers.go

```go
import (
    "encoding/json"
    "strconv"

    "github.com/google/uuid"
    "github.com/valyala/fasthttp"

    "service/internal/domain/{name}/dto"
    "service/internal/domain/{name}/usecase/buissines"
    pkgerrors "service/pkg/errors"
    "service/pkg/httputil"
)
```

### delivery/http/router.go

```go
import (
    "github.com/fasthttp/router"

    "service/pkg/httputil"
    "service/pkg/logger"
)
```

### fx.go

```go
import (
    "go.uber.org/fx"

    "service/internal/domain/{name}/delivery/http"
    "service/internal/domain/{name}/repository/postgres"
    "service/internal/domain/{name}/usecase/buissines"
)
```
