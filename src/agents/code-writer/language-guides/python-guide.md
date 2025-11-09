# Python Language Guide

Complete reference for writing idiomatic, production-ready Python code following PEP 8, PEP 484 (Type Hints), and modern Python 3.10+ best practices.

## Style Guide & Formatting (PEP 8)

### Code Layout

**Indentation**: 4 spaces per level (never tabs)

```python
# Good
def function():
    if condition:
        do_something()
        do_something_else()

# Bad - tabs or 2 spaces
def function():
  if condition:
      do_something()
```

**Line Length**:
- **Maximum 79 characters** for code
- **Maximum 72 characters** for comments and docstrings

```python
# Good - implicit line continuation
result = some_function(
    argument1, argument2,
    argument3, argument4
)

# Good - backslash continuation (when necessary)
with open('/path/to/file1') as file1, \
     open('/path/to/file2') as file2:
    process(file1, file2)

# Bad - too long
result = some_function(argument1, argument2, argument3, argument4, argument5, argument6)
```

**Binary Operators**: Break **before** the operator (PEP 8 modern style)

```python
# Good - operator at start of line
income = (gross_wages
          + taxable_interest
          + (dividends - qualified_dividends)
          - ira_deduction
          - student_loan_interest)

# Bad - operator at end
income = (gross_wages +
          taxable_interest +
          (dividends - qualified_dividends) -
          ira_deduction -
          student_loan_interest)
```

### Blank Lines

- **2 blank lines** between top-level functions and classes
- **1 blank line** between methods inside a class
- **Sparingly** inside functions to separate logical sections

```python
# Good
class MyClass:
    def method1(self):
        pass

    def method2(self):
        pass


def top_level_function():
    pass


class AnotherClass:
    pass
```

### Imports

**Order**: standard library, third-party, local application

```python
# Good
import os
import sys

import requests
from fastapi import FastAPI

from myapp.models import User
from myapp.services import UserService

# Bad - mixed order
from myapp.models import User
import os
from fastapi import FastAPI
import sys
```

**Separate lines** (except `from X import A, B`):

```python
# Good
import os
import sys

from typing import List, Optional

# Bad
import os, sys
```

**Avoid wildcard imports**:

```python
# Bad
from module import *

# Good
from module import specific_function, SpecificClass
```

## Naming Conventions

### General Principle

> "Names visible to the user as part of the API should follow conventions that reflect usage rather than implementation."

### Naming Styles

**Functions, variables, methods**: `lowercase_with_underscores`

```python
# Good
def calculate_total():
    pass

user_name = "John"
item_count = 5

# Bad
def calculateTotal():
    pass

userName = "John"
```

**Classes**: `CapWords` (PascalCase)

```python
# Good
class UserService:
    pass

class HTTPClient:
    pass

# Bad
class user_service:
    pass

class Http_Client:
    pass
```

**Constants**: `UPPER_CASE_WITH_UNDERSCORES`

```python
# Good
MAX_CONNECTIONS = 100
DEFAULT_TIMEOUT = 30

# Bad
maxConnections = 100
```

**Private/Internal**: Leading underscore `_`

```python
class MyClass:
    def public_method(self):
        pass

    def _internal_method(self):  # Internal use
        pass

    def __private_method(self):  # Name mangling
        pass
```

### Avoid Single Letters

**Never use** `l`, `O`, `I` as single-character names (ambiguous with 1, 0)

## Type Hints (PEP 484)

### Basic Type Annotations

```python
# Function annotations
def greeting(name: str) -> str:
    return f'Hello {name}'

# Variable annotations
age: int = 30
names: list[str] = ["John", "Jane"]
user: User = User("John")

# Optional types
def find_user(id: int) -> Optional[User]:
    return database.get(id)  # May return None
```

### Modern Type Hints (Python 3.10+)

**Use built-in types directly** (no need for `typing.List`, `typing.Dict`):

```python
# Good - Python 3.10+
def process_items(items: list[str]) -> dict[str, int]:
    return {item: len(item) for item in items}

# Old style - still works but verbose
from typing import List, Dict

def process_items(items: List[str]) -> Dict[str, int]:
    return {item: len(item) for item in items}
```

**Union types with `|`** (Python 3.10+):

```python
# Good - Python 3.10+
def process(value: int | str) -> None:
    pass

# Old style
from typing import Union

def process(value: Union[int, str]) -> None:
    pass
```

### Type Aliases

```python
# Type aliases for readability
UserId = int
UserDict = dict[str, any]

def get_user(user_id: UserId) -> UserDict:
    return {"id": user_id, "name": "John"}
```

### Generic Types

```python
from typing import TypeVar, Generic

T = TypeVar('T')

class Stack(Generic[T]):
    def __init__(self) -> None:
        self.items: list[T] = []

    def push(self, item: T) -> None:
        self.items.append(item)

    def pop(self) -> T:
        return self.items.pop()

# Usage
int_stack: Stack[int] = Stack()
int_stack.push(1)
```

## Idiomatic Patterns

### String Comparisons

**Use methods, not string slicing**:

```python
# Good
if filename.endswith('.py'):
    pass

if text.startswith('Hello'):
    pass

# Bad
if filename[-3:] == '.py':
    pass

if text[:5] == 'Hello':
    pass
```

### Sequence Checks

**Use truthiness, not len()**:

```python
# Good
if not seq:
    print("Empty sequence")

if seq:
    print("Has items")

# Bad
if len(seq) == 0:
    print("Empty sequence")

if len(seq) > 0:
    print("Has items")
```

### Comparisons

**Use `is` for singletons** (None, True, False):

```python
# Good
if value is None:
    pass

if flag is True:  # Though usually just: if flag:
    pass

# Bad
if value == None:
    pass
```

**Use `isinstance()` for type checking**:

```python
# Good
if isinstance(obj, str):
    pass

# Bad
if type(obj) == str:
    pass
```

### Context Managers

**Always use `with` for resource management**:

```python
# Good
with open('file.txt') as f:
    data = f.read()

# Bad - file might not close if exception occurs
f = open('file.txt')
data = f.read()
f.close()
```

### List Comprehensions

**Use comprehensions for simple transformations**:

```python
# Good
squares = [x**2 for x in range(10)]
even_squares = [x**2 for x in range(10) if x % 2 == 0]

# Good - generator for large datasets
sum_of_squares = sum(x**2 for x in range(1000000))

# Bad - manual loop for simple case
squares = []
for x in range(10):
    squares.append(x**2)
```

### Dictionary Operations

```python
# Good - get with default
value = my_dict.get('key', default_value)

# Good - setdefault
my_dict.setdefault('key', []).append(value)

# Good - dict comprehension
squared = {x: x**2 for x in range(10)}

# Bad
if 'key' in my_dict:
    value = my_dict['key']
else:
    value = default_value
```

## Exception Handling

### Catch Specific Exceptions

```python
# Good
try:
    value = int(user_input)
except ValueError as e:
    print(f"Invalid number: {e}")
except KeyError as e:
    print(f"Missing key: {e}")

# Bad - too broad
try:
    value = int(user_input)
except Exception:
    print("Something went wrong")
```

### Clean Exception Messages

```python
# Good
class ValidationError(Exception):
    def __init__(self, field: str, message: str):
        self.field = field
        super().__init__(f"Validation failed for {field}: {message}")

# Usage
raise ValidationError("email", "Invalid format")

# Bad
raise Exception("Invalid email format")
```

### Resource Cleanup

```python
# Good - context manager
with database.transaction():
    database.insert(data)
    database.commit()

# Good - custom context manager
from contextlib import contextmanager

@contextmanager
def managed_resource():
    resource = acquire_resource()
    try:
        yield resource
    finally:
        release_resource(resource)
```

## FastAPI Patterns

### Route Definitions

```python
from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel

app = FastAPI()

class UserCreate(BaseModel):
    name: str
    email: str

class UserResponse(BaseModel):
    id: int
    name: str
    email: str

    class Config:
        from_attributes = True

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@app.post("/users", response_model=UserResponse, status_code=201)
async def create_user(user: UserCreate, db: Session = Depends(get_db)):
    db_user = User(**user.dict())
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user
```

### Dependency Injection

```python
from fastapi import Depends
from sqlalchemy.orm import Session

# Database dependency
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Service dependency
def get_user_service(db: Session = Depends(get_db)) -> UserService:
    return UserService(db)

# Usage in route
@app.get("/users/{user_id}")
async def get_user(
    user_id: int,
    service: UserService = Depends(get_user_service)
):
    return service.get_user(user_id)
```

### Pydantic Models with Validation

```python
from pydantic import BaseModel, EmailStr, Field, validator

class UserCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    age: int = Field(..., ge=0, le=150)

    @validator('name')
    def name_must_not_be_blank(cls, v):
        if not v.strip():
            raise ValueError('Name cannot be blank')
        return v.strip()

    @validator('age')
    def age_must_be_adult(cls, v):
        if v < 18:
            raise ValueError('User must be 18 or older')
        return v
```

## Django Patterns

### Model Definition

```python
from django.db import models
from django.core.validators import MinLengthValidator

class User(models.Model):
    name = models.CharField(
        max_length=100,
        validators=[MinLengthValidator(2)]
    )
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'users'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['email']),
        ]

    def __str__(self):
        return self.name
```

### Views (Class-Based)

```python
from django.views.generic import ListView, CreateView, UpdateView
from django.urls import reverse_lazy

class UserListView(ListView):
    model = User
    template_name = 'users/list.html'
    context_object_name = 'users'
    paginate_by = 20

    def get_queryset(self):
        return User.objects.filter(is_active=True)

class UserCreateView(CreateView):
    model = User
    template_name = 'users/create.html'
    fields = ['name', 'email']
    success_url = reverse_lazy('user-list')

    def form_valid(self, form):
        form.instance.created_by = self.request.user
        return super().form_valid(form)
```

## SQLAlchemy Patterns

### Model Definition

```python
from sqlalchemy import Column, Integer, String, DateTime, Boolean
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()

class User(Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    is_active = Column(Boolean, default=True)

    def __repr__(self):
        return f"<User(id={self.id}, email='{self.email}')>"
```

### Repository Pattern

```python
from sqlalchemy.orm import Session
from typing import Optional

class UserRepository:
    def __init__(self, db: Session):
        self.db = db

    def find_by_id(self, user_id: int) -> Optional[User]:
        return self.db.query(User).filter(User.id == user_id).first()

    def find_by_email(self, email: str) -> Optional[User]:
        return self.db.query(User).filter(User.email == email).first()

    def create(self, user: User) -> User:
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def update(self, user: User) -> User:
        self.db.commit()
        self.db.refresh(user)
        return user

    def delete(self, user: User) -> None:
        self.db.delete(user)
        self.db.commit()
```

## Testing with pytest

### Test Structure (Arrange-Act-Assert)

```python
import pytest
from myapp.services import UserService
from myapp.models import User

def test_create_user_with_valid_data():
    # Arrange
    service = UserService()
    user_data = {
        "name": "John Doe",
        "email": "john@example.com"
    }

    # Act
    user = service.create(user_data)

    # Assert
    assert user.name == "John Doe"
    assert user.email == "john@example.com"
    assert user.id is not None

def test_create_user_with_duplicate_email_raises_error():
    # Arrange
    service = UserService()
    service.create({"name": "John", "email": "john@example.com"})

    # Act & Assert
    with pytest.raises(ValidationError) as exc_info:
        service.create({"name": "Jane", "email": "john@example.com"})

    assert "already exists" in str(exc_info.value)
```

### Fixtures

```python
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

@pytest.fixture
def db_session():
    """Create a test database session"""
    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()

    yield session

    session.close()

@pytest.fixture
def user_repository(db_session):
    """Create a UserRepository with test database"""
    return UserRepository(db_session)

@pytest.fixture
def sample_user():
    """Create a sample user for testing"""
    return User(name="John Doe", email="john@example.com")

# Usage
def test_find_user(user_repository, sample_user, db_session):
    db_session.add(sample_user)
    db_session.commit()

    found = user_repository.find_by_email("john@example.com")
    assert found is not None
    assert found.name == "John Doe"
```

### Parametrized Tests

```python
@pytest.mark.parametrize("email,expected", [
    ("valid@example.com", True),
    ("invalid", False),
    ("@example.com", False),
    ("test@test", False),
])
def test_email_validation(email, expected):
    result = EmailValidator.is_valid(email)
    assert result == expected

@pytest.mark.parametrize("age", [17, 0, -1, 151])
def test_age_validation_rejects_invalid(age):
    with pytest.raises(ValidationError):
        User(name="John", email="john@example.com", age=age)
```

## Code Templates

### FastAPI Application Structure

```python
# main.py
from fastapi import FastAPI, Depends
from app.routers import users
from app.database import engine, Base

Base.metadata.create_all(bind=engine)

app = FastAPI(title="My API", version="1.0.0")

app.include_router(users.router, prefix="/api/v1/users", tags=["users"])

@app.get("/health")
async def health_check():
    return {"status": "healthy"}
```

```python
# app/routers/users.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.schemas import UserCreate, UserResponse
from app.services import UserService

router = APIRouter()

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: int,
    db: Session = Depends(get_db)
):
    service = UserService(db)
    user = service.get_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.post("/", response_model=UserResponse, status_code=201)
async def create_user(
    user_data: UserCreate,
    db: Session = Depends(get_db)
):
    service = UserService(db)
    return service.create(user_data)
```

## Common Anti-Patterns to Avoid

### 1. Mutable Default Arguments

```python
# Bad - mutable default
def add_item(item, items=[]):
    items.append(item)
    return items

# Problem: default list is shared across calls!
add_item(1)  # [1]
add_item(2)  # [1, 2] - unexpected!

# Good
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

### 2. Catching Too Broad Exceptions

```python
# Bad
try:
    do_something()
except:  # Catches everything, including KeyboardInterrupt!
    pass

# Good
try:
    do_something()
except ValueError as e:
    logger.error(f"Invalid value: {e}")
```

### 3. Using `+` for String Building

```python
# Bad - inefficient for many strings
result = ""
for item in items:
    result += str(item) + ", "

# Good - use join
result = ", ".join(str(item) for item in items)

# Good - for formatting
result = f"{name}, {age} years old"
```

### 4. Not Using Enumerate

```python
# Bad
for i in range(len(items)):
    print(i, items[i])

# Good
for i, item in enumerate(items):
    print(i, item)
```

## Security Best Practices

### Password Hashing

```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Hashing
hashed = pwd_context.hash("my_password")

# Verification
is_valid = pwd_context.verify("my_password", hashed)
```

### SQL Injection Prevention

```python
# Good - parameterized query (SQLAlchemy)
user = db.query(User).filter(User.email == email).first()

# Good - parameterized query (raw SQL)
cursor.execute("SELECT * FROM users WHERE email = ?", (email,))

# Bad - string concatenation (SQL injection risk!)
query = f"SELECT * FROM users WHERE email = '{email}'"
```

### Input Validation

```python
from pydantic import BaseModel, validator, EmailStr

class UserInput(BaseModel):
    email: EmailStr  # Built-in email validation
    age: int

    @validator('age')
    def validate_age(cls, v):
        if v < 0 or v > 150:
            raise ValueError('Age must be between 0 and 150')
        return v
```

## Quick Reference

### Common Imports

```python
# Standard library
import os
import sys
from pathlib import Path
from typing import Optional, List, Dict
from datetime import datetime, timedelta

# FastAPI
from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel, Field, validator

# SQLAlchemy
from sqlalchemy import Column, Integer, String, create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.ext.declarative import declarative_base

# pytest
import pytest
from pytest import fixture
```

### String Formatting

```python
# f-strings (preferred)
message = f"Hello, {name}!"

# format method
message = "Hello, {}!".format(name)

# %-formatting (old style, avoid)
message = "Hello, %s!" % name
```

### Path Operations

```python
from pathlib import Path

# Good - pathlib
path = Path("folder") / "file.txt"
if path.exists():
    content = path.read_text()

# Old style - os.path
import os
path = os.path.join("folder", "file.txt")
if os.path.exists(path):
    with open(path) as f:
        content = f.read()
```
