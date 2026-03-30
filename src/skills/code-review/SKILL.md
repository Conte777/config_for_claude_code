---
name: code-review
description: This skill should be used when the user asks to "провести ревью", "проверить код", "найти проблемы в коде", "code review", "найти баги", "проверить на ошибки", "analyze code quality", "ревью PR", "review pull request", or needs guidance on concurrency issues, security vulnerabilities, or language-specific code quality for Go, Java, Python.
allowed-tools: Bash, Read, Grep, Glob, LSP, WebFetch, WebSearch, mcp__context7__resolve-library-id, mcp__context7__query-docs
---

# Code Review Skill

Скил для проведения code review с поддержкой Go, Java, Python и их популярных фреймворков.

## Overview

Этот скил предоставляет структурированный подход к code review с фокусом на:
- **Security** — уязвимости, утечки секретов, инъекции
- **Concurrency** — race conditions, deadlocks, утечки goroutine/потоков
- **Performance** — сложность алгоритмов, memory leaks, N+1 queries
- **Best Practices** — идиоматичный код, обработка ошибок, тестируемость

## Review Process

### Step 1: Detect Language & Frameworks

Определи язык и фреймворки по расширениям файлов и импортам:

| Индикатор | Язык/Фреймворк |
|-----------|----------------|
| `.go`, `go.mod` | Go |
| `fx.New`, `fx.Module` | Go + Uber FX |
| `.java`, `pom.xml`, `build.gradle` | Java |
| `@SpringBootApplication`, `@RestController` | Java + Spring |
| `.py`, `requirements.txt`, `pyproject.toml` | Python |
| `FastAPI`, `@app.get` | Python + FastAPI |
| `google.golang.org/grpc` | Go + gRPC |
| `segmentio/kafka-go`, `kafkaconnector` | Go + Kafka |
| `go-redis/redis`, `redisconnector` | Go + Redis |

### Step 2: Apply Checks

Загрузи соответствующие reference файлы и примени проверки:

1. **Всегда:** `../coding-rules/references/common.md` — security, race conditions, performance
2. **По языку:**
   - Go: `../coding-rules/references/golang/patterns.md`
   - Go + FX: `../coding-rules/references/golang/uber-fx.md`
   - Go (архитектура): `../coding-rules/references/golang/clean-architecture.md`
   - Java: `../coding-rules/references/java/patterns.md`
   - Java + Spring: `../coding-rules/references/java/spring.md`
   - Python: `../coding-rules/references/python/patterns.md`
   - Python + FastAPI: `../coding-rules/references/python/fastapi.md`
   - Go + gRPC: `../coding-rules/references/golang/grpc.md`
   - Go + Kafka: `../coding-rules/references/golang/kafka.md`
   - Go + Redis: `../coding-rules/references/golang/redis.md`

### Step 3: Generate Report

Сформируй отчёт на русском языке по шаблону из `examples/review-report-template.md`.

## Severity Levels

| Уровень | Emoji | Критерии | Действие |
|---------|-------|----------|----------|
| CRITICAL | 🔴 | Security vulnerability, data loss, production crash | Требует немедленного исправления |
| HIGH | 🟠 | Race condition, resource leak, significant bug, blocking in async | Исправить до merge |
| LOW | 🔵 | Performance issue, code smell, minor improvement | По возможности |

## Common Checks Quick Reference

### Security Checks
| Проверка | Описание |
|----------|----------|
| Input Validation | Валидация пользовательского ввода |
| SQL Injection | Параметризованные запросы vs конкатенация |
| Secret Exposure | Секреты в коде, логах, ошибках |
| Path Traversal | Проверка путей к файлам |

### Concurrency Checks
| Проверка | Описание |
|----------|----------|
| Race Conditions | Доступ к shared state без синхронизации |
| Deadlocks | Порядок блокировок, вложенные локи |
| Resource Leaks | Незакрытые goroutines/threads/connections |
| TOCTOU | Time-of-check to time-of-use |

### Performance Checks
| Проверка | Описание |
|----------|----------|
| Complexity | O(n²) и хуже в hot paths |
| Memory | Аллокации в циклах, unbounded caches |
| I/O | Blocking в async, отсутствие pooling |
| Queries | N+1, отсутствие индексов |

## Language Highlights

### Go
- **Goroutine leaks**: unbuffered channels, missing done signal
- **Defer**: defer in loops, resource cleanup order
- **Errors**: `%w` wrapping, unchecked errors
- **Context**: propagation, cancellation handling
- **gRPC**: error mapping, metadata propagation, client lifecycle
- **Kafka**: consumer idempotency, outbox pattern, DLQ
- **Redis**: cache invalidation, distributed locks, key naming

### Java
- **Null safety**: NPE риски, Optional misuse
- **Synchronized**: double-checked locking, lock ordering
- **Resources**: try-with-resources, connection leaks
- **Streams**: parallel stream pitfalls, side effects

### Python
- **GIL**: threading for I/O vs multiprocessing for CPU
- **Context managers**: manual cleanup vs `with`
- **Async**: blocking in async, proper await usage
- **Types**: Optional без проверки, missing hints

## Workflow

1. Получи список файлов для ревью (от пользователя или через git diff)
2. Для каждого файла:
   - Определи язык и фреймворки
   - Загрузи соответствующие references
   - Прочитай файл и проанализируй
3. Собери все findings в единый отчёт
4. Отсортируй по severity (CRITICAL → LOW)
5. Выведи отчёт на русском языке

## Additional Resources

Детальные паттерны и anti-patterns находятся в:
- `../coding-rules/references/common.md` — общие проверки
- `../coding-rules/references/golang/patterns.md` — Go специфика
- `../coding-rules/references/golang/uber-fx.md` — Uber FX паттерны
- `../coding-rules/references/golang/clean-architecture.md` — DDD/Clean Architecture (Go)
- `../coding-rules/references/golang/grpc.md` — gRPC паттерны
- `../coding-rules/references/golang/kafka.md` — Kafka паттерны
- `../coding-rules/references/golang/redis.md` — Redis паттерны
- `../coding-rules/references/java/patterns.md` — Java специфика
- `../coding-rules/references/java/spring.md` — Spring паттерны
- `../coding-rules/references/python/patterns.md` — Python специфика
- `../coding-rules/references/python/fastapi.md` — FastAPI паттерны
- `examples/review-report-template.md` — шаблон отчёта
