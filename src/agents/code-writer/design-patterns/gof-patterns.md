# Gang of Four Design Patterns

Key design patterns from "Design Patterns: Elements of Reusable Object-Oriented Software" (1994), with examples in Go, Java, and Python.

## Creational Patterns

### Singleton

**Purpose**: Ensure a class has only one instance and provide a global access point.

**When to use**: Database connections, configuration managers, logging.

**Go Example**:
```go
package singleton

import "sync"

type Database struct {
    connection string
}

var instance *Database
var once sync.Once

func GetInstance() *Database {
    once.Do(func() {
        instance = &Database{connection: "db_connection"}
    })
    return instance
}
```

**Java Example**:
```java
public class Database {
    private static volatile Database instance;
    private String connection;

    private Database() {
        this.connection = "db_connection";
    }

    public static Database getInstance() {
        if (instance == null) {
            synchronized (Database.class) {
                if (instance == null) {
                    instance = new Database();
                }
            }
        }
        return instance;
    }
}
```

**Python Example**:
```python
class Database:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance.connection = "db_connection"
        return cls._instance
```

### Factory Method

**Purpose**: Define an interface for creating objects, but let subclasses decide which class to instantiate.

**When to use**: When you don't know the exact type of object needed until runtime.

**Go Example**:
```go
type PaymentProcessor interface {
    Process(amount float64) error
}

type CreditCard struct{}
func (c *CreditCard) Process(amount float64) error { return nil }

type PayPal struct{}
func (p *PayPal) Process(amount float64) error { return nil }

func NewPaymentProcessor(method string) PaymentProcessor {
    switch method {
    case "credit_card":
        return &CreditCard{}
    case "paypal":
        return &PayPal{}
    default:
        return nil
    }
}
```

### Builder

**Purpose**: Separate construction of complex object from its representation.

**When to use**: Objects with many optional parameters or complex construction.

**Java Example**:
```java
public class User {
    private final String name;
    private final String email;
    private final int age;
    private final String address;

    private User(Builder builder) {
        this.name = builder.name;
        this.email = builder.email;
        this.age = builder.age;
        this.address = builder.address;
    }

    public static class Builder {
        private final String name;
        private final String email;
        private int age;
        private String address;

        public Builder(String name, String email) {
            this.name = name;
            this.email = email;
        }

        public Builder age(int age) {
            this.age = age;
            return this;
        }

        public Builder address(String address) {
            this.address = address;
            return this;
        }

        public User build() {
            return new User(this);
        }
    }
}

// Usage
User user = new User.Builder("John", "john@example.com")
    .age(30)
    .address("123 Main St")
    .build();
```

## Structural Patterns

### Adapter

**Purpose**: Convert interface of a class into another interface clients expect.

**When to use**: Integrate incompatible interfaces.

**Python Example**:
```python
# Existing interface
class OldPaymentSystem:
    def old_pay(self, amount: float):
        print(f"Old system: paying {amount}")

# Target interface
class PaymentProcessor:
    def process_payment(self, amount: float):
        pass

# Adapter
class PaymentAdapter(PaymentProcessor):
    def __init__(self, old_system: OldPaymentSystem):
        self.old_system = old_system

    def process_payment(self, amount: float):
        self.old_system.old_pay(amount)

# Usage
old_system = OldPaymentSystem()
adapter = PaymentAdapter(old_system)
adapter.process_payment(100.0)
```

### Decorator

**Purpose**: Attach additional responsibilities to an object dynamically.

**When to use**: Add functionality without modifying existing code.

**Go Example**:
```go
type Coffee interface {
    Cost() float64
    Description() string
}

type SimpleCoffee struct{}

func (c *SimpleCoffee) Cost() float64 { return 5.0 }
func (c *SimpleCoffee) Description() string { return "Simple coffee" }

type MilkDecorator struct {
    coffee Coffee
}

func (m *MilkDecorator) Cost() float64 {
    return m.coffee.Cost() + 1.0
}

func (m *MilkDecorator) Description() string {
    return m.coffee.Description() + ", milk"
}

// Usage
coffee := &SimpleCoffee{}
withMilk := &MilkDecorator{coffee: coffee}
// Cost: 6.0, Description: "Simple coffee, milk"
```

## Behavioral Patterns

### Strategy

**Purpose**: Define a family of algorithms, encapsulate each one, make them interchangeable.

**When to use**: Multiple algorithms for a task, need to switch at runtime.

**Java Example**:
```java
public interface SortStrategy {
    void sort(int[] array);
}

public class QuickSort implements SortStrategy {
    public void sort(int[] array) {
        // Quick sort implementation
    }
}

public class MergeSort implements SortStrategy {
    public void sort(int[] array) {
        // Merge sort implementation
    }
}

public class Sorter {
    private SortStrategy strategy;

    public void setStrategy(SortStrategy strategy) {
        this.strategy = strategy;
    }

    public void sort(int[] array) {
        strategy.sort(array);
    }
}

// Usage
Sorter sorter = new Sorter();
sorter.setStrategy(new QuickSort());
sorter.sort(data);
```

### Observer

**Purpose**: Define one-to-many dependency so when one object changes state, dependents are notified.

**When to use**: Event handling, pub-sub systems.

**Python Example**:
```python
from abc import ABC, abstractmethod
from typing import List

class Observer(ABC):
    @abstractmethod
    def update(self, message: str):
        pass

class Subject:
    def __init__(self):
        self._observers: List[Observer] = []

    def attach(self, observer: Observer):
        self._observers.append(observer)

    def detach(self, observer: Observer):
        self._observers.remove(observer)

    def notify(self, message: str):
        for observer in self._observers:
            observer.update(message)

class EmailObserver(Observer):
    def update(self, message: str):
        print(f"Email sent: {message}")

class SMSObserver(Observer):
    def update(self, message: str):
        print(f"SMS sent: {message}")

# Usage
subject = Subject()
subject.attach(EmailObserver())
subject.attach(SMSObserver())
subject.notify("User registered")
```

### Template Method

**Purpose**: Define skeleton of an algorithm, let subclasses override specific steps.

**When to use**: Algorithm with invariant parts and variant parts.

**Go Example**:
```go
type DataProcessor interface {
    LoadData() error
    ProcessData() error
    SaveData() error
}

type BaseProcessor struct {
    processor DataProcessor
}

func (bp *BaseProcessor) Execute() error {
    if err := bp.processor.LoadData(); err != nil {
        return err
    }
    if err := bp.processor.ProcessData(); err != nil {
        return err
    }
    return bp.processor.SaveData()
}

type CSVProcessor struct {
    BaseProcessor
}

func (cp *CSVProcessor) LoadData() error {
    // Load CSV
    return nil
}

func (cp *CSVProcessor) ProcessData() error {
    // Process CSV
    return nil
}

func (cp *CSVProcessor) SaveData() error {
    // Save CSV
    return nil
}
```

## Pattern Selection Guide

| Use Case | Pattern |
|----------|---------|
| Single instance needed | Singleton |
| Complex object construction | Builder |
| Create objects without specifying class | Factory Method |
| Incompatible interfaces | Adapter |
| Add functionality dynamically | Decorator |
| Switch algorithms at runtime | Strategy |
| Notify multiple objects of changes | Observer |
| Algorithm with fixed structure, variable steps | Template Method |

## Anti-Patterns to Avoid

❌ **God Object**: Single class doing everything (violates SRP)
❌ **Singleton Overuse**: Not everything needs to be singleton
❌ **Pattern for Pattern's Sake**: Use patterns only when needed
❌ **Over-engineering**: YAGNI - don't add complexity prematurely

## Best Practices

✅ Apply patterns when they solve a specific problem
✅ Prefer composition over inheritance
✅ Keep it simple (KISS) - don't force patterns
✅ Use interfaces for flexibility
✅ Document why you chose a pattern
