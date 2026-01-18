# Java Patterns Reference

Паттерны и anti-patterns специфичные для Java.

## Null Safety

### 1. Missing Null Checks

**Anti-pattern:**
```java
// BAD: NPE waiting to happen
public String getUserName(User user) {
    return user.getName().toUpperCase();
}
```

**Pattern:**
```java
// GOOD: Defensive null checks
public String getUserName(User user) {
    if (user == null || user.getName() == null) {
        return "";
    }
    return user.getName().toUpperCase();
}

// GOOD: Using Optional
public String getUserName(Optional<User> user) {
    return user
        .map(User::getName)
        .map(String::toUpperCase)
        .orElse("");
}
```

**Severity:** 🟠 HIGH

### 2. Optional.get() Without Check

**Anti-pattern:**
```java
// BAD: Optional.get() without isPresent()
Optional<User> user = findUser(id);
String name = user.get().getName(); // NoSuchElementException!
```

**Pattern:**
```java
// GOOD: Use orElse/orElseThrow
Optional<User> user = findUser(id);
String name = user
    .map(User::getName)
    .orElse("Unknown");

// GOOD: With specific exception
User u = findUser(id)
    .orElseThrow(() -> new UserNotFoundException(id));
```

**Severity:** 🟠 HIGH

### 3. Returning Null Collections

**Anti-pattern:**
```java
// BAD: Returning null for collections
public List<User> findUsers(String query) {
    if (query.isEmpty()) {
        return null;
    }
    return userRepository.find(query);
}
```

**Pattern:**
```java
// GOOD: Return empty collection
public List<User> findUsers(String query) {
    if (query.isEmpty()) {
        return Collections.emptyList();
    }
    return userRepository.find(query);
}
```

**Severity:** 🟡 MEDIUM

## Synchronization

### 1. Double-Checked Locking

**Anti-pattern:**
```java
// BAD: Broken double-checked locking
private static Singleton instance;

public static Singleton getInstance() {
    if (instance == null) {
        synchronized (Singleton.class) {
            if (instance == null) {
                instance = new Singleton(); // Not thread-safe!
            }
        }
    }
    return instance;
}
```

**Pattern:**
```java
// GOOD: Volatile for visibility
private static volatile Singleton instance;

public static Singleton getInstance() {
    if (instance == null) {
        synchronized (Singleton.class) {
            if (instance == null) {
                instance = new Singleton();
            }
        }
    }
    return instance;
}

// GOOD: Initialization-on-demand holder idiom
private static class Holder {
    static final Singleton INSTANCE = new Singleton();
}

public static Singleton getInstance() {
    return Holder.INSTANCE;
}
```

**Severity:** 🟠 HIGH

### 2. Lock Ordering Deadlocks

**Anti-pattern:**
```java
// BAD: Potential deadlock
class Transfer {
    void transfer(Account from, Account to, int amount) {
        synchronized (from) {
            synchronized (to) {
                from.debit(amount);
                to.credit(amount);
            }
        }
    }
}
// Thread 1: transfer(A, B, 100) - locks A, waits for B
// Thread 2: transfer(B, A, 50)  - locks B, waits for A
```

**Pattern:**
```java
// GOOD: Consistent lock ordering
class Transfer {
    void transfer(Account from, Account to, int amount) {
        Account first = from.getId() < to.getId() ? from : to;
        Account second = from.getId() < to.getId() ? to : from;

        synchronized (first) {
            synchronized (second) {
                from.debit(amount);
                to.credit(amount);
            }
        }
    }
}
```

**Severity:** 🟠 HIGH

### 3. Synchronized on Non-Final Field

**Anti-pattern:**
```java
// BAD: Lock object can change
private Object lock = new Object();

public void setLock(Object newLock) {
    lock = newLock; // Now different threads use different locks!
}

public void doWork() {
    synchronized (lock) {
        // Not actually synchronized!
    }
}
```

**Pattern:**
```java
// GOOD: Final lock object
private final Object lock = new Object();

public void doWork() {
    synchronized (lock) {
        // Properly synchronized
    }
}
```

**Severity:** 🟠 HIGH

## Resource Management

### 1. Try-With-Resources

**Anti-pattern:**
```java
// BAD: Resource leak possible
public String readFile(String path) throws IOException {
    BufferedReader reader = new BufferedReader(new FileReader(path));
    try {
        return reader.readLine();
    } finally {
        reader.close(); // Exception here loses original exception
    }
}
```

**Pattern:**
```java
// GOOD: Try-with-resources
public String readFile(String path) throws IOException {
    try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
        return reader.readLine();
    }
}

// GOOD: Multiple resources
public void copy(String src, String dst) throws IOException {
    try (InputStream in = new FileInputStream(src);
         OutputStream out = new FileOutputStream(dst)) {
        in.transferTo(out);
    }
}
```

**Severity:** 🟠 HIGH

### 2. Connection Leaks

**Anti-pattern:**
```java
// BAD: Connection leak on exception
public User findUser(int id) throws SQLException {
    Connection conn = dataSource.getConnection();
    PreparedStatement stmt = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
    stmt.setInt(1, id);
    ResultSet rs = stmt.executeQuery();
    // If exception here, connection never closed!
    User user = mapUser(rs);
    conn.close();
    return user;
}
```

**Pattern:**
```java
// GOOD: Proper resource management
public User findUser(int id) throws SQLException {
    try (Connection conn = dataSource.getConnection();
         PreparedStatement stmt = conn.prepareStatement("SELECT * FROM users WHERE id = ?")) {
        stmt.setInt(1, id);
        try (ResultSet rs = stmt.executeQuery()) {
            if (rs.next()) {
                return mapUser(rs);
            }
            return null;
        }
    }
}
```

**Severity:** 🔴 CRITICAL

## Thread Safety

### 1. Non-Thread-Safe Collections

**Anti-pattern:**
```java
// BAD: HashMap is not thread-safe
private Map<String, User> cache = new HashMap<>();

public User getUser(String id) {
    return cache.get(id); // Race condition!
}

public void putUser(String id, User user) {
    cache.put(id, user); // ConcurrentModificationException possible
}
```

**Pattern:**
```java
// GOOD: Use concurrent collections
private Map<String, User> cache = new ConcurrentHashMap<>();

// GOOD: Or synchronize access
private final Map<String, User> cache = new HashMap<>();

public synchronized User getUser(String id) {
    return cache.get(id);
}

public synchronized void putUser(String id, User user) {
    cache.put(id, user);
}
```

**Severity:** 🟠 HIGH

### 2. Shared Mutable State

**Anti-pattern:**
```java
// BAD: Mutable state shared between threads
public class Counter {
    private int count = 0;

    public void increment() {
        count++; // Not atomic!
    }

    public int getCount() {
        return count;
    }
}
```

**Pattern:**
```java
// GOOD: Use AtomicInteger
public class Counter {
    private final AtomicInteger count = new AtomicInteger(0);

    public void increment() {
        count.incrementAndGet();
    }

    public int getCount() {
        return count.get();
    }
}
```

**Severity:** 🟠 HIGH

### 3. Date/Calendar Thread Safety

**Anti-pattern:**
```java
// BAD: SimpleDateFormat is not thread-safe
private static final SimpleDateFormat FORMAT = new SimpleDateFormat("yyyy-MM-dd");

public String formatDate(Date date) {
    return FORMAT.format(date); // Race condition!
}
```

**Pattern:**
```java
// GOOD: Use DateTimeFormatter (immutable)
private static final DateTimeFormatter FORMAT =
    DateTimeFormatter.ofPattern("yyyy-MM-dd");

public String formatDate(LocalDate date) {
    return date.format(FORMAT);
}

// GOOD: Or ThreadLocal for legacy code
private static final ThreadLocal<SimpleDateFormat> FORMAT =
    ThreadLocal.withInitial(() -> new SimpleDateFormat("yyyy-MM-dd"));

public String formatDate(Date date) {
    return FORMAT.get().format(date);
}
```

**Severity:** 🟠 HIGH

## Stream API

### 1. Parallel Stream Misuse

**Anti-pattern:**
```java
// BAD: Parallel for small collections
List<String> names = Arrays.asList("a", "b", "c");
names.parallelStream()
    .map(String::toUpperCase)
    .collect(Collectors.toList());

// BAD: Parallel with side effects
List<String> results = new ArrayList<>();
items.parallelStream()
    .forEach(item -> results.add(process(item))); // Not thread-safe!
```

**Pattern:**
```java
// GOOD: Sequential for small collections
names.stream()
    .map(String::toUpperCase)
    .collect(Collectors.toList());

// GOOD: Collect for thread-safe accumulation
List<String> results = items.parallelStream()
    .map(this::process)
    .collect(Collectors.toList());
```

**Severity:** 🟡 MEDIUM

### 2. Side Effects in Streams

**Anti-pattern:**
```java
// BAD: Side effects in map
Map<String, Integer> counts = new HashMap<>();
items.stream()
    .map(item -> {
        counts.merge(item.getType(), 1, Integer::sum); // Side effect!
        return item;
    })
    .collect(Collectors.toList());
```

**Pattern:**
```java
// GOOD: Use proper collectors
Map<String, Long> counts = items.stream()
    .collect(Collectors.groupingBy(
        Item::getType,
        Collectors.counting()
    ));
```

**Severity:** 🟡 MEDIUM
