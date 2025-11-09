# SOLID Principles

SOLID is an acronym for five design principles introduced by Robert C. Martin (Uncle Bob) that make software designs more understandable, flexible, and maintainable.

## 1. Single Responsibility Principle (SRP)

**Principle**: A class should have only one reason to change. Every class should have only one responsibility.

### Why It Matters
- Easier to understand and maintain
- Reduces coupling
- Easier to test
- Changes to one responsibility don't affect others

### Examples

#### Go

```go
// Bad - multiple responsibilities
type UserManager struct {
    db *sql.DB
}

func (um *UserManager) CreateUser(user *User) error {
    // Save to database
    if err := um.db.Save(user); err != nil {
        return err
    }
    // Send email
    email := fmt.Sprintf("Welcome %s!", user.Name)
    return sendEmail(user.Email, email)
}

// Good - separated responsibilities
type UserRepository struct {
    db *sql.DB
}

func (ur *UserRepository) Save(user *User) error {
    return ur.db.Save(user)
}

type EmailService struct {
    smtpHost string
}

func (es *EmailService) SendWelcomeEmail(user *User) error {
    email := fmt.Sprintf("Welcome %s!", user.Name)
    return sendEmail(user.Email, email)
}

type UserService struct {
    repo  *UserRepository
    email *EmailService
}

func (us *UserService) CreateUser(user *User) error {
    if err := us.repo.Save(user); err != nil {
        return err
    }
    return us.email.SendWelcomeEmail(user)
}
```

#### Java

```java
// Bad - multiple responsibilities
public class UserManager {
    public void createUser(User user) {
        // Database logic
        database.save(user);
        // Email logic
        emailService.send(user.getEmail(), "Welcome!");
        // Logging logic
        logger.log("User created: " + user.getName());
    }
}

// Good - separated responsibilities
public class UserRepository {
    public void save(User user) {
        database.save(user);
    }
}

public class EmailService {
    public void sendWelcomeEmail(User user) {
        send(user.getEmail(), "Welcome " + user.getName());
    }
}

public class UserService {
    private final UserRepository repository;
    private final EmailService emailService;

    public UserService(UserRepository repository, EmailService emailService) {
        this.repository = repository;
        this.emailService = emailService;
    }

    public void createUser(User user) {
        repository.save(user);
        emailService.sendWelcomeEmail(user);
    }
}
```

#### Python

```python
# Bad - multiple responsibilities
class UserManager:
    def create_user(self, user: User):
        # Database logic
        self.db.save(user)
        # Email logic
        self.send_email(user.email, "Welcome!")
        # Report generation
        self.generate_report(user)

# Good - separated responsibilities
class UserRepository:
    def save(self, user: User):
        self.db.save(user)

class EmailService:
    def send_welcome_email(self, user: User):
        self.send_email(user.email, f"Welcome {user.name}!")

class UserService:
    def __init__(self, repository: UserRepository, email_service: EmailService):
        self.repository = repository
        self.email_service = email_service

    def create_user(self, user: User):
        self.repository.save(user)
        self.email_service.send_welcome_email(user)
```

## 2. Open-Closed Principle (OCP)

**Principle**: Software entities should be open for extension but closed for modification.

### Why It Matters
- Add new functionality without changing existing code
- Reduces risk of breaking existing features
- Promotes reusability

### Examples

#### Go

```go
// Bad - needs modification to add new payment methods
type PaymentProcessor struct{}

func (pp *PaymentProcessor) Process(amount float64, method string) error {
    if method == "credit_card" {
        return processCreditCard(amount)
    } else if method == "paypal" {
        return processPayPal(amount)
    }
    // Need to modify this function for new payment methods
    return errors.New("unknown payment method")
}

// Good - open for extension
type PaymentMethod interface {
    Process(amount float64) error
}

type CreditCardPayment struct{}

func (cc *CreditCardPayment) Process(amount float64) error {
    return processCreditCard(amount)
}

type PayPalPayment struct{}

func (pp *PayPalPayment) Process(amount float64) error {
    return processPayPal(amount)
}

type PaymentProcessor struct {
    method PaymentMethod
}

func (pp *PaymentProcessor) Process(amount float64) error {
    return pp.method.Process(amount)
}

// New payment method - no modification needed
type BitcoinPayment struct{}

func (bp *BitcoinPayment) Process(amount float64) error {
    return processBitcoin(amount)
}
```

#### Java

```java
// Bad
public class AreaCalculator {
    public double calculateArea(Object shape) {
        if (shape instanceof Rectangle) {
            Rectangle rect = (Rectangle) shape;
            return rect.width * rect.height;
        } else if (shape instanceof Circle) {
            Circle circle = (Circle) shape;
            return Math.PI * circle.radius * circle.radius;
        }
        // Must modify to add new shapes
        return 0;
    }
}

// Good - open for extension
public interface Shape {
    double calculateArea();
}

public class Rectangle implements Shape {
    private double width;
    private double height;

    @Override
    public double calculateArea() {
        return width * height;
    }
}

public class Circle implements Shape {
    private double radius;

    @Override
    public double calculateArea() {
        return Math.PI * radius * radius;
    }
}

// New shape - no modification to existing code
public class Triangle implements Shape {
    private double base;
    private double height;

    @Override
    public double calculateArea() {
        return 0.5 * base * height;
    }
}
```

#### Python

```python
# Bad
class DiscountCalculator:
    def calculate(self, customer_type: str, amount: float) -> float:
        if customer_type == "regular":
            return amount * 0.1
        elif customer_type == "premium":
            return amount * 0.2
        # Must modify to add new customer types
        return 0

# Good - open for extension
from abc import ABC, abstractmethod

class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: float) -> float:
        pass

class RegularDiscount(DiscountStrategy):
    def calculate(self, amount: float) -> float:
        return amount * 0.1

class PremiumDiscount(DiscountStrategy):
    def calculate(self, amount: float) -> float:
        return amount * 0.2

class DiscountCalculator:
    def __init__(self, strategy: DiscountStrategy):
        self.strategy = strategy

    def calculate(self, amount: float) -> float:
        return self.strategy.calculate(amount)

# New discount type - no modification needed
class VIPDiscount(DiscountStrategy):
    def calculate(self, amount: float) -> float:
        return amount * 0.3
```

## 3. Liskov Substitution Principle (LSP)

**Principle**: Objects of a superclass should be replaceable with objects of a subclass without breaking the application.

### Why It Matters
- Ensures polymorphism works correctly
- Prevents unexpected behavior in inheritance hierarchies
- Maintains code correctness

### Examples

#### Go

```go
// Bad - violates LSP
type Bird interface {
    Fly() error
}

type Sparrow struct{}

func (s *Sparrow) Fly() error {
    return nil // Can fly
}

type Penguin struct{}

func (p *Penguin) Fly() error {
    return errors.New("penguins cannot fly") // Violation!
}

// Good - follows LSP
type Bird interface {
    Move() error
}

type FlyingBird interface {
    Bird
    Fly() error
}

type Sparrow struct{}

func (s *Sparrow) Move() error { return nil }
func (s *Sparrow) Fly() error  { return nil }

type Penguin struct{}

func (p *Penguin) Move() error { return nil } // Swims/walks
```

#### Java

```java
// Bad - violates LSP
public class Rectangle {
    protected int width;
    protected int height;

    public void setWidth(int width) { this.width = width; }
    public void setHeight(int height) { this.height = height; }
    public int getArea() { return width * height; }
}

public class Square extends Rectangle {
    @Override
    public void setWidth(int width) {
        this.width = width;
        this.height = width; // Violates LSP
    }

    @Override
    public void setHeight(int height) {
        this.width = height; // Violates LSP
        this.height = height;
    }
}

// Good - follows LSP
public interface Shape {
    int getArea();
}

public class Rectangle implements Shape {
    private int width;
    private int height;

    public Rectangle(int width, int height) {
        this.width = width;
        this.height = height;
    }

    @Override
    public int getArea() {
        return width * height;
    }
}

public class Square implements Shape {
    private int side;

    public Square(int side) {
        this.side = side;
    }

    @Override
    public int getArea() {
        return side * side;
    }
}
```

## 4. Interface Segregation Principle (ISP)

**Principle**: No client should be forced to depend on methods it does not use.

### Why It Matters
- Prevents "fat" interfaces
- Reduces coupling
- Increases cohesion
- Makes code more maintainable

### Examples

#### Go

```go
// Bad - fat interface
type Worker interface {
    Work()
    Eat()
    Sleep()
}

type Robot struct{}

func (r *Robot) Work()  {}
func (r *Robot) Eat()   {} // Robots don't eat!
func (r *Robot) Sleep() {} // Robots don't sleep!

// Good - segregated interfaces
type Workable interface {
    Work()
}

type Eatable interface {
    Eat()
}

type Sleepable interface {
    Sleep()
}

type Human struct{}

func (h *Human) Work()  {}
func (h *Human) Eat()   {}
func (h *Human) Sleep() {}

type Robot struct{}

func (r *Robot) Work() {} // Only implements what it needs
```

#### Java

```java
// Bad - fat interface
public interface Printer {
    void print(Document doc);
    void scan(Document doc);
    void fax(Document doc);
}

public class SimplePrinter implements Printer {
    public void print(Document doc) { /* Implementation */ }
    public void scan(Document doc) { throw new UnsupportedOperationException(); }
    public void fax(Document doc) { throw new UnsupportedOperationException(); }
}

// Good - segregated interfaces
public interface Printable {
    void print(Document doc);
}

public interface Scannable {
    void scan(Document doc);
}

public interface Faxable {
    void fax(Document doc);
}

public class SimplePrinter implements Printable {
    public void print(Document doc) { /* Implementation */ }
}

public class MultiFunctionPrinter implements Printable, Scannable, Faxable {
    public void print(Document doc) { /* Implementation */ }
    public void scan(Document doc) { /* Implementation */ }
    public void fax(Document doc) { /* Implementation */ }
}
```

#### Python

```python
# Bad - fat interface
class MultiFunctionDevice(ABC):
    @abstractmethod
    def print(self, document):
        pass

    @abstractmethod
    def scan(self, document):
        pass

    @abstractmethod
    def fax(self, document):
        pass

class SimplePrinter(MultiFunctionDevice):
    def print(self, document):
        pass  # OK

    def scan(self, document):
        raise NotImplementedError("Cannot scan")

    def fax(self, document):
        raise NotImplementedError("Cannot fax")

# Good - segregated interfaces
class Printer(ABC):
    @abstractmethod
    def print(self, document):
        pass

class Scanner(ABC):
    @abstractmethod
    def scan(self, document):
        pass

class FaxMachine(ABC):
    @abstractmethod
    def fax(self, document):
        pass

class SimplePrinter(Printer):
    def print(self, document):
        pass

class MultiFunctionDevice(Printer, Scanner, FaxMachine):
    def print(self, document):
        pass

    def scan(self, document):
        pass

    def fax(self, document):
        pass
```

## 5. Dependency Inversion Principle (DIP)

**Principle**:
- High-level modules should not depend on low-level modules. Both should depend on abstractions.
- Abstractions should not depend on details. Details should depend on abstractions.

### Why It Matters
- Decouples high-level and low-level components
- Makes code more flexible and testable
- Facilitates dependency injection

### Examples

#### Go

```go
// Bad - high-level depends on low-level
type MySQLDatabase struct{}

func (db *MySQLDatabase) Save(data string) error {
    // MySQL-specific implementation
    return nil
}

type UserService struct {
    db *MySQLDatabase // Tightly coupled
}

func (us *UserService) CreateUser(name string) error {
    return us.db.Save(name)
}

// Good - both depend on abstraction
type Database interface {
    Save(data string) error
}

type MySQLDatabase struct{}

func (db *MySQLDatabase) Save(data string) error {
    return nil
}

type PostgreSQLDatabase struct{}

func (db *PostgreSQLDatabase) Save(data string) error {
    return nil
}

type UserService struct {
    db Database // Depends on abstraction
}

func (us *UserService) CreateUser(name string) error {
    return us.db.Save(name)
}
```

#### Java

```java
// Bad - high-level depends on low-level
public class MySQLDatabase {
    public void save(String data) {
        // MySQL-specific logic
    }
}

public class UserService {
    private MySQLDatabase database = new MySQLDatabase(); // Tight coupling

    public void createUser(String name) {
        database.save(name);
    }
}

// Good - both depend on abstraction
public interface Database {
    void save(String data);
}

public class MySQLDatabase implements Database {
    @Override
    public void save(String data) {
        // MySQL-specific logic
    }
}

public class PostgreSQLDatabase implements Database {
    @Override
    public void save(String data) {
        // PostgreSQL-specific logic
    }
}

public class UserService {
    private final Database database; // Depends on abstraction

    public UserService(Database database) {
        this.database = database;
    }

    public void createUser(String name) {
        database.save(name);
    }
}
```

#### Python

```python
# Bad - high-level depends on low-level
class MySQLDatabase:
    def save(self, data: str):
        # MySQL-specific logic
        pass

class UserService:
    def __init__(self):
        self.db = MySQLDatabase()  # Tight coupling

    def create_user(self, name: str):
        self.db.save(name)

# Good - both depend on abstraction
from abc import ABC, abstractmethod

class Database(ABC):
    @abstractmethod
    def save(self, data: str):
        pass

class MySQLDatabase(Database):
    def save(self, data: str):
        # MySQL-specific logic
        pass

class PostgreSQLDatabase(Database):
    def save(self, data: str):
        # PostgreSQL-specific logic
        pass

class UserService:
    def __init__(self, database: Database):  # Depends on abstraction
        self.db = database

    def create_user(self, name: str):
        self.db.save(name)

# Usage with dependency injection
mysql_db = MySQLDatabase()
postgres_db = PostgreSQLDatabase()

service1 = UserService(mysql_db)
service2 = UserService(postgres_db)
```

## Quick Reference

### When to Apply Each Principle

| Principle | When to Use |
|-----------|-------------|
| **SRP** | Class/module doing multiple things |
| **OCP** | Need to add new functionality frequently |
| **LSP** | Using inheritance/polymorphism |
| **ISP** | Interfaces with methods not all clients need |
| **DIP** | Tight coupling between layers |

### Red Flags

- **Violating SRP**: "This class does X **and** Y"
- **Violating OCP**: Modifying existing code to add features
- **Violating LSP**: Subclass breaks parent's contract
- **Violating ISP**: Empty method implementations or throwing "not supported"
- **Violating DIP**: `new` keyword for dependencies, concrete types in constructors

### Benefits of SOLID

✅ Easier to maintain and extend
✅ More testable code
✅ Reduced coupling
✅ Better code organization
✅ Fewer bugs from changes
