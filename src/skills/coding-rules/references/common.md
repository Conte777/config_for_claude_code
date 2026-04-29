# Common Patterns Reference

Общие проверки, применимые ко всем языкам. Примеры даны в псевдокоде.

**Language-specific rules:**
- Go: `golang/patterns.md`
- Java: `java/patterns.md`
- Python: `python/patterns.md`

## Security Patterns

### 1. Input Validation

**Проблема:** Пользовательский ввод используется напрямую без валидации.

**Anti-pattern:**
```
function handleRequest(userInput):
    executeCommand("ls", userInput)  // Command injection!
```

**Pattern:**
```
ALLOWED_VALUES = ["home", "tmp", "data"]

function handleRequest(userInput):
    if userInput not in ALLOWED_VALUES:
        return error("Invalid input")
    executeCommand("ls", userInput)
```

**Признаки в коде:**
- Пользовательский ввод передаётся в shell команды
- Отсутствие whitelist/blacklist проверок
- Прямое использование request параметров

**Severity:** 🔴 CRITICAL

---

### 2. SQL/NoSQL Injection

**Проблема:** Конкатенация строк для построения запросов.

**Anti-pattern:**
```
query = "SELECT * FROM users WHERE id = " + userId
database.execute(query)
```

**Pattern:**
```
query = "SELECT * FROM users WHERE id = ?"
database.execute(query, [userId])
```

**Признаки в коде:**
- Конкатенация строк с `+` или string interpolation в SQL
- Использование `format()`, `sprintf()`, f-strings для SQL
- Отсутствие prepared statements / parameterized queries

**Severity:** 🔴 CRITICAL

---

### 3. Secret Exposure

**Проблема:** Секреты в коде, логах или сообщениях об ошибках.

**Anti-pattern:**
```
API_KEY = "sk-1234567890abcdef"  // Hardcoded!

log("Connecting with password: " + password)  // In logs!

return error("Auth failed for token: " + token)  // In response!
```

**Pattern:**
```
API_KEY = getenv("API_KEY")

log("Connecting to service")

return error("Authentication failed")
```

**Признаки в коде:**
- Строки похожие на ключи/токены (`sk-`, `ghp_`, `AKIA`)
- Логирование переменных `password`, `token`, `secret`, `key`
- Секреты в error messages возвращаемых клиенту

**Severity:** 🔴 CRITICAL

---

### 4. Path Traversal

**Проблема:** Пользователь может выйти за пределы разрешённой директории.

**Anti-pattern:**
```
function serveFile(filename):
    return readFile("/uploads/" + filename)
    // filename = "../../../etc/passwd" -> reads /etc/passwd
```

**Pattern:**
```
function serveFile(filename):
    basePath = "/uploads"
    fullPath = normalizePath(basePath + "/" + filename)

    if not startsWith(fullPath, basePath):
        return error("Invalid path")

    return readFile(fullPath)
```

**Признаки в коде:**
- Конкатенация base path + user input без проверки
- Отсутствие `..` проверки или path normalization
- Прямое использование filename из request

**Severity:** 🔴 CRITICAL

---

### 5. Authentication Bypass

**Проблема:** Недостаточная проверка аутентификации.

**Anti-pattern:**
```
function getUser(request):
    userId = request.params.userId
    return database.getUser(userId)  // No auth check!
```

**Pattern:**
```
function getUser(request):
    currentUser = authenticate(request)
    if currentUser.id != request.params.userId:
        if not currentUser.isAdmin:
            return error("Forbidden")
    return database.getUser(request.params.userId)
```

**Признаки в коде:**
- Endpoints без проверки аутентификации
- IDOR (Insecure Direct Object Reference)
- Доверие client-side данным для авторизации

**Severity:** 🔴 CRITICAL

---

## Race Condition Patterns

### 1. Check-Then-Act (TOCTOU)

**Проблема:** Состояние может измениться между проверкой и действием.

**Anti-pattern:**
```
if fileExists(path):
    // File could be deleted here by another thread!
    data = readFile(path)
```

**Pattern:**
```
try:
    data = readFile(path)
catch FileNotFoundError:
    handleMissingFile()
```

**Признаки в коде:**
- `if exists() then use()` паттерн
- Проверка и использование ресурса не атомарны
- Отсутствие блокировок при shared state

**Severity:** 🟠 HIGH

---

### 2. Read-Modify-Write

**Проблема:** Неатомарные операции над shared state.

**Anti-pattern:**
```
// Thread-unsafe increment
counter = counter + 1

// Thread-unsafe balance update
balance = getBalance(account)
balance = balance - amount
setBalance(account, balance)
```

**Pattern:**
```
// Atomic increment
atomicIncrement(counter)

// Transaction with lock
lock(account):
    balance = getBalance(account)
    balance = balance - amount
    setBalance(account, balance)
```

**Признаки в коде:**
- `x = x + 1` или `x++` без синхронизации
- Read-modify-write без транзакции/блокировки
- Shared mutable state без mutex/lock

**Severity:** 🟠 HIGH

---

### 3. Double-Checked Locking (неправильная реализация)

**Проблема:** Singleton без правильной синхронизации.

**Anti-pattern:**
```
instance = null

function getInstance():
    if instance == null:           // Check 1
        lock(mutex):
            if instance == null:   // Check 2
                instance = new Object()  // Not visible to other threads!
    return instance
```

**Pattern:**
```
// Use language-specific thread-safe singleton
// Or volatile/atomic for instance variable
// Or initialize at startup
```

**Признаки в коде:**
- Double-checked locking без volatile/atomic
- Lazy initialization shared объектов
- Singleton pattern без proper synchronization

**Severity:** 🟠 HIGH

---

## Resource Management Patterns

### 1. Resource Leak

**Проблема:** Ресурсы не освобождаются при ошибках.

**Anti-pattern:**
```
function process():
    file = open("data.txt")
    connection = openConnection()

    result = doWork(file, connection)  // Exception here = leak!

    file.close()
    connection.close()
    return result
```

**Pattern:**
```
function process():
    try:
        file = open("data.txt")
        connection = openConnection()
        return doWork(file, connection)
    finally:
        file?.close()
        connection?.close()

// Or use language-specific constructs:
// - Go: defer
// - Java: try-with-resources
// - Python: with
// - C#: using
```

**Признаки в коде:**
- `open()` без соответствующего `close()` в finally/defer
- Multiple resources без proper cleanup order
- Early return без освобождения ресурсов

**Severity:** 🟠 HIGH

---

### 2. Connection Pool Exhaustion

**Проблема:** Соединения не возвращаются в пул.

**Anti-pattern:**
```
function getData():
    conn = pool.getConnection()
    result = conn.query("SELECT ...")
    return result  // Connection never returned!
```

**Pattern:**
```
function getData():
    conn = pool.getConnection()
    try:
        return conn.query("SELECT ...")
    finally:
        pool.releaseConnection(conn)
```

**Признаки в коде:**
- `getConnection()` без `releaseConnection()` или `close()`
- Connections используются вне try-finally
- Отсутствие connection timeout

**Severity:** 🟠 HIGH

---

### 3. Unbounded Growth

**Проблема:** Структуры данных растут без ограничений.

**Anti-pattern:**
```
cache = {}

function getCached(key):
    if key not in cache:
        cache[key] = expensiveCompute(key)  // Grows forever!
    return cache[key]
```

**Pattern:**
```
cache = LRUCache(maxSize=1000)

function getCached(key):
    if key not in cache:
        cache[key] = expensiveCompute(key)  // Evicts old entries
    return cache[key]
```

**Признаки в коде:**
- Map/Dict без size limit
- List/Array с append без bounds
- Queue без max size

**Severity:** 🟠 HIGH

---

## Error Handling Patterns

### 1. Silent Failure

**Проблема:** Ошибки игнорируются.

**Anti-pattern:**
```
try:
    processData(data)
catch Exception:
    pass  // What happened? Nobody knows.
```

**Pattern:**
```
try:
    processData(data)
catch ValidationError as e:
    log.warn("Invalid data", e)
    return defaultValue
catch Exception as e:
    log.error("Unexpected error", e)
    raise  // Re-throw or handle appropriately
```

**Признаки в коде:**
- Пустые catch блоки
- `catch (Exception)` без обработки
- Игнорирование return value ошибки

**Severity:** 🟠 HIGH

---

### 2. Silent Skip Business Condition

**Проблема:** При невыполнении бизнес-условия use case возвращает дефолт/пустой результат вместо ошибки. Клиент получает успешный ответ там, где должен получить осмысленный fail — UI не покажет причину, метрики не зафиксируют сбой, поведение нельзя отличить от валидного "пустого" сценария.

**Anti-pattern:**
```
function calculateMaxWithdrawal(account, direction):
    if not directionAvailable(direction):
        return 0          // клиент думает, что доступно 0 — а должен был узнать причину

    if account.balance < minAmount:
        return Result{}, nil  // пустой результат вместо ошибки

    // ... корректная ветка
```

```
function processOrder(order):
    if not order.isEligible():
        return            // тихий выход — нет ни ошибки, ни сигнала
```

**Pattern:**
```
// объявляем типизированные domain-ошибки
ErrDirectionNotAvailable = new DomainError("direction not available")
ErrAmountBelowMin        = new DomainError("amount below minimum")
ErrOrderNotEligible      = new DomainError("order not eligible")

function calculateMaxWithdrawal(account, direction):
    if not directionAvailable(direction):
        return null, ErrDirectionNotAvailable
    if account.balance < minAmount:
        return null, ErrAmountBelowMin
    // ...

// transport-слой маппит domain-ошибку в корректный код:
//   gRPC FailedPrecondition / HTTP 409 / 400 в зависимости от семантики
```

**Признаки в коде:**
- `if !cond { return default, nil }` или `return zeroValue, nil` в use case при невыполнении бизнес-условия
- Пустой `else`-блок без error
- HTTP 200 с пустым телом / нулями вместо явного 4xx
- `continue` в цикле обработки batch-операции при невалидном элементе без сбора причин в результирующий отчёт

**Severity:** 🟠 HIGH

---

### 3. Error Information Leak

**Проблема:** Детали ошибок раскрываются пользователю.

**Anti-pattern:**
```
try:
    result = database.query(sql)
catch DatabaseError as e:
    return response(500, str(e))  // Stack trace to user!
```

**Pattern:**
```
try:
    result = database.query(sql)
catch DatabaseError as e:
    log.error("Database error", e)  // Log full details
    return response(500, "Internal server error")  // Generic to user
```

**Признаки в коде:**
- Exception message в HTTP response
- Stack trace в API response
- Database errors в client-facing messages

**Severity:** 🟠 HIGH

---

## Financial / Money Calculations

### 1. Floating Point for Money

**Проблема:** Денежные суммы на `float`/`double` теряют точность из-за бинарного представления. `0.1 + 0.2 ≠ 0.3`. Накопленная погрешность в финансовых расчётах превращается в реальные деньги — расхождение балансов, ошибки в комиссиях, неправильные конверсии.

**Anti-pattern:**
```
balance: float64 = 0.1 + 0.2
// balance == 0.30000000000000004 — расходится с ожидаемым 0.3

fee: float64 = amount * 0.025
// результат может потерять последние знаки после запятой
```

**Pattern:**
```
// Использовать decimal-тип с явной точностью
// Go:     github.com/shopspring/decimal — Decimal
// Java:   java.math.BigDecimal
// Python: decimal.Decimal

balance = Decimal("0.1") + Decimal("0.2")    // ровно 0.3
fee     = amount.Mul(Decimal("0.025")).Round(scale)
```

**Признаки в коде:**
- Поля `amount`, `balance`, `fee`, `price`, `total` имеют тип `float`/`double`
- Парсинг суммы через `parseFloat`/`Atof`/`float()`
- Сравнение денег через `==`/`!=` (в float-арифметике это ненадёжно)

**Severity:** 🔴 CRITICAL

---

### 2. Different Money Concepts as One Type

**Проблема:** В одной формуле смешиваются `total`, `available`, `reserved`, `balance` без различения типов. Компилятор не ловит перепутанные источники: `available - reserved` и `total - reserved` — разные семантические операции, но в коде неотличимы. В результате в формулу попадает поле, не относящееся к домену операции (например, замороженные средства учитываются в расчёте максимально доступной к выводу суммы).

**Anti-pattern:**
```
function maxWithdrawal(acc):
    // total включает зарезервированные средства, которые нельзя выводить
    return acc.total - acc.fee

// нет различия между "сколько лежит" и "сколько можно тратить"
```

**Pattern:**
```
// Разные виды сумм — разные типы; компилятор ловит перепутанные источники
type Total      Decimal  // всё, что числится
type Available  Decimal  // total минус reserved
type Reserved   Decimal  // удержанные операции

function maxWithdrawal(acc):
    return acc.available - acc.fee   // available уже без reserved
```

**Признаки в коде:**
- Поля `total`/`balance`/`available`/`reserved` имеют один и тот же тип `Decimal`/`BigDecimal`/`float`
- Формулы вида `cfg.Total - cfg.Reserved` без явного типа результата
- В одной функции `available` и `total` участвуют в одной арифметической операции

**Severity:** 🟠 HIGH

---

### 3. Unexplained Operation Order

**Проблема:** Финансовые расчёты с делением и округлением чувствительны к порядку операций: `(a-b)/c` ≠ `a/c - b/c` при ненулевой ошибке округления. Если порядок выбран случайно или скопирован, при изменении формулы легко получить расхождение копеек, которое накапливается на больших объёмах.

**Anti-pattern:**
```
// порядок операций без обоснования; делим до округления промежуточных результатов
fee = (amount * rate / 100).Round(2)
net = amount - fee
```

**Pattern:**
```
// Формула сопровождается ссылкой на источник (тикет/спека) и пояснением порядка.
// Где требуется — явный Round(scale) на каждом промежуточном шаге.

// FEE_SCALE = 2 (копейки/центы); rate в долях единицы (0.025), не в процентах.
// Источник: spec/finance/fees-v3.md, см. секцию "Order matters".
fee = amount.Mul(rate).Round(FEE_SCALE)   // округляем комиссию первой
net = amount.Sub(fee)                      // baseline остаётся точным
```

**Признаки в коде:**
- Деление без явного `Round(scale)` после
- Длинные цепочки `Mul/Div` без комментария про порядок
- Отсутствие unit-тестов на граничные случаи: zero, exact match, scale boundary, negative, overflow

**Severity:** 🟠 HIGH

---

## Performance Anti-Patterns

### 1. N+1 Query

**Проблема:** Дополнительный запрос на каждый элемент.

**Anti-pattern:**
```
orders = database.query("SELECT * FROM orders")
for order in orders:
    items = database.query("SELECT * FROM items WHERE order_id = ?", order.id)
    // N queries for N orders!
```

**Pattern:**
```
orders = database.query("""
    SELECT o.*, i.*
    FROM orders o
    JOIN items i ON o.id = i.order_id
""")
// Single query with JOIN
```

**Признаки в коде:**
- Query внутри цикла
- Lazy loading без batch fetching
- Отсутствие JOIN для связанных данных

**Severity:** 🔵 LOW (но может быть HIGH при большом N)

---

### 2. Blocking in Event Loop

**Проблема:** Синхронные операции в async коде.

**Anti-pattern:**
```
async function handleRequest():
    data = syncHttpCall(url)  // Blocks entire event loop!
    return process(data)
```

**Pattern:**
```
async function handleRequest():
    data = await asyncHttpCall(url)  // Non-blocking
    return process(data)
```

**Признаки в коде:**
- Sync I/O в async функциях
- `time.sleep()` в async контексте
- CPU-intensive код без offload в thread pool

**Severity:** 🟠 HIGH (для высоконагруженных систем)
