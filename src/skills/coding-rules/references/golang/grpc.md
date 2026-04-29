# Go + gRPC Patterns Reference

Паттерны и anti-patterns для gRPC серверов и клиентов в Go.

**See also:**
- `patterns.md` — общие Go паттерны
- `uber-fx.md` — Uber FX lifecycle, DI
- `clean-architecture.md` — DDD layers

## Server Lifecycle

### 1. Blocking Serve in OnStart

**Проблема:** `grpc.Server.Serve()` блокирует — вызов в `OnStart` вешает весь FX lifecycle.

**Anti-pattern:**
```go
// BAD: Blocking OnStart — app never finishes starting
lc.Append(fx.Hook{
    OnStart: func(ctx context.Context) error {
        lis, _ := net.Listen("tcp", ":50051")
        return srv.Serve(lis) // Blocks forever!
    },
})
```

**Pattern:**
```go
// GOOD: Non-blocking Serve + GracefulStop
func RegisterGRPCServer(lc fx.Lifecycle, srv *grpc.Server) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            lis, err := net.Listen("tcp", ":50051")
            if err != nil {
                return fmt.Errorf("grpc listen: %w", err)
            }
            go func() {
                if err := srv.Serve(lis); err != nil {
                    log.Printf("grpc serve error: %v", err)
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error {
            srv.GracefulStop()
            return nil
        },
    })
}
```

**Severity:** 🔴 CRITICAL

### 2. Missing GracefulStop

**Проблема:** `srv.Stop()` обрывает все in-flight запросы. `GracefulStop()` ждёт завершения.

**Anti-pattern:**
```go
// BAD: Abrupt stop drops in-flight RPCs
OnStop: func(ctx context.Context) error {
    srv.Stop() // All active RPCs immediately fail
    return nil
},
```

**Pattern:**
```go
// GOOD: GracefulStop with context deadline fallback
OnStop: func(ctx context.Context) error {
    stopped := make(chan struct{})
    go func() {
        srv.GracefulStop()
        close(stopped)
    }()
    select {
    case <-stopped:
        return nil
    case <-ctx.Done():
        srv.Stop() // Force stop if context expires
        return nil
    }
},
```

**Severity:** 🟠 HIGH

### 3. Stateful Server: Methods on Type vs Lifecycle Functions

**Проблема:** Когда у gRPC-сервера есть состояние (listener, конфиг, handler, базовый `*grpc.Server`), вынос lifecycle в отдельную функцию `RegisterLifecycle(p lifecycleParams)` со `fx.In`-структурой раздувает код, заставляет тащить замыкания над `var listener net.Listener` и плодит boilerplate. Чище — сделать тип `Server` с методами `OnStart`/`OnStop` и подключить их одной строкой через `fx.Hook{OnStart: s.OnStart, OnStop: s.OnStop}`.

**Контекст:** оба варианта встречаются в проектах, но методы на типе масштабируются лучше — состояние явно живёт в полях, не в захваченных переменных, и тестирование становится прямолинейным.

**Anti-pattern:**
```go
// BAD: lifecycle вынесен в отдельную функцию + замыкание над listener
type lifecycleParams struct {
    fx.In
    Lifecycle fx.Lifecycle
    Config    *containers.GRPCServerConfig
    Logger    logger.ILogger
    Server    *grpc.Server
}

func RegisterLifecycle(p lifecycleParams) {
    var listener net.Listener
    p.Lifecycle.Append(fx.Hook{
        OnStart: func(context.Context) error {
            addr := fmt.Sprintf(":%d", p.Config.Port)
            var err error
            listener, err = net.Listen(p.Config.TransportName, addr)
            if err != nil {
                return fmt.Errorf("listen %s: %w", addr, err)
            }
            go func() {
                if serveErr := p.Server.Serve(listener); serveErr != nil &&
                    !errors.Is(serveErr, grpc.ErrServerStopped) {
                    panic("gRPC server failed: " + serveErr.Error())
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error { /* ... */ },
    })
}
```

**Pattern:**
```go
// GOOD: состояние и lifecycle — на типе Server
type Server struct {
    cfg     *containers.GRPCServerConfig
    log     logger.ILogger
    handler *grpcHandlers.Handler
    base    *grpc.Server
    lis     net.Listener
}

func New(cfg *containers.GRPCServerConfig, log logger.ILogger, h *grpcHandlers.Handler) *Server {
    return &Server{cfg: cfg, log: log, handler: h}
}

func (s *Server) OnStart(_ context.Context) error {
    s.base = grpc.NewServer(tracinggrpc.GRPCServerOptions()...)
    pb.RegisterFooServiceExternalServer(s.base, s.handler)
    pb.RegisterFooServiceInternalServer(s.base, s.handler)
    reflection.Register(s.base)

    addr := fmt.Sprintf(":%d", s.cfg.Port)
    lis, err := net.Listen(s.cfg.TransportName, addr)
    if err != nil {
        return fmt.Errorf("listen %s: %w", addr, err)
    }
    s.lis = lis

    go func() {
        if err := s.base.Serve(lis); err != nil && !errors.Is(err, grpc.ErrServerStopped) {
            s.log.Errorw("grpc serve failed", "error", err)
        }
    }()
    return nil
}

func (s *Server) OnStop(ctx context.Context) error {
    done := make(chan struct{})
    go func() {
        s.base.GracefulStop()
        close(done)
    }()
    select {
    case <-done:
        return nil
    case <-ctx.Done():
        s.base.Stop()
        return ctx.Err()
    }
}

// FX-wiring — одна строка, никаких lifecycleParams:
var Module = fx.Module("server",
    fx.Provide(New),
    fx.Invoke(func(lc fx.Lifecycle, s *Server) {
        lc.Append(fx.Hook{OnStart: s.OnStart, OnStop: s.OnStop})
    }),
)
```

**Преимущества:**
- состояние (`lis`, `base`) живёт в полях, а не в захваченных переменных
- легко тестировать: `Server.OnStart`/`OnStop` вызываются напрямую
- `fx.In`-структура не нужна — конструктор `New` сам берёт зависимости

**Severity:** 🟡 MEDIUM (читаемость + консистентность с большинством сервисов команды)

## Error Mapping

### 3. Raw Errors in gRPC Responses

**Проблема:** Возврат обычной Go ошибки вместо gRPC status — клиент получает `Unknown` с сырым сообщением.

**Anti-pattern:**
```go
// BAD: Raw error leaks internal details
func (s *Server) GetOrder(ctx context.Context, req *pb.GetOrderRequest) (*pb.OrderResponse, error) {
    order, err := s.uc.GetOrder(ctx, req.Id)
    if err != nil {
        return nil, err // Client sees codes.Unknown + internal error text
    }
    return toProto(order), nil
}
```

**Pattern:**
```go
// GOOD: Map domain errors to gRPC status codes
func (s *Server) GetOrder(ctx context.Context, req *pb.GetOrderRequest) (*pb.OrderResponse, error) {
    order, err := s.uc.GetOrder(ctx, req.Id)
    if err != nil {
        return nil, mapToGRPCError(err)
    }
    return toProto(order), nil
}

func mapToGRPCError(err error) error {
    var notFound *errors.NotFoundError
    var validation *errors.ValidationError
    var conflict *errors.ConflictError

    switch {
    case errors.As(err, &notFound):
        return status.Error(codes.NotFound, notFound.Error())
    case errors.As(err, &validation):
        return status.Error(codes.InvalidArgument, validation.Error())
    case errors.As(err, &conflict):
        return status.Error(codes.AlreadyExists, conflict.Error())
    default:
        return status.Error(codes.Internal, "internal error")
    }
}
```

**Severity:** 🟠 HIGH

### 4. Type Switch Instead of errors.As

**Проблема:** Type switch ломается при обёрнутых ошибках (`fmt.Errorf("...: %w", err)`).

**Anti-pattern:**
```go
// BAD: Breaks with wrapped errors
switch err.(type) {
case *NotFoundError:
    return status.Error(codes.NotFound, err.Error())
case *ValidationError:
    return status.Error(codes.InvalidArgument, err.Error())
}
```

**Pattern:**
```go
// GOOD: errors.As unwraps the chain
var notFound *NotFoundError
if errors.As(err, &notFound) {
    return status.Error(codes.NotFound, notFound.Error())
}
```

**Severity:** 🟡 MEDIUM

## Metadata Propagation

### 5. Lost Metadata on Forwarding

**Проблема:** При вызове другого gRPC сервиса metadata/trace context из входящего запроса теряется.

**Anti-pattern:**
```go
// BAD: Metadata from incoming request is lost
func (s *Server) Process(ctx context.Context, req *pb.Request) (*pb.Response, error) {
    // ctx has incoming metadata, but outgoing call starts fresh
    resp, err := s.otherClient.DoSomething(ctx, &pb.OtherRequest{})
    // Trace context lost — distributed tracing broken
    return resp, err
}
```

**Pattern:**
```go
// GOOD: Propagate metadata via outgoing context
func (s *Server) Process(ctx context.Context, req *pb.Request) (*pb.Response, error) {
    md, ok := metadata.FromIncomingContext(ctx)
    if ok {
        ctx = metadata.NewOutgoingContext(ctx, md)
    }
    resp, err := s.otherClient.DoSomething(ctx, &pb.OtherRequest{})
    return resp, err
}

// BETTER: Use OpenTelemetry interceptor for automatic propagation
conn, err := grpc.NewClient(addr,
    grpc.WithUnaryInterceptor(otelgrpc.UnaryClientInterceptor()),
    grpc.WithStreamInterceptor(otelgrpc.StreamClientInterceptor()),
)
```

**Severity:** 🟠 HIGH

### 6. Missing Request ID Propagation

**Проблема:** Request ID не передаётся между сервисами — невозможно трассировать цепочку вызовов.

**Anti-pattern:**
```go
// BAD: No request ID in outgoing call
func (s *Server) Handle(ctx context.Context, req *pb.Request) (*pb.Response, error) {
    result, err := s.client.Call(context.Background(), &pb.CallRequest{})
    // ...
}
```

**Pattern:**
```go
// GOOD: Extract and forward request ID
func (s *Server) Handle(ctx context.Context, req *pb.Request) (*pb.Response, error) {
    md, _ := metadata.FromIncomingContext(ctx)
    outCtx := metadata.NewOutgoingContext(ctx, md)
    result, err := s.client.Call(outCtx, &pb.CallRequest{})
    // ...
}
```

**Severity:** 🟡 MEDIUM

## Client Connection Management

### 7. New Dial Per Request

**Проблема:** Создание нового gRPC соединения на каждый запрос — утечка ресурсов и высокая латентность.

**Anti-pattern:**
```go
// BAD: New connection per request
func (s *Service) CallOther(ctx context.Context) error {
    conn, err := grpc.NewClient("other-service:50051",
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    if err != nil {
        return err
    }
    defer conn.Close()
    client := pb.NewOtherServiceClient(conn)
    _, err = client.DoSomething(ctx, &pb.Request{})
    return err
}
```

**Pattern:**
```go
// GOOD: Shared connection via DI
func NewOtherServiceClient(lc fx.Lifecycle, cfg *Config) (pb.OtherServiceClient, error) {
    conn, err := grpc.NewClient(cfg.OtherServiceAddr,
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    if err != nil {
        return nil, fmt.Errorf("dial other-service: %w", err)
    }
    lc.Append(fx.Hook{
        OnStop: func(ctx context.Context) error {
            return conn.Close()
        },
    })
    return pb.NewOtherServiceClient(conn), nil
}
```

**Severity:** 🟠 HIGH

### 8. Missing Client Timeout

**Проблема:** gRPC вызов без deadline может висеть бесконечно.

**Anti-pattern:**
```go
// BAD: No timeout — can hang forever
resp, err := client.GetData(context.Background(), req)
```

**Pattern:**
```go
// GOOD: Context with timeout
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
resp, err := client.GetData(ctx, req)
```

**Severity:** 🟠 HIGH

## Interceptors

### 9. Duplicated Cross-Cutting Concerns

**Проблема:** Логирование, аутентификация, recovery дублируются в каждом handler.

**Anti-pattern:**
```go
// BAD: Repeated in every handler
func (s *Server) GetUser(ctx context.Context, req *pb.GetUserRequest) (*pb.UserResponse, error) {
    log.Printf("GetUser called with id=%s", req.Id)
    if err := s.auth.Check(ctx); err != nil {
        return nil, status.Error(codes.Unauthenticated, "unauthorized")
    }
    defer func() {
        if r := recover(); r != nil {
            log.Printf("panic in GetUser: %v", r)
        }
    }()
    // ... business logic
}
```

**Pattern:**
```go
// GOOD: Interceptor chain
srv := grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        otelgrpc.UnaryServerInterceptor(),   // tracing
        grpc_recovery.UnaryServerInterceptor(), // panic recovery
        loggingInterceptor,                   // request logging
        authInterceptor,                      // authentication
    ),
)

func loggingInterceptor(
    ctx context.Context,
    req interface{},
    info *grpc.UnaryServerInfo,
    handler grpc.UnaryHandler,
) (interface{}, error) {
    start := time.Now()
    resp, err := handler(ctx, req)
    log.Printf("method=%s duration=%s err=%v", info.FullMethod, time.Since(start), err)
    return resp, err
}
```

**Severity:** 🟡 MEDIUM

### 10. Missing Panic Recovery

**Проблема:** Паника в handler обрушивает весь gRPC сервер.

**Anti-pattern:**
```go
// BAD: No recovery — panic kills the server
srv := grpc.NewServer()
```

**Pattern:**
```go
// GOOD: Recovery interceptor
import grpc_recovery "github.com/grpc-ecosystem/go-grpc-middleware/recovery"

recoveryOpt := grpc_recovery.WithRecoveryHandler(func(p interface{}) error {
    log.Printf("recovered from panic: %v", p)
    return status.Error(codes.Internal, "internal error")
})

srv := grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        grpc_recovery.UnaryServerInterceptor(recoveryOpt),
    ),
    grpc.ChainStreamInterceptor(
        grpc_recovery.StreamServerInterceptor(recoveryOpt),
    ),
)
```

**Severity:** 🟠 HIGH

## Request Validation

### 11. Manual Validation in Handlers

**Проблема:** Ручная валидация полей в каждом handler — дублирование и легко забыть.

**Anti-pattern:**
```go
// BAD: Manual validation in every handler
func (s *Server) CreateOrder(ctx context.Context, req *pb.CreateOrderRequest) (*pb.OrderResponse, error) {
    if req.UserId == "" {
        return nil, status.Error(codes.InvalidArgument, "user_id required")
    }
    if req.Amount <= 0 {
        return nil, status.Error(codes.InvalidArgument, "amount must be positive")
    }
    if req.Currency == "" {
        return nil, status.Error(codes.InvalidArgument, "currency required")
    }
    // ... business logic
}
```

**Pattern:**
```go
// GOOD: Proto validation + interceptor
// In .proto file:
// import "validate/validate.proto";
// message CreateOrderRequest {
//   string user_id = 1 [(validate.rules).string.min_len = 1];
//   double amount = 2 [(validate.rules).double.gt = 0];
//   string currency = 3 [(validate.rules).string.min_len = 1];
// }

// Validation interceptor
func validationInterceptor(
    ctx context.Context,
    req interface{},
    info *grpc.UnaryServerInfo,
    handler grpc.UnaryHandler,
) (interface{}, error) {
    if v, ok := req.(interface{ Validate() error }); ok {
        if err := v.Validate(); err != nil {
            return nil, status.Error(codes.InvalidArgument, err.Error())
        }
    }
    return handler(ctx, req)
}
```

**Severity:** 🟡 MEDIUM

### 12. Zero-Value Check for Required Fields

**Проблема:** Proto3 не различает "не передано" и "значение по умолчанию" для скаляров.

**Anti-pattern:**
```go
// BAD: Missed zero-value check for proto3 scalars
func (s *Server) Transfer(ctx context.Context, req *pb.TransferRequest) (*pb.TransferResponse, error) {
    // req.Amount is 0 if not sent — proto3 default
    s.uc.Transfer(ctx, req.FromId, req.ToId, req.Amount) // Transfers 0!
    // ...
}
```

**Pattern:**
```go
// GOOD: Explicit zero-value validation
func (s *Server) Transfer(ctx context.Context, req *pb.TransferRequest) (*pb.TransferResponse, error) {
    if req.Amount == 0 {
        return nil, status.Error(codes.InvalidArgument, "amount must be non-zero")
    }
    // ... business logic
}

// BETTER: Use optional fields or wrappers in proto
// double amount = 1 [(validate.rules).double.gt = 0];
// google.protobuf.DoubleValue amount = 1; // nil = not set
```

**Severity:** 🟡 MEDIUM

## Server Registration

### 13. Reflection Registration

**Проблема:** Сервер без reflection — `grpcurl`, `grpcui` и другие инструменты не могут обнаружить сервисы.

**Anti-pattern:**
```go
// BAD: No reflection — grpcurl/grpcui can't discover services
srv := grpc.NewServer()
pb.RegisterOrderServiceServer(srv, orderServer)
// grpcurl localhost:50051 list → "Failed to list services"
```

**Pattern:**
```go
// GOOD: Register reflection for discoverability
import "google.golang.org/grpc/reflection"

srv := grpc.NewServer()
pb.RegisterOrderServiceServer(srv, orderServer)
reflection.Register(srv) // Enable grpcurl/grpcui/postman
```

**Severity:** 💡 INFO

### 14. Multi-Domain Proto Service: Aggregate Handler via Embedding

**Проблема:** Один gRPC-сервис в proto содержит RPC-методы из нескольких доменов (например, `LiquidityServiceExternal` с `ListThresholds`, `CreateAdjustment`, `GetLatestReconciliations`). gRPC требует, чтобы один объект реализовывал весь интерфейс. Если методов 8–12, ручное делегирование на доменные хендлеры превращается в десятки однострочных проксей `return h.<domain>.<Method>(ctx, req)` — чистый boilerplate, который может расходиться с доменным хендлером (баг при рефакторинге сигнатур).

**Anti-pattern:**
```go
// BAD: ручное делегирование, ~3 строки на каждый метод
type Handler struct {
    pb.UnimplementedFooServiceExternalServer
    pb.UnimplementedFooServiceInternalServer

    threshold      *thresholdgrpc.Handler
    adjustment     *adjustmentgrpc.Handler
    reconciliation *reconciliationgrpc.Handler
}

func (h *Handler) ListThresholds(ctx context.Context, req *pb.ListThresholdsRequest) (*pb.ListThresholdsResponse, error) {
    return h.threshold.ListThresholds(ctx, req)
}
func (h *Handler) UpsertThreshold(ctx context.Context, req *pb.UpsertThresholdRequest) (*pb.UpsertThresholdResponse, error) {
    return h.threshold.UpsertThreshold(ctx, req)
}
// ... ещё 7–10 одинаковых проксей
```

**Pattern:**
```go
// GOOD: Go embedding — методы автоматически промоутятся в Handler
type Handler struct {
    pb.UnimplementedFooServiceExternalServer
    pb.UnimplementedFooServiceInternalServer

    *thresholdgrpc.Handler
    *adjustmentgrpc.Handler
    *reconciliationgrpc.Handler
}

func NewHandler(
    t *thresholdgrpc.Handler,
    a *adjustmentgrpc.Handler,
    r *reconciliationgrpc.Handler,
) *Handler {
    return &Handler{
        Handler:                t, // см. ниже про коллизии имён полей
        AdjustmentHandler:      a,
        ReconciliationHandler:  r,
    }
}
```

**Условия применимости:**
- доменные хендлеры **не embed-ят** `pb.Unimplemented*Server` (иначе при aggregate возникнут коллизии методов-заглушек)
- proto-методы между доменами имеют уникальные имена (обычно так и есть — `ListThresholds` ≠ `ListAdjustments`)
- доменные хендлеры — это самостоятельные типы, а не интерфейсы

**Где жить aggregate-handler-у:** в transport/delivery-слое — например, `internal/infrastructure/grpc/server/` или `internal/delivery/grpc/aggregate/` рядом с регистрацией сервера. Он не относится ни к одному домену, его задача — собрать proto-контракт из доменных частей.

**Когда aggregate не нужен:** если в сервисе один домен или каждый домен имеет свой proto-сервис — доменный хендлер сразу регистрируется как `pb.RegisterFooServiceServer(srv, domainHandler)` и aggregate излишен.

**Severity:** 🟡 MEDIUM (читаемость + меньше boilerplate-багов)

## Metadata Helpers

### 14. Metadata Extraction Helpers

**Проблема:** Ручной разбор `metadata.FromIncomingContext()` в каждом handler — дублирование и подверженность ошибкам.

**Anti-pattern:**
```go
// BAD: Manual metadata parsing in every handler
func (s *Server) GetOrder(ctx context.Context, req *pb.GetOrderRequest) (*pb.OrderResponse, error) {
    md, ok := metadata.FromIncomingContext(ctx)
    if !ok {
        return nil, status.Error(codes.Internal, "no metadata")
    }
    vals := md.Get("x-request-id")
    var requestID string
    if len(vals) > 0 {
        requestID = vals[0]
    }
    // Same boilerplate in every handler...
}
```

**Pattern:**
```go
// GOOD: Reusable helper functions
func ExtractStringFromMD(ctx context.Context, key string) string {
    md, ok := metadata.FromIncomingContext(ctx)
    if !ok {
        return ""
    }
    vals := md.Get(key)
    if len(vals) == 0 {
        return ""
    }
    return vals[0]
}

func (s *Server) GetOrder(ctx context.Context, req *pb.GetOrderRequest) (*pb.OrderResponse, error) {
    requestID := ExtractStringFromMD(ctx, "x-request-id")
    tenantID := ExtractStringFromMD(ctx, "x-tenant-id")
    // Clean and reusable
}
```

**Severity:** 🟡 MEDIUM

## Client Configuration

### 16. DB-backed Idempotency Interceptor

**Проблема:** Сетевые retry на стороне клиента (как gRPC retry-policy, так и ручные) приводят к повторному выполнению того же мутирующего RPC. Без идемпотентности — двойные списания, дубликаты заказов. In-memory кеш ключей не подходит: при перезапуске или работе нескольких реплик ключи теряются. Идиоматичный шаблон — interceptor поверх таблицы `idempotency_keys`.

**Шаблон:**
1. Клиент передаёт `Idempotency-Key: <uuid>` в metadata.
2. Interceptor вычисляет хэш payload-а (детерминированная сериализация — `proto.MarshalOptions{Deterministic: true}`).
3. Делает `INSERT ... ON CONFLICT DO NOTHING` в `idempotency_keys (key, request_hash, response, status, completed_at)`.
4. Если запись свежая (insert прошёл) — пробрасывает запрос дальше, после успеха handler-а сохраняет `response` и `status='completed'`.
5. Если запись уже есть и завершена — возвращает закэшированный response.
6. Если есть, но `status='in_progress'` и не истёк lease — возвращает `codes.AlreadyExists` (или ждёт, в зависимости от семантики).
7. Если хэш payload-а не совпадает с уже зарезервированным — возвращает `codes.InvalidArgument` ("idempotency key reused with different payload").

**Pattern:**
```go
type IdempotencyStore interface {
    // Reserve atomically inserts a key. If key exists, returns existing record.
    Reserve(ctx context.Context, key string, requestHash []byte, leaseTTL time.Duration) (*IdempotencyRecord, bool, error)
    Complete(ctx context.Context, key string, response []byte, statusCode codes.Code) error
}

type IdempotencyRecord struct {
    Key         string
    RequestHash []byte
    Response    []byte
    Status      string // "in_progress" | "completed"
    CompletedAt sql.NullTime
}

func IdempotencyInterceptor(store IdempotencyStore, codec Codec) grpc.UnaryServerInterceptor {
    return func(
        ctx context.Context,
        req interface{},
        info *grpc.UnaryServerInfo,
        handler grpc.UnaryHandler,
    ) (interface{}, error) {
        // только для мутирующих методов; остальные пропускаем
        if !isMutating(info.FullMethod) {
            return handler(ctx, req)
        }

        md, _ := metadata.FromIncomingContext(ctx)
        key := firstOrEmpty(md.Get("idempotency-key"))
        if key == "" {
            return handler(ctx, req) // ключ не передан — без защиты
        }

        reqHash, err := codec.Hash(req)
        if err != nil {
            return nil, status.Error(codes.Internal, "hash request")
        }

        rec, fresh, err := store.Reserve(ctx, key, reqHash, 30*time.Second)
        if err != nil {
            return nil, status.Error(codes.Internal, "reserve idempotency key")
        }
        if !fresh {
            // уже видели этот ключ
            if !bytes.Equal(rec.RequestHash, reqHash) {
                return nil, status.Error(codes.InvalidArgument,
                    "idempotency key reused with different payload")
            }
            if rec.Status == "completed" {
                return codec.Decode(rec.Response, info)
            }
            return nil, status.Error(codes.AlreadyExists, "request in progress")
        }

        // первый раз — пробрасываем, ключ доступен handler-у через ctx
        ctx = context.WithValue(ctx, idempotencyKeyCtx{}, key)
        resp, handlerErr := handler(ctx, req)

        // фиксируем результат (даже при ошибке — если хотим кэшировать ошибки)
        respBytes, _ := codec.Encode(resp)
        statusCode := status.Code(handlerErr)
        if storeErr := store.Complete(ctx, key, respBytes, statusCode); storeErr != nil {
            // логируем, но возвращаем оригинальный результат
        }
        return resp, handlerErr
    }
}
```

**Соображения:**
- идемпотентность должна быть **per-method** (или по группам), иначе один и тот же ключ для `CreateOrder` и `CreateRefund` коллизит
- TTL записей: краткосрочный (минуты — для in-progress lease) и долгосрочный (часы/сутки — для completed); чистится фоновой задачей
- хэш считается по детерминированной сериализации; для proto-сообщений включить `Deterministic: true`, иначе порядок полей в map-ах ломает хэш
- если handler сохраняет данные транзакционно, идеально включить `idempotency_keys` в **ту же транзакцию** — иначе возможна частичная неконсистентность; тогда interceptor просто резервирует ключ, а commit делает handler через outbox-подобный механизм

**Severity:** 🟠 HIGH

## Proto ↔ Domain Mapping

### Where Mapping Methods Live

**Проблема:** Если методы `FromProto`/`ToProto` живут в `domain/entities`, домен начинает зависеть от `proto/*` — ломается dependency rule (transport не должен протекать в domain). Если разбросаны inline в gRPC handler-ах — дублирование при использовании одной сущности в нескольких RPC.

**Anti-pattern:**
```go
// BAD: proto-импорт в domain/entities
package entities

import pb "project/proto/order/v1"

type Order struct {
    ID     uuid.UUID
    Status OrderStatus
}

func (o *Order) ToProto() *pb.Order { /* ... */ } // domain знает про proto
```

**Pattern:**
```go
// GOOD: маппинг живёт в delivery/grpc, в отдельном файле mapping.go
// internal/domain/order/delivery/grpc/mapping.go
package grpc

import (
    "project/internal/domain/order/entities"
    pb "project/proto/order/v1"
)

func orderToProto(o *entities.Order) *pb.Order {
    return &pb.Order{
        Id:     o.ID.String(),
        Status: orderStatusToProto(o.Status),
    }
}

func orderFromProto(p *pb.Order) (*entities.Order, error) {
    id, err := uuid.Parse(p.GetId())
    if err != nil {
        return nil, fmt.Errorf("parse order id: %w", err)
    }
    return &entities.Order{
        ID:     id,
        Status: orderStatusFromProto(p.GetStatus()),
    }, nil
}

func orderStatusToProto(s entities.OrderStatus) pb.OrderStatus {
    switch s {
    case entities.OrderStatusPending:
        return pb.OrderStatus_ORDER_STATUS_PENDING
    case entities.OrderStatusCompleted:
        return pb.OrderStatus_ORDER_STATUS_COMPLETED
    default:
        return pb.OrderStatus_ORDER_STATUS_UNSPECIFIED
    }
}
```

**Правила:**
- маппинг живёт в `delivery/grpc/` (или `delivery/http/` — для HTTP-DTO) — там же, где импортируется proto
- `domain/entities` не импортирует ни `proto/*`, ни `*pb`-пакеты
- enum-маппинг в отдельных функциях — упрощает обновление при изменении proto-enum-ов
- ошибки в `FromProto` (некорректный UUID, невалидный enum) возвращаем как `*ValidationError`, чтобы handler смог замапить в `codes.InvalidArgument`
- если методов много, можно использовать `protoc-gen-go-mapper` или ручной адаптер; обёртки типа `(d *Domain) FromProto(*pb.X)` не используем — они тянут proto в domain

**Severity:** 🟡 MEDIUM

### 17. Client Interceptor Chain

**Проблема:** Логирование, трейсинг и retry добавляются вручную при каждом gRPC-вызове вместо централизованных interceptor'ов.

**Anti-pattern:**
```go
// BAD: Manual logging/tracing per call
func (c *Client) GetUser(ctx context.Context, id string) (*pb.UserResponse, error) {
    start := time.Now()
    span, ctx := opentracing.StartSpanFromContext(ctx, "grpc.GetUser")
    defer span.Finish()

    resp, err := c.client.GetUser(ctx, &pb.GetUserRequest{Id: id})

    log.Printf("GetUser id=%s duration=%s err=%v", id, time.Since(start), err)
    return resp, err
}
```

**Pattern:**
```go
// GOOD: Interceptor chain on client connection
conn, err := grpc.NewClient(addr,
    grpc.WithTransportCredentials(insecure.NewCredentials()),
    grpc.WithChainUnaryInterceptor(
        otelgrpc.UnaryClientInterceptor(),     // tracing
        loggingClientInterceptor,               // logging
        retryInterceptor,                       // retry with backoff
    ),
    grpc.WithChainStreamInterceptor(
        otelgrpc.StreamClientInterceptor(),
    ),
)

func loggingClientInterceptor(
    ctx context.Context,
    method string,
    req, reply interface{},
    cc *grpc.ClientConn,
    invoker grpc.UnaryInvoker,
    opts ...grpc.CallOption,
) error {
    start := time.Now()
    err := invoker(ctx, method, req, reply, cc, opts...)
    log.Printf("grpc call method=%s duration=%s err=%v", method, time.Since(start), err)
    return err
}
```

**Severity:** 🟡 MEDIUM
