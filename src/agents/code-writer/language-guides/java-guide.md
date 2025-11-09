# Java Language Guide

Complete reference for writing modern, maintainable Java code following Google Java Style Guide and industry best practices (Java 17+).

## Style Guide & Formatting

### Google Java Style Guide Essentials

**This guide follows Google Java Style Guide** (updated 2018), which is more current than Oracle Code Conventions (1999).

### Braces

**K&R Style** (Kernighan and Ritchie):
- Opening brace on same line
- Closing brace on its own line
- Used with `if`, `else`, `for`, `do`, `while` - even when body is empty

```java
// Good
if (condition) {
    doSomething();
} else {
    doSomethingElse();
}

// Bad
if (condition)
{
    doSomething();
}
```

### Indentation and Whitespace

**Indentation**: +2 spaces for each new block
**Line length**: 100 characters (exceptions: package/import, URLs, long identifiers)
**Whitespace**: ASCII spaces only (0x20), never tabs

```java
// Good - 2 space indentation
public class Example {
  public void method() {
    if (condition) {
      doSomething();
    }
  }
}

// Bad - tabs or 4 spaces
public class Example {
    public void method() {
        if (condition) {
            doSomething();
        }
    }
}
```

### Line Wrapping

**When to break**:
- After commas
- Before operators
- Higher-level breaks preferred
- Continuation lines indented at least +4 spaces

```java
// Good
String message = "This is a very long message that needs to be "
    + "split across multiple lines for better readability.";

// Method with many parameters
public void processData(
    String firstName,
    String lastName,
    int age,
    String address) {
    // Implementation
}
```

## Naming Conventions

### Classes and Interfaces

**UpperCamelCase** for class names:

```java
// Good
public class UserService { }
public class HttpClient { }
public interface PaymentProcessor { }

// Bad
public class userService { }
public class HTTPClient { }  // Don't capitalize all letters in acronyms
```

### Methods

**lowerCamelCase** verbs for method names:

```java
// Good
public void sendMessage() { }
public User findById(Long id) { }
public boolean isActive() { }

// Bad
public void SendMessage() { }
public User find_by_id(Long id) { }
```

### Variables

**lowerCamelCase** for variables and parameters:

```java
// Good
private String userName;
private int itemCount;

// Bad
private String user_name;
private String UserName;
```

### Constants

**UPPER_SNAKE_CASE** for static final immutable fields:

```java
// Good
public static final int MAX_COUNT = 100;
public static final String DEFAULT_NAME = "Unknown";

// Bad - not truly constant (mutable)
public static final List<String> NAMES = new ArrayList<>();
```

### Packages

**All lowercase**, consecutive words concatenated:

```java
// Good
package com.example.deepspace;

// Bad
package com.example.deepSpace;
package com.example.deep_space;
```

## Modern Java Features (17 & 21)

### Records (Java 16+)

**Use records for immutable data carriers**:

```java
// Good - concise, clear intent
public record User(String name, String email, int age) {}

// Usage
User user = new User("John", "john@example.com", 30);
String name = user.name();

// Bad - traditional approach for simple DTOs
public class User {
    private final String name;
    private final String email;
    private final int age;

    public User(String name, String email, int age) {
        this.name = name;
        this.email = email;
        this.age = age;
    }

    // Getters...
}
```

**Records with validation**:

```java
public record User(String name, String email) {
    public User {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Name cannot be blank");
        }
        if (email == null || !email.contains("@")) {
            throw new IllegalArgumentException("Invalid email");
        }
    }
}
```

### Enhanced Switch Expressions (Java 17)

**Always use arrow syntax** for new code:

```java
// Good - arrow style (Java 17+)
String result = switch (day) {
    case MONDAY, FRIDAY -> "Busy day";
    case TUESDAY -> "Meeting day";
    case SATURDAY, SUNDAY -> "Weekend";
    default -> "Regular day";
};

// Bad - old style with fallthrough risk
String result;
switch (day) {
    case MONDAY:
    case FRIDAY:
        result = "Busy day";
        break;
    // ...
}
```

### Pattern Matching

**Pattern matching for instanceof** (Java 16+):

```java
// Good
if (obj instanceof String str) {
    System.out.println(str.toUpperCase());
}

// Bad - old style
if (obj instanceof String) {
    String str = (String) obj;
    System.out.println(str.toUpperCase());
}
```

**Pattern matching for switch** (Java 21+):

```java
// Good
String formatted = switch (obj) {
    case Integer i -> String.format("int %d", i);
    case Long l -> String.format("long %d", l);
    case String s -> String.format("String %s", s);
    default -> obj.toString();
};
```

### Text Blocks (Java 15+)

**For multi-line strings**:

```java
// Good
String json = """
    {
        "name": "John",
        "age": 30
    }
    """;

// Bad - concatenation
String json = "{\n" +
    "    \"name\": \"John\",\n" +
    "    \"age\": 30\n" +
    "}";
```

## Idiomatic Patterns

### Exception Handling

**Always catch specific exceptions**:

```java
// Good
try {
    processData();
} catch (FileNotFoundException e) {
    log.error("File not found: {}", e.getMessage());
} catch (IOException e) {
    log.error("IO error: {}", e.getMessage());
}

// Bad - catching general Exception
try {
    processData();
} catch (Exception e) {
    // Too broad
}
```

**NEVER silently ignore exceptions**:

```java
// Bad - empty catch
try {
    riskyOperation();
} catch (Exception e) {
    // Silent failure
}

// Good - at minimum, log it
try {
    riskyOperation();
} catch (Exception e) {
    log.warn("Operation failed, using default", e);
    useDefault();
}

// Good - if truly intentional, document it
try {
    cleanup();
} catch (Exception e) {
    // Intentionally ignored - cleanup is best-effort
}
```

### Optional Pattern

**Use Optional for nullable returns**:

```java
// Good
public Optional<User> findById(Long id) {
    return Optional.ofNullable(database.get(id));
}

// Usage
Optional<User> user = findById(123L);
user.ifPresent(u -> System.out.println(u.name()));

// With default
String name = findById(123L)
    .map(User::name)
    .orElse("Unknown");

// Bad - returning null
public User findById(Long id) {
    return database.get(id);  // Can return null
}
```

### Stream API

**Use streams for collection operations**:

```java
// Good
List<String> names = users.stream()
    .filter(User::isActive)
    .map(User::getName)
    .sorted()
    .collect(Collectors.toList());

// Collectors
Map<String, User> userMap = users.stream()
    .collect(Collectors.toMap(User::getId, Function.identity()));

// Bad - manual iteration
List<String> names = new ArrayList<>();
for (User user : users) {
    if (user.isActive()) {
        names.add(user.getName());
    }
}
Collections.sort(names);
```

## Programming Practices

### Annotations

**@Override - always use when overriding**:

```java
// Good
@Override
public String toString() {
    return "User: " + name;
}

// Bad - missing @Override
public String toString() {
    return "User: " + name;
}
```

**Annotation placement**:
- Type-use annotations: before the type
- Declaration annotations: on separate line

```java
// Type-use annotation
public String process(@NonNull String input) { }

// Declaration annotation
@Deprecated
public void oldMethod() { }

@RequestMapping("/users")
@Validated
public class UserController { }
```

### Static Members

**Access static members through class name**:

```java
// Good
String value = Constants.DEFAULT_VALUE;

// Bad - through instance
Constants instance = new Constants();
String value = instance.DEFAULT_VALUE;
```

### Javadoc

**Document all public APIs**:

```java
/**
 * Processes user registration.
 *
 * @param request the registration request containing user details
 * @return the created user
 * @throws ValidationException if request validation fails
 * @throws DuplicateEmailException if email already exists
 */
public User register(RegistrationRequest request)
    throws ValidationException, DuplicateEmailException {
    // Implementation
}
```

**Block tags order**: `@param`, `@return`, `@throws`, `@deprecated`

## Spring Boot Best Practices

### Controller-Service-Repository Pattern

**Controllers**: Handle HTTP, not business logic

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor  // Lombok - generates constructor
public class UserController {

    private final UserService userService;

    @GetMapping("/{id}")
    public ResponseEntity<UserResponse> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(this::toResponse)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<UserResponse> createUser(
        @Valid @RequestBody CreateUserRequest request) {
        User user = userService.create(request);
        return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(toResponse(user));
    }

    private UserResponse toResponse(User user) {
        return new UserResponse(user.getId(), user.getName(), user.getEmail());
    }
}
```

### Service Layer

**Contains business logic**:

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional(readOnly = true)
    public Optional<User> findById(Long id) {
        return userRepository.findById(id);
    }

    @Transactional
    public User create(CreateUserRequest request) {
        validateEmail(request.email());

        User user = User.builder()
            .name(request.name())
            .email(request.email())
            .password(passwordEncoder.encode(request.password()))
            .build();

        return userRepository.save(user);
    }

    private void validateEmail(String email) {
        if (userRepository.existsByEmail(email)) {
            throw new DuplicateEmailException("Email already exists: " + email);
        }
    }
}
```

### Repository Layer

**Data access with Spring Data JPA**:

```java
@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    @Query("SELECT u FROM User u WHERE u.active = true")
    List<User> findActiveUsers();
}
```

### Constructor Injection

**Always use constructor injection** (not field injection):

```java
// Good - constructor injection
@Service
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;

    public UserService(UserRepository userRepository, EmailService emailService) {
        this.userRepository = userRepository;
        this.emailService = emailService;
    }
}

// Better - Lombok
@Service
@RequiredArgsConstructor
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;
}

// Bad - field injection
@Service
public class UserService {
    @Autowired
    private UserRepository userRepository;
}
```

### Entity Classes

**JPA entities with Lombok**:

```java
@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}
```

## Testing with JUnit 5

### Test Structure (Given-When-Then)

```java
@SpringBootTest
class UserServiceTest {

    @Autowired
    private UserService userService;

    @MockBean
    private UserRepository userRepository;

    @Test
    void shouldCreateUser_whenValidRequest() {
        // Given
        CreateUserRequest request = new CreateUserRequest(
            "John Doe",
            "john@example.com",
            "password123"
        );

        User expected = User.builder()
            .id(1L)
            .name("John Doe")
            .email("john@example.com")
            .build();

        when(userRepository.save(any(User.class))).thenReturn(expected);

        // When
        User result = userService.create(request);

        // Then
        assertThat(result).isNotNull();
        assertThat(result.getName()).isEqualTo("John Doe");
        assertThat(result.getEmail()).isEqualTo("john@example.com");
    }

    @Test
    void shouldThrowException_whenEmailExists() {
        // Given
        CreateUserRequest request = new CreateUserRequest(
            "John Doe",
            "existing@example.com",
            "password123"
        );

        when(userRepository.existsByEmail("existing@example.com"))
            .thenReturn(true);

        // When & Then
        assertThatThrownBy(() -> userService.create(request))
            .isInstanceOf(DuplicateEmailException.class)
            .hasMessageContaining("Email already exists");
    }
}
```

### Parameterized Tests

```java
@ParameterizedTest
@ValueSource(strings = {"", " ", "invalid-email", "@example.com"})
void shouldRejectInvalidEmails(String email) {
    CreateUserRequest request = new CreateUserRequest("John", email, "pass");

    assertThatThrownBy(() -> userService.create(request))
        .isInstanceOf(ValidationException.class);
}

@ParameterizedTest
@CsvSource({
    "john@example.com, true",
    "invalid, false",
    "@example.com, false"
})
void shouldValidateEmail(String email, boolean expected) {
    boolean result = EmailValidator.isValid(email);
    assertThat(result).isEqualTo(expected);
}
```

### AssertJ Assertions

**Use AssertJ for fluent assertions**:

```java
// Good - AssertJ
assertThat(user.getName()).isEqualTo("John");
assertThat(users).hasSize(3)
    .extracting(User::getName)
    .containsExactly("John", "Jane", "Bob");

// Bad - JUnit assertions
assertEquals("John", user.getName());
assertEquals(3, users.size());
```

## Code Templates

### REST Controller Template

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Slf4j
public class UserController {

    private final UserService userService;

    @GetMapping
    public ResponseEntity<List<UserResponse>> getAllUsers() {
        List<User> users = userService.findAll();
        return ResponseEntity.ok(users.stream()
            .map(this::toResponse)
            .toList());
    }

    @GetMapping("/{id}")
    public ResponseEntity<UserResponse> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(this::toResponse)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<UserResponse> createUser(
        @Valid @RequestBody CreateUserRequest request) {
        User user = userService.create(request);
        return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(toResponse(user));
    }

    @PutMapping("/{id}")
    public ResponseEntity<UserResponse> updateUser(
        @PathVariable Long id,
        @Valid @RequestBody UpdateUserRequest request) {
        return userService.update(id, request)
            .map(this::toResponse)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteUser(@PathVariable Long id) {
        userService.delete(id);
        return ResponseEntity.noContent().build();
    }

    private UserResponse toResponse(User user) {
        return new UserResponse(
            user.getId(),
            user.getName(),
            user.getEmail()
        );
    }
}
```

### Exception Handler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<ErrorResponse> handleValidation(ValidationException ex) {
        log.warn("Validation error: {}", ex.getMessage());
        ErrorResponse error = new ErrorResponse(
            "VALIDATION_ERROR",
            ex.getMessage()
        );
        return ResponseEntity.badRequest().body(error);
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(ResourceNotFoundException ex) {
        ErrorResponse error = new ErrorResponse(
            "NOT_FOUND",
            ex.getMessage()
        );
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneral(Exception ex) {
        log.error("Unexpected error", ex);
        ErrorResponse error = new ErrorResponse(
            "INTERNAL_ERROR",
            "An unexpected error occurred"
        );
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(error);
    }

    private record ErrorResponse(String code, String message) {}
}
```

## Common Anti-Patterns to Avoid

### 1. God Class

```java
// Bad - does everything
public class UserManager {
    public User createUser() { }
    public void sendEmail() { }
    public void generateReport() { }
    public void processPayment() { }
}

// Good - single responsibility
public class UserService { }
public class EmailService { }
public class ReportService { }
public class PaymentService { }
```

### 2. Null Checks Everywhere

```java
// Bad
public String getUserName(User user) {
    if (user != null) {
        if (user.getName() != null) {
            return user.getName();
        }
    }
    return "Unknown";
}

// Good - use Optional
public String getUserName(Optional<User> user) {
    return user
        .map(User::getName)
        .orElse("Unknown");
}
```

### 3. Catching and Rethrowing

```java
// Bad
try {
    doSomething();
} catch (Exception e) {
    throw e;  // Pointless
}

// Good - add context or don't catch
try {
    doSomething();
} catch (IOException e) {
    throw new ServiceException("Failed to process file", e);
}
```

## Security Best Practices

### Password Encoding

```java
@Configuration
public class SecurityConfig {

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}

// Usage
@Service
@RequiredArgsConstructor
public class UserService {
    private final PasswordEncoder passwordEncoder;

    public User create(CreateUserRequest request) {
        String encodedPassword = passwordEncoder.encode(request.password());
        // Never store plain text passwords!
    }
}
```

### Input Validation

```java
public record CreateUserRequest(
    @NotBlank(message = "Name is required")
    @Size(min = 2, max = 100)
    String name,

    @NotBlank(message = "Email is required")
    @Email(message = "Invalid email format")
    String email,

    @NotBlank(message = "Password is required")
    @Size(min = 8, message = "Password must be at least 8 characters")
    String password
) {}
```

### SQL Injection Prevention

```java
// Good - parameterized query
@Query("SELECT u FROM User u WHERE u.email = :email")
Optional<User> findByEmail(@Param("email") String email);

// Bad - string concatenation (vulnerable to SQL injection)
@Query("SELECT u FROM User u WHERE u.email = '" + email + "'")
```

## Quick Reference

### Common Imports

```java
// Spring Boot
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.jpa.repository.JpaRepository;

// Lombok
import lombok.RequiredArgsConstructor;
import lombok.Data;
import lombok.Builder;

// JUnit 5
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

// Java built-in
import java.util.*;
import java.time.LocalDateTime;
import java.util.stream.Collectors;
```

### Lombok Annotations Quick Reference

```java
@Data                    // @Getter + @Setter + @ToString + @EqualsAndHashCode
@Getter / @Setter        // Generate getters/setters
@NoArgsConstructor       // No-args constructor
@AllArgsConstructor      // All-args constructor
@RequiredArgsConstructor // Constructor for final fields
@Builder                 // Builder pattern
@Slf4j                   // Logger field: log.info()
```
