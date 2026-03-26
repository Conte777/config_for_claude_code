---
name: verify
description: This skill should be used when the user asks to "верифицировать проект", "запустить проверки", "verify", "прогнать тесты и линтеры", "проверить что всё работает", or needs to run full project verification (tests + static analysis + DI validation).
version: 0.1.0
---

Run full project verification. Auto-detect project type and execute all relevant checks sequentially. Stop on first failure.

## Project Detection

Determine project type by marker files in the current working directory (search upward if needed):

| Marker | Type | Stack |
|--------|------|-------|
| `go.mod` | Go | go test, go vet, DI validation |
| `pyproject.toml` | Python | pytest, ruff, mypy |
| `pom.xml` | Java | mvn test, checkstyle |

If multiple markers found, run checks for the primary one (closest to working directory).

## Go Project

### 1. Run tests
```bash
go test ./... -count=1
```

### 2. Run go vet
```bash
go vet ./...
```

### 3. Validate DI graph (if applicable)
Search for `TestCreateApp` in `internal/app/`:
```bash
grep -rl "TestCreateApp" internal/app/ 2>/dev/null
```

If found, run DI validation:
```bash
go test ./internal/app/ -run TestCreateApp -v -count=1
```

If not found, skip this step and note it in the report.

## Python Project

### 1. Run tests
```bash
uv run pytest
```

### 2. Run linter
```bash
uv run ruff check .
```

### 3. Run type checker (if configured)
Check if mypy is configured in `pyproject.toml` (`[tool.mypy]` section). If yes:
```bash
uv run mypy .
```

## Java Project

### 1. Run tests
```bash
mvn test
```

### 2. Run checkstyle (if configured)
Check if checkstyle plugin exists in `pom.xml`. If yes:
```bash
mvn checkstyle:check
```

## Output

Report results concisely:
- If all pass: "All checks passed" with list of executed steps
- If any fail: show the failing step and relevant error output, do not continue to next steps
