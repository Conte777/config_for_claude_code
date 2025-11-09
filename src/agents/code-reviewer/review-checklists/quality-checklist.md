# Code Quality Review Checklist

This checklist covers code quality aspects including SOLID principles, design patterns, maintainability, and best practices.

## 1. SOLID Principles

### Single Responsibility Principle (SRP)

**Check for:**
- [ ] Each class/function has one clear purpose
- [ ] No "god objects" with too many responsibilities
- [ ] Changes to one feature don't require modifying many unrelated classes

**Red flags:**
```
Class doing too much:
- UserManager: handles authentication, authorization, database, email, logging
- Utils: contains unrelated helper functions

Fix: Split into UserAuthenticator, UserRepository, EmailService, etc.
```

### Open/Closed Principle (OCP)

**Check for:**
- [ ] Code open for extension, closed for modification
- [ ] Strategy pattern for different behaviors
- [ ] Plugin architecture where applicable

**Example:**
```python
# Bad: Needs modification for new payment types
def process_payment(type, amount):
    if type == 'credit_card':
        # process credit card
    elif type == 'paypal':
        # process paypal
    # Adding new type requires modifying this function

# Good: Open for extension
class PaymentProcessor:
    def process(self, amount): pass

class CreditCardProcessor(PaymentProcessor):
    def process(self, amount): ...

class PayPalProcessor(PaymentProcessor):
    def process(self, amount): ...
```

### Liskov Substitution Principle (LSP)

**Check for:**
- [ ] Subclasses can replace parent class without breaking functionality
- [ ] Subclasses don't weaken preconditions or strengthen postconditions
- [ ] No inappropriate inheritance

**Red flags:**
```
Violating LSP:
- Square inheriting from Rectangle (breaks width/height independence)
- Overridden methods that throw NotImplementedError
```

### Interface Segregation Principle (ISP)

**Check for:**
- [ ] Interfaces are small and focused
- [ ] Clients not forced to depend on methods they don't use
- [ ] No "fat interfaces"

**Red flags:**
```
Fat interface:
- Interface with 20 methods, but clients only use 2-3
- Forcing empty implementations of unused methods
```

### Dependency Inversion Principle (DIP)

**Check for:**
- [ ] High-level modules don't depend on low-level modules
- [ ] Dependencies on abstractions (interfaces), not concrete classes
- [ ] Dependency injection used

**Example:**
```java
// Bad: Depends on concrete class
class UserService {
    private MySQLDatabase db = new MySQLDatabase();  // ❌
}

// Good: Depends on abstraction
class UserService {
    private Database db;  // Interface

    public UserService(Database db) {  // Dependency injection
        this.db = db;
    }
}
```

## 2. DRY (Don't Repeat Yourself)

**Check for:**
- [ ] No duplicated code (extract to functions/methods)
- [ ] No copy-paste programming
- [ ] Shared logic in reusable modules

**Red flags:**
```
Code duplication:
- Same validation logic in 5 different places
- Copied functions with minor differences
- Duplicated constants/configuration

Fix: Extract to shared function/class/module
```

**Balance:** Don't over-DRY - some duplication is acceptable if abstraction would be forced/unclear.

## 3. KISS (Keep It Simple, Stupid)

**Check for:**
- [ ] Simple, straightforward solutions preferred
- [ ] No premature optimization
- [ ] No over-engineering

**Red flags:**
```
Over-engineering:
- Factory pattern for creating simple objects
- Complex inheritance hierarchy for 2 classes
- Enterprise-level architecture for small project
- Complicated abstractions for simple problems
```

## 4. YAGNI (You Aren't Gonna Need It)

**Check for:**
- [ ] No features implemented "just in case"
- [ ] No speculative generality
- [ ] Code implements current requirements only

**Red flags:**
```
YAGNI violations:
- Configuration for features not yet planned
- Abstractions for future requirements
- Hooks/extension points with no users
```

## 5. Naming Conventions

### Clear and Descriptive Names

**Check for:**
- [ ] Variables named after their purpose
- [ ] Functions named after what they do (verbs)
- [ ] Classes named after what they represent (nouns)
- [ ] No abbreviations unless well-known

**Good names:**
```
getUserById(id)
calculateTotalPrice(items)
class UserAuthenticator
isEmailValid(email)
```

**Bad names:**
```
getData(x)  // Too generic
process()  // What does it process?
temp, tmp  // Meaningless
e, d, mgr  // Unclear abbreviations
```

### Consistent Naming

**Check for:**
- [ ] Consistent terminology (don't mix "user" and "customer" for same concept)
- [ ] Consistent verb usage (get/fetch/retrieve - pick one)
- [ ] Language conventions followed (camelCase, snake_case, etc.)

## 6. Function/Method Quality

### Function Length

**Check for:**
- [ ] Functions are short (ideally <20 lines, max 50 lines)
- [ ] Functions do one thing
- [ ] No deeply nested code (max 3 levels of indentation)

**Red flags:**
```
- Function with 200 lines
- 5-6 levels of nested if statements
- Function doing multiple unrelated things
```

### Function Parameters

**Check for:**
- [ ] Minimal parameters (ideally ≤3, max 5)
- [ ] No boolean flags (split into separate functions)
- [ ] Parameter objects for many parameters

**Red flags:**
```python
# Too many parameters
def create_user(name, email, age, address, city, country, zip, phone):  # ❌

# Boolean flag anti-pattern
def save_user(user, is_admin):  # ❌ Split into save_user() and save_admin()

# Better
class UserData:
    def __init__(self, name, email, address, ...):
        ...

def create_user(user_data: UserData):  # ✅
```

### Return Values

**Check for:**
- [ ] Consistent return types
- [ ] No null/None for errors (use exceptions or Result type)
- [ ] No "magic values" (-1, null, empty string for different meanings)

## 7. Error Handling

### Exception Handling

**Check for:**
- [ ] Specific exceptions caught, not generic
- [ ] Errors logged with context
- [ ] Resources cleaned up (using finally or context managers)
- [ ] Errors don't expose sensitive information

**Red flags:**
```python
# Bad
try:
    risky()
except:  # ❌ Too broad
    pass  # ❌ Silent failure

# Good
try:
    risky()
except SpecificError as e:
    logger.error(f"Operation failed: {e}")
    raise CustomError("User-friendly message") from e
```

### Error Messages

**Check for:**
- [ ] Error messages are clear and actionable
- [ ] Include context (what operation failed, why)
- [ ] No stack traces exposed to end users

## 8. Code Organization

### File Structure

**Check for:**
- [ ] Related code grouped together
- [ ] Clear separation of concerns (models, services, controllers)
- [ ] No circular dependencies
- [ ] Import order logical and consistent

### Module Size

**Check for:**
- [ ] Files not too large (<500 lines preferred)
- [ ] Modules have clear purpose
- [ ] No "dump" modules (utils.py, helpers.js with random functions)

## 9. Comments and Documentation

### When to Comment

**Check for:**
- [ ] Comments explain WHY, not WHAT (code explains what)
- [ ] Complex algorithms explained
- [ ] Non-obvious business rules documented
- [ ] TODOs include ticket numbers and context

**Good comments:**
```python
# Calculate discount based on tier (Business Rule #BR-2023-45)
# Platinum: 20%, Gold: 15%, Silver: 10%

# Using binary search here because list is pre-sorted
# Performance: O(log n) vs O(n) for linear search
```

**Bad comments:**
```python
# Increment counter
counter += 1  # ❌ Code is self-explanatory

# Get user
user = get_user()  # ❌ Adds no value
```

### Self-Documenting Code

**Check for:**
- [ ] Code is clear enough to not need comments
- [ ] Descriptive names eliminate need for comments
- [ ] Extract method to name complex logic

**Example:**
```python
# Bad: Needs comment
# Check if user has premium access
if user.subscription_level > 2 and user.payment_status == 'active':

# Good: Self-explanatory
if user.has_premium_access():
```

### Documentation

**Check for:**
- [ ] Public APIs documented (docstrings, JSDoc, Javadoc)
- [ ] Parameters and return values described
- [ ] Examples provided for complex APIs
- [ ] README exists and is up to date

## 10. Test Quality

### Test Coverage

**Check for:**
- [ ] Critical paths have tests
- [ ] Edge cases tested
- [ ] Error cases tested
- [ ] Coverage > 70% (ideally > 80%)

### Test Quality

**Check for:**
- [ ] Tests are clear and readable
- [ ] Tests are isolated (no dependencies between tests)
- [ ] Tests are fast
- [ ] No test code duplication (use fixtures/helpers)
- [ ] Test names describe what they test

**Good test names:**
```python
test_user_login_with_invalid_password_returns_error()
test_calculate_discount_for_platinum_user()
test_empty_cart_total_is_zero()
```

### Test Anti-Patterns

**Red flags:**
```
- Tests that test nothing (no assertions)
- Tests with sleep() for timing issues
- Tests that depend on external services (use mocks)
- Flaky tests (pass/fail randomly)
- Tests that test implementation details, not behavior
```

## 11. Code Smells

### Common Code Smells

**Check for:**
- [ ] **Long Method**: Functions > 50 lines
- [ ] **Large Class**: Classes > 500 lines or > 20 methods
- [ ] **Long Parameter List**: > 5 parameters
- [ ] **Duplicate Code**: Same logic in multiple places
- [ ] **Dead Code**: Unused functions, commented code
- [ ] **Magic Numbers**: Hardcoded values without explanation
- [ ] **Feature Envy**: Method uses data from another class more than its own
- [ ] **Data Clumps**: Same group of parameters always appear together
- [ ] **Shotgun Surgery**: One change requires modifying many classes

### Refactoring Opportunities

**Check for:**
- [ ] Complex conditionals → Strategy pattern or polymorphism
- [ ] Long methods → Extract smaller methods
- [ ] Duplicate code → Extract to shared function
- [ ] Large classes → Split responsibilities
- [ ] Magic numbers → Named constants

## 12. Maintainability

### Code Readability

**Check for:**
- [ ] Consistent formatting (use auto-formatter)
- [ ] Logical code flow (top to bottom)
- [ ] No clever tricks (prefer clarity over cleverness)
- [ ] Proper indentation and whitespace

### Dependencies

**Check for:**
- [ ] Dependencies up to date
- [ ] No unused dependencies
- [ ] Dependency versions pinned (for reproducibility)
- [ ] License compatibility checked

### Configuration

**Check for:**
- [ ] Configuration separated from code
- [ ] Environment-specific config (dev, staging, prod)
- [ ] Secrets not in code (use environment variables)
- [ ] Sensible defaults provided

## Code Quality Severity

**CRITICAL**:
- God classes (1000+ lines, 50+ methods)
- Massive functions (200+ lines)
- SOLID violations causing architectural issues
- No error handling in critical paths

**HIGH**:
- Significant code duplication
- Poor naming (unclear what code does)
- Missing tests for critical functionality
- Circular dependencies
- Deep nesting (4+ levels)

**MEDIUM**:
- Long functions (50-100 lines)
- Too many parameters (5-7)
- Some code duplication
- Inconsistent naming
- Missing documentation

**LOW**:
- Minor naming improvements
- Comment improvements
- Test coverage gaps (non-critical paths)
- Minor refactoring opportunities

## Quick Quality Checklist

- [ ] **SOLID**: Single responsibility? Depends on abstractions?
- [ ] **DRY**: No duplicated code?
- [ ] **KISS**: Simple solution, not over-engineered?
- [ ] **Naming**: Clear, descriptive, consistent?
- [ ] **Functions**: Short, focused, minimal parameters?
- [ ] **Errors**: Proper exception handling and logging?
- [ ] **Organization**: Clear structure, no circular deps?
- [ ] **Comments**: Explain WHY, not WHAT?
- [ ] **Tests**: Critical paths covered, edge cases tested?
- [ ] **Code Smells**: No long methods, large classes, duplicates?
