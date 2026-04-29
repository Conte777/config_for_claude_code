# Go + HTTP Patterns Reference

Паттерны и anti-patterns для HTTP-серверов в Go.

**See also:**
- `patterns.md` — общие Go паттерны
- `clean-architecture.md` — DTO/Entity boundary, layout
- `validation.md` — request validation
- `observability.md` — logging, tracing, metrics

## Framework Selection

Go-экосистема предлагает несколько HTTP-фреймворков. Выбор влияет на стиль handler-ов, middleware-композицию и производительность.

| Фреймворк      | Сильные стороны                                  | Когда выбирать                                                    | Когда избегать                                              |
|----------------|--------------------------------------------------|-------------------------------------------------------------------|-------------------------------------------------------------|
| `net/http` + `http.ServeMux` (Go 1.22+) | Стандарт. Поддержка `{id}` и method-prefix-ов. Нулевые зависимости. | Простые сервисы, prototypes, embed-приложения. | Сложные middleware-цепочки, нужна валидация bind-аргументов. |
| `chi`          | Лёгкий router поверх `net/http`, идиоматичные middleware (стандартная сигнатура `func(http.Handler) http.Handler`), groups и sub-routers | Микросервисы со средней-большой routing-схемой, важна совместимость с `net/http` middleware-экосистемой. | Когда нужен built-in binding/validation.                    |
| `echo`         | Удобный binding (`c.Bind(&req)`), middleware-цепочка, group-роутинг, validator-интеграция | Сервисы с тяжёлой request/response-обработкой; команды, привыкшие к Spring-style API. | Хочется минимум абстракций.                                  |
| `gin`          | Похож на `echo`, очень популярен. JSON-binding, validator out of the box. | Тот же класс задач, что `echo`. Большое community + примеры. | Не любите глобальный context-объект.                         |
| `fiber`        | Поверх `fasthttp`, очень быстр; API в стиле Express | High-throughput сервисы, где разница в латентности критична. | Несовместим с `net/http` middleware. HTTP/2/HTTPS-нюансы.    |
| `fasthttp` напрямую | Максимальная производительность                  | Edge-сервисы, RPC-style endpoints, нагрузка > 50k RPS на инстанс. | Любая пользовательская/админ-API; экосистема ограничена.     |

**Эвристика:**
- 90% сервисов справится `chi` или `echo`
- `gin` ↔ `echo` — личное предпочтение; в команде придерживайтесь одного
- `fiber`/`fasthttp` — только когда профилирование подтверждает, что HTTP — bottleneck

---

## Middleware Composition

### Standard Order

**Проблема:** Порядок middleware важен. Recovery поверх authentication даст stack trace в response с user-данными; logging до tracing — без trace_id; rate limit после auth — DoS-уязвимость.

**Pattern (рекомендуемый порядок, снаружи внутрь):**
```go
r := chi.NewRouter()

// 1. Request ID — генерим/принимаем X-Request-ID, кладём в ctx
r.Use(requestid.Middleware)

// 2. Tracing — span со всем входящим запросом
r.Use(otelhttp.NewMiddleware("http-server"))

// 3. Logging — после tracing, чтобы trace_id попал в логи
r.Use(loggingMiddleware(logger))

// 4. Recovery — ДО auth, чтобы panic в auth не утопил процесс
r.Use(middleware.Recoverer)

// 5. Compression — gzip/brotli
r.Use(middleware.Compress(5))

// 6. CORS — для browser clients
r.Use(corsMiddleware)

// 7. Rate limit — общий для public API
r.Use(rateLimitMiddleware)

// 8. Authentication — здесь заканчивается публичная часть
r.Use(authMiddleware)

// 9. Authorization (per-route) — если нужно
```

**Severity:** 🟠 HIGH

### Custom Middleware Skeleton

```go
func loggingMiddleware(logger *zap.Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
            defer func() {
                logger.Info("http request",
                    zap.String("method", r.Method),
                    zap.String("path", r.URL.Path),
                    zap.Int("status", ww.Status()),
                    zap.Duration("duration", time.Since(start)),
                    zap.String("request_id", requestid.FromContext(r.Context())),
                )
            }()
            next.ServeHTTP(ww, r)
        })
    }
}
```

---

## Route Groups

### Per-Group Middleware Composition

**Проблема:** Без группировки роутов middleware-цепочка повторяется для каждого endpoint-а: 20 endpoint-ов → 20 раз указан `authMiddleware`.

**Pattern (chi):**
```go
r := chi.NewRouter()
r.Use(commonMiddleware...) // глобальные

// Public routes
r.Group(func(r chi.Router) {
    r.Get("/healthz", healthHandler)
    r.Post("/login", loginHandler)
})

// Authenticated routes
r.Group(func(r chi.Router) {
    r.Use(authMiddleware)

    r.Get("/api/v1/me", meHandler)

    // Admin sub-group: дополнительный middleware
    r.Group(func(r chi.Router) {
        r.Use(adminOnlyMiddleware)
        r.Get("/api/v1/admin/users", adminListUsers)
    })
})
```

**Pattern (echo):**
```go
e := echo.New()
e.Use(commonMiddleware...)

api := e.Group("/api/v1")
api.Use(authMiddleware)

api.GET("/me", meHandler)

admin := api.Group("/admin")
admin.Use(adminOnlyMiddleware)
admin.GET("/users", adminListUsers)
```

**Severity:** 🟡 MEDIUM

---

## Unified Error Response

### Single JSON Error Format

**Проблема:** Без единого формата ошибок клиенты не могут программно обработать ответы: одни endpoint-ы возвращают `{"error":"..."}`, другие `{"message":"..."}`, третьи — plain text от `http.Error`.

**Pattern:**
```go
type APIError struct {
    Code    string                 `json:"code"`              // машинно-читаемый код: "validation_failed", "order_not_found"
    Message string                 `json:"message"`           // человекочитаемое сообщение
    Details map[string]interface{} `json:"details,omitempty"` // контекст: field, retry_after, etc.
    TraceID string                 `json:"trace_id,omitempty"`
}

type APIErrorResponse struct {
    Error APIError `json:"error"`
}

func writeError(w http.ResponseWriter, r *http.Request, err error) {
    httpStatus, apiErr := mapError(err)
    apiErr.TraceID = trace.SpanContextFromContext(r.Context()).TraceID().String()

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(httpStatus)
    _ = json.NewEncoder(w).Encode(APIErrorResponse{Error: apiErr})
}

func mapError(err error) (int, APIError) {
    var ve *ValidationError
    var nfe *NotFoundError
    var ce *ConflictError

    switch {
    case errors.As(err, &ve):
        return http.StatusBadRequest, APIError{
            Code:    "validation_failed",
            Message: ve.Error(),
            Details: map[string]interface{}{"field": ve.Field},
        }
    case errors.As(err, &nfe):
        return http.StatusNotFound, APIError{
            Code:    "not_found",
            Message: nfe.Error(),
        }
    case errors.As(err, &ce):
        return http.StatusConflict, APIError{
            Code:    "conflict",
            Message: ce.Error(),
        }
    case errors.Is(err, context.DeadlineExceeded):
        return http.StatusGatewayTimeout, APIError{
            Code:    "timeout",
            Message: "request timed out",
        }
    default:
        return http.StatusInternalServerError, APIError{
            Code:    "internal_error",
            Message: "internal server error", // НЕ протекаем err.Error() наружу
        }
    }
}
```

**Правила:**
- ВСЕГДА один формат ошибок на сервис — клиенты пишут единый decoder
- `code` — стабильный машинно-читаемый идентификатор; `message` — может меняться, локализоваться
- НЕ выкидывать `err.Error()` для `Internal` — может содержать секреты, SQL-фрагменты, имена внутренних сервисов
- `details` для контекстной информации (имя поля, ID конфликтующей записи)
- `trace_id` помогает корреляции с логами
- HTTP-статусы маппятся из доменных ошибок одним местом — обычно функцией `mapError` или middleware-error-handler-ом

**Severity:** 🟠 HIGH

---

## Request Validation

### Bind + Validate at Handler Boundary

**Проблема:** Валидация в use case-е смешивает структурные проверки (поле обязательное, длина строки) с бизнес-правилами (баланс достаточен, статус ордера разрешает операцию). Use case загромождается тривиальными проверками; ошибки структурной валидации возвращаются с тем же типом, что бизнес-ошибки — клиенту сложно различать.

**Pattern:**
```go
type CreateOrderRequest struct {
    UserID   string  `json:"user_id"  validate:"required,uuid"`
    Amount   float64 `json:"amount"   validate:"required,gt=0"`
    Currency string  `json:"currency" validate:"required,len=3"`
}

func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
    var req CreateOrderRequest

    // 1. Bind: десериализуем body
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeError(w, r, &ValidationError{Field: "body", Msg: "malformed JSON"})
        return
    }

    // 2. Validate: структурная валидация по тегам
    if err := h.validator.Struct(req); err != nil {
        writeError(w, r, validationErrorFromTag(err))
        return
    }

    // 3. Use case получает уже валидный request, занимается ТОЛЬКО бизнесом
    resp, err := h.uc.CreateOrder(r.Context(), &req)
    if err != nil {
        writeError(w, r, err)
        return
    }

    writeJSON(w, http.StatusCreated, resp)
}
```

**Правила:**
- bind + validate — в handler-е, **до** вызова use case
- структурная валидация: `required`, `min`, `max`, `len`, `oneof`, `uuid`, `email` — на тегах
- бизнес-валидация: "баланс достаточен", "статус позволяет переход" — в use case
- ошибки валидации по полям — возвращаем как `ValidationError{Field: "amount", Msg: "must be > 0"}`
- query params bindится через `gorilla/schema`, `go-chi/render` или ручной парсинг
- (см. `validation.md` для детального устройства validator-а)

**Severity:** 🟠 HIGH

---

## Server Lifecycle

### Graceful Shutdown

**Проблема:** `srv.ListenAndServe()` без graceful shutdown оборвёт in-flight запросы при SIGTERM.

**Pattern:**
```go
func RegisterHTTPServer(lc fx.Lifecycle, h http.Handler, cfg *Config, logger *zap.Logger) {
    srv := &http.Server{
        Addr:              fmt.Sprintf(":%d", cfg.Port),
        Handler:           h,
        ReadHeaderTimeout: 5 * time.Second,
        ReadTimeout:       30 * time.Second,
        WriteTimeout:      30 * time.Second,
        IdleTimeout:       120 * time.Second,
    }

    lc.Append(fx.Hook{
        OnStart: func(_ context.Context) error {
            ln, err := net.Listen("tcp", srv.Addr)
            if err != nil {
                return fmt.Errorf("listen %s: %w", srv.Addr, err)
            }
            go func() {
                if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
                    logger.Error("http serve", zap.Error(err))
                }
            }()
            return nil
        },
        OnStop: func(ctx context.Context) error {
            return srv.Shutdown(ctx) // дожидается окончания in-flight, использует deadline ctx
        },
    })
}
```

**Замечания:**
- ВСЕГДА устанавливать `ReadHeaderTimeout` — иначе уязвимость Slowloris
- `Shutdown(ctx)` использует deadline — если ctx истёк, force-closе соединений
- HTTP/2 streams закрываются грациозно

**Severity:** 🟠 HIGH

---

## Request Body Reading

### Limit Body Size

**Проблема:** Без `MaxBytesReader` атакующий шлёт огромное тело, пока процесс не упадёт по OOM.

**Anti-pattern:**
```go
// BAD: безлимитное чтение body
body, _ := io.ReadAll(r.Body) // 10GB? Нет проблем — процесс умрёт.
```

**Pattern:**
```go
const maxBodySize = 1 << 20 // 1 MiB

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
    r.Body = http.MaxBytesReader(w, r.Body, maxBodySize)
    var req CreateRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        var maxErr *http.MaxBytesError
        if errors.As(err, &maxErr) {
            writeError(w, r, &ValidationError{Field: "body", Msg: "request too large"})
            return
        }
        // ...
    }
}
```

Часто полезнее middleware:
```go
func bodyLimitMiddleware(maxBytes int64) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
            next.ServeHTTP(w, r)
        })
    }
}
```

**Severity:** 🟠 HIGH (DoS защита)
