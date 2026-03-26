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

### 15. Client Interceptor Chain

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
