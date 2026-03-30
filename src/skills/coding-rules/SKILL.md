---
name: coding-rules
description: This skill should be used when the user asks to "написать код", "исправить баг", "fix bug", "реализовать фичу", "implement feature", "добавить функцию", "создать класс", "рефакторинг", "refactor", "оптимизировать", "optimize", "debug", "отладить", "написать тест", "write test", "паттерны", "patterns", "anti-patterns", "архитектура", "architecture", "clean code", "обработка ошибок", "error handling", "валидация", "безопасность", "security", "concurrency", "performance", "спланировать изменения", "plan changes", "design solution", "спроектировать", or when writing, modifying, planning, or reviewing any Go, Java, Python code.
---

# Coding Rules

Language-specific coding rules: patterns, anti-patterns, and best practices for Go, Java, Python.
Auto-loaded when writing, modifying, planning, or reviewing code.

## How to Use

### Step 1: Always Load Common Rules

Load `references/common.md` for every code-related task. It covers:
- Security (input validation, injection, secrets, path traversal)
- Race conditions & concurrency (shared state, deadlocks, TOCTOU)
- Resource management (leaks, cleanup, connection pools)
- Error handling (propagation, retries, idempotency)
- Performance (complexity, allocations, caching, N+1 queries)

### Step 2: Detect Language

Determine the language from file extensions, imports, or project files:

| Indicator | Language |
|-----------|----------|
| `.go`, `go.mod`, `go.sum` | Go |
| `.java`, `pom.xml`, `build.gradle` | Java |
| `.py`, `pyproject.toml`, `requirements.txt` | Python |

Load the corresponding language rules:

| Language | Reference file |
|----------|---------------|
| Go | `references/golang/patterns.md` |
| Java | `references/java/patterns.md` |
| Python | `references/python/patterns.md` |

### Step 3: Detect Frameworks

Check imports, config files, and annotations for framework indicators:

| Indicator | Framework | Additional reference |
|-----------|-----------|---------------------|
| `fx.New`, `fx.Module`, `fx.Provide` | Go + Uber FX | `references/golang/uber-fx.md` |
| DDD layers, `internal/domain/` | Go + Clean Architecture | `references/golang/clean-architecture.md` |
| `google.golang.org/grpc`, `.proto` | Go + gRPC | `references/golang/grpc.md` |
| `segmentio/kafka-go`, `kafkaconnector` | Go + Kafka | `references/golang/kafka.md` |
| `go-redis/redis`, `redisconnector` | Go + Redis | `references/golang/redis.md` |
| `testing`, `testify`, `_test.go` | Go + Testing | `references/golang/testing.md` |
| `@SpringBootApplication`, `@RestController` | Java + Spring | `references/java/spring.md` |
| `FastAPI`, `@app.get`, `@router` | Python + FastAPI | `references/python/fastapi.md` |

### Step 4: Apply Rules

**When writing or modifying code:**
- Follow patterns from loaded references
- Avoid anti-patterns listed in the rules
- Apply security checks from `common.md` at system boundaries

**When planning changes:**
- Use rules to identify affected layers and potential issues
- Consider concurrency and performance implications upfront

**When reviewing code:**
- Use rules as a checklist for each detected language/framework
- Prioritize: security > concurrency > correctness > performance

## Reference Files Summary

```
references/
├── common.md              # Cross-language: security, concurrency, performance
├── golang/
│   ├── patterns.md        # Go idioms, error handling, context, goroutines
│   ├── uber-fx.md         # DI patterns: fx.Module, fx.Provide, fx.Invoke
│   ├── clean-architecture.md  # DDD layers, dependency rule, boundaries
│   ├── grpc.md            # Error mapping, interceptors, metadata, lifecycle
│   ├── kafka.md           # Consumer idempotency, outbox, DLQ, partitioning
│   ├── redis.md           # Cache invalidation, distributed locks, key naming
│   └── testing.md         # Table tests, mocks, integration tests, fixtures
├── java/
│   ├── patterns.md        # Null safety, streams, resources, synchronized
│   └── spring.md          # Bean lifecycle, @Transactional, security, testing
└── python/
    ├── patterns.md        # GIL, async, context managers, type hints
    └── fastapi.md         # Dependency injection, middleware, Pydantic, async
```
