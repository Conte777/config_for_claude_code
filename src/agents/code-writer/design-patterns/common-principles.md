# Common Programming Principles

Essential software development principles that guide clean, maintainable code: DRY, KISS, and YAGNI.

## DRY - Don't Repeat Yourself

**Principle**: Every piece of knowledge must have a single, unambiguous, authoritative representation within a system.

### Why It Matters
- Changes need to be made in only one place
- Reduces bugs from inconsistent copies
- Easier to maintain and understand
- Improves code reusability

### Bad Example (Repetition)

**Go**:
```go
// Bad - repeated validation logic
func CreateUser(name, email string) error {
    if len(name) < 2 {
        return errors.New("name too short")
    }
    if !strings.Contains(email, "@") {
        return errors.New("invalid email")
    }
    // Create user
    return nil
}

func UpdateUser(id int, name, email string) error {
    if len(name) < 2 {
        return errors.New("name too short")
    }
    if !strings.Contains(email, "@") {
        return errors.New("invalid email")
    }
    // Update user
    return nil
}
```

### Good Example (DRY)

**Go**:
```go
// Good - validation logic in one place
func validateUserData(name, email string) error {
    if len(name) < 2 {
        return errors.New("name too short")
    }
    if !strings.Contains(email, "@") {
        return errors.New("invalid email")
    }
    return nil
}

func CreateUser(name, email string) error {
    if err := validateUserData(name, email); err != nil {
        return err
    }
    // Create user
    return nil
}

func UpdateUser(id int, name, email string) error {
    if err := validateUserData(name, email); err != nil {
        return err
    }
    // Update user
    return nil
}
```

**Java**:
```java
// Good - using service layer
public class UserService {
    public void createUser(String name, String email) throws ValidationException {
        validateUser(name, email);
        // Create logic
    }

    public void updateUser(Long id, String name, String email) throws ValidationException {
        validateUser(name, email);
        // Update logic
    }

    private void validateUser(String name, String email) throws ValidationException {
        if (name.length() < 2) {
            throw new ValidationException("Name too short");
        }
        if (!email.contains("@")) {
            throw new ValidationException("Invalid email");
        }
    }
}
```

**Python**:
```python
# Good - validator class
class UserValidator:
    @staticmethod
    def validate(name: str, email: str):
        if len(name) < 2:
            raise ValueError("Name too short")
        if "@" not in email:
            raise ValueError("Invalid email")

class UserService:
    def create_user(self, name: str, email: str):
        UserValidator.validate(name, email)
        # Create logic

    def update_user(self, user_id: int, name: str, email: str):
        UserValidator.validate(name, email)
        # Update logic
```

### When DRY Applies
✅ Business logic
✅ Validation rules
✅ Data transformations
✅ Configuration values

### When NOT to Apply DRY
❌ Coincidental duplication (different contexts)
❌ Over-abstraction that reduces readability
❌ Test code (some duplication acceptable for clarity)

## KISS - Keep It Simple, Stupid

**Principle**: Systems work best when they're kept simple. Simplicity should be a key goal in design.

### Why It Matters
- Simple code is easier to understand
- Fewer bugs hide in simple code
- Easier to maintain and modify
- Faster to write and test

### Bad Example (Complex)

**Java**:
```java
// Bad - over-engineered
public interface StrategyFactory {
    Strategy createStrategy(StrategyType type);
}

public class ConcreteStrategyFactory implements StrategyFactory {
    public Strategy createStrategy(StrategyType type) {
        return StrategyRegistry.getInstance()
            .getStrategyBuilder(type)
            .withDefaults()
            .build();
    }
}

public class DiscountCalculator {
    private StrategyFactory factory;

    public double calculate(double amount, StrategyType type) {
        Strategy strategy = factory.createStrategy(type);
        return strategy.execute(amount);
    }
}
```

### Good Example (Simple)

**Java**:
```java
// Good - straightforward
public class DiscountCalculator {
    public double calculate(double amount, String customerType) {
        if (customerType.equals("regular")) {
            return amount * 0.9;
        } else if (customerType.equals("premium")) {
            return amount * 0.8;
        }
        return amount;
    }
}
```

**Python**:
```python
# Bad - unnecessarily complex
from abc import ABC, abstractmethod

class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: float) -> float:
        pass

class RegularStrategy(DiscountStrategy):
    def calculate(self, amount: float) -> float:
        return amount * 0.9

class PremiumStrategy(DiscountStrategy):
    def calculate(self, amount: float) -> float:
        return amount * 0.8

class StrategyFactory:
    @staticmethod
    def create(customer_type: str) -> DiscountStrategy:
        if customer_type == "regular":
            return RegularStrategy()
        return PremiumStrategy()

# Good - simple and clear
def calculate_discount(amount: float, customer_type: str) -> float:
    discounts = {
        "regular": 0.9,
        "premium": 0.8
    }
    return amount * discounts.get(customer_type, 1.0)
```

**Go**:
```go
// Bad - over-complicated
type CalculatorInterface interface {
    Calculate(value float64) (float64, error)
}

type CalculatorFactory struct{}

func (cf *CalculatorFactory) Create(operation string) CalculatorInterface {
    // Complex factory logic
}

// Good - simple
func Calculate(a, b float64, operation string) (float64, error) {
    switch operation {
    case "add":
        return a + b, nil
    case "subtract":
        return a - b, nil
    default:
        return 0, errors.New("unknown operation")
    }
}
```

### KISS Guidelines
✅ Start with the simplest solution
✅ Add complexity only when needed
✅ Prefer clear code over clever code
✅ Use standard patterns, not exotic ones
✅ Write code others can understand

### Complexity Warning Signs
❌ More than 3 levels of nesting
❌ Functions longer than ~20 lines
❌ Complex inheritance hierarchies
❌ Too many design patterns in small codebase

## YAGNI - You Aren't Gonna Need It

**Principle**: Don't implement functionality until you actually need it.

### Why It Matters
- Saves development time
- Reduces code complexity
- Avoids wrong assumptions
- Keeps codebase lean

### Bad Example (Premature Features)

**Java**:
```java
// Bad - implementing features "just in case"
public class User {
    private Long id;
    private String name;
    private String email;

    // Maybe we'll need these someday?
    private String phoneNumber;
    private String address;
    private String city;
    private String country;
    private String zipCode;
    private LocalDateTime lastLoginDate;
    private Integer loginCount;
    private String preferredLanguage;
    private String timezone;
    private Boolean emailVerified;
    private Boolean phoneVerified;
    private String profilePicture;
    private String bio;
    // ... 20 more fields
}
```

### Good Example (Only What's Needed)

**Java**:
```java
// Good - only current requirements
public class User {
    private Long id;
    private String name;
    private String email;
    // Add more fields when actually needed
}
```

**Python**:
```python
# Bad - over-engineered for future needs
class UserRepository:
    def find_by_id(self, user_id: int):
        pass

    def find_by_email(self, email: str):
        pass

    # These aren't used yet, but maybe someday...
    def find_by_phone(self, phone: str):
        pass

    def find_by_name_fuzzy(self, name: str):
        pass

    def find_by_registration_date_range(self, start, end):
        pass

    def find_by_last_login_before(self, date):
        pass

# Good - only implemented methods
class UserRepository:
    def find_by_id(self, user_id: int):
        pass

    def find_by_email(self, email: str):
        pass
    # Add other methods when requirements emerge
```

**Go**:
```go
// Bad - caching layer not needed yet
type UserService struct {
    repo  *UserRepository
    cache *Cache           // Not using this yet
    queue *MessageQueue    // Not using this yet
    log   *Logger
}

// Good - only what's needed now
type UserService struct {
    repo *UserRepository
    log  *Logger
}
```

### YAGNI Guidelines
✅ Implement features when needed, not when anticipated
✅ Design for current requirements
✅ Refactor when new requirements emerge
✅ Trust that you can add features later

### Not YAGNI (These ARE needed)
✓ Security measures
✓ Error handling
✓ Logging
✓ Basic validation
✓ Tests

## Combining Principles

### Real-World Example

**Problem**: User registration with email sending

**Bad** (Violates all three):
```python
# Bad - repetitive, complex, over-engineered
class UserRegistrationHandler:
    def register_standard_user(self, name, email, password):
        # Validation
        if len(name) < 2:
            raise ValueError("Name too short")
        if "@" not in email:
            raise ValueError("Invalid email")

        # Save user
        user = User(name, email, password)
        db.save(user)

        # Send email with complex template engine (not needed yet)
        template_engine = TemplateEngine()
        template_factory = TemplateFactory()
        email_builder = EmailBuilder()
        email_service = EmailServiceFactory().create("smtp")
        # ... 20 lines of email setup
        email_service.send(email)

    def register_premium_user(self, name, email, password):
        # Same validation (repetition!)
        if len(name) < 2:
            raise ValueError("Name too short")
        if "@" not in email:
            raise ValueError("Invalid email")
        # ... repeat everything
```

**Good** (DRY, KISS, YAGNI):
```python
# Good - DRY, simple, minimal
class UserService:
    def __init__(self, repository, email_service):
        self.repository = repository
        self.email_service = email_service

    def register(self, name: str, email: str, password: str) -> User:
        self._validate(name, email)  # DRY - single validation

        user = User(name, email, password)
        self.repository.save(user)  # KISS - straightforward

        # YAGNI - simple email, no template engine yet
        self.email_service.send(email, f"Welcome {name}!")

        return user

    def _validate(self, name: str, email: str):  # DRY
        if len(name) < 2:
            raise ValueError("Name too short")
        if "@" not in email:
            raise ValueError("Invalid email")
```

## Quick Reference

| Principle | Question to Ask |
|-----------|----------------|
| **DRY** | Am I copy-pasting code? |
| **KISS** | Is this simpler than it needs to be? |
| **YAGNI** | Do I actually need this now? |

### Red Flags

❌ Copy-pasting code blocks → Violates DRY
❌ Hard to explain what code does → Violates KISS
❌ "We might need this later" → Violates YAGNI

### Green Flags

✅ Single source of truth for each concept (DRY)
✅ Code reads like English (KISS)
✅ Every line serves current requirements (YAGNI)
