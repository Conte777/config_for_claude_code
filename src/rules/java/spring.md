# Java + Spring Patterns Reference

Паттерны и anti-patterns для Spring Framework.

## Dependency Injection

### 1. Field Injection Anti-Pattern

**Anti-pattern:**
```java
// BAD: Field injection
@Service
public class UserService {
    @Autowired
    private UserRepository userRepository;

    @Autowired
    private EmailService emailService;
}
```

**Проблемы:**
- Невозможно создать immutable объекты
- Сложнее тестировать (нужен reflection)
- Скрывает зависимости
- Возможен null если Spring не инициализировал

**Pattern:**
```java
// GOOD: Constructor injection
@Service
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;

    public UserService(UserRepository userRepository, EmailService emailService) {
        this.userRepository = userRepository;
        this.emailService = emailService;
    }
}

// GOOD: Lombok for brevity
@Service
@RequiredArgsConstructor
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;
}
```

**Severity:** 🟡 MEDIUM

### 2. Circular Dependencies

**Anti-pattern:**
```java
// BAD: Circular dependency
@Service
public class ServiceA {
    private final ServiceB serviceB;

    public ServiceA(ServiceB serviceB) {
        this.serviceB = serviceB;
    }
}

@Service
public class ServiceB {
    private final ServiceA serviceA; // Cycle!

    public ServiceB(ServiceA serviceA) {
        this.serviceA = serviceA;
    }
}
```

**Pattern:**
```java
// GOOD: Break cycle with interface
public interface ServiceAOperations {
    void doSomething();
}

@Service
public class ServiceA implements ServiceAOperations {
    private final ServiceB serviceB;
    // ...
}

@Service
public class ServiceB {
    private final ServiceAOperations serviceA;
    // ...
}

// GOOD: Or use @Lazy
@Service
public class ServiceB {
    private final ServiceA serviceA;

    public ServiceB(@Lazy ServiceA serviceA) {
        this.serviceA = serviceA;
    }
}
```

**Severity:** 🟠 HIGH

## Transactions

### 1. Self-Invocation Trap

**Anti-pattern:**
```java
// BAD: @Transactional ignored on self-invocation
@Service
public class UserService {
    public void processUsers(List<Long> ids) {
        for (Long id : ids) {
            processUser(id); // @Transactional ignored!
        }
    }

    @Transactional
    public void processUser(Long id) {
        // This runs WITHOUT transaction when called from processUsers
    }
}
```

**Pattern:**
```java
// GOOD: Inject self
@Service
public class UserService {
    private final UserService self;

    public UserService(@Lazy UserService self) {
        this.self = self;
    }

    public void processUsers(List<Long> ids) {
        for (Long id : ids) {
            self.processUser(id); // Now @Transactional works
        }
    }

    @Transactional
    public void processUser(Long id) {
        // Runs with transaction
    }
}

// GOOD: Or separate into two services
@Service
public class UserBatchService {
    private final UserService userService;

    public void processUsers(List<Long> ids) {
        for (Long id : ids) {
            userService.processUser(id);
        }
    }
}
```

**Severity:** 🔴 CRITICAL

### 2. Transaction Propagation

**Anti-pattern:**
```java
// BAD: Unexpected rollback
@Transactional
public void outerMethod() {
    try {
        innerMethod(); // Marked for rollback
    } catch (Exception e) {
        // Caught, but transaction still rolls back!
        log.error("Error", e);
    }
}

@Transactional
public void innerMethod() {
    throw new RuntimeException("Error");
}
```

**Pattern:**
```java
// GOOD: Use REQUIRES_NEW for independent transaction
@Transactional
public void outerMethod() {
    try {
        innerMethod();
    } catch (Exception e) {
        log.error("Error", e);
        // Outer transaction continues
    }
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
public void innerMethod() {
    throw new RuntimeException("Error");
    // Only this transaction rolls back
}
```

**Severity:** 🟠 HIGH

### 3. Checked Exceptions Don't Rollback

**Anti-pattern:**
```java
// BAD: Checked exception doesn't trigger rollback
@Transactional
public void process() throws BusinessException {
    repository.save(entity);
    throw new BusinessException("Error"); // No rollback by default!
}
```

**Pattern:**
```java
// GOOD: Specify rollback for checked exceptions
@Transactional(rollbackFor = BusinessException.class)
public void process() throws BusinessException {
    repository.save(entity);
    throw new BusinessException("Error"); // Now rolls back
}

// GOOD: Or use unchecked exceptions
@Transactional
public void process() {
    repository.save(entity);
    throw new BusinessRuntimeException("Error"); // Rolls back
}
```

**Severity:** 🟠 HIGH

## Security

### 1. @PreAuthorize Configuration

**Anti-pattern:**
```java
// BAD: Missing @EnableMethodSecurity
@RestController
public class AdminController {
    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/admin/users")
    public List<User> getAllUsers() {
        return userService.findAll();
        // @PreAuthorize ignored without @EnableMethodSecurity!
    }
}
```

**Pattern:**
```java
// GOOD: Enable method security
@Configuration
@EnableMethodSecurity
public class SecurityConfig {
    // ...
}

@RestController
public class AdminController {
    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/admin/users")
    public List<User> getAllUsers() {
        return userService.findAll();
    }
}
```

**Severity:** 🔴 CRITICAL

### 2. CSRF Configuration

**Anti-pattern:**
```java
// BAD: Disabling CSRF for all endpoints
@Configuration
public class SecurityConfig {
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf().disable(); // Dangerous for web apps!
        return http.build();
    }
}
```

**Pattern:**
```java
// GOOD: Disable only for APIs, keep for web
@Configuration
public class SecurityConfig {
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf
                .ignoringRequestMatchers("/api/**") // API uses JWT
                // Web forms still protected
            );
        return http.build();
    }
}
```

**Severity:** 🟠 HIGH

## JPA / Data

### 1. N+1 Query Problem

**Anti-pattern:**
```java
// BAD: N+1 queries
@Entity
public class Order {
    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
    private List<OrderItem> items;
}

// In service:
List<Order> orders = orderRepository.findAll();
for (Order order : orders) {
    order.getItems().size(); // +1 query per order!
}
```

**Pattern:**
```java
// GOOD: Fetch join
public interface OrderRepository extends JpaRepository<Order, Long> {
    @Query("SELECT o FROM Order o JOIN FETCH o.items")
    List<Order> findAllWithItems();
}

// GOOD: EntityGraph
@EntityGraph(attributePaths = {"items"})
List<Order> findAll();

// GOOD: Batch fetching
@Entity
public class Order {
    @OneToMany(mappedBy = "order")
    @BatchSize(size = 100)
    private List<OrderItem> items;
}
```

**Severity:** 🟡 MEDIUM

### 2. Lazy Loading Outside Session

**Anti-pattern:**
```java
// BAD: LazyInitializationException
@Transactional
public Order getOrder(Long id) {
    return orderRepository.findById(id).orElseThrow();
}

// In controller (outside transaction):
Order order = orderService.getOrder(1L);
order.getItems(); // LazyInitializationException!
```

**Pattern:**
```java
// GOOD: Initialize within transaction
@Transactional
public Order getOrderWithItems(Long id) {
    Order order = orderRepository.findById(id).orElseThrow();
    Hibernate.initialize(order.getItems());
    return order;
}

// GOOD: Use DTO
@Transactional
public OrderDTO getOrder(Long id) {
    Order order = orderRepository.findById(id).orElseThrow();
    return OrderDTO.from(order); // Copy data
}

// GOOD: Fetch join
@Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.id = :id")
Optional<Order> findByIdWithItems(@Param("id") Long id);
```

**Severity:** 🟠 HIGH

## REST Controller

### 1. Missing Validation

**Anti-pattern:**
```java
// BAD: No input validation
@PostMapping("/users")
public User createUser(@RequestBody UserRequest request) {
    return userService.create(request); // Invalid data saved!
}
```

**Pattern:**
```java
// GOOD: Use validation annotations
public class UserRequest {
    @NotBlank
    @Size(min = 2, max = 100)
    private String name;

    @Email
    @NotNull
    private String email;
}

@PostMapping("/users")
public User createUser(@Valid @RequestBody UserRequest request) {
    return userService.create(request);
}
```

**Severity:** 🟠 HIGH

### 2. Exception Handling

**Anti-pattern:**
```java
// BAD: Exposing internal errors
@GetMapping("/users/{id}")
public User getUser(@PathVariable Long id) {
    return userRepository.findById(id)
        .orElseThrow(); // Returns 500 with stack trace!
}
```

**Pattern:**
```java
// GOOD: Global exception handler
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(EntityNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(EntityNotFoundException e) {
        return ResponseEntity
            .status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse("Resource not found", e.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneral(Exception e) {
        log.error("Unexpected error", e);
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("Internal error", "Please try again later"));
    }
}
```

**Severity:** 🟡 MEDIUM
