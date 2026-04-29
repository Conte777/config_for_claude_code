# Go + Observability Patterns Reference

Структурированное логирование, метрики и трейсинг — без них невозможно эксплуатировать сервис в production.

**See also:**
- `patterns.md` — общие Go паттерны
- `grpc.md` — gRPC interceptors для tracing/metrics
- `kafka.md` — propagation через Kafka headers
- `http.md` — middleware-цепочка

## Logging

### Use `zap` for Structured Logging

**Проблема:** `log.Printf("user %s did %s", id, action)` — текст, который сложно фильтровать в Kibana/Loki. Без структурированных полей нельзя делать "all errors with user_id=X" одним запросом.

**Pattern (uber-go/zap):**
```go
import "go.uber.org/zap"

logger, err := zap.NewProduction()
if err != nil { /* ... */ }
defer logger.Sync()

// JSON-output с полями
logger.Info("order created",
    zap.String("order_id", orderID.String()),
    zap.String("user_id", userID.String()),
    zap.String("trace_id", traceID),
    zap.Float64("amount", amount),
)
// Output: {"level":"info","ts":...,"msg":"order created","order_id":"...","user_id":"..."}
```

**Уровни и когда какой:**
| Уровень | Когда                                             | Пример                                            |
|---------|---------------------------------------------------|---------------------------------------------------|
| `Debug` | Внутреннее состояние, временно для troubleshooting | `cache key built`, `query plan selected`          |
| `Info`  | Ключевые бизнес-события                            | `order created`, `payment processed`              |
| `Warn`  | Восстановимая аномалия — стоит обратить внимание   | `cache miss above threshold`, `retry succeeded`   |
| `Error` | Невосстановимая ошибка операции (но не процесса)   | `failed to process order: db error`               |
| `Fatal` | Завершить процесс с `os.Exit(1)`                   | Только в `main()` при критических init-ошибках. **Никогда** в hot path. |

### Контекстные поля через child logger

**Проблема:** Каждый `logger.Info` повторяет одни и те же `request_id`, `user_id`. Boilerplate + риск пропустить поле.

**Pattern:**
```go
// В middleware/handler — добавляем поля один раз
logger := h.logger.With(
    zap.String("request_id", requestid.FromContext(ctx)),
    zap.String("trace_id", trace.SpanContextFromContext(ctx).TraceID().String()),
)

ctx = ctxzap.ToContext(ctx, logger) // helper, кладём в ctx

// Глубоко в use case — извлекаем
log := ctxzap.FromContext(ctx)
log.Info("processing order", zap.String("order_id", id.String()))
// автоматически с request_id и trace_id
```

**Sampling для high-throughput сервисов:**
```go
// zap.NewProductionConfig() уже включает sampling (первый и каждый сотый из секунды),
// для тонкой настройки:
cfg := zap.NewProductionConfig()
cfg.Sampling = &zap.SamplingConfig{
    Initial:    100,  // первые 100 сообщений каждого уровня в секунду
    Thereafter: 100,  // далее — каждое 100-е
}
```

**Severity:** 🟠 HIGH

### Anti-patterns

```go
// BAD: log + return — тот же error логируется дважды (тут и выше по стеку)
if err != nil {
    logger.Error("failed", zap.Error(err))
    return err
}

// BAD: PII в логах
logger.Info("login", zap.String("password", req.Password))

// BAD: error.Error() как msg, без zap.Error(err) — теряем stack
logger.Error(err.Error())

// GOOD: log один раз на верхнем уровне (handler/middleware) ИЛИ контекстное обогащение через wrap
return fmt.Errorf("create order for user %s: %w", userID, err)
```

---

## Metrics (Prometheus)

### Naming Conventions

**Pattern:**
```
<service>_<subsystem>_<name>_<unit>
```

| Имя метрики                                   | Тип       | Когда                                         |
|-----------------------------------------------|-----------|-----------------------------------------------|
| `order_http_requests_total`                   | counter   | количество HTTP-запросов                       |
| `order_http_request_duration_seconds`         | histogram | время ответа                                   |
| `order_db_pool_open_connections`              | gauge     | текущее число открытых соединений              |
| `order_kafka_consumer_lag`                    | gauge     | текущий lag consumer-группы                    |

**Правила:**
- `_total` суффикс — обязателен для counter
- `_seconds`, `_bytes`, `_ratio` — единицы измерения в имени
- НЕ использовать camelCase или dashes — только snake_case

### High-Cardinality Labels — Don't

**Проблема:** Labels вроде `user_id`, `order_id`, `request_id` — high-cardinality (миллионы значений). Каждое уникальное сочетание label-ов = отдельный time-series, что взрывает Prometheus storage.

**Anti-pattern:**
```go
// BAD: order_id даёт миллион time-series
ordersProcessed.WithLabelValues(orderID.String()).Inc()
```

**Pattern:**
```go
import "github.com/prometheus/client_golang/prometheus/promauto"

var (
    httpRequestsTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "order_http_requests_total",
            Help: "Total HTTP requests",
        },
        []string{"method", "path", "status"}, // bounded — небольшое число значений
    )

    httpRequestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "order_http_request_duration_seconds",
            Help:    "HTTP request duration",
            Buckets: prometheus.DefBuckets, // или кастом: []float64{0.005, 0.01, 0.025, 0.05, ...}
        },
        []string{"method", "path"},
    )
)

httpRequestsTotal.WithLabelValues("POST", "/orders", "201").Inc()
httpRequestDuration.WithLabelValues("POST", "/orders").Observe(0.123)
```

**Правила:**
- labels должны иметь bounded cardinality: HTTP method (5 значений), endpoint (десятки), status code (десятки)
- Никогда не label по: user_id, order_id, IP, request_id
- `path` нормализовать: `/orders/123` → `/orders/{id}`

**Severity:** 🟠 HIGH

### Histogram Buckets

**Проблема:** Default buckets `[0.005, 0.01, 0.025, ..., 10]` плохо подходят для всех случаев: для DB-запросов широкие интервалы скрывают p95, для long-polling — слишком узкие.

**Pattern:**
```go
// Для HTTP API (типично 1ms–1s)
httpBuckets := prometheus.ExponentialBuckets(0.001, 2, 12) // 1ms, 2ms, 4ms, ..., 4s

// Для DB-запросов (обычно sub-100ms)
dbBuckets := []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0}

// Для long-running операций
batchBuckets := prometheus.LinearBuckets(1, 5, 20) // 1s, 6s, 11s, ..., 96s
```

**Severity:** 🟡 MEDIUM

---

## Tracing (OpenTelemetry)

### Span Propagation Through Context

**Проблема:** Без передачи trace context через `context.Context` каждый сервис стартует свой trace — distributed tracing разваливается.

**Pattern:**
```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/attribute"
    "go.opentelemetry.io/otel/codes"
    "go.opentelemetry.io/otel/trace"
)

var tracer = otel.Tracer("project/internal/domain/order")

func (uc *UseCase) CreateOrder(ctx context.Context, req *CreateOrderRequest) (*Order, error) {
    ctx, span := tracer.Start(ctx, "UseCase.CreateOrder",
        trace.WithAttributes(
            attribute.String("user.id", req.UserID.String()),
            attribute.Float64("order.amount", req.Amount),
        ),
    )
    defer span.End()

    order, err := uc.repo.Create(ctx, &Order{/* ... */}) // ctx с активным span — child будет ребёнком
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return nil, err
    }
    span.SetAttributes(attribute.String("order.id", order.ID.String()))
    return order, nil
}
```

### Cross-Service Propagation

HTTP/gRPC interceptor-ы из `otelhttp`/`otelgrpc` пакетов автоматически инжектят/извлекают trace context. Для Kafka — propagator с custom carrier (см. `kafka.md`).

```go
// HTTP server
import "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

mux := http.NewServeMux()
handler := otelhttp.NewHandler(mux, "http-server")

// HTTP client
client := &http.Client{
    Transport: otelhttp.NewTransport(http.DefaultTransport),
}

// gRPC server
srv := grpc.NewServer(
    grpc.ChainUnaryInterceptor(otelgrpc.UnaryServerInterceptor()),
)

// gRPC client
conn, _ := grpc.NewClient(addr,
    grpc.WithChainUnaryInterceptor(otelgrpc.UnaryClientInterceptor()),
)
```

### Span Attributes Conventions

OTel определяет стандартные attribute-имена ([semantic conventions](https://opentelemetry.io/docs/specs/semconv/)). Использовать их вместо самопальных:

```go
// GOOD: semantic conventions
import semconv "go.opentelemetry.io/otel/semconv/v1.26.0"

span.SetAttributes(
    semconv.HTTPRequestMethodKey.String("POST"),
    semconv.URLPathKey.String("/orders"),
    semconv.UserIDKey.String(userID.String()),
)

// BAD: самопальные имена — Grafana не покажет в стандартных view
span.SetAttributes(attribute.String("method", "POST"))
```

**Severity:** 🟡 MEDIUM

---

## Correlation IDs

### `request_id` (HTTP) and `trace_id` (OTel)

**Проблема:** При диагностике production-инцидента нужно соединить логи между сервисами. Один способ — OTel `trace_id`; другой — `request_id`, генерируемый на edge и пробрасываемый через headers.

**Pattern (HTTP middleware):**
```go
type ctxKey struct{ name string }
var requestIDKey = ctxKey{"request_id"}

func RequestIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        id := r.Header.Get("X-Request-ID")
        if id == "" {
            id = uuid.New().String()
        }
        ctx := context.WithValue(r.Context(), requestIDKey, id)
        w.Header().Set("X-Request-ID", id) // эхо в response
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

func RequestIDFromContext(ctx context.Context) string {
    if id, ok := ctx.Value(requestIDKey).(string); ok {
        return id
    }
    return ""
}
```

**Зачем оба:**
- `trace_id` — формальный из OTel, привязан к sample-rate (обычно 1–10% запросов трейсятся)
- `request_id` — всегда есть, идёт во все логи
- Когда инцидент происходит на нетрассируемом запросе, `request_id` остаётся единственным способом склеить путь по логам

**Pattern (zap + ctx):**
```go
func loggerFromContext(ctx context.Context, base *zap.Logger) *zap.Logger {
    fields := []zap.Field{}
    if rid := RequestIDFromContext(ctx); rid != "" {
        fields = append(fields, zap.String("request_id", rid))
    }
    sc := trace.SpanContextFromContext(ctx)
    if sc.IsValid() {
        fields = append(fields, zap.String("trace_id", sc.TraceID().String()))
    }
    return base.With(fields...)
}
```

### Cross-Service Forwarding

При вызове downstream-сервиса:
- HTTP: `req.Header.Set("X-Request-ID", id)` (или middleware с `otelhttp.NewTransport` для trace_id)
- gRPC: `metadata.AppendToOutgoingContext(ctx, "x-request-id", id)`
- Kafka: добавить header `{"x-request-id": id}` в каждое сообщение

**Severity:** 🟠 HIGH (без correlation IDs диагностика инцидентов в распределённой системе становится невыполнимой)
