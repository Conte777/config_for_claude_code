# Go + Validation Patterns Reference

Структурная валидация input-данных через `go-playground/validator/v10` — де-факто стандарт в Go-экосистеме.

**See also:**
- `http.md` — bind + validate at handler boundary
- `clean-architecture.md` — DTO vs Entity boundary
- `patterns.md` — error types

## Validator Setup

### Single Instance Per Application

**Проблема:** Validator при инициализации компилирует teги. Создание нового validator-а на каждом запросе — пустая работа.

**Pattern:**
```go
import "github.com/go-playground/validator/v10"

// Один экземпляр на приложение, инжектится через FX/DI
func NewValidator() *validator.Validate {
    v := validator.New()

    // Использовать имена JSON-полей в ошибках вместо struct-имён
    v.RegisterTagNameFunc(func(fld reflect.StructField) string {
        name := strings.SplitN(fld.Tag.Get("json"), ",", 2)[0]
        if name == "-" {
            return ""
        }
        return name
    })

    // Регистрируем кастомные валидаторы (см. ниже)
    _ = v.RegisterValidation("currency", validateCurrency)

    return v
}
```

**Severity:** 🟡 MEDIUM

---

## Common Tags

```go
type CreateOrderRequest struct {
    UserID   uuid.UUID `json:"user_id"  validate:"required"`
    Amount   float64   `json:"amount"   validate:"required,gt=0,lte=1000000"`
    Currency string    `json:"currency" validate:"required,len=3,uppercase,currency"`
    Email    string    `json:"email"    validate:"omitempty,email"`
    Items    []Item    `json:"items"    validate:"required,min=1,max=100,dive"`
    Note     string    `json:"note"     validate:"max=500"`
    Status   string    `json:"status"   validate:"omitempty,oneof=pending confirmed"`
    URL      string    `json:"url"      validate:"omitempty,url"`
}

type Item struct {
    ProductID uuid.UUID `json:"product_id" validate:"required"`
    Quantity  int       `json:"quantity"   validate:"required,min=1,max=999"`
}
```

**Часто используемые теги:**
| Тег                    | Значение                                    |
|------------------------|---------------------------------------------|
| `required`             | Поле должно быть установлено                 |
| `omitempty`            | Не валидировать, если поле "пустое"          |
| `min=N`/`max=N`        | Длина строки/слайса/числа                    |
| `len=N`                | Точное значение длины                        |
| `gt=N`/`gte=N`         | Greater (>=) than                            |
| `lt=N`/`lte=N`         | Less (<=) than                               |
| `oneof=a b c`          | Enum: значение должно быть из списка         |
| `email`/`url`/`uuid`   | Формат                                       |
| `dive`                 | Применить теги к элементам слайса/мапы       |
| `e164`                 | Phone number в E.164 format                  |
| `alphanum`             | Только буквы и цифры                         |

---

## Custom Validators

### Field-Level Validator

**Проблема:** Built-in тегов недостаточно — валидируем currency-код против ISO 4217, бизнес-формат идентификатора.

**Pattern:**
```go
var validCurrencies = map[string]struct{}{
    "USD": {}, "EUR": {}, "GBP": {}, "JPY": {}, // и т.д.
}

func validateCurrency(fl validator.FieldLevel) bool {
    code := fl.Field().String()
    _, ok := validCurrencies[code]
    return ok
}

// Регистрируем при инициализации:
v.RegisterValidation("currency", validateCurrency)

// Использование:
type Request struct {
    Currency string `json:"currency" validate:"required,currency"`
}
```

### Struct-Level Validator

**Проблема:** Кросс-полевая валидация (`StartDate < EndDate`, `MinPrice < MaxPrice`) не выражается тегами на одном поле.

**Pattern:**
```go
type DateRange struct {
    StartDate time.Time `json:"start_date" validate:"required"`
    EndDate   time.Time `json:"end_date"   validate:"required"`
}

func dateRangeStructLevel(sl validator.StructLevel) {
    dr := sl.Current().Interface().(DateRange)
    if !dr.EndDate.After(dr.StartDate) {
        sl.ReportError(dr.EndDate, "end_date", "EndDate", "gtfield_start_date", "")
    }
}

// Регистрация:
v.RegisterStructValidation(dateRangeStructLevel, DateRange{})
```

Альтернатива — built-in тег `gtfield`:
```go
type DateRange struct {
    StartDate time.Time `validate:"required"`
    EndDate   time.Time `validate:"required,gtfield=StartDate"`
}
```

`gtfield`/`ltfield`/`eqfield` хватает для большинства случаев; struct-level — для сложной логики.

---

## Validation at Boundary, Not in Use Case

**Проблема:** Когда `validator.Struct(req)` вызывается из use case-а, тестам бизнес-логики нужно поднимать validator-инстанс. Это размывает ответственность: handler перестал быть единственной точкой ответа за формат запроса.

**Anti-pattern:**
```go
// BAD: валидация в use case
func (uc *UseCase) CreateOrder(ctx context.Context, req *CreateOrderRequest) error {
    if err := uc.validator.Struct(req); err != nil { // загрязняет UC
        return err
    }
    // бизнес-логика
}
```

**Pattern:**
```go
// GOOD: валидация в handler/transport, UC получает уже валидный req
func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
    var req CreateOrderRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil { /* ... */ }
    if err := h.validator.Struct(req); err != nil {
        h.writeValidationError(w, err)
        return
    }
    // UC занимается ТОЛЬКО бизнесом
    resp, err := h.uc.CreateOrder(r.Context(), &req)
    // ...
}
```

**Правила:**
- структурная валидация (формат, длина, range) — на границе (HTTP/gRPC handler)
- бизнес-валидация (баланс достаточен, статус разрешает переход, объект существует) — в use case
- если эти проверки смешиваются в одном слое, тестировать UC становится сложно: тесты должны конструировать формально валидные запросы

**Severity:** 🟠 HIGH

---

## Translation: Validator Errors → API Errors

**Проблема:** `validator.ValidationErrors` имеет богатую структуру (`Field`, `Tag`, `Param`), но raw-вывод (`field 'amount' failed on the 'gt' tag`) не подходит для пользователя.

**Pattern:**
```go
type FieldError struct {
    Field   string `json:"field"`
    Message string `json:"message"`
}

func toFieldErrors(err error) []FieldError {
    var ve validator.ValidationErrors
    if !errors.As(err, &ve) {
        return nil
    }
    out := make([]FieldError, 0, len(ve))
    for _, fe := range ve {
        out = append(out, FieldError{
            Field:   fe.Field(), // через RegisterTagNameFunc — берёт json-имя
            Message: humanMessage(fe),
        })
    }
    return out
}

func humanMessage(fe validator.FieldError) string {
    switch fe.Tag() {
    case "required":
        return "is required"
    case "email":
        return "must be a valid email"
    case "uuid":
        return "must be a valid UUID"
    case "min":
        return fmt.Sprintf("must be at least %s", fe.Param())
    case "max":
        return fmt.Sprintf("must be at most %s", fe.Param())
    case "gt":
        return fmt.Sprintf("must be greater than %s", fe.Param())
    case "lte":
        return fmt.Sprintf("must be at most %s", fe.Param())
    case "oneof":
        return fmt.Sprintf("must be one of: %s", fe.Param())
    case "len":
        return fmt.Sprintf("must be exactly %s characters", fe.Param())
    case "currency":
        return "must be a valid ISO 4217 currency code"
    default:
        return fmt.Sprintf("failed validation: %s", fe.Tag())
    }
}
```

**Использование:**
```go
func (h *Handler) writeValidationError(w http.ResponseWriter, err error) {
    fieldErrors := toFieldErrors(err)
    writeJSON(w, http.StatusBadRequest, APIErrorResponse{
        Error: APIError{
            Code:    "validation_failed",
            Message: "request validation failed",
            Details: map[string]interface{}{"errors": fieldErrors},
        },
    })
}
```

Если нужен i18n — использовать `validator/v10/translations/<locale>` (англ., рус., нем., и т.д.):
```go
import (
    "github.com/go-playground/locales/ru"
    ut "github.com/go-playground/universal-translator"
    ru_translations "github.com/go-playground/validator/v10/translations/ru"
)

russian := ru.New()
uni := ut.New(russian, russian)
trans, _ := uni.GetTranslator("ru")
ru_translations.RegisterDefaultTranslations(v, trans)
```

**Severity:** 🟡 MEDIUM

---

## Pure `Validate()`: No Mutation, No Defaults

**Проблема:** Метод `Validate()` под "проверочным" именем мутирует поля Request — нормализует регистр, обрезает пробелы, перезаписывает `Limit`/`Offset` дефолтами. Вызывающий код передаёт указатель в `r.Validate()` ради проверки и не ожидает, что после вызова содержимое объекта изменилось. Это скрытый side effect: ошибка валидации может ничего не вернуть, но запрос уже отличается от пришедшего по сети, и трассировку "что прислал клиент" уже не восстановить.

**Anti-pattern:**
```go
// BAD: Validate мутирует Request — defaults и нормализация спрятаны под "проверкой"
type Request struct {
    Limit  int    `json:"limit"`
    Offset int    `json:"offset"`
    Sort   string `json:"sort"`
}

func (r *Request) Validate() error {
    if r.Limit <= 0 || r.Limit > 100 {
        r.Limit = 20 // тихий defaults
    }
    if r.Offset < 0 {
        r.Offset = 0 // и здесь
    }
    r.Sort = strings.ToLower(strings.TrimSpace(r.Sort)) // нормализация
    if r.Sort != "" && r.Sort != "asc" && r.Sort != "desc" {
        return fmt.Errorf("invalid sort: %q", r.Sort)
    }
    return nil
}
```

**Pattern:**
```go
// GOOD: Validate только проверяет, defaults — отдельный метод
type Request struct {
    Limit  int    `json:"limit"`
    Offset int    `json:"offset"`
    Sort   string `json:"sort"`
}

func (r *Request) Validate() error {
    if r.Limit < 0 || r.Limit > 100 {
        return fmt.Errorf("limit must be in [0, 100], got %d", r.Limit)
    }
    if r.Offset < 0 {
        return fmt.Errorf("offset must be >= 0, got %d", r.Offset)
    }
    if r.Sort != "" && r.Sort != "asc" && r.Sort != "desc" {
        return fmt.Errorf("invalid sort: %q", r.Sort)
    }
    return nil
}

func (r *Request) ApplyDefaults(cfg *Config) {
    if r.Limit == 0 {
        r.Limit = cfg.DefaultLimit
    }
    // ...
}

// в handler:
if err := req.Validate(); err != nil {
    return badRequest(w, err)
}
req.ApplyDefaults(h.cfg)
```

**Правила:**
- `Validate()` — read-only по объекту; единственный side effect — возвращаемая ошибка
- defaults задавать в конструкторе DTO (`NewListRequest(...)`), `ApplyDefaults(cfg)` или при unmarshal через JSON-теги/`envDefault`
- нормализацию (trim/case) делать в отдельном `Normalize()` — отдельный метод, чтобы тесты валидации не зависели от формы входа
- если по бизнес-причине значение надо переписать — назвать метод явно: `Normalize`, `Sanitize`, `WithDefaults`

**Признаки в коде:**
- В теле `Validate()` есть присвоения полям receiver-а (`r.X = ...`)
- Тесты валидации ожидают, что после `Validate()` поля изменились
- Имя метода — `Validate`, но в коде он используется как `r.Validate(); h.uc.Do(&r)` для сидинга defaults
- При повторном вызове `Validate()` объект отличается от первого вызова

**Severity:** 🟠 HIGH (скрытый side effect, маскированный под проверочное имя — ломает ожидания вызывающих и затрудняет трассировку входа)

---

## Validate Values Against Config, Not Just Key Existence

**Проблема:** Whitelist для фильтрации/сортировки/поиска часто реализуется как `map[string]struct{}` — "разрешённые колонки". Проверяется только наличие ключа, операторы (`$gt`, `$lt`, `$in`, `$like`) — нет. Атакующий или некорректный клиент пишет `status=$gt:5` и получает поведение, которое для этой колонки никогда не задумывалось: сравнение enum-строки числовым оператором, подзапрос со скрытыми побочными эффектами, full-scan по индексу.

**Anti-pattern:**
```go
// BAD: проверка только наличия колонки, операторы игнорируются
type FilterableColumns map[string]struct{}

var allowed = FilterableColumns{
    "status":     {},
    "created_at": {},
    "amount":     {},
}

func ValidateFilter(col, op string) error {
    if _, ok := allowed[col]; !ok {
        return fmt.Errorf("column %s not filterable", col)
    }
    return nil // оператор не проверяется
}

// $gt для status пройдёт — но смысла не имеет
ValidateFilter("status", "$gt") // → nil
```

**Pattern:**
```go
// GOOD: whitelist хранит {Column, разрешённые Ops}
type ColumnConfig struct {
    Ops []string // "$eq", "$ne", "$gt", "$lt", "$in", "$like"
}

type FilterableColumns map[string]ColumnConfig

var allowed = FilterableColumns{
    "status":     {Ops: []string{"$eq", "$ne", "$in"}},
    "created_at": {Ops: []string{"$eq", "$gt", "$lt", "$gte", "$lte"}},
    "amount":     {Ops: []string{"$eq", "$gt", "$lt", "$gte", "$lte"}},
}

func ValidateFilter(col, op string) error {
    cfg, ok := allowed[col]
    if !ok {
        return fmt.Errorf("column %s not filterable", col)
    }
    if !slices.Contains(cfg.Ops, op) {
        return fmt.Errorf("operator %s not allowed for %s; got %v", op, col, cfg.Ops)
    }
    return nil
}

ValidateFilter("status", "$gt") // → "operator $gt not allowed for status"
```

**Расширения:**
- whitelist значений для enum-колонок: `Values: []string{"pending", "completed"}` — если op = `$eq`/`$in`, проверять и значение
- ограничение длины строкового значения для `$like` — иначе full-scan через `'%' || huge_string || '%'`
- разные whitelist'ы для разных ролей (admin/user) — структура `{Ops, ValuesByRole}`

**Признаки в коде:**
- Whitelist — `map[string]struct{}` или `[]string`, без `Ops`/`Values`
- Тесты проверяют только "колонка не из списка → error"; нет кейса "оператор не из списка"
- Парсер фильтра принимает любые `$op` и передаёт их в SQL, надеясь на валидацию выше
- Есть инциденты "почему `$gt` для status вернул странный результат"

**Severity:** 🟠 HIGH
