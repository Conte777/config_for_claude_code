# Go + Kafka Patterns Reference

Паттерны и anti-patterns для Kafka consumer/producer в Go.

**See also:**
- `patterns.md` — общие Go паттерны
- `uber-fx.md` — Uber FX lifecycle, DI

## Consumer Group Setup

### 1. Missing Graceful Shutdown

**Проблема:** Consumer без graceful shutdown теряет сообщения или получает rebalance timeout.

**Anti-pattern:**
```go
// BAD: No shutdown handling — messages lost on restart
func (c *Consumer) Run() {
    for {
        msg, err := c.reader.ReadMessage(context.Background())
        if err != nil {
            log.Fatal(err) // Kills process, no cleanup
        }
        c.process(msg)
    }
}
```

**Pattern:**
```go
// GOOD: Graceful shutdown via context
func (c *Consumer) Run(ctx context.Context) error {
    for {
        msg, err := c.reader.FetchMessage(ctx)
        if err != nil {
            if errors.Is(err, context.Canceled) {
                return nil // Graceful shutdown
            }
            return fmt.Errorf("fetch message: %w", err)
        }
        if err := c.process(ctx, msg); err != nil {
            c.logger.Error("process message failed", zap.Error(err))
            continue // Don't commit failed messages
        }
        if err := c.reader.CommitMessages(ctx, msg); err != nil {
            return fmt.Errorf("commit message: %w", err)
        }
    }
}

// FX lifecycle integration
func registerConsumer(lc fx.Lifecycle, c *Consumer) {
    var cancel context.CancelFunc
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            runCtx, fn := context.WithCancel(context.Background())
            cancel = fn
            go c.Run(runCtx)
            return nil
        },
        OnStop: func(ctx context.Context) error {
            cancel()
            return c.reader.Close()
        },
    })
}
```

**Severity:** 🟠 HIGH

### 2. Auto-Commit Without Processing Guarantee

**Проблема:** Auto-commit коммитит offset до завершения обработки — при crash сообщение потеряно.

**Anti-pattern:**
```go
// BAD: Auto-commit may lose messages
reader := kafka.NewReader(kafka.ReaderConfig{
    Brokers:        []string{"kafka:9092"},
    GroupID:        "my-group",
    Topic:          "events",
    CommitInterval: time.Second, // Auto-commits every second
})

msg, _ := reader.ReadMessage(ctx) // Offset committed automatically
process(msg) // If this crashes, message is lost
```

**Pattern:**
```go
// GOOD: Manual commit after successful processing
reader := kafka.NewReader(kafka.ReaderConfig{
    Brokers: []string{"kafka:9092"},
    GroupID: "my-group",
    Topic:   "events",
})

msg, err := reader.FetchMessage(ctx) // Does NOT commit
if err != nil {
    return err
}
if err := process(ctx, msg); err != nil {
    return err // Will re-read the same message
}
reader.CommitMessages(ctx, msg) // Explicit commit
```

**Severity:** 🟠 HIGH

## Consumer Error Handling

### 3. log.Fatal on Transient Errors

**Проблема:** `log.Fatal` на временных ошибках (network blip, rebalance) убивает сервис.

**Anti-pattern:**
```go
// BAD: Fatal on transient error
msg, err := reader.ReadMessage(ctx)
if err != nil {
    log.Fatalf("kafka read error: %v", err) // Kills process
}
```

**Pattern:**
```go
// GOOD: Retry with backoff, DLQ for poison messages
func (c *Consumer) processWithRetry(ctx context.Context, msg kafka.Message) error {
    var lastErr error
    for attempt := 0; attempt < c.maxRetries; attempt++ {
        if err := c.process(ctx, msg); err != nil {
            lastErr = err
            c.logger.Warn("process failed, retrying",
                zap.Int("attempt", attempt+1),
                zap.Error(err),
            )
            time.Sleep(c.backoff(attempt))
            continue
        }
        return nil
    }
    // Send to DLQ after max retries
    if err := c.sendToDLQ(ctx, msg, lastErr); err != nil {
        c.logger.Error("failed to send to DLQ", zap.Error(err))
    }
    return lastErr
}
```

**Severity:** 🟠 HIGH

### 4. Missing DLQ Strategy

**Проблема:** Без DLQ (Dead Letter Queue) "poison message" блокирует consumer бесконечно.

**Anti-pattern:**
```go
// BAD: Infinite retry on unprocessable message
for {
    msg, _ := reader.FetchMessage(ctx)
    for {
        if err := process(msg); err != nil {
            time.Sleep(time.Second) // Retry forever
            continue
        }
        break
    }
    reader.CommitMessages(ctx, msg)
}
```

**Pattern:**
```go
// GOOD: DLQ for unprocessable messages
func (c *Consumer) sendToDLQ(ctx context.Context, msg kafka.Message, processErr error) error {
    dlqMsg := kafka.Message{
        Topic: c.topic + ".dlq",
        Key:   msg.Key,
        Value: msg.Value,
        Headers: append(msg.Headers,
            kafka.Header{Key: "original-topic", Value: []byte(c.topic)},
            kafka.Header{Key: "error", Value: []byte(processErr.Error())},
            kafka.Header{Key: "failed-at", Value: []byte(time.Now().UTC().Format(time.RFC3339))},
        ),
    }
    return c.dlqWriter.WriteMessages(ctx, dlqMsg)
}
```

**Severity:** 🟠 HIGH

## Producer Patterns

### 5. Fire-and-Forget Without Error Check

**Проблема:** Игнорирование ошибки записи — сообщение молча теряется.

**Anti-pattern:**
```go
// BAD: Error ignored — message silently lost
writer.WriteMessages(ctx, kafka.Message{
    Key:   []byte(orderID),
    Value: data,
})
```

**Pattern:**
```go
// GOOD: Check write error
if err := writer.WriteMessages(ctx, kafka.Message{
    Key:   []byte(orderID),
    Value: data,
}); err != nil {
    return fmt.Errorf("kafka write order event: %w", err)
}
```

**Severity:** 🟠 HIGH

### 6. Missing Partition Key for Ordering

**Проблема:** Без partition key сообщения об одной сущности могут попасть в разные партиции — порядок не гарантирован.

**Anti-pattern:**
```go
// BAD: No key — round-robin partition assignment
writer.WriteMessages(ctx, kafka.Message{
    Value: data, // No key — order not guaranteed per entity
})
```

**Pattern:**
```go
// GOOD: Partition key ensures per-entity ordering
writer.WriteMessages(ctx, kafka.Message{
    Key:   []byte(orderID), // All events for this order go to same partition
    Value: data,
})
```

**Severity:** 🟡 MEDIUM

## Idempotency

### 7. Duplicate Processing on Rebalance

**Проблема:** При rebalance consumer group сообщения могут обработаться повторно.

**Anti-pattern:**
```go
// BAD: No deduplication — double processing on rebalance
func (c *Consumer) process(ctx context.Context, msg kafka.Message) error {
    var event OrderEvent
    json.Unmarshal(msg.Value, &event)
    return c.uc.CreateOrder(ctx, event.Order) // Duplicate order!
}
```

**Pattern:**
```go
// GOOD: Idempotency key check
func (c *Consumer) process(ctx context.Context, msg kafka.Message) error {
    var event OrderEvent
    if err := json.Unmarshal(msg.Value, &event); err != nil {
        return fmt.Errorf("unmarshal event: %w", err)
    }

    idempotencyKey := fmt.Sprintf("%s:%d:%d", msg.Topic, msg.Partition, msg.Offset)
    processed, err := c.dedup.IsProcessed(ctx, idempotencyKey)
    if err != nil {
        return fmt.Errorf("check idempotency: %w", err)
    }
    if processed {
        return nil // Already handled
    }

    if err := c.uc.CreateOrder(ctx, event.Order); err != nil {
        return err
    }

    return c.dedup.MarkProcessed(ctx, idempotencyKey, 24*time.Hour)
}
```

**Severity:** 🟠 HIGH

## Outbox Pattern

### 8. Dual Write Without Transactional Guarantee

**Проблема:** Запись в БД и Kafka не атомарна — при crash одно из двух может потеряться.

**Anti-pattern:**
```go
// BAD: Dual write — not atomic
func (uc *UseCase) CreateOrder(ctx context.Context, order *Order) error {
    if err := uc.repo.Save(ctx, order); err != nil {
        return err
    }
    // If crash here — order saved, event lost
    return uc.producer.Send(ctx, OrderCreatedEvent{OrderID: order.ID})
}
```

**Pattern:**
```go
// GOOD: Outbox pattern — write event to DB in same transaction
func (uc *UseCase) CreateOrder(ctx context.Context, order *Order) error {
    return uc.repo.WithTransaction(ctx, func(tx *sqlx.Tx) error {
        if err := uc.repo.SaveTx(ctx, tx, order); err != nil {
            return err
        }
        event := outbox.Event{
            AggregateID:   order.ID,
            AggregateType: "order",
            EventType:     "order.created",
            Payload:       toJSON(order),
        }
        return uc.outbox.StoreTx(ctx, tx, event)
    })
}

// Relay worker polls outbox table and sends to Kafka
// See shared/outbox package for implementation
```

**Severity:** 🟠 HIGH

## Serialization

### 9. Unversioned Message Format

**Проблема:** Без версии схемы невозможно эволюционировать формат без breaking changes.

**Anti-pattern:**
```go
// BAD: No version — can't evolve schema
type OrderEvent struct {
    OrderID string `json:"order_id"`
    Amount  float64 `json:"amount"`
}
data, _ := json.Marshal(event)
writer.WriteMessages(ctx, kafka.Message{Value: data})
```

**Pattern:**
```go
// GOOD: Envelope with version and type
type EventEnvelope struct {
    Type    string          `json:"type"`
    Version string          `json:"version"`
    Time    time.Time       `json:"time"`
    Payload json.RawMessage `json:"payload"`
}

func newEnvelope(eventType, version string, payload interface{}) ([]byte, error) {
    payloadBytes, err := json.Marshal(payload)
    if err != nil {
        return nil, err
    }
    return json.Marshal(EventEnvelope{
        Type:    eventType,
        Version: version,
        Time:    time.Now().UTC(),
        Payload: payloadBytes,
    })
}

// Usage
data, err := newEnvelope("order.created", "v1", orderEvent)
```

**Severity:** 🟡 MEDIUM

### 10. JSON When Protobuf Available

**Проблема:** JSON вместо Protobuf между внутренними сервисами — больше трафик, нет strict schema.

**Anti-pattern:**
```go
// BAD: JSON for internal service communication
data, _ := json.Marshal(event)
writer.WriteMessages(ctx, kafka.Message{Value: data})
```

**Pattern:**
```go
// GOOD: Protobuf for internal events
data, err := proto.Marshal(event)
if err != nil {
    return fmt.Errorf("marshal event: %w", err)
}
writer.WriteMessages(ctx, kafka.Message{
    Key:   []byte(event.OrderId),
    Value: data,
    Headers: []kafka.Header{
        {Key: "content-type", Value: []byte("application/protobuf")},
    },
})
```

**Severity:** 💡 INFO

## Consumer Registration

### 11. Consumer Handler Registration

**Проблема:** Ручная инициализация каждого consumer без единого паттерна регистрации — дублирование lifecycle кода.

**Anti-pattern:**
```go
// BAD: Manual consumer setup for each topic
func registerConsumers(lc fx.Lifecycle, cfg *Config, logger *zap.Logger) {
    // Copy-pasted for every consumer
    consumer1 := NewOrderConsumer(cfg, logger)
    var cancel1 context.CancelFunc
    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            runCtx, fn := context.WithCancel(context.Background())
            cancel1 = fn
            go consumer1.Run(runCtx)
            return nil
        },
        OnStop: func(ctx context.Context) error {
            cancel1()
            return consumer1.Close()
        },
    })
    // Repeat for consumer2, consumer3...
}
```

**Pattern:**
```go
// GOOD: Unified handler registration with concurrency control
type ConsumerRegistry struct {
    lc      fx.Lifecycle
    brokers []string
    logger  *zap.Logger
}

func (r *ConsumerRegistry) AddHandler(
    topic string,
    groupID string,
    handler func(ctx context.Context, msg kafka.Message) error,
    concurrency int,
) {
    reader := kafka.NewReader(kafka.ReaderConfig{
        Brokers: r.brokers,
        GroupID: groupID,
        Topic:   topic,
    })

    r.lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            runCtx, cancel := context.WithCancel(context.Background())
            for i := 0; i < concurrency; i++ {
                go func() {
                    for {
                        msg, err := reader.FetchMessage(runCtx)
                        if err != nil {
                            if errors.Is(err, context.Canceled) {
                                return
                            }
                            r.logger.Error("fetch message", zap.Error(err))
                            continue
                        }
                        if err := handler(runCtx, msg); err != nil {
                            r.logger.Error("handle message", zap.Error(err))
                            continue
                        }
                        reader.CommitMessages(runCtx, msg)
                    }
                }()
            }
            _ = cancel // stored for OnStop
            return nil
        },
    })
}

// Usage
registry.AddHandler("orders.created", "order-processor", orderHandler, 3)
registry.AddHandler("payments.completed", "payment-processor", paymentHandler, 1)
```

**Severity:** 🟡 MEDIUM

### 12.1 Handler Registry Pattern

**Проблема:** Когда сервис подписан на 5+ топиков, отдельный consumer для каждого топика — boilerplate (отдельный reader, цикл, lifecycle hook). Это не только дублирование кода, но и сложность диагностики: каждый consumer пишет логи в своей логике, нет единой точки фильтрации/трейсинга.

**Pattern:**
```go
// Handler — обработчик одного логического события
type Handler interface {
    Topic() string
    GroupID() string
    Handle(ctx context.Context, msg kafka.Message) error
}

// Registry собирает все handler-ы в один consumer-loop
type Registry struct {
    handlers []Handler
    brokers  []string
    logger   *zap.Logger
}

func (r *Registry) Register(h Handler) {
    r.handlers = append(r.handlers, h)
}

func (r *Registry) Run(ctx context.Context) error {
    var wg sync.WaitGroup
    for _, h := range r.handlers {
        wg.Add(1)
        go func(h Handler) {
            defer wg.Done()
            r.runHandler(ctx, h)
        }(h)
    }
    wg.Wait()
    return nil
}

func (r *Registry) runHandler(ctx context.Context, h Handler) {
    reader := kafka.NewReader(kafka.ReaderConfig{
        Brokers: r.brokers,
        GroupID: h.GroupID(),
        Topic:   h.Topic(),
    })
    defer reader.Close()

    for {
        msg, err := reader.FetchMessage(ctx)
        if err != nil {
            if errors.Is(err, context.Canceled) {
                return
            }
            r.logger.Error("fetch", zap.String("topic", h.Topic()), zap.Error(err))
            continue
        }
        if err := h.Handle(ctx, msg); err != nil {
            r.logger.Error("handle", zap.String("topic", h.Topic()), zap.Error(err))
            continue // не коммитим, переобработаем
        }
        if err := reader.CommitMessages(ctx, msg); err != nil {
            r.logger.Error("commit", zap.String("topic", h.Topic()), zap.Error(err))
        }
    }
}
```

```go
// Регистрация handler-ов в одной точке
func RegisterHandlers(reg *Registry, oh *OrderHandler, ph *PaymentHandler, uh *UserHandler) {
    reg.Register(oh)
    reg.Register(ph)
    reg.Register(uh)
}

// FX:
var Module = fx.Module("kafka",
    fx.Provide(NewRegistry),
    fx.Invoke(RegisterHandlers),
    fx.Invoke(func(lc fx.Lifecycle, reg *Registry) {
        var cancel context.CancelFunc
        lc.Append(fx.Hook{
            OnStart: func(_ context.Context) error {
                runCtx, fn := context.WithCancel(context.Background())
                cancel = fn
                go reg.Run(runCtx)
                return nil
            },
            OnStop: func(_ context.Context) error {
                cancel()
                return nil
            },
        })
    }),
)
```

**Преимущества:**
- единое место для cross-cutting concerns: tracing, metrics (`kafka_messages_processed_total{topic}`), DLQ-роутинг
- добавление нового топика — одна строка `reg.Register(newHandler)`, не новый lifecycle hook
- shutdown централизован — все consumer-ы реагируют на один `ctx.Done()`

**Severity:** 🟡 MEDIUM

### 12.2 Domain Event Listener (Thin Adapter)

**Проблема:** Когда Kafka-handler обрастает бизнес-логикой (валидация, обращение к БД, сторонние вызовы), он превращается в use case со специфичным транспортом. Тестировать его становится сложно — нужно поднимать Kafka, мокать producer-ов, etc. Use case же привязывается к kafka-формату сообщений и теряет переносимость на другие транспорты (HTTP, scheduled job).

**Anti-pattern:**
```go
// BAD: бизнес-логика в kafka-handler — нельзя дёрнуть из теста или другого транспорта
type OrderEventHandler struct {
    repo deps.OrderRepository
    bus  deps.EventBus
}

func (h *OrderEventHandler) Handle(ctx context.Context, msg kafka.Message) error {
    var event OrderCreatedEvent
    if err := json.Unmarshal(msg.Value, &event); err != nil { /* ... */ }
    // десятки строк бизнес-логики прямо тут
    order, err := h.repo.GetByID(ctx, event.OrderID)
    // ...
    if err := h.bus.Publish(ctx, NewEvent{}); err != nil { /* ... */ }
    return nil
}
```

**Pattern:**
```go
// GOOD: listener — тонкий адаптер. Бизнес-логика — в use case.
// internal/domain/order/delivery/kafka/listener.go
package kafka

import "project/internal/domain/order/usecase"

type OrderListener struct {
    uc *usecase.UseCase
}

func NewOrderListener(uc *usecase.UseCase) *OrderListener {
    return &OrderListener{uc: uc}
}

func (l *OrderListener) Topic() string  { return "orders.created" }
func (l *OrderListener) GroupID() string { return "order-processor" }

func (l *OrderListener) Handle(ctx context.Context, msg kafka.Message) error {
    var event OrderCreatedEvent
    if err := json.Unmarshal(msg.Value, &event); err != nil {
        return fmt.Errorf("unmarshal: %w", err)
    }
    // делегируем — никакой бизнес-логики в listener-е
    return l.uc.HandleOrderCreated(ctx, event.ToDomain())
}
```

**Правила:**
- listener живёт в `delivery/kafka/` (не в `infrastructure/kafka/`)
- задача listener-а: десериализовать → валидировать формат → конвертировать в domain-тип → вызвать use case
- НЕ обращается напрямую к репозиторию, БД, другим внешним сервисам
- use case обрабатывает событие так же, как обработал бы вызов от HTTP-handler-а или планировщика
- инфраструктурный consumer (registry, reader, lifecycle) — отдельная сущность в `infrastructure/kafka/`

**Severity:** 🟡 MEDIUM

### 12.3 Outbox Variants: App-side Polling vs CDC

**Проблема:** Section 8 описала classic outbox: приложение пишет в `outbox`-таблицу в той же транзакции, фоновый воркер опрашивает её и публикует в Kafka. Это работает, но имеет недостатки: лишние SELECT-нагрузки на БД, latency = poll-interval, дополнительный код для воркера. В крупных проектах часто заменяют app-side polling на **Change Data Capture** через Debezium/Kafka Connect — он читает WAL/binlog Postgres/MySQL и публикует изменения сразу.

**Сравнение вариантов:**

| Аспект                     | App-side polling          | CDC (Debezium)                                |
|----------------------------|---------------------------|-----------------------------------------------|
| Сколько кода писать        | Воркер + транзакция в outbox | Конфиг Debezium-коннектора + обработчик в consumer-е |
| Latency                    | poll interval (1–5s типично) | sub-second (читает WAL realtime)             |
| Инфраструктура             | ничего сверху Postgres       | Kafka Connect + Debezium                     |
| Семантика гарантий         | "at least once" с явным offset в `outbox.published_at` | "at least once", offset хранит Debezium      |
| Эволюция схемы событий     | Полный контроль формата events.json | Формат привязан к таблице — нужны view-таблицы или transforms |
| Отказоустойчивость         | Простое: воркер падает → restart, polling продолжает | Сложнее: нужен мониторинг Debezium-кластера   |

**Когда app-side polling:**
- небольшой/средний сервис, нет инфраструктуры Kafka Connect
- нужен полный контроль над форматом event-ов (custom envelope, version, etc.)
- допустима latency 1–5 секунд

**Когда CDC:**
- уже есть Kafka Connect / Debezium в инфраструктуре
- критична низкая latency (sub-second)
- много таблиц/событий, дублировать outbox-механику в каждом сервисе накладно
- готовы инвестировать в мониторинг и schema-registry

**Pattern (CDC consumer):**
```go
// CDC-сообщения от Debezium имеют envelope: {before, after, op, source, ts_ms}
type DebeziumEnvelope struct {
    Before json.RawMessage `json:"before"`
    After  json.RawMessage `json:"after"`
    Op     string          `json:"op"` // "c", "u", "d", "r"
    Source struct {
        Table string `json:"table"`
        TsMs  int64  `json:"ts_ms"`
    } `json:"source"`
}

func (h *OrderCDCListener) Handle(ctx context.Context, msg kafka.Message) error {
    var env DebeziumEnvelope
    if err := json.Unmarshal(msg.Value, &env); err != nil {
        return fmt.Errorf("unmarshal envelope: %w", err)
    }
    if env.Op != "c" { // нас интересуют только инсерты
        return nil
    }
    var order entities.Order
    if err := json.Unmarshal(env.After, &order); err != nil {
        return fmt.Errorf("unmarshal order: %w", err)
    }
    return h.uc.HandleOrderCreated(ctx, &order)
}
```

**Замечания:**
- идемпотентность всё равно нужна: Debezium тоже даёт "at least once"
- топики Debezium именуются `<server>.<schema>.<table>` — нужно учитывать в consumer group naming
- НЕ публиковать раздел между app-side outbox и CDC одновременно для одной таблицы — два источника событий на один поток

**Severity:** 🟡 MEDIUM (архитектурный выбор)

### 13. Producer with OTel Tracing

**Проблема:** Producer без трейсинга — trace context теряется между сервисами, distributed tracing разрывается.

**Anti-pattern:**
```go
// BAD: No tracing — trace context lost between services
func (p *Producer) SendEvent(ctx context.Context, topic string, event *OrderEvent) error {
    data, err := json.Marshal(event)
    if err != nil {
        return fmt.Errorf("marshal event: %w", err)
    }
    return p.writer.WriteMessages(ctx, kafka.Message{
        Topic: topic,
        Key:   []byte(event.OrderID),
        Value: data,
        // No trace headers — downstream consumer starts new trace
    })
}
```

**Pattern:**
```go
// GOOD: OTel span + trace propagation via kafka headers
func (p *Producer) SendEvent(ctx context.Context, topic string, event *OrderEvent) error {
    ctx, span := p.tracer.Start(ctx, "kafka.produce",
        trace.WithAttributes(
            attribute.String("messaging.system", "kafka"),
            attribute.String("messaging.destination", topic),
            attribute.String("messaging.message.key", event.OrderID),
        ),
    )
    defer span.End()

    data, err := json.Marshal(event)
    if err != nil {
        span.RecordError(err)
        return fmt.Errorf("marshal event: %w", err)
    }

    // Inject trace context into kafka headers
    headers := make([]kafka.Header, 0)
    propagator := otel.GetTextMapPropagator()
    carrier := &KafkaHeaderCarrier{headers: &headers}
    propagator.Inject(ctx, carrier)

    return p.writer.WriteMessages(ctx, kafka.Message{
        Topic:   topic,
        Key:     []byte(event.OrderID),
        Value:   data,
        Headers: headers,
    })
}

// KafkaHeaderCarrier implements propagation.TextMapCarrier
type KafkaHeaderCarrier struct {
    headers *[]kafka.Header
}

func (c *KafkaHeaderCarrier) Set(key, val string) {
    *c.headers = append(*c.headers, kafka.Header{Key: key, Value: []byte(val)})
}

func (c *KafkaHeaderCarrier) Get(key string) string {
    for _, h := range *c.headers {
        if h.Key == key {
            return string(h.Value)
        }
    }
    return ""
}

func (c *KafkaHeaderCarrier) Keys() []string {
    keys := make([]string, len(*c.headers))
    for i, h := range *c.headers {
        keys[i] = h.Key
    }
    return keys
}
```

**Severity:** 🟡 MEDIUM
