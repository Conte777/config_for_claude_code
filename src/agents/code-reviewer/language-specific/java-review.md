# Java Code Review Guide

This guide provides Java-specific patterns, idioms, anti-patterns, and best practices for code review.

## Java Idioms and Best Practices

### Naming Conventions

**✅ Good Practices:**
```java
// Classes: PascalCase
public class UserService {}

// Methods and variables: camelCase
public User getUser() {}
private String userName;

// Constants: UPPER_SNAKE_CASE
public static final int MAX_RETRY_COUNT = 3;

// Interfaces: PascalCase (don't prefix with 'I')
public interface PaymentProcessor {}  // ✅ Not IPaymentProcessor
```

### Exception Handling

**✅ Good Practices:**
```java
// Catch specific exceptions
try {
    processPayment(amount);
} catch (InsufficientFundsException e) {
    logger.error("Payment failed: insufficient funds", e);
    throw new PaymentProcessingException("Unable to process payment", e);
} catch (NetworkException e) {
    logger.error("Network error during payment", e);
    retry(amount);
}

// Try-with-resources for auto-closeable resources
try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
    return reader.readLine();
} // Automatically closed

// Multiple resources
try (FileInputStream input = new FileInputStream("input.txt");
     FileOutputStream output = new FileOutputStream("output.txt")) {
    // Process
}
```

**❌ Anti-Patterns:**
```java
// DON'T: Catch generic Exception
try {
    riskyOperation();
} catch (Exception e) {  // ❌ Too broad
    // Handle
}

// DON'T: Empty catch blocks
try {
    operation();
} catch (IOException e) {
    // ❌ Silent failure
}

// DON'T: Swallow exceptions without logging
try {
    criticalOperation();
} catch (Exception e) {
    return null;  // ❌ Exception information lost
}

// DON'T: Manually close resources
BufferedReader reader = new BufferedReader(new FileReader(path));
try {
    return reader.readLine();
} finally {
    reader.close();  // ❌ Use try-with-resources
}
```

### Null Safety and Optional

**✅ Good Practices (Java 8+):**
```java
// Use Optional for nullable return values
public Optional<User> findUser(Long id) {
    User user = repository.findById(id);
    return Optional.ofNullable(user);
}

// Chaining with Optional
String username = userService.findUser(id)
    .map(User::getName)
    .orElse("Anonymous");

// Optional with exception
User user = userService.findUser(id)
    .orElseThrow(() -> new UserNotFoundException("User not found: " + id));
```

**❌ Anti-Patterns:**
```java
// DON'T: Return null for collections
public List<User> getUsers() {
    return null;  // ❌ Return Collections.emptyList()
}

// DON'T: Use Optional as parameter
public void processUser(Optional<User> user) {  // ❌ Anti-pattern
    // Just use User and check for null
}

// DON'T: Call get() without checking
Optional<User> user = findUser(id);
return user.get();  // ❌ Can throw NoSuchElementException
```

### Streams API (Java 8+)

**✅ Good Practices:**
```java
// Filter and map
List<String> activeUserNames = users.stream()
    .filter(User::isActive)
    .map(User::getName)
    .collect(Collectors.toList());

// Reduce
int totalPoints = users.stream()
    .mapToInt(User::getPoints)
    .sum();

// Group by
Map<String, List<User>> usersByRole = users.stream()
    .collect(Collectors.groupingBy(User::getRole));

// Parallel streams for CPU-intensive operations
List<Result> results = items.parallelStream()
    .map(this::expensiveOperation)
    .collect(Collectors.toList());
```

**❌ Anti-Patterns:**
```java
// DON'T: Modify state in stream operations
users.stream()
    .forEach(user -> user.setProcessed(true));  // ❌ Side effects

// DON'T: Use parallel streams for IO operations
files.parallelStream()
    .forEach(this::processFile);  // ❌ IO is not CPU-bound

// DON'T: Collect to stream multiple times
Stream<User> stream = users.stream();
long count = stream.count();
List<User> list = stream.collect(Collectors.toList());  // ❌ Stream already consumed
```

### Immutability

**✅ Good Practices:**
```java
// Immutable class
public final class User {
    private final Long id;
    private final String name;
    private final List<String> roles;

    public User(Long id, String name, List<String> roles) {
        this.id = id;
        this.name = name;
        // Defensive copy
        this.roles = Collections.unmodifiableList(new ArrayList<>(roles));
    }

    // Only getters, no setters
    public Long getId() { return id; }
    public String getName() { return name; }
    public List<String> getRoles() { return roles; }
}

// Records (Java 14+)
public record User(Long id, String name, List<String> roles) {}
```

### Equals and HashCode

**✅ Good Practices:**
```java
@Override
public boolean equals(Object o) {
    if (this == o) return true;
    if (o == null || getClass() != o.getClass()) return false;
    User user = (User) o;
    return Objects.equals(id, user.id) &&
           Objects.equals(name, user.name);
}

@Override
public int hashCode() {
    return Objects.hash(id, name);
}
```

**❌ Anti-Patterns:**
```java
// DON'T: Override equals without hashCode
@Override
public boolean equals(Object o) {  // ❌ Also override hashCode!
    // ...
}

// DON'T: Use == for object comparison
if (user1 == user2) {  // ❌ Use equals()
    // ...
}
```

## Java Security Patterns

### SQL Injection Prevention

**✅ Good Practices:**
```java
// Use PreparedStatement with parameters
String sql = "SELECT * FROM users WHERE id = ?";
try (PreparedStatement stmt = conn.prepareStatement(sql)) {
    stmt.setLong(1, userId);
    ResultSet rs = stmt.executeQuery();
}

// JPA/Hibernate with named parameters
String jpql = "SELECT u FROM User u WHERE u.email = :email";
TypedQuery<User> query = em.createQuery(jpql, User.class);
query.setParameter("email", email);
User user = query.getSingleResult();
```

**❌ Anti-Patterns:**
```java
// DON'T: String concatenation in SQL
String sql = "SELECT * FROM users WHERE id = " + userId;  // ❌ SQL injection
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery(sql);

// DON'T: String formatting
String sql = String.format("SELECT * FROM users WHERE name = '%s'", userName);  // ❌
```

### Input Validation

**✅ Good Practices:**
```java
// Bean Validation (JSR 380)
public class UserDTO {
    @NotNull(message = "Name is required")
    @Size(min = 2, max = 50, message = "Name must be 2-50 characters")
    private String name;

    @Email(message = "Invalid email format")
    private String email;

    @Min(value = 0, message = "Age must be positive")
    private Integer age;
}

// Manual validation with whitelisting
private static final Pattern EMAIL_PATTERN =
    Pattern.compile("^[A-Za-z0-9+_.-]+@(.+)$");

public boolean isValidEmail(String email) {
    return email != null && EMAIL_PATTERN.matcher(email).matches();
}
```

### Authentication and Authorization

**✅ Good Practices:**
```java
// Password hashing with BCrypt
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

private BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

public String hashPassword(String plainPassword) {
    return encoder.encode(plainPassword);
}

public boolean verifyPassword(String plainPassword, String hashedPassword) {
    return encoder.matches(plainPassword, hashedPassword);
}

// Secure random for tokens
import java.security.SecureRandom;

public String generateToken() {
    SecureRandom random = new SecureRandom();
    byte[] bytes = new byte[32];
    random.nextBytes(bytes);
    return Base64.getEncoder().encodeToString(bytes);
}
```

**❌ Anti-Patterns:**
```java
// DON'T: Use Random for security
Random random = new Random();  // ❌ Not cryptographically secure
String token = String.valueOf(random.nextInt());

// DON'T: Store passwords in plaintext
user.setPassword(plainPassword);  // ❌ Hash it!

// DON'T: Use weak hashing
String hashed = MessageDigest.getInstance("MD5")
    .digest(password.getBytes());  // ❌ MD5 is broken
```

## Java Performance Patterns

### String Operations

**✅ Good Practices:**
```java
// StringBuilder for concatenation in loops
StringBuilder sb = new StringBuilder();
for (String s : strings) {
    sb.append(s);
}
String result = sb.toString();

// String.format() for complex formatting
String message = String.format(
    "User %s (ID: %d) has %d points",
    user.getName(), user.getId(), user.getPoints()
);
```

**❌ Anti-Patterns:**
```java
// DON'T: String concatenation in loops
String result = "";
for (String s : strings) {
    result += s;  // ❌ Creates new String each time
}

// DON'T: StringBuffer in single-threaded code
StringBuffer sb = new StringBuffer();  // ❌ Use StringBuilder
```

### Collections

**✅ Good Practices:**
```java
// Specify initial capacity when size is known
List<User> users = new ArrayList<>(expectedSize);
Map<Long, User> userMap = new HashMap<>(expectedSize);

// Use appropriate collection type
Set<String> uniqueNames = new HashSet<>();  // Fast lookup

// Immutable collections (Java 9+)
List<String> immutableList = List.of("a", "b", "c");
Map<String, Integer> immutableMap = Map.of("key", 1);
```

**❌ Anti-Patterns:**
```java
// DON'T: Use wrong collection type
List<String> names = new ArrayList<>();
if (names.contains(searchName)) {  // ❌ O(n), use Set for O(1)
    // ...
}

// DON'T: Synchronize when not needed
List<User> users = Collections.synchronizedList(new ArrayList<>());  // ❌ If single-threaded
```

### Resource Management

**✅ Good Practices:**
```java
// Always close resources
try (Connection conn = dataSource.getConnection();
     PreparedStatement stmt = conn.prepareStatement(sql)) {
    // Use connection
} // Automatically closed

// Connection pooling
@Configuration
public class DataSourceConfig {
    @Bean
    public DataSource dataSource() {
        HikariConfig config = new HikariConfig();
        config.setMaximumPoolSize(10);
        return new HikariDataSource(config);
    }
}
```

## Concurrency Patterns

**✅ Good Practices:**
```java
// Use concurrent collections
Map<String, User> cache = new ConcurrentHashMap<>();

// ExecutorService for thread management
ExecutorService executor = Executors.newFixedThreadPool(10);
try {
    List<Future<Result>> futures = new ArrayList<>();
    for (Task task : tasks) {
        futures.add(executor.submit(task));
    }
    // Collect results
    for (Future<Result> future : futures) {
        Result result = future.get();
    }
} finally {
    executor.shutdown();
}

// Synchronized block (minimize scope)
private final Object lock = new Object();

public void updateCounter() {
    synchronized (lock) {  // Only critical section
        counter++;
    }
}
```

**❌ Anti-Patterns:**
```java
// DON'T: Synchronize entire method unnecessarily
public synchronized void process() {  // ❌ Too broad
    // Only small part needs sync
}

// DON'T: Use Thread.sleep() for coordination
while (!ready) {
    Thread.sleep(100);  // ❌ Use proper synchronization
}
```

## Design Patterns and SOLID

**✅ Good Practices:**
```java
// Dependency Injection (Spring)
@Service
public class UserService {
    private final UserRepository repository;

    @Autowired
    public UserService(UserRepository repository) {
        this.repository = repository;
    }
}

// Builder pattern for complex objects
public class User {
    private final String name;
    private final String email;
    private final int age;

    private User(Builder builder) {
        this.name = builder.name;
        this.email = builder.email;
        this.age = builder.age;
    }

    public static class Builder {
        private String name;
        private String email;
        private int age;

        public Builder name(String name) {
            this.name = name;
            return this;
        }

        public Builder email(String email) {
            this.email = email;
            return this;
        }

        public Builder age(int age) {
            this.age = age;
            return this;
        }

        public User build() {
            return new User(this);
        }
    }
}
```

## Common Java Review Checklist

When reviewing Java code, check for:

- [ ] Exception handling: specific exceptions caught and logged
- [ ] Resources closed with try-with-resources
- [ ] PreparedStatement used for SQL (not string concatenation)
- [ ] Passwords hashed with BCrypt/PBKDF2 (not MD5/SHA1)
- [ ] SecureRandom used for security tokens (not Random)
- [ ] Optional used for nullable returns (not returning null)
- [ ] equals() and hashCode() overridden together
- [ ] StringBuilder used for string concatenation in loops
- [ ] Collections have appropriate initial capacity
- [ ] Concurrent collections used in multithreaded code
- [ ] Immutable classes are final with final fields
- [ ] Bean Validation annotations used (@NotNull, @Size, etc.)
- [ ] Streams not consumed multiple times
- [ ] No unnecessary synchronization
- [ ] Dependency injection used (not new keyword for services)
