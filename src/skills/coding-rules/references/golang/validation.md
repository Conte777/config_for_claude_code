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
