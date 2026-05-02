# Go Microservice Template (DDD + FX + gRPC + Kafka)

Высокоуровневый шаблон типичного Go-микросервиса: дерево каталогов,
порядок FX-композиции, разбиение домена по слоям и базовые side-modules
(outbox, workers, kafka consumers). Документ — собирательный baseline,
универсальный по отношению к выбору библиотек.

## Когда использовать

Применяйте этот шаблон, когда планируете или создаёте новый Go-сервис
с DI на Uber FX, gRPC как первичным транспортом, PostgreSQL как
основным хранилищем и Kafka как шиной асинхронных событий. Для
правил отдельных слоёв и технологий читайте соответствующие файлы:

- `clean-architecture.md` — entities / DTO / deps / repository / usecase / delivery / workers / domain errors / pagination.
- `uber-fx.md` — lifecycle hooks, `fx.Provide`/`fx.Invoke`, `fx.As`, shutdown ordering, тестирование графа.
- `grpc.md` — server lifecycle, error mapping, interceptors, proto ↔ entity mapping.
- `kafka.md` — listener pattern, handler registry, idempotency, transactional event log, DLQ.
- `postgres.md` — pgx/sqlx, транзакции (`WithTx`), `SELECT … FOR UPDATE SKIP LOCKED`, error mapping.
- `observability.md` — zap, Prometheus, OpenTelemetry.
- `migrations.md` — naming, expand-contract, idempotent migrations.
- `validation.md` — `validate`-теги, чистый `Validate()`, defaults через `ApplyDefaults()`.

Шаблон **не** покрывает HTTP API / fasthttp / swagger / реверс-прокси —
для них применяется отдельная спецификация.

---

## Top-level layout

```
cmd/
└── app/
    └── main.go              # signal handling + fx.New(app.CreateApp())
config/
└── config.go                # service config (struct + envPrefix tags + Validate)
internal/
├── app/
│   └── app.go               # CreateApp(): композиция всех fx.Module
├── entity/                  # cross-domain entity types (НЕ внутри domain/)
├── domain/
│   ├── fx.go                # ОДНА плоская fx.Module("domain", ...) на сервис
│   ├── <aggregate>/
│   │   ├── deps/            # interface contracts (репозитории + клиенты внешних сервисов)
│   │   ├── delivery/
│   │   │   ├── grpc/        # primary delivery: handlers + convertX (proto↔entity)
│   │   │   └── kafka/       # consumers для входящих async-событий
│   │   ├── repository/
│   │   │   ├── postgres/    # реализация на DB-коннекторе с ambient-tx
│   │   │   └── redis/       # опциональный кэш
│   │   ├── usecase/         # business-логика
│   │   └── outbox/<topic>/  # опциональные per-topic publishers
│   ├── outbox/fx.go         # side-module: outbox dispatcher
│   └── worker/fx.go         # side-module: domain-level workers
└── infrastructure/
    ├── grpc/
    │   ├── server/          # gRPC server bootstrap + interceptors
    │   └── clients/<svc>/   # per-upstream gRPC client + fx.go
    ├── kafka/
    │   ├── consumer/        # Kafka consumer bootstrap
    │   └── producer/        # Kafka producer bootstrap
    ├── worker/              # infra-level workers (singular — без `s`)
    └── outbox/              # outbox dispatcher infra (если домен пустой)
pkg/                         # service-local utilities (errors, ctxutil, mapfn, ...)
migrations/                  # SQL миграции, Flyway-style: V<N>__<desc>.sql
```

Ключевые правила формы:

- `internal/entity/` живёт на internal-уровне, **не** внутри `domain/<name>/`.
- В сервисе **одна плоская `internal/domain/fx.go`** — один `fx.Module("domain", ...)` со всеми `fx.Provide` для use case-ов и репозиториев. Per-aggregate `fx.go` не создаём.
- gRPC-клиенты внешних сервисов лежат в `internal/infrastructure/grpc/clients/<svc>/`, **не** в `repository/http_clients/`.
- HTTP-клиенты допустимы только для third-party vendor (Postmark, биржи, …) и кладутся в `repository/http_clients/<vendor>/`.
- Worker-каталог singular: `worker/`, не `workers/`.
- Side-modules (outbox, worker, audit, email, …) — siblings of `domain.Module` в композиции `app.CreateApp`.

---

## Domain aggregate layout

`internal/domain/<aggregate>/` содержит один связный фрагмент бизнес-логики:

| Папка | Назначение |
|-------|------------|
| `deps/` | interface contracts — репозитории, кэш, порты внешних сервисов; `context.Context` первым аргументом. |
| `delivery/grpc/` | primary delivery: handlers + `convertX` (proto ↔ entity); `validateAll()` на входе; `mapError(err) → status.Error(codes.*)` на выходе. |
| `delivery/kafka/` | consumers входящих async-событий; идемпотентность по `event_id` или ключу агрегата (см. `kafka.md → Idempotency`). |
| `repository/postgres/` | реализация интерфейсов из `deps/` поверх DB-коннектора с поддержкой ambient-tx (`db.Do(ctx)` / `db.WithTx(ctx, fn)`). |
| `repository/redis/` | опциональный кэш (`Get`, `Set`, `Invalidate`). |
| `usecase/` | бизнес-логика; инжектится `Logger`; `decimal.Decimal` для денежных полей; возвращает DTO, не entity. |
| `outbox/<topic>/` | опционально: per-topic publishers, если домен эмитит внешние события. |

Маппинг entity ↔ DTO — внутри use case (`mapping.go` рядом). Маппинг proto ↔ DTO — в `delivery/grpc/` (см. `grpc.md → Proto ↔ Domain Mapping`). Подробные правила слоёв — `clean-architecture.md`.

---

## FX composition (canonical order)

`internal/app/app.go::CreateApp` собирает FX-граф в фиксированном порядке.
Регистрация = старт сверху вниз, shutdown — LIFO снизу вверх (см. `uber-fx.md → Shutdown Ordering`).

```go
func CreateApp() fx.Option {
    return fx.Options(
        // 1. observability — стартует первой, останавливается последней
        LoggerModule,
        TracerModule,
        MeterModule,

        // 2. infrastructure-клиенты (DB / Redis)
        PostgresModule,
        RedisModule,

        // 3. внешние gRPC-клиенты
        infrastructure.GRPCClientsModule,

        // 4. бизнес-домен — одна плоская fx.Module
        domain.Module,

        // 5. side-modules (outbox, workers, audit, email, …)
        outbox.Module,
        worker.Module,

        // 6. inbound transports
        infrastructure.KafkaConsumerModule,
        infrastructure.GRPCServerModule,

        // 7. healthcheck — последним вверх, первым в not-ready
        HealthCheckModule,
        ReadinessProbe,

        fx.Provide(config.Out, context.Background),
    )
}
```

Канонический start-порядок: **observability → DB/Redis → external gRPC clients → domain → side-modules → kafka consumer → gRPC server → healthcheck**. Shutdown — обратный.

`cmd/app/main.go` остаётся минимальным — `fx.New(...).Run()` сам слушает SIGINT/SIGTERM:

```go
func main() {
    fx.New(
        app.CreateApp(),
        fx.StartTimeout(30*time.Second),
        fx.StopTimeout(30*time.Second),
    ).Run()
}
```

Граф валидируется тестом — `internal/app/app_test.go`:

```go
func Test__CreateApp(t *testing.T) {
    require.NoError(t, fx.ValidateApp(CreateApp()))
}
```

Запуск: `go test -run Test__CreateApp ./internal/app`.

---

## Конфигурация

`config/config.go` — единый struct, поля собираются через `envPrefix` и валидируются `validate`-тегами. Defaults — отдельный `ApplyDefaults()` (см. `validation.md → Pure Validate()`); `Validate()` остаётся чистым.

```go
type Config struct {
    Postgres PostgresConfig `envPrefix:"POSTGRES_"`
    Redis    RedisConfig    `envPrefix:"REDIS_"`
    Kafka    KafkaConfig    `envPrefix:"KAFKA_"`
    GRPC     GRPCConfig     `envPrefix:"GRPC_"`
    Outbox   OutboxConfig   `envPrefix:"OUTBOX_"`
}

type PostgresConfig struct {
    DSN          string        `env:"DSN"          validate:"required"`
    MaxOpenConns int           `env:"MAX_OPEN"     validate:"min=1"`
    QueryTimeout time.Duration `env:"QUERY_TIMEOUT"`
}

type Result struct {
    fx.Out

    Postgres PostgresConfig
    Redis    RedisConfig
    Kafka    KafkaConfig
    GRPC     GRPCConfig
    Outbox   OutboxConfig
}

func Out(cfg Config) Result { return Result{Postgres: cfg.Postgres, /* ... */ } }
```

Подключение в FX через `fx.Provide(config.Out)` — каждый модуль принимает только свой sub-config (см. `uber-fx.md → Config Decomposition`).

---

## Outbox pattern

Применяется для **at-least-once** доставки доменных событий в Kafka без распределённой транзакции: запись в outbox-таблицу выполняется внутри той же `db.WithTx`, что и бизнес-изменение, а отдельный dispatcher читает таблицу и публикует сообщения в Kafka.

Layout:

```
internal/domain/<aggregate>/outbox/<topic>/   # per-topic publishers (Send/SendBatch)
internal/domain/outbox/fx.go                  # side-module: dispatcher (relay → Kafka)
internal/infrastructure/outbox/               # альтернативно — если outbox чисто-инфраструктурный
```

Use case пишет событие в той же транзакции, что и бизнес-данные:

```go
func (uc *UseCase) CreateOrder(ctx context.Context, req *dto.CreateOrderRequest) error {
    return uc.db.WithTx(ctx, func(tx Tx) error {
        if err := uc.repo.Create(tx, order); err != nil {
            return err
        }
        return uc.outboxOrders.Send(tx, OrderCreatedEvent{ID: order.ID, ...})
    })
}
```

Dispatcher запускается через `fx.Lifecycle` в side-module `outbox.Module`:
читает «несозревшие» строки → публикует в Kafka → помечает как отправленные. Идемпотентность достигается на стороне consumer-а по `event_id` — детали в `kafka.md → Transactional Event Log`.

---

## Background workers (claim-pattern)

Domain-level workers — side-module `internal/domain/worker/fx.go`. Infra-level workers (общие, не привязанные к агрегату) — `internal/infrastructure/worker/`. Каталог **singular**: `worker/`.

Канонический pattern для multi-instance-friendly job-runner-а — claim-row через `SELECT … FOR UPDATE SKIP LOCKED` + lease с TTL (см. `postgres.md → Anti-patterns → N+1 Queries` и пример с `SKIP LOCKED` в реальной кодовой базе):

```go
func (w *Worker) tick(ctx context.Context) error {
    return w.db.WithTx(ctx, func(tx Tx) error {
        rows, err := tx.QueryxContext(ctx, `
            UPDATE jobs
               SET locked_until = NOW() + INTERVAL '30 seconds'
             WHERE id = (
                 SELECT id FROM jobs
                  WHERE locked_until < NOW() AND status = 'pending'
                  ORDER BY created_at
                  LIMIT 1
                  FOR UPDATE SKIP LOCKED
             )
         RETURNING id, payload
        `)
        // ... обработать и закрыть job
        return err
    })
}
```

Lifecycle: регистрируется через `fx.Lifecycle` (`OnStart` запускает goroutine с тикером, `OnStop` отменяет shared `context.Context` и ждёт завершение текущего tick-а — см. `uber-fx.md → Lifecycle Hooks`).

---

## Kafka consumers (delivery)

Handlers входящих событий лежат в `internal/domain/<aggregate>/delivery/kafka/`. Каждый handler — тонкий адаптер: декодирует payload, валидирует, вызывает use case, мапит ошибки на retry/DLQ-решение (см. `kafka.md → Listener Pattern, Handler Registry`).

Регистрация на consumer выполняется **поздним `fx.Invoke`** — после того, как сам consumer и все handler-ы созданы:

```go
fx.Invoke(func(c kafka.Consumer, h orderkafka.Handler) error {
    return c.Register("orders.events", h.Handle)
})
```

Идемпотентность обязательна: ключ — `event_id` или составной ключ агрегата + версии (см. `kafka.md → Idempotency`). DLQ-стратегия и обработка transient errors — `kafka.md → Consumer Error Handling`.

---

## Категории shared-инфраструктуры

Сервис обычно полагается на набор переиспользуемых FX-модулей. Конкретные имена пакетов варьируются; важна **роль**:

| Роль | Что предоставляет |
|------|-------------------|
| DB connector | пул, ambient-tx (`Do(ctx)`, `WithTx(ctx, fn)`), интерфейс `DB` для репозиториев |
| Logger | structured logging (zap-style) с контекстными полями |
| Tracer | OpenTelemetry traces для gRPC / Kafka / DB |
| Meter | Prometheus метрики (counters, histograms) |
| Healthcheck | `/healthz`, `/readyz` пробы; readiness тогглится на shutdown первым |
| Configurator | YAML/ENV config + `Validate()` |
| Outbox SDK | `Send` (write inside tx), `StartProcessMessages` (relay → Kafka) |
| Pagination | filter / sort / limit с whitelist columns + operators |
| Cache | in-memory cache (`Cache`, `SnapshotCache`, `DeadlineCache`) |

Реализации этих модулей **не переписываются локально** — сервис подключает готовые `fx.Module` и инжектит их интерфейсы.

---

## Conventions cheat-sheet

- `internal/entity/`, **не** `internal/domain/entity/`.
- `config/` лежит на корневом уровне сервиса — **не** `internal/config/`.
- Одна плоская `internal/domain/fx.go` на сервис; per-aggregate `fx.go` не создаём.
- Worker-каталог singular: `worker/`.
- Репозитории принимают DB-интерфейс с ambient-tx (`Do(ctx)` / `WithTx(ctx, fn)`), а не `*sqlx.DB` / `*pgxpool.Pool` напрямую — иначе нельзя писать в outbox внутри той же транзакции, что и бизнес-данные.
- gRPC server создаётся в `OnStart`; `pb.RegisterXServiceServer(server, handler)` вызывается inline там же, не отдельным `fx.Invoke` (см. `grpc.md → Stateful Server`).
- Inter-service clients = gRPC; лежат в `internal/infrastructure/grpc/clients/<svc>/`.
- HTTP-клиенты только для third-party vendor → `repository/http_clients/<vendor>/`.
- Typed domain errors (`ValidationError`, `NotFoundError`, `ConflictError`, …) → gRPC `status.Error(codes.*)` через mapper в delivery; в use case proto-типы запрещены.
- Миграции — Flyway-style вне бинарника: `migrations/V<N>__<desc>.sql`.
- Module name — kebab-case (`order-service`, `payment-service`).
- `Validate()` чистый, без мутаций; defaults — отдельный `ApplyDefaults()`.
- `time.Time` для дат, `decimal.Decimal` для денежных полей; `string` для денег запрещён.
- entity не содержит `validate:"…"`-тегов; DTO не содержит `db:"…"`-тегов.
- Граф FX валидируется в CI: `go test -run Test__CreateApp ./internal/app`.

---

## Опциональные расширения

HTTP API на fasthttp, swagger-документация, reverse-proxy / API-gateway, REST-surface для внешних клиентов — за пределами этого шаблона; для них применяется отдельная gateway-спецификация.
