# Go Testing Patterns Reference

Паттерны и anti-patterns для тестирования Go кода: mockery, testify, table tests, integration tests.

**See also:**
- `patterns.md` — общие Go паттерны
- `uber-fx.md` — Uber FX lifecycle, DI, fxtest

## Mockery Usage

### 1. Missing go:generate Directive

**Проблема:** Моки генерируются вручную и не обновляются при изменении интерфейса.

**Anti-pattern:**
```go
// BAD: Manual mock creation — drifts from interface
type MockRepository struct {
    mock.Mock
}

func (m *MockRepository) GetUser(ctx context.Context, id string) (*User, error) {
    args := m.Called(ctx, id)
    return args.Get(0).(*User), args.Error(1)
}
// Interface changed? Mock still compiles with old signature
```

**Pattern:**
```go
// GOOD: go:generate keeps mocks in sync
//go:generate mockery --name=Repository --output=./mocks --outpkg=mocks --case=underscore

type Repository interface {
    GetUser(ctx context.Context, id string) (*User, error)
    SaveUser(ctx context.Context, user *User) error
}

// Run: go generate ./...
// Mocks auto-generated in ./mocks/repository.go
```

**Severity:** 🟡 MEDIUM

### 2. Mock Expectation Without Assertion

**Проблема:** Mock настроен, но `AssertExpectations` не вызван — тест пройдёт даже если метод не вызывался.

**Anti-pattern:**
```go
// BAD: No assertion — test passes even if GetUser never called
func TestService_Process(t *testing.T) {
    repo := mocks.NewMockRepository(t)
    repo.On("GetUser", mock.Anything, "123").Return(&User{ID: "123"}, nil)

    svc := NewService(repo)
    svc.Process(context.Background(), "123")
    // Missing: repo.AssertExpectations(t)
}
```

**Pattern:**
```go
// GOOD: Use mocks.NewMockRepository(t) — auto-asserts on cleanup
func TestService_Process(t *testing.T) {
    repo := mocks.NewMockRepository(t) // Auto-calls AssertExpectations via t.Cleanup
    repo.EXPECT().GetUser(mock.Anything, "123").Return(&User{ID: "123"}, nil)

    svc := NewService(repo)
    err := svc.Process(context.Background(), "123")
    require.NoError(t, err)
}
```

**Severity:** 🟡 MEDIUM

## Table-Driven Tests

### 3. Non-Table Test with Repeated Logic

**Проблема:** Копирование test setup для каждого кейса — дублирование и сложно добавить новый кейс.

**Anti-pattern:**
```go
// BAD: Duplicated test logic
func TestValidateAmount(t *testing.T) {
    err := ValidateAmount(100)
    assert.NoError(t, err)

    err = ValidateAmount(0)
    assert.Error(t, err)

    err = ValidateAmount(-1)
    assert.Error(t, err)
}
```

**Pattern:**
```go
// GOOD: Table-driven test
func TestValidateAmount(t *testing.T) {
    tests := []struct {
        name    string
        amount  float64
        wantErr bool
    }{
        {"positive amount", 100, false},
        {"zero amount", 0, true},
        {"negative amount", -1, true},
        {"max amount", math.MaxFloat64, false},
        {"very small positive", 0.01, false},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := ValidateAmount(tt.amount)
            if tt.wantErr {
                require.Error(t, err)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

**Severity:** 🟡 MEDIUM

### 4. Missing Edge Cases in Table Tests

**Проблема:** Table test покрывает только happy path — пропущены граничные случаи.

**Anti-pattern:**
```go
// BAD: Only happy path
tests := []struct {
    name string
    input string
    want  string
}{
    {"normal", "hello", "HELLO"},
}
```

**Pattern:**
```go
// GOOD: Include edge cases
tests := []struct {
    name    string
    input   string
    want    string
    wantErr bool
}{
    {"normal string", "hello", "HELLO", false},
    {"empty string", "", "", false},
    {"already uppercase", "HELLO", "HELLO", false},
    {"unicode", "привет", "ПРИВЕТ", false},
    {"mixed case", "HeLLo", "HELLO", false},
    {"with numbers", "hello123", "HELLO123", false},
}
```

**Severity:** 🟡 MEDIUM

## Testify Patterns

### 5. assert vs require Misuse

**Проблема:** `assert` после критической ошибки — тест продолжает и паникует на nil pointer.

**Anti-pattern:**
```go
// BAD: assert continues on failure — nil pointer panic
func TestGetUser(t *testing.T) {
    user, err := repo.GetUser(ctx, "123")
    assert.NoError(t, err)      // Test continues even if err != nil
    assert.Equal(t, "John", user.Name) // PANIC: user is nil!
}
```

**Pattern:**
```go
// GOOD: require stops test on critical failure
func TestGetUser(t *testing.T) {
    user, err := repo.GetUser(ctx, "123")
    require.NoError(t, err)     // Stops here if err != nil
    assert.Equal(t, "John", user.Name) // Safe — user is not nil

    // Rule of thumb:
    // require — for preconditions (err != nil, not nil, len > 0)
    // assert — for value comparisons after preconditions met
}
```

**Severity:** 🟡 MEDIUM

### 6. Comparing Complex Structs

**Проблема:** `assert.Equal` на структурах с unexported полями или time.Time — ложные failures.

**Anti-pattern:**
```go
// BAD: time.Time comparison may fail due to monotonic clock
assert.Equal(t, expected, actual) // Fails on time.Time fields
```

**Pattern:**
```go
// GOOD: Use options for complex comparisons
assert.Equal(t, expected.ID, actual.ID)
assert.Equal(t, expected.Name, actual.Name)
assert.WithinDuration(t, expected.CreatedAt, actual.CreatedAt, time.Second)

// GOOD: Or use go-cmp for deep comparison
import "github.com/google/go-cmp/cmp"
import "github.com/google/go-cmp/cmp/cmpopts"

if diff := cmp.Diff(expected, actual,
    cmpopts.EquateApproxTime(time.Second),
    cmpopts.IgnoreUnexported(User{}),
); diff != "" {
    t.Errorf("mismatch (-want +got):\n%s", diff)
}
```

**Severity:** 💡 INFO

## Integration Tests

### 7. Shared State Between Tests

**Проблема:** Тесты используют общую БД без изоляции — порядок выполнения влияет на результат.

**Anti-pattern:**
```go
// BAD: Shared database state
func TestCreateUser(t *testing.T) {
    db := getSharedDB()
    repo := NewRepo(db)
    repo.Create(ctx, &User{ID: "1", Name: "John"})
    // Leftover data affects other tests
}

func TestListUsers(t *testing.T) {
    db := getSharedDB()
    repo := NewRepo(db)
    users, _ := repo.List(ctx) // May include users from other tests
}
```

**Pattern:**
```go
// GOOD: Transaction rollback for isolation
func TestCreateUser(t *testing.T) {
    db := getTestDB(t)
    tx, err := db.BeginTxx(ctx, nil)
    require.NoError(t, err)
    t.Cleanup(func() { tx.Rollback() })

    repo := NewRepo(tx)
    err = repo.Create(ctx, &User{ID: "1", Name: "John"})
    require.NoError(t, err)

    user, err := repo.GetByID(ctx, "1")
    require.NoError(t, err)
    assert.Equal(t, "John", user.Name)
    // Rollback on cleanup — no leftover data
}
```

**Severity:** 🟠 HIGH

### 8. Testcontainers for Real Dependencies

**Проблема:** Тесты зависят от внешних сервисов (Redis, Postgres) на машине разработчика.

**Anti-pattern:**
```go
// BAD: Depends on locally running Postgres
func TestRepo(t *testing.T) {
    db, _ := sql.Open("postgres", "localhost:5432/testdb")
    // Fails if Postgres not running locally
}
```

**Pattern:**
```go
// GOOD: Testcontainers for portable integration tests
import "github.com/testcontainers/testcontainers-go"
import "github.com/testcontainers/testcontainers-go/modules/postgres"

func setupPostgres(t *testing.T) *sql.DB {
    t.Helper()
    ctx := context.Background()

    pgContainer, err := postgres.Run(ctx,
        "postgres:16-alpine",
        postgres.WithDatabase("testdb"),
        testcontainers.WithWaitStrategy(
            wait.ForLog("database system is ready").WithStartupTimeout(30*time.Second),
        ),
    )
    require.NoError(t, err)
    t.Cleanup(func() { pgContainer.Terminate(ctx) })

    connStr, err := pgContainer.ConnectionString(ctx, "sslmode=disable")
    require.NoError(t, err)

    db, err := sql.Open("postgres", connStr)
    require.NoError(t, err)
    t.Cleanup(func() { db.Close() })

    return db
}
```

**Severity:** 🟡 MEDIUM

## FX Testing

### 9. Testing with Full App Instead of fxtest

**Проблема:** Тестирование с полным `fx.New` — тяжёлые зависимости, сложно изолировать.

**Anti-pattern:**
```go
// BAD: Full app for unit test
func TestService(t *testing.T) {
    app := fx.New(AppModule) // Starts DB, Redis, Kafka...
    app.Start(context.Background())
    defer app.Stop(context.Background())
}
```

**Pattern:**
```go
// GOOD: fxtest with minimal dependencies
func TestService(t *testing.T) {
    var svc *Service

    app := fxtest.New(t,
        fx.Provide(
            func() deps.Repository { return mocks.NewMockRepository(t) },
            func() *redis.Client { return redismock.NewClient(t) },
            NewService,
        ),
        fx.Populate(&svc),
    )
    app.RequireStart()
    t.Cleanup(func() { app.RequireStop() })

    // Test svc with mocked dependencies
}
```

**Severity:** 🟡 MEDIUM

### 10. Smoke Test for DI Graph

**Проблема:** Изменение зависимости ломает DI граф — узнаём только при запуске.

**Anti-pattern:**
```go
// BAD: No DI validation — broken graph discovered at deploy
```

**Pattern:**
```go
// GOOD: Smoke test validates entire DI graph at compile/test time
func Test__CreateApp(t *testing.T) {
    app := fxtest.New(t,
        fx.Options(app.CreateApp()),
        fx.Supply(testConfig()),
    )
    app.RequireStart()
    app.RequireStop()
}

// Run on every PR: go test -run Test__CreateApp ./internal/app
```

**Severity:** 🟠 HIGH

## Mockery Configuration

### 11. Mockery Config File

**Проблема:** `//go:generate mockery` в каждом файле с интерфейсом — дублирование и сложно поддерживать единые настройки.

**Anti-pattern:**
```go
// BAD: go:generate in every file — scattered config
// file: internal/repository/user.go
//go:generate mockery --name=UserRepository --output=./mocks --outpkg=mocks --case=underscore

// file: internal/repository/order.go
//go:generate mockery --name=OrderRepository --output=./mocks --outpkg=mocks --case=underscore

// file: internal/service/payment.go
//go:generate mockery --name=PaymentService --output=./mocks --outpkg=mocks --case=underscore
// Forgot --case=underscore? Different output dir? Hard to keep consistent
```

**Pattern:**
```yaml
# GOOD: Centralized .mockery.yml in project root
# .mockery.yml
all: true
dir: "{{.InterfaceDir}}/mocks"
outpkg: mocks
case: underscore
with-expecter: true
exported: false
```

```go
// Just run: mockery
// All interfaces discovered and mocks generated consistently
// No go:generate directives needed in source files
```

**Severity:** 💡 INFO

## Environment Testing

### 12. Config Tests with t.Setenv

**Проблема:** `os.Setenv()` в тестах без очистки — env переменные утекают между тестами, вызывая flaky failures.

**Anti-pattern:**
```go
// BAD: os.Setenv leaks between tests
func TestConfigFromEnv(t *testing.T) {
    os.Setenv("DATABASE_URL", "postgres://test:5432/db")
    os.Setenv("REDIS_URL", "redis://test:6379")
    // If test fails here, env vars leak to other tests

    cfg, err := LoadConfig()
    require.NoError(t, err)
    assert.Equal(t, "postgres://test:5432/db", cfg.DatabaseURL)

    os.Unsetenv("DATABASE_URL") // Easy to forget
    os.Unsetenv("REDIS_URL")    // Easy to forget
}
```

**Pattern:**
```go
// GOOD: t.Setenv auto-restores on test cleanup
func TestConfigFromEnv(t *testing.T) {
    t.Setenv("DATABASE_URL", "postgres://test:5432/db")
    t.Setenv("REDIS_URL", "redis://test:6379")
    // Automatically restored when test ends — even on failure

    cfg, err := LoadConfig()
    require.NoError(t, err)
    assert.Equal(t, "postgres://test:5432/db", cfg.DatabaseURL)
}

// GOOD: Table test with env vars
func TestConfigValidation(t *testing.T) {
    tests := []struct {
        name    string
        envVars map[string]string
        wantErr bool
    }{
        {
            name:    "valid config",
            envVars: map[string]string{"DATABASE_URL": "postgres://localhost:5432/db"},
        },
        {
            name:    "missing required var",
            envVars: map[string]string{},
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            for k, v := range tt.envVars {
                t.Setenv(k, v)
            }
            _, err := LoadConfig()
            if tt.wantErr {
                require.Error(t, err)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

**Severity:** 🟡 MEDIUM
