# Java Libraries Quick Reference

## Spring Boot

### Basic Setup
**Purpose**: Production-ready Spring applications
**Best For**: Enterprise apps, microservices, REST APIs

```java
// Application entry point
@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
```

### REST Controller
```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping("/{id}")
    public ResponseEntity<UserDto> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<UserDto> createUser(@Valid @RequestBody CreateUserRequest request) {
        UserDto user = userService.create(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(user);
    }
}
```

### Service Layer
```java
@Service
@RequiredArgsConstructor
@Transactional
public class UserService {

    private final UserRepository repository;

    @Transactional(readOnly = true)
    public Optional<User> findById(Long id) {
        return repository.findById(id);
    }

    public User create(CreateUserRequest request) {
        User user = User.builder()
            .name(request.getName())
            .email(request.getEmail())
            .build();
        return repository.save(user);
    }
}
```

### Repository
```java
@Repository
public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);

    @Query("SELECT u FROM User u WHERE u.active = true")
    List<User> findActiveUsers();

    boolean existsByEmail(String email);
}
```

## Hibernate/JPA

### Entity Definition
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

    @Column(nullable = false, length = 100)
    private String name;

    @Column(nullable = false, unique = true)
    private String email;

    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL)
    private List<Order> orders;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id")
    private Company company;

    @CreationTimestamp
    private LocalDateTime createdAt;

    @UpdateTimestamp
    private LocalDateTime updatedAt;
}
```

## Lombok

### Common Annotations
```java
@Data                    // @Getter + @Setter + @ToString + @EqualsAndHashCode
@Getter / @Setter        // Generate getters/setters
@NoArgsConstructor       // No-args constructor
@AllArgsConstructor      // All-args constructor
@RequiredArgsConstructor // Constructor for final fields
@Builder                 // Builder pattern
@Slf4j                   // Logger field: log.info()
@Value                   // Immutable class

// Example usage
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UserDto {
    private Long id;
    private String name;
    private String email;
}

// Usage
UserDto user = UserDto.builder()
    .id(1L)
    .name("John")
    .email("john@example.com")
    .build();
```

## JUnit 5

### Basic Test
```java
@SpringBootTest
class UserServiceTest {

    @Autowired
    private UserService userService;

    @MockBean
    private UserRepository repository;

    @Test
    void shouldCreateUser_whenValidRequest() {
        // Given
        CreateUserRequest request = new CreateUserRequest("John", "john@example.com");
        User expected = User.builder().id(1L).name("John").build();

        when(repository.save(any(User.class))).thenReturn(expected);

        // When
        User result = userService.create(request);

        // Then
        assertThat(result).isNotNull();
        assertThat(result.getName()).isEqualTo("John");
        verify(repository, times(1)).save(any(User.class));
    }

    @ParameterizedTest
    @CsvSource({"john@example.com, true", "invalid, false"})
    void shouldValidateEmail(String email, boolean expected) {
        boolean result = EmailValidator.isValid(email);
        assertThat(result).isEqualTo(expected);
    }
}
```

## Jackson (JSON Processing)

```java
import com.fasterxml.jackson.databind.ObjectMapper;

ObjectMapper mapper = new ObjectMapper();

// Object to JSON
String json = mapper.writeValueAsString(user);

// JSON to Object
User user = mapper.readValue(json, User.class);

// Custom naming
@JsonProperty("user_name")
private String userName;

// Ignore fields
@JsonIgnore
private String password;

// Date format
@JsonFormat(pattern = "yyyy-MM-dd")
private LocalDate birthDate;
```

## Apache Commons

### Commons Lang
```java
import org.apache.commons.lang3.StringUtils;

StringUtils.isEmpty(str);
StringUtils.isBlank(str);
StringUtils.capitalize(str);
StringUtils.join(list, ", ");
```

### Commons Collections
```java
import org.apache.commons.collections4.CollectionUtils;

CollectionUtils.isEmpty(list);
CollectionUtils.isNotEmpty(list);
CollectionUtils.intersection(list1, list2);
```

## Validation

```java
import jakarta.validation.constraints.*;

public class CreateUserRequest {

    @NotBlank(message = "Name is required")
    @Size(min = 2, max = 100)
    private String name;

    @NotBlank
    @Email(message = "Invalid email")
    private String email;

    @Min(18)
    @Max(150)
    private Integer age;

    @Pattern(regexp = "^\\+?[1-9]\\d{1,14}$")
    private String phoneNumber;
}
```

## RestTemplate / WebClient

### RestTemplate (Synchronous)
```java
@Service
public class ApiClient {
    private final RestTemplate restTemplate;

    public User getUser(Long id) {
        return restTemplate.getForObject(
            "https://api.example.com/users/" + id,
            User.class
        );
    }

    public User createUser(CreateUserRequest request) {
        return restTemplate.postForObject(
            "https://api.example.com/users",
            request,
            User.class
        );
    }
}
```

### WebClient (Reactive)
```java
@Service
public class ReactiveApiClient {
    private final WebClient webClient;

    public Mono<User> getUser(Long id) {
        return webClient.get()
            .uri("/users/{id}", id)
            .retrieve()
            .bodyToMono(User.class);
    }
}
```
