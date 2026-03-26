---
name: check-di
description: This skill should be used when the user asks to "проверить DI", "check-di", "валидировать зависимости", "проверить Uber FX граф", "validate DI graph", or after adding/changing fx.Provide, fx.Invoke, fx.Module in a Go project with Uber FX.
version: 0.1.0
---

Validate the Uber FX dependency injection graph without starting the application.

## Steps

### 1. Find DI validation test

Search for `TestCreateApp` in the project:

```bash
grep -rl "TestCreateApp" internal/app/ 2>/dev/null
```

If not found, also check:
```bash
grep -rl "TestCreateApp" . --include="*_test.go" 2>/dev/null
```

### 2. Run validation

If `TestCreateApp` is found, run it:

```bash
go test ./internal/app/ -run TestCreateApp -v -count=1
```

Use the actual path where the test was found if it differs from `internal/app/`.

### 3. Report

- **Pass:** "DI graph is valid — all dependencies resolved"
- **Fail:** Show the missing or conflicting dependency from the error output. Suggest which `fx.Provide`, `fx.Supply`, or `fx.Module` needs to be added or updated.
- **No test found:** "TestCreateApp not found. To enable DI validation, create a test that calls `fxtest.New(t, app.Module()).RequireStart().RequireStop()`"
