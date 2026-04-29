# Database Migrations Reference

Управление эволюцией схемы БД через Go-инструменты: `goose`, `golang-migrate`. Принципы безопасной миграции под нагрузкой.

**See also:**
- `postgres.md` — driver selection, transactions

## Tool Selection

| Инструмент              | Сильные стороны                                                  | Когда выбирать                                          |
|-------------------------|------------------------------------------------------------------|---------------------------------------------------------|
| `pressly/goose`         | Go-API + CLI; поддержка Go-миграций (для сложных трансформаций); embed-friendly | Стандартный выбор для Go-проектов.                       |
| `golang-migrate/migrate` | CLI-first, поддержка многих БД (Postgres, MySQL, SQLite, etc.)   | Multi-DB проекты, нужен CLI без сборки кода.            |
| `atlas` (ariga.io/atlas) | Декларативные schema-as-code, diff-based                          | Большие схемы, хочется управлять схемой как кодом.       |
| `dbmate`                 | Простой CLI, минимум фич                                          | Очень маленькие проекты.                                 |

**Эвристика:** Большинство Go-сервисов идут на `goose` или `golang-migrate`. Принципы ниже применимы к обоим.

---

## File Naming

**Pattern:** `<NNNNNNN>_<short_description>.<up|down>.sql`

```
migrations/
├── 0000001_create_orders_table.up.sql
├── 0000001_create_orders_table.down.sql
├── 0000002_add_status_index.up.sql
├── 0000002_add_status_index.down.sql
├── 0000003_split_user_name_columns.up.sql
└── 0000003_split_user_name_columns.down.sql
```

**Правила:**
- Префикс — нумерация (с padding до 7 знаков) или timestamp (`20260101120000_...`). Timestamp лучше для команд: меньше merge-конфликтов
- Описание — `snake_case`, глагол в начале (`create`, `add`, `drop`, `rename`)
- Каждая миграция — две файла: `up` и `down`
- Goose поддерживает single-file format с `-- +goose Up` / `-- +goose Down` секциями — приемлемо

---

## Idempotent Migrations

**Проблема:** Если миграция падает на полпути и её перезапустить, она повторно выполняет уже сделанное и падает на дублирующемся `CREATE TABLE`. Идемпотентные команды решают это.

**Anti-pattern:**
```sql
-- BAD: упадёт при повторном запуске
CREATE TABLE orders (id UUID PRIMARY KEY);
CREATE INDEX idx_orders_status ON orders(status);
```

**Pattern:**
```sql
-- GOOD: идемпотентно
CREATE TABLE IF NOT EXISTS orders (id UUID PRIMARY KEY);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

-- Для добавления колонок:
ALTER TABLE orders ADD COLUMN IF NOT EXISTS notes TEXT;

-- Для дропов:
DROP INDEX IF EXISTS idx_orders_status;
DROP TABLE IF EXISTS orders_old;
```

**Когда не получится:**
- `ALTER TABLE ... DROP COLUMN x` — нет `IF EXISTS` для дропа колонки в Postgres до 14; используем `DO $$ ... $$` блоки для условности
- backfill-данных (`UPDATE`) сами по себе идемпотентны при правильной логике (`WHERE x IS NULL`)

**Severity:** 🟠 HIGH

---

## Rollback Strategy

### Always Write `down`

**Проблема:** Без `down`-миграции откат означает ручное восстановление БД из бэкапа — медленно и опасно.

**Правило:** **каждая** `up` имеет `down`, который возвращает схему к предыдущему состоянию.

**Pattern:**
```sql
-- 0000005_add_orders_currency.up.sql
ALTER TABLE orders ADD COLUMN currency VARCHAR(3) NOT NULL DEFAULT 'USD';

-- 0000005_add_orders_currency.down.sql
ALTER TABLE orders DROP COLUMN currency;
```

### When `down` Is Impossible

Иногда откат невозможен без потери данных:
- сплит колонки `name` → `first_name` + `last_name` (потеряли пробелы/среднее имя)
- удаление таблицы с данными
- агрессивный type-change с потерей точности

**Pattern для документирования:**
```sql
-- 0000010_split_user_name.down.sql
-- IRREVERSIBLE: this migration is data-destructive on rollback.
-- Reverting requires a backup restore. See ADR-XXXX.

SELECT 1; -- placeholder, чтобы файл не был пустым
```

Или упасть явно:
```sql
DO $$ BEGIN
    RAISE EXCEPTION 'Migration 0000010 is irreversible; restore from backup';
END $$;
```

**Severity:** 🟠 HIGH

---

## Backwards-Compatible Schema Changes (Expand-Contract)

### Two-Phase Migrations Under Load

**Проблема:** Сервис, развёрнутый в N репликах, обновляется rolling-update — некоторое время старая версия и новая работают одновременно. Миграция, ломающая контракт схемы, обрушит старую версию.

**Сценарий:** переименовать `users.name` → `users.full_name`.

**Anti-pattern (одношаговая миграция):**
```sql
-- BAD: старая версия после миграции упадёт на SELECT name FROM users
ALTER TABLE users RENAME COLUMN name TO full_name;
```

**Pattern (expand-contract):**

**Фаза 1 (expand) — деплой 1:**
```sql
-- 0000020_users_add_full_name.up.sql
ALTER TABLE users ADD COLUMN full_name VARCHAR(255);
UPDATE users SET full_name = name; -- backfill
-- триггер для синхронизации, если есть активные writes:
CREATE OR REPLACE FUNCTION sync_user_name() RETURNS trigger AS $$
BEGIN
    NEW.full_name := COALESCE(NEW.full_name, NEW.name);
    NEW.name := COALESCE(NEW.name, NEW.full_name);
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER users_sync_name BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION sync_user_name();
```

Теперь обе колонки `name` и `full_name` синхронизированы. Старый и новый код работают.

**Деплой 2:** код переписывается на использование `full_name`.

**Фаза 2 (contract) — деплой 3:**
```sql
-- 0000021_users_drop_name.up.sql
DROP TRIGGER users_sync_name ON users;
DROP FUNCTION sync_user_name();
ALTER TABLE users DROP COLUMN name;
```

**Принципы expand-contract:**
- **Add** новой структуры (колонка/таблица) — без удаления старой
- **Backfill** данных в новую структуру
- **Sync** записей через триггер или application-level (zero-downtime)
- **Migrate readers** — code читает из новой структуры
- **Migrate writers** — code пишет только в новую структуру
- **Drop** старой структуры — после того, как ни один код её не использует

**Severity:** 🔴 CRITICAL для production-сервисов с непрерывной нагрузкой

### Long-Running Migrations on Large Tables

**Проблема:** `ALTER TABLE ... ADD COLUMN c TEXT NOT NULL DEFAULT 'x'` на таблице 100M строк блокирует таблицу на минуты — outage.

**Pattern:**
```sql
-- Шаг 1: добавить nullable колонку — instant
ALTER TABLE orders ADD COLUMN currency VARCHAR(3);

-- Шаг 2: backfill батчами в отдельной миграции / job-е
UPDATE orders SET currency = 'USD' WHERE currency IS NULL AND id BETWEEN $1 AND $2;
-- (повторить для всех диапазонов; в Postgres 12+ можно использовать UPDATE ... LIMIT неприменимо,
--  использовать CTE с LIMIT или loop по id-ranges)

-- Шаг 3: добавить NOT NULL constraint — после backfill (instant в PG 11+)
ALTER TABLE orders ALTER COLUMN currency SET NOT NULL;

-- Шаг 4: добавить default для будущих INSERT (instant в PG 11+)
ALTER TABLE orders ALTER COLUMN currency SET DEFAULT 'USD';
```

**Индексы на больших таблицах:**
```sql
-- BAD: блокирует таблицу
CREATE INDEX idx_orders_status ON orders(status);

-- GOOD: CONCURRENTLY — без блокировки, может занять часы
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_status ON orders(status);
-- Замечание: CONCURRENTLY нельзя в транзакции; goose нужно настроить
-- через `-- +goose NO TRANSACTION` или `-- +goose StatementBegin`
```

**Severity:** 🔴 CRITICAL

---

## Goose-Specific Tips

### Disable Transaction for `CREATE INDEX CONCURRENTLY`

```sql
-- +goose NO TRANSACTION
-- +goose Up
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_status ON orders(status);

-- +goose Down
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_status;
```

### Embed Migrations into Binary

```go
import (
    "embed"
    "github.com/pressly/goose/v3"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func RunMigrations(db *sql.DB) error {
    goose.SetBaseFS(migrationsFS)
    if err := goose.SetDialect("postgres"); err != nil {
        return err
    }
    return goose.Up(db, "migrations")
}
```

**Преимущества:** миграции едут с бинарём, не зависят от файловой системы хост-машины. Применимо для CI или single-binary деплоев.

### Schema Versioning Table

`goose` создаёт `goose_db_version`, `golang-migrate` — `schema_migrations`. Никогда не редактировать вручную, кроме случая ручного восстановления после сбоя — и тогда документировать инцидент.

**Severity:** 💡 INFO

---

## Anti-patterns

### 1. Editing Applied Migrations

**Проблема:** Изменить `0000005_add_currency.up.sql` после того, как она применилась в prod → checksum не совпадёт, или (если без checksum) изменения не применятся в новых средах.

**Правило:** прикладные миграции — иммутабельны. Чтобы исправить ошибку, создать новую `0000006_fix_currency.up.sql`.

### 2. Mixing Schema and Data in One Migration

**Anti-pattern:**
```sql
-- BAD: schema + data в одном файле
CREATE TABLE permissions (...);
INSERT INTO permissions VALUES ('admin'), ('user'), ('guest');
```

**Pattern:** seed-данные — отдельный механизм (init scripts, separate seed-tool, application bootstrap). Миграции — только schema.

### 3. Long-Running `ALTER` Without `lock_timeout`

**Проблема:** Миграция захватывает `ACCESS EXCLUSIVE` lock и ждёт. Если таблица занята — миграция висит, блокируя всех.

**Pattern:**
```sql
SET lock_timeout = '5s'; -- быстро упасть, не блокировать прод
SET statement_timeout = '30s';
ALTER TABLE orders ADD COLUMN ...;
```

Если миграция падает по timeout — это сигнал, что нужен зап-зап-цепочка из maintenance window или expand-contract.

**Severity:** 🟠 HIGH
