# Common Patterns Reference

Общие проверки, применимые ко всем языкам. Примеры даны в псевдокоде.

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

### 2. Error Information Leak

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
