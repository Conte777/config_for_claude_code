# Internal Packages Reference

Detailed documentation for internal infrastructure packages used across microservices.

---

## Infrastructure Connectors

### pgconnector

PostgreSQL connection with pooling, transaction management, hooks, and migrations.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/pgconnector`

**Key Interface:**

```go
type IDB interface {
    Do(ctx context.Context) *sqlx.DB
    WithTx(ctx context.Context, fn func(ctx context.Context) error) error
}
```

**FX Module:** `pgconnectorfx.PGConnectorFx`

**Usage:**

```go
// Inject IDB
func NewRepository(db pgconnector.IDB) deps.Repository {
    return &repo{db: db}
}

// Simple query
func (r *repo) GetByID(ctx context.Context, id uuid.UUID) (*Entity, error) {
    var entity Entity
    err := r.db.Do(ctx).GetContext(ctx, &entity, `SELECT * FROM table WHERE id = $1`, id)
    return &entity, err
}

// Transaction
func (r *repo) CreateWithItems(ctx context.Context, order *Order, items []Item) error {
    return r.db.WithTx(ctx, func(ctx context.Context) error {
        _, err := r.db.Do(ctx).NamedExecContext(ctx, insertOrderQuery, order)
        if err != nil {
            return err
        }
        for _, item := range items {
            _, err := r.db.Do(ctx).NamedExecContext(ctx, insertItemQuery, item)
            if err != nil {
                return err
            }
        }
        return nil
    })
}
```

**Configuration:**

```
DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_DATABASE
DB_SSL_MODE                       # disable/require/verify-ca/verify-full
DB_POOL_MAX_OPEN_CONNECTS         # Default: 10
DB_POOL_CONN_MAX_LIFETIME_SEC     # Default: 300
DB_POOL_MAX_IDLE_CONNECTS         # Default: 5
DB_LOG_EXEC_TIME                  # true/false
```

**Hooks:**
- `TracingHook` - OpenTelemetry spans for SQL queries
- `ExecTimeHook` - Execution time logging

---

### redisconnector

Redis client with OpenTelemetry tracing, supports standalone and Sentinel modes.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/redisconnector`

**Key Interface:**

```go
type IRedis interface {
    Get(ctx context.Context, key string) *redis.StringCmd
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) *redis.StatusCmd
    Del(ctx context.Context, keys ...string) *redis.IntCmd
    // ... all redis.Client methods
}
```

**FX Modules:**
- `redisfx.RedisFx` - Standalone Redis
- `redissentinelfx.RedisSentinelFx` - Redis Sentinel

**Usage:**

```go
func NewCache(redis redisconnector.IRedis) *Cache {
    return &Cache{redis: redis}
}

func (c *Cache) Get(ctx context.Context, key string) (string, error) {
    result := c.redis.Get(ctx, key)
    if result.Err() == redis.Nil {
        return "", ErrNotFound
    }
    return result.Val(), result.Err()
}

func (c *Cache) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
    return c.redis.Set(ctx, key, value, ttl).Err()
}
```

**Configuration:**

```
REDIS_DSN              # redis:6379
REDIS_DB               # 0-15
REDIS_USER             # Optional
REDIS_PASSWORD         # Optional
REDIS_TSL_REQUIRED     # true/false
REDIS_READ_TIMEOUT     # 5s
REDIS_WRITE_TIMEOUT    # 5s
```

---

### kafkaconnector

Kafka producer and consumer with OpenTelemetry tracing, supports JSON and Avro serialization.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/kafkaconnector`

**Key Interfaces:**

```go
type IProducer interface {
    Produce(ctx context.Context, topic string, key, value []byte) error
    ProduceJSON(ctx context.Context, topic string, key string, value interface{}) error
    ProduceAvro(ctx context.Context, topic string, key string, value interface{}) error
}

type IConsumer interface {
    AddSimpleHandler(topic string, handler Handler, workers int)
    AddSimpleJSONHandler(topic string, factory func() interface{}, handler JSONHandler, workers int)
    Consume() // Blocking
}
```

**Usage - Producer:**

```go
func NewService(producer kafkaconnector.IProducer) *Service {
    return &Service{producer: producer}
}

func (s *Service) PublishEvent(ctx context.Context, event *Event) error {
    return s.producer.ProduceJSON(ctx, "events-topic", event.ID.String(), event)
}
```

**Usage - Consumer:**

```go
func RegisterHandlers(consumer kafkaconnector.IConsumer, handler *Handler) {
    consumer.AddSimpleJSONHandler(
        "events-topic",
        func() interface{} { return &Event{} }, // Factory for deserialization
        handler.HandleEvent,
        5, // Worker count
    )
}

func (h *Handler) HandleEvent(ctx context.Context, msg *Event) error {
    // Process event
    return nil
}

// In fx.Invoke - blocking call
func StartConsumer(lc fx.Lifecycle, consumer kafkaconnector.IConsumer) {
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            go consumer.Consume() // Blocking, run in goroutine
            return nil
        },
    })
}
```

**Configuration:**

```
KAFKA_BROKERS              # kafka:9092
KAFKA_GROUP_ID             # consumer-group
KAFKA_SCHEMA_REGISTRY_URL  # For Avro
```

---

### rabbitconnector

RabbitMQ producer and consumer with OpenTelemetry tracing and auto-reconnect.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/rabbitconnector`

**Key Interfaces:**

```go
type IProducer interface {
    Publish(ctx context.Context, routingKey string, body []byte) error
    PublishJSON(ctx context.Context, routingKey string, body interface{}) error
}

type IConsumer interface {
    AddSimpleHandler(routingKey string, handler Handler, workers int)
    Consume() // Blocking
}

type Handler func(ctx context.Context, delivery amqp.Delivery) Action

type Action int
const (
    Ack Action = iota
    Nack
    Reject
)
```

**Usage:**

```go
func (h *Handler) HandleMessage(ctx context.Context, delivery amqp.Delivery) rabbitconnector.Action {
    var msg Message
    if err := json.Unmarshal(delivery.Body, &msg); err != nil {
        return rabbitconnector.Reject
    }

    if err := h.process(ctx, &msg); err != nil {
        return rabbitconnector.Nack // Will be requeued
    }

    return rabbitconnector.Ack
}
```

---

### vaultconnector

HashiCorp Vault integration for secrets management with AppRole authentication.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/vaultconnector`

**Key Interface:**

```go
type Connector interface {
    GetSecret(path string) (map[string]interface{}, error)
    FXStart() error
    FXStop() error
}
```

**FX Module:** `VaultFx`

**Usage:**

```go
func NewService(vault vaultconnector.Connector) *Service {
    return &Service{vault: vault}
}

func (s *Service) GetAPIKey(ctx context.Context) (string, error) {
    secret, err := s.vault.GetSecret("secret/data/api-keys")
    if err != nil {
        return "", err
    }
    return secret["api_key"].(string), nil
}
```

**Configuration:**

```
VAULT_ADDRESS    # https://vault:8200
VAULT_ROLE_ID    # AppRole role ID
VAULT_SECRET_ID  # AppRole secret ID
```

---

### s3

S3-compatible storage operations using AWS SDK v2.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/s3`

**Key Interface:**

```go
type IS3 interface {
    UploadFile(ctx context.Context, key string, data io.Reader) error
    DownloadFile(ctx context.Context, key string) ([]byte, error)
}
```

**FX Module:** `S3Fx`

**Configuration:**

```
S3_KEY       # Access key
S3_SECRET    # Secret key
S3_ENDPOINT  # https://s3.amazonaws.com
S3_REGION    # us-east-1
S3_BUCKET    # bucket-name
```

---

### clickhouseconnector

ClickHouse connection with native protocol, OpenTelemetry tracing, hooks, and batch inserts.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/shared/clickhouseconnector`

**Key Interface:**

```go
type ICH interface {
    Exec(ctx context.Context, query string, args ...any) error
    Query(ctx context.Context, query string, args ...any) (driver.Rows, error)
    QueryRow(ctx context.Context, query string, args ...any) driver.Row
    Select(ctx context.Context, dest any, query string, args ...any) error
    PrepareBatch(ctx context.Context, query string, opts ...driver.PrepareBatchOption) (driver.Batch, error)
    Ping(ctx context.Context) error
    Close() error
    FXStart(ctx context.Context) error
    FXStop(ctx context.Context) error
}
```

**FX Module:** `clickhouseconnectorfx.ClickHouseConnectorFx`

**Usage:**

```go
// Inject ICH
func NewRepository(ch clickhouseconnector.ICH) *Repository {
    return &Repository{ch: ch}
}

// Simple query
func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*Entity, error) {
    var entities []Entity
    err := r.ch.Select(ctx, &entities, `SELECT * FROM table WHERE id = ?`, id)
    if len(entities) == 0 {
        return nil, ErrNotFound
    }
    return &entities[0], err
}

// Exec
func (r *Repository) Insert(ctx context.Context, entity *Entity) error {
    return r.ch.Exec(ctx,
        `INSERT INTO table (id, name, created_at) VALUES (?, ?, ?)`,
        entity.ID, entity.Name, entity.CreatedAt,
    )
}

// Batch insert
func (r *Repository) BulkInsert(ctx context.Context, entities []Entity) error {
    batch, err := r.ch.PrepareBatch(ctx, "INSERT INTO table")
    if err != nil {
        return err
    }
    for _, e := range entities {
        if err := batch.Append(e.ID, e.Name, e.CreatedAt); err != nil {
            return err
        }
    }
    return batch.Send()
}
```

**Configuration:**

```
CLICKHOUSE_HOSTS=host1,host2           # Comma-separated hosts (failover)
CLICKHOUSE_PORT=9000                   # Native protocol port
CLICKHOUSE_DATABASE=mydb
CLICKHOUSE_USERNAME=user
CLICKHOUSE_PASSWORD=password
CLICKHOUSE_POOL_MAX_OPEN_CONNS=10
CLICKHOUSE_POOL_MAX_IDLE_CONNS=5
CLICKHOUSE_POOL_CONN_MAX_LIFETIME_SEC=300
CLICKHOUSE_TLS_ENABLED=false
CLICKHOUSE_COMPRESSION_ENABLED=true
CLICKHOUSE_COMPRESSION_METHOD=lz4     # lz4/zstd/none
CLICKHOUSE_LOG_EXEC_TIME=true
CLICKHOUSE_TRACING_ENABLED=true
```

**Hooks:**
- `ExecTimeHook` — Execution time logging
- `TracingHook` — OpenTelemetry spans for ClickHouse queries

---

## Observability

### logger

Structured logging with zap and OpenTelemetry integration via otelzap.

**Import:** `git.bwg-io.site/processing/new-cryptoprocessing/pkg/logger`

**Key Interface:**

```go
type ILogger interface {
    Debug(args ...interface{})
    Debugf(template string, args ...interface{})
    Debugw(msg string, keysAndValues ...interface{})
    DebugwCtx(ctx context.Context, msg string, keysAndValues ...interface{})

    Info(args ...interface{})
    Infof(template string, args ...interface{})
    Infow(msg string, keysAndValues ...interface{})
    InfowCtx(ctx context.Context, msg string, keysAndValues ...interface{})

    Warn(args ...interface{})
    Warnf(template string, args ...interface{})
    Warnw(msg string, keysAndValues ...interface{})
    WarnwCtx(ctx context.Context, msg string, keysAndValues ...interface{})

    Error(args ...interface{})
    Errorf(template string, args ...interface{})
    Errorw(msg string, keysAndValues ...interface{})
    ErrorwCtx(ctx context.Context, msg string, keysAndValues ...interface{})
}
```

**FX Module:** `loggerfx.LoggerFx`

**Usage:**

```go
func NewService(log logger.ILogger) *Service {
    return &Service{log: log}
}

func (s *Service) Process(ctx context.Context, id uuid.UUID) error {
    s.log.InfowCtx(ctx, "processing started", "id", id)

    if err := s.doWork(ctx); err != nil {
        s.log.ErrorwCtx(ctx, "processing failed", "id", id, "error", err)
        return err
    }

    s.log.InfowCtx(ctx, "processing completed", "id", id)
    return nil
}
```

**Configuration:**

```
LOGGER_SERVICE_NAME     # my-service
LOGGER_SERVICE_VERSION  # 1.0.0
LOGGER_DEVELOPMENT      # true/false
LOGGER_ENCODING         # json/console
LOGGER_LEVEL            # debug/info/warn/error
```

---

### tracer

OpenTelemetry tracing for gRPC, Kafka, RabbitMQ, and database operations.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/tracer`

**Key Interface:**

```go
type ITracer interface {
    Start(ctx context.Context, spanName string, opts ...trace.SpanStartOption) (context.Context, trace.Span)
}
```

**FX Module:** `tracerfx.TracerFx`

**Usage:**

```go
func (s *Service) Process(ctx context.Context, id uuid.UUID) error {
    ctx, span := tracer.Get().Start(ctx, "Service.Process")
    defer span.End()

    span.SetAttributes(attribute.String("order.id", id.String()))

    if err := s.doWork(ctx); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return err
    }

    return nil
}
```

**gRPC Integration:**

```go
// Server
grpc.NewServer(tracer.WithGRPCServerOptions()...)

// Client
conn, _ := grpc.Dial(addr, tracer.WithGRPCClientOptions()...)
```

**Kafka Integration:**

```go
// Inject trace into message
headers := tracer.InjectKafkaTrace(ctx)

// Extract trace from message
ctx = tracer.ExtractKafkaTrace(ctx, headers)

// Wrap handler with tracing
wrappedHandler := tracer.WrapKafkaHandler("topic", handler)
```

---

### meter

Prometheus metrics collection via OpenTelemetry.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/meter`

**Key Interface:**

```go
type IMeter interface {
    Int64Counter(name string, opts ...metric.Int64CounterOption) (metric.Int64Counter, error)
    Int64UpDownCounter(name string, opts ...metric.Int64UpDownCounterOption) (metric.Int64UpDownCounter, error)
    Int64Histogram(name string, opts ...metric.Int64HistogramOption) (metric.Int64Histogram, error)
    Float64Counter(name string, opts ...metric.Float64CounterOption) (metric.Float64Counter, error)
}
```

**Usage:**

```go
func NewService(meter meter.IMeter) *Service {
    counter, _ := meter.Int64Counter("orders_processed",
        metric.WithDescription("Number of processed orders"),
    )
    return &Service{counter: counter}
}

func (s *Service) Process(ctx context.Context) {
    s.counter.Add(ctx, 1, metric.WithAttributes(
        attribute.String("status", "success"),
    ))
}
```

**Endpoints:**
- `/metrics` - Prometheus metrics
- `/debug/pprof/*` - Profiling

---

### healthcheck

Kubernetes health and readiness probes with pprof endpoints.

**Import:** `gl.dteam.site/cryptoprocessing/pkg/healthcheck`

**FX Modules:**
- `healthfx.HealthCheckFx` - Main health check
- `healthfx.ReadinessProbeFX` - Readiness probe

**Endpoints:**
- `/healthz` - Liveness probe
- `/readyz` - Readiness probe
- `/debug/pprof/*` - Profiling

**Configuration:**

```
HEALTHCHECK_PORT  # 8081
HEALTHCHECK_PATH  # /healthz
```

---

## Utilities

### configurator

Universal configuration parsing from YAML or ENV with validation.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/configurator`

**Usage:**

```go
type Config struct {
    Server ServerConfig `envPrefix:"SERVER_" yaml:"Server" validate:"required"`
    DB     DBConfig     `envPrefix:"DB_" yaml:"DB" validate:"required"`
}

func LoadConfig() (*Config, error) {
    cfg, err := configurator.NewConfigurator[Config](
        configurator.ParseTypeENV,
    ).GetConfig()
    return &cfg, err
}
```

**Parse Types:**
- `ParseTypeYAML` - From YAML files
- `ParseTypeENV` - From environment variables

---

### events

Event types for inter-service communication.

**Import:** `git.bwg-io.site/processing/new-cryptoprocessing/pkg/events/v2`

**Key Types:**

```go
type Event[T AnyOrder] struct {
    ID        uuid.UUID
    Type      EventType
    Order     T
    Timestamp time.Time
}

type InvoiceOrder struct { /* ... */ }
type WithdrawOrder struct { /* ... */ }
type OILOrder struct { /* ... */ }
type BatchOrder struct { /* ... */ }
```

All types have `IsValid() error` method for validation.

---

### outbox

Transactional Outbox pattern for guaranteed message delivery.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/outbox`

**Key Interface:**

```go
type Sender interface {
    SendMessage(ctx context.Context, msg *Message) error
    OnStart(ctx context.Context) error
    OnStop(ctx context.Context) error
}

type Message struct {
    ID         uuid.UUID
    RoutingKey string
    Body       []byte
    CreatedAt  time.Time
}
```

**Usage:**

```go
sender, _ := outbox.New(log, config,
    outbox.WithDefaultStorage(db),
    outbox.WithSender(rabbitProducer),
)

// In transaction
err := db.WithTx(ctx, func(ctx context.Context) error {
    // Save to database
    if err := repo.Create(ctx, entity); err != nil {
        return err
    }

    // Queue message (saved in same transaction)
    return sender.SendMessage(ctx, &outbox.Message{
        RoutingKey: "entity.created",
        Body:       jsonData,
    })
})
```

**Storage Options:**
- PostgreSQL (default)
- Redis
- In-Memory (testing)

---

### memcache

Generic thread-safe in-memory caches.

**Import:** Internal package

**Cache Types:**

```go
// Basic concurrent map
cache := memcache.NewCache[string, int]()
cache.Set("key", 42)
val, ok := cache.Get("key")
cache.Delete("key")

// Snapshot cache with TTL and bulk loading
snapshot := memcache.NewSnapshotStorage(
    ctx,
    time.Minute,                    // Refresh interval
    loader,                         // func(ctx) ([]T, error)
    keyExtractor,                   // func(T) K
    errHandler,                     // func(error)
)
snapshot.Start()
val, ok := snapshot.Get("key")

// Deadline cache with per-key TTL
deadline := memcache.NewDeadlineCache[string, int]()
deadline.SetWithDeadline("key", 42, time.Now().Add(time.Minute))
val, ok := deadline.Get("key") // Returns false if expired
```

---

### pagination

Reusable pagination primitives.

**Import:** `git.bwg-io.site/processing/new-cryptoprocessing/pkg/pagination`

**Usage:**

```go
type ListRequest struct {
    Limit  int `query:"limit" validate:"min=1,max=100"`
    Offset int `query:"offset" validate:"min=0"`
}

type ListResponse[T any] struct {
    Items []T `json:"items"`
    Total int `json:"total"`
}
```

---

### access_level_guard

gRPC access control via protobuf annotations.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/access-level-guard`

**Usage:**

```go
// Build guard
guardBuilder := aGuard.NewAccessGuardBuilder()
guardBuilder.Register(proto.MyService_ServiceDesc, proto.File_my_service_proto)
guard := guardBuilder.Build()

// Add interceptor
grpc.NewServer(
    grpc.UnaryInterceptor(guard.AccessLevelUnaryInterceptor()),
    grpc.StreamInterceptor(guard.AccessLevelStreamInterceptor()),
)
```

**Proto Definition:**

```protobuf
import "access_level.proto";

service MyService {
    rpc GetUser(GetUserRequest) returns (GetUserResponse) {
        option (access_level.required) = "user:read";
    }
}
```

---

### tlser

TLS certificate management for gRPC.

**Import:** `git.itcrew.info/Fri_releases/cryptoprocessing/backend-cp/pkg/tlser`

**Key Interface:**

```go
type ITLSProvider interface {
    Init() error
    GetCredentials(serviceName string) credentials.TransportCredentials
}
```

**FX Module:** `TLSProviderFx`

**Usage:**

```go
// Server with mTLS
creds := tlsProvider.GetCredentials("my-service")
grpc.NewServer(grpc.Creds(creds))

// Client
creds := tlsProvider.GetCredentials("target-service")
conn, _ := grpc.Dial(addr, grpc.WithTransportCredentials(creds))
```

---

### wallet_streamer

Wallet subscription and streaming mechanism.

**Import:** Internal package

**Key Interfaces:**

```go
type IStreamer interface {
    Subscribe(ctx context.Context, blockchain string) (<-chan *Wallet, error)
    Unsubscribe(blockchain string)
}

type ISubscriber interface {
    Connect(ctx context.Context) error
    IterAllWallets(ctx context.Context) (<-chan *Wallet, error)
}
```

**Data Flow:**
1. Historical wallets via `IterAllWallets()`
2. New wallets in real-time via subscription channel
3. Auto-reconnect on disconnect

---

## Quick Reference Table

| Package | FX Module | Key Interface | Primary Use |
|---------|-----------|---------------|-------------|
| pgconnector | `pgconnectorfx.PGConnectorFx` | `IDB` | PostgreSQL operations |
| redisconnector | `redisfx.RedisFx` | `IRedis` | Redis caching |
| kafkaconnector | Manual | `IProducer`, `IConsumer` | Event streaming |
| rabbitconnector | Manual | `IProducer`, `IConsumer` | Message queue |
| vaultconnector | `VaultFx` | `Connector` | Secrets management |
| s3 | `S3Fx` | `IS3` | File storage |
| clickhouseconnector | `clickhouseconnectorfx.ClickHouseConnectorFx` | `ICH` | ClickHouse operations |
| logger | `loggerfx.LoggerFx` | `ILogger` | Structured logging |
| tracer | `tracerfx.TracerFx` | `ITracer` | Distributed tracing |
| meter | `meterFx` | `IMeter` | Metrics collection |
| healthcheck | `healthfx.HealthCheckFx` | - | Health probes |
| configurator | - | `Configurator[T]` | Configuration loading |
| outbox | Manual | `Sender` | Guaranteed delivery |
| memcache | - | `Cache[K,V]` | In-memory caching |
| access_level_guard | - | `AccessLevelGuard` | gRPC authorization |
| tlser | `TLSProviderFx` | `ITLSProvider` | TLS certificates |
