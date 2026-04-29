# Go + Postgres Patterns Reference

Паттерны и anti-patterns работы с Postgres из Go: выбор драйвера, транзакции, prepared statements, pool tuning.

**See also:**
- `patterns.md` — общие Go паттерны
- `clean-architecture.md` — repository layer
- `migrations.md` — schema evolution

## Driver / Library Selection

| Библиотека                                  | Уровень       | Сильные стороны                                                  | Когда выбирать                                                |
|---------------------------------------------|---------------|------------------------------------------------------------------|---------------------------------------------------------------|
| `database/sql` + `lib/pq`                   | низкий, стандарт | Стандартная библиотека. Простой API. `lib/pq` де-факто старый, но работает. | Переносимость на другие БД, минимум зависимостей.             |
| `database/sql` + `jackc/pgx/v5/stdlib`      | низкий-средний | Тот же `database/sql`-API, но pgx-драйвер быстрее `lib/pq` и активно поддерживается. | Хочется stdlib-API, но без mh `lib/pq` legacy.                |
| `jackc/pgx/v5` напрямую                     | средний-высокий | Собственный API; нативная поддержка Postgres-типов, batching, COPY, listen/notify, named params | Высоконагруженные сервисы, нужны Postgres-специфичные фичи.   |
| `jmoiron/sqlx`                              | низкий-средний | Поверх `database/sql`: `Get`/`Select` с struct-mapping через `db:"..."` теги, `NamedExecContext` | Стандартный CRUD без переписывания scanloop-ов.               |
| `sqlc`                                      | code-gen      | Генерирует Go-код из SQL-запросов. Type-safe, нет ручного маппинга. | Большие сервисы с сложными запросами, желание SQL-as-source-of-truth. |

**Эвристика:**
- Простой CRUD-сервис → `database/sql` (через `pgx/stdlib` драйвер) + `sqlx` для удобства маппинга
- Тяжёлые batch-операции, listen/notify, COPY → `pgx` напрямую
- Команда любит SQL-first → `sqlc`
- НЕ использовать ORM (`gorm`) — добавляет магии, скрывает SQL, тяжело оптимизировать; ORM — оправдан в редких случаях рапид-прототипирования

---

## Transactions

### `WithTx` Helper

**Проблема:** Ручной `BeginTx` + `defer Rollback` + `Commit` повторяется в каждом методе. Часто забывают rollback при early return → connection leak.

**Anti-pattern:**
```go
// BAD: ручное управление tx, легко забыть rollback
func (r *Repo) CreateOrder(ctx context.Context, o *Order) error {
    tx, err := r.db.BeginTxx(ctx, nil)
    if err != nil {
        return err
    }
    if _, err := tx.ExecContext(ctx, "INSERT ..."); err != nil {
        tx.Rollback() // забыть → leak
        return err
    }
    if _, err := tx.ExecContext(ctx, "INSERT items ..."); err != nil {
        // забыли rollback здесь → leak
        return err
    }
    return tx.Commit()
}
```

**Pattern:**
```go
// Helper, который сам делает rollback при ошибке/панике
func WithTx(ctx context.Context, db *sqlx.DB, fn func(tx *sqlx.Tx) error) (err error) {
    tx, err := db.BeginTxx(ctx, nil)
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer func() {
        if p := recover(); p != nil {
            _ = tx.Rollback()
            panic(p)
        }
        if err != nil {
            if rbErr := tx.Rollback(); rbErr != nil && !errors.Is(rbErr, sql.ErrTxDone) {
                err = fmt.Errorf("rollback after %w: %v", err, rbErr)
            }
            return
        }
        if commitErr := tx.Commit(); commitErr != nil {
            err = fmt.Errorf("commit: %w", commitErr)
        }
    }()
    return fn(tx)
}

// Использование
func (r *Repo) CreateOrder(ctx context.Context, o *Order) error {
    return WithTx(ctx, r.db, func(tx *sqlx.Tx) error {
        if _, err := tx.NamedExecContext(ctx, insertOrderSQL, o); err != nil {
            return fmt.Errorf("insert order: %w", err)
        }
        for _, item := range o.Items {
            if _, err := tx.NamedExecContext(ctx, insertItemSQL, item); err != nil {
                return fmt.Errorf("insert item: %w", err)
            }
        }
        return nil
    })
}
```

**Severity:** 🟠 HIGH

### Passing `Tx` Through `context.Context` (Optional)

**Проблема:** Когда use case делает несколько операций через разные репозитории, нужно, чтобы все они работали в одной транзакции. Передавать `*sqlx.Tx` в каждый метод — раздувает сигнатуры.

**Pattern (через ctx):**
```go
type txCtxKey struct{}

// DBTX — общий интерфейс над *sqlx.DB и *sqlx.Tx
type DBTX interface {
    GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error
    NamedExecContext(ctx context.Context, query string, arg interface{}) (sql.Result, error)
    // ...
}

func WithTxCtx(ctx context.Context, db *sqlx.DB, fn func(ctx context.Context) error) error {
    return WithTx(ctx, db, func(tx *sqlx.Tx) error {
        ctx := context.WithValue(ctx, txCtxKey{}, tx)
        return fn(ctx)
    })
}

func (r *Repo) executor(ctx context.Context) DBTX {
    if tx, ok := ctx.Value(txCtxKey{}).(*sqlx.Tx); ok {
        return tx
    }
    return r.db
}

func (r *Repo) Save(ctx context.Context, o *Order) error {
    _, err := r.executor(ctx).NamedExecContext(ctx, insertOrderSQL, o)
    return err
}

// Использование в use case-е
func (uc *UseCase) CreateOrderWithItems(ctx context.Context, o *Order) error {
    return WithTxCtx(ctx, uc.db, func(ctx context.Context) error {
        if err := uc.orderRepo.Save(ctx, o); err != nil {
            return err
        }
        return uc.itemRepo.SaveAll(ctx, o.Items)
    })
}
```

**Соображения:**
- паттерн "tx в ctx" удобен, но скрывает поведение — программисту неочевидно, что метод репозитория может работать в транзакции
- альтернатива — explicit `*sqlx.Tx` в сигнатуре (`SaveTx(ctx, tx, o)`); надёжнее, но многословнее
- выбор зависит от стиля команды; зафиксируйте один вариант на проект

**Severity:** 🟡 MEDIUM

---

## Prepared Statements & Batching

### Prepared Statements for Repeated Queries

**Проблема:** Каждый `db.QueryContext(ctx, sql, args...)` парсит SQL заново. Для горячих запросов это видимая нагрузка на planner.

**Pattern:**
```go
// pgx-style: prepared statement через connection
type Repo struct {
    pool *pgxpool.Pool
}

func (r *Repo) GetByID(ctx context.Context, id uuid.UUID) (*Order, error) {
    const queryName = "get_order_by_id"
    const sql = `SELECT id, status, amount FROM orders WHERE id = $1`

    var o Order
    err := r.pool.QueryRow(ctx, sql, id).Scan(&o.ID, &o.Status, &o.Amount)
    if err != nil {
        return nil, err
    }
    return &o, nil
}

// pgx prepares automatically; именованных stmt-ов в pgxpool нет, но пул кэширует.
// database/sql: r.db.PreparedContext(ctx, sql) — храните *sql.Stmt в Repo.
```

**Когда стоит:**
- запрос вызывается > 100 раз/секунду
- сложный план (joins на десятки таблиц)
- БД-инстанс под высокой CPU-нагрузкой и `pg_stat_statements` показывает плановое время сравнимым с execute time

В типичных случаях `pgx` сам кэширует prepared statements, специальных действий не нужно.

### pgx Batch

**Проблема:** Серия похожих запросов (insert N строк, update N записей) — N round-trip-ов. Можно слить в один batch.

**Pattern:**
```go
import "github.com/jackc/pgx/v5"

func (r *Repo) InsertOrders(ctx context.Context, orders []Order) error {
    batch := &pgx.Batch{}
    for _, o := range orders {
        batch.Queue(`INSERT INTO orders (id, status, amount) VALUES ($1, $2, $3)`,
            o.ID, o.Status, o.Amount)
    }

    br := r.pool.SendBatch(ctx, batch)
    defer br.Close()

    for range orders {
        if _, err := br.Exec(); err != nil {
            return fmt.Errorf("batch exec: %w", err)
        }
    }
    return nil
}

// Для очень больших объёмов (тысячи строк) — pgx.CopyFrom (Postgres COPY).
```

**Severity:** 🟡 MEDIUM

---

## Connection Pool Tuning

### Recommended Defaults

**Проблема:** Default-настройки пула часто не подходят: `MaxOpenConns=0` (`database/sql`) означает unlimited, что приводит к exhaustion на стороне Postgres (`max_connections`); `MaxIdleConns=2` — слишком мало, новые запросы постоянно открывают новые соединения.

**Pattern (`database/sql`):**
```go
db, _ := sql.Open("pgx", dsn)
db.SetMaxOpenConns(25)        // верхняя граница — должно быть < Postgres max_connections / число реплик
db.SetMaxIdleConns(10)        // держим N idle, чтобы не open/close на каждый запрос
db.SetConnMaxLifetime(30 * time.Minute) // регулярно ротируем (DNS-изменения, failover)
db.SetConnMaxIdleTime(5 * time.Minute)  // закрываем долго-idle (TCP keepalive проблемы)
```

**Pattern (`pgxpool`):**
```go
import "github.com/jackc/pgx/v5/pgxpool"

cfg, _ := pgxpool.ParseConfig(dsn)
cfg.MaxConns = 25
cfg.MinConns = 5
cfg.MaxConnLifetime = 30 * time.Minute
cfg.MaxConnIdleTime = 5 * time.Minute
cfg.HealthCheckPeriod = 1 * time.Minute // pool пингует idle соединения

pool, err := pgxpool.NewWithConfig(ctx, cfg)
```

**Эвристика для `MaxConns`:**
- `Postgres.max_connections` (обычно 100–200) делим на число одновременно работающих реплик сервиса плюс других сервисов с этой БД
- Например: Postgres `max_connections=200`, три сервиса по 4 реплики каждый → каждому сервису ~16 соединений на реплику
- Слишком высокий `MaxConns` → Postgres начинает swap-ить, латентность растёт

**Severity:** 🟠 HIGH (приводит к outage при росте нагрузки)

---

## Error Mapping

### Postgres Errors → Domain Errors

**Проблема:** Сырые `pgconn.PgError` или `*pq.Error` протекают наружу — handler-ы не могут различить "уникальный constraint" от "deadlock" от "syntax error".

**Pattern:**
```go
import "github.com/jackc/pgx/v5/pgconn"

func mapPgError(err error) error {
    if err == nil {
        return nil
    }
    if errors.Is(err, sql.ErrNoRows) || errors.Is(err, pgx.ErrNoRows) {
        return ErrNotFound
    }
    var pgErr *pgconn.PgError
    if errors.As(err, &pgErr) {
        switch pgErr.Code {
        case "23505": // unique_violation
            return &ConflictError{Resource: pgErr.ConstraintName, Reason: "unique violation"}
        case "23503": // foreign_key_violation
            return &ValidationError{Field: pgErr.ConstraintName, Msg: "foreign key violation"}
        case "40P01": // deadlock_detected
            return ErrDeadlock // обычно retryable
        case "40001": // serialization_failure
            return ErrSerialization // retryable
        case "57014": // query_canceled (statement_timeout)
            return ErrTimeout
        }
    }
    return err
}

// Использование
func (r *Repo) Create(ctx context.Context, o *Order) error {
    if _, err := r.db.NamedExecContext(ctx, insertSQL, o); err != nil {
        return mapPgError(err)
    }
    return nil
}
```

**Severity:** 🟡 MEDIUM

---

## Anti-patterns

### 1. Long-Running Transactions

**Проблема:** Транзакция, которая держит row-locks дольше нескольких секунд, блокирует другие запросы. Особенно критично при `SELECT FOR UPDATE`.

**Anti-pattern:**
```go
// BAD: внешний HTTP-вызов внутри транзакции
return WithTx(ctx, db, func(tx *sqlx.Tx) error {
    if _, err := tx.ExecContext(ctx, "UPDATE orders SET status='processing' WHERE id=$1", id); err != nil {
        return err
    }
    // 30 секунд ждём ответ от платёжного шлюза, всё это время держим lock
    if err := paymentGateway.Charge(ctx, amount); err != nil {
        return err
    }
    _, err := tx.ExecContext(ctx, "UPDATE orders SET status='paid' WHERE id=$1", id)
    return err
})
```

**Pattern:**
- Внутри транзакции — только БД-операции
- Внешние вызовы — снаружи
- Оптимистичная блокировка через `WHERE status='pending'` или version-column
- Saga-паттерн или транзакционный лог событий для координации

**Severity:** 🔴 CRITICAL

### 2. N+1 Queries

**Проблема:** Цикл из запросов в БД для связанных сущностей.

**Anti-pattern:**
```go
// BAD: N+1 — запрос на каждый order
orders, _ := r.db.SelectContext(ctx, &orders, "SELECT * FROM orders LIMIT 100")
for _, o := range orders {
    var items []Item
    r.db.SelectContext(ctx, &items, "SELECT * FROM items WHERE order_id = $1", o.ID)
    o.Items = items
}
```

**Pattern:**
```go
// GOOD: один запрос с JOIN или IN
orders, _ := r.db.SelectContext(ctx, &orders, "SELECT * FROM orders LIMIT 100")
ids := make([]uuid.UUID, len(orders))
for i, o := range orders {
    ids[i] = o.ID
}

query, args, _ := sqlx.In("SELECT * FROM items WHERE order_id IN (?)", ids)
query = r.db.Rebind(query)
var items []Item
r.db.SelectContext(ctx, &items, query, args...)

byOrder := groupByOrderID(items)
for i := range orders {
    orders[i].Items = byOrder[orders[i].ID]
}
```

**Severity:** 🟠 HIGH

### 3. Unclosed Rows

**Проблема:** `sql.Rows` без `defer rows.Close()` блокирует соединение в пуле — connection leak.

**Anti-pattern:**
```go
// BAD: rows не закрыты — connection возвращается в пул только по GC
rows, err := db.QueryContext(ctx, "SELECT id FROM orders")
if err != nil { return err }
for rows.Next() { /* ... */ }
// забыли rows.Close()
```

**Pattern:**
```go
rows, err := db.QueryContext(ctx, "SELECT id FROM orders")
if err != nil {
    return err
}
defer rows.Close()

for rows.Next() {
    var id uuid.UUID
    if err := rows.Scan(&id); err != nil {
        return err
    }
    // ...
}
return rows.Err()
```

При использовании `sqlx.Get`/`SelectContext` это обрабатывается автоматически; ошибка типична для ручных `Query`.

**Severity:** 🔴 CRITICAL

### 4. SQL Injection via Concatenation

**Anti-pattern:**
```go
// BAD: SQL injection
query := "SELECT * FROM users WHERE name = '" + userInput + "'"
db.QueryContext(ctx, query)
```

**Pattern:**
```go
// GOOD: параметризированный запрос
db.QueryContext(ctx, "SELECT * FROM users WHERE name = $1", userInput)
```

Для динамических `WHERE` — собирать параметризованные фрагменты, а не интерполировать значения. Для динамических идентификаторов (имя таблицы) — whitelist + `pq.QuoteIdentifier`.

**Severity:** 🔴 CRITICAL
