# Python Code Review Guide

This guide provides Python-specific patterns, idioms, anti-patterns, and best practices for code review.

## Python Idioms and Best Practices (PEP 8)

### Naming Conventions

**✅ Good Practices:**
```python
# Variables and functions: lowercase_with_underscores
user_name = "John"
def get_user_data():
    pass

# Classes: CapitalizedWords
class UserService:
    pass

# Constants: UPPERCASE_WITH_UNDERSCORES
MAX_CONNECTIONS = 100

# Private/internal: prefix with underscore
def _internal_helper():
    pass
```

**❌ Anti-Patterns:**
```python
# DON'T: camelCase for variables/functions
userName = "John"  # ❌ Use user_name
def getUserData():  # ❌ Use get_user_data()
    pass

# DON'T: mixedCase for classes
class userService:  # ❌ Use UserService
    pass
```

### List Comprehensions and Generator Expressions

**✅ Good Practices:**
```python
# List comprehension for simple transformations
squares = [x**2 for x in range(10)]

# Generator expression for large datasets (memory efficient)
sum_of_squares = sum(x**2 for x in range(1000000))

# Comprehension with condition
even_squares = [x**2 for x in range(10) if x % 2 == 0]

# Dict comprehension
user_map = {user.id: user for user in users}
```

**❌ Anti-Patterns:**
```python
# DON'T: Complex comprehensions that hurt readability
result = [item.process().validate().transform()
          for sublist in nested_list
          for item in sublist
          if item.is_valid() and item.status == 'active'
          and item.priority > 5]  # ❌ Too complex, use explicit loops

# DON'T: Use list() when generator is sufficient
sum_of_squares = sum([x**2 for x in range(1000000)])  # ❌ Wastes memory
```

### Context Managers

**✅ Good Practices:**
```python
# Always use context managers for resources
with open('file.txt', 'r') as f:
    data = f.read()
# File automatically closed

# Multiple context managers
with open('input.txt') as infile, open('output.txt', 'w') as outfile:
    outfile.write(infile.read())

# Custom context manager
from contextlib import contextmanager

@contextmanager
def database_connection(conn_string):
    conn = connect(conn_string)
    try:
        yield conn
    finally:
        conn.close()
```

**❌ Anti-Patterns:**
```python
# DON'T: Manually close resources
f = open('file.txt')
data = f.read()
f.close()  # ❌ Forgotten if exception occurs

# DON'T: Forget cleanup in exception
try:
    f = open('file.txt')
    data = f.read()
finally:
    f.close()  # ❌ Use context manager instead
```

### Exception Handling

**✅ Good Practices:**
```python
# Catch specific exceptions
try:
    result = int(user_input)
except ValueError as e:
    logger.error(f"Invalid input: {e}")
    return None

# Multiple exceptions
try:
    process_data()
except (IOError, ValueError) as e:
    handle_error(e)

# Re-raise with context
try:
    save_to_db(data)
except DatabaseError as e:
    logger.error(f"Failed to save: {e}")
    raise  # Re-raise original exception
```

**❌ Anti-Patterns:**
```python
# DON'T: Bare except
try:
    risky_operation()
except:  # ❌ Catches everything, including KeyboardInterrupt
    pass

# DON'T: Catch Exception without logging
try:
    process()
except Exception:
    pass  # ❌ Silent failure

# DON'T: Exception swallowing
try:
    critical_operation()
except Exception as e:
    return None  # ❌ Error is lost
```

### Type Hints (Python 3.5+)

**✅ Good Practices:**
```python
from typing import List, Dict, Optional, Union

def get_user_names(users: List[User]) -> List[str]:
    return [user.name for user in users]

# Optional for nullable values
def find_user(user_id: int) -> Optional[User]:
    return users.get(user_id)

# Union for multiple types
def process(value: Union[int, str]) -> str:
    return str(value)

# TypedDict for structured dicts
from typing import TypedDict

class UserDict(TypedDict):
    id: int
    name: str
    email: str
```

**❌ Anti-Patterns:**
```python
# DON'T: Inconsistent type hints
def process_data(users):  # ❌ Missing type hints
    return users

# DON'T: Use mutable defaults
def add_item(item: str, items: List[str] = []):  # ❌ Dangerous!
    items.append(item)
    return items
# Use: items: Optional[List[str]] = None, then items = items or []
```

## Python Security Patterns

### SQL Injection Prevention

**✅ Good Practices:**
```python
# ALWAYS use parameterized queries
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# With SQLAlchemy (ORM)
from sqlalchemy import text
result = session.execute(
    text("SELECT * FROM users WHERE id = :id"),
    {"id": user_id}
)

# Better: Use ORM methods
user = session.query(User).filter_by(id=user_id).first()
```

**❌ Anti-Patterns:**
```python
# DON'T: String formatting in SQL
query = f"SELECT * FROM users WHERE id = {user_id}"  # ❌ SQL injection
cursor.execute(query)

# DON'T: % formatting
query = "SELECT * FROM users WHERE name = '%s'" % username  # ❌
cursor.execute(query)
```

### Input Validation and Sanitization

**✅ Good Practices:**
```python
import re
from email_validator import validate_email

# Validate email
def is_valid_email(email: str) -> bool:
    try:
        validate_email(email)
        return True
    except:
        return False

# Whitelist validation
ALLOWED_ACTIONS = {'read', 'write', 'delete'}

def is_valid_action(action: str) -> bool:
    return action in ALLOWED_ACTIONS

# Sanitize HTML
from bleach import clean
safe_html = clean(user_html, tags=['p', 'a', 'strong'], strip=True)
```

### Password Hashing

**✅ Good Practices:**
```python
from passlib.hash import bcrypt

# Hash password
def hash_password(password: str) -> str:
    return bcrypt.hash(password)

# Verify password
def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.verify(password, hashed)
```

**❌ Anti-Patterns:**
```python
# DON'T: Store passwords in plaintext
user.password = request.form['password']  # ❌

# DON'T: Use weak hashing (MD5, SHA1)
import hashlib
hashed = hashlib.md5(password.encode()).hexdigest()  # ❌ Not secure

# DON'T: Hash without salt
hashed = hashlib.sha256(password.encode()).hexdigest()  # ❌ No salt
```

### Secrets and Configuration

**✅ Good Practices:**
```python
import os
from dotenv import load_dotenv

# Load from environment variables
load_dotenv()
SECRET_KEY = os.environ.get('SECRET_KEY')
DATABASE_URL = os.environ.get('DATABASE_URL')

# Validate required secrets
if not SECRET_KEY:
    raise ValueError("SECRET_KEY environment variable is required")

# Use secrets module for tokens
import secrets
token = secrets.token_urlsafe(32)
```

**❌ Anti-Patterns:**
```python
# DON'T: Hardcode secrets
API_KEY = "sk-1234567890"  # ❌
DATABASE_PASSWORD = "admin123"  # ❌

# DON'T: Commit .env files
# Add .env to .gitignore!
```

## Python Performance Patterns

### Use Built-in Functions and Libraries

**✅ Good Practices:**
```python
# Use sum() instead of manual loop
total = sum(numbers)

# Use any() and all()
has_negative = any(x < 0 for x in numbers)
all_positive = all(x > 0 for x in numbers)

# Use collections.Counter for counting
from collections import Counter
word_counts = Counter(words)

# Use set operations for membership testing
allowed_ids = {1, 2, 3, 4, 5}  # O(1) lookup
if user_id in allowed_ids:  # Fast
    pass
```

**❌ Anti-Patterns:**
```python
# DON'T: Reinvent the wheel
total = 0
for num in numbers:
    total += num  # ❌ Use sum(numbers)

# DON'T: Use list for membership testing
allowed_ids = [1, 2, 3, 4, 5]  # O(n) lookup
if user_id in allowed_ids:  # ❌ Slow, use set
    pass
```

### String Operations

**✅ Good Practices:**
```python
# Use join() for concatenating many strings
parts = ['Hello', 'World', '!']
result = ' '.join(parts)  # Fast

# f-strings for formatting (Python 3.6+)
message = f"User {user.name} has {user.points} points"

# str.startswith() and str.endswith()
if filename.endswith('.txt'):
    process_text_file(filename)
```

**❌ Anti-Patterns:**
```python
# DON'T: Concatenate strings in loop
result = ""
for s in strings:
    result += s  # ❌ Slow, creates new string each time

# DON'T: Old-style formatting
message = "User %s has %d points" % (name, points)  # ❌ Use f-strings
```

### Avoid Global State

**✅ Good Practices:**
```python
# Dependency injection
class UserService:
    def __init__(self, db: Database):
        self.db = db

# Class/instance variables
class Config:
    def __init__(self):
        self.debug = False
```

**❌ Anti-Patterns:**
```python
# DON'T: Global mutable state
users = []  # ❌ Global variable

def add_user(user):
    global users  # ❌ Modifying global state
    users.append(user)
```

## Python-Specific Issues to Flag

### Mutable Default Arguments

**❌ Anti-Pattern:**
```python
def append_to_list(item, my_list=[]):  # ❌ DANGEROUS!
    my_list.append(item)
    return my_list

# Problem: List is shared across calls
list1 = append_to_list(1)  # [1]
list2 = append_to_list(2)  # [1, 2] - oops!
```

**✅ Fix:**
```python
def append_to_list(item, my_list=None):
    if my_list is None:
        my_list = []
    my_list.append(item)
    return my_list
```

### Import Statements

**✅ Good Practices:**
```python
# Imports at top of file
import os
import sys
from typing import List, Dict

# Group imports: stdlib, third-party, local
import os  # stdlib
import sys

import requests  # third-party
from flask import Flask

from myapp import models  # local
```

**❌ Anti-Patterns:**
```python
# DON'T: Wildcard imports
from module import *  # ❌ Pollutes namespace

# DON'T: Circular imports
# a.py
from b import something  # ❌ If b imports from a
```

## Async/Await Patterns (Python 3.5+)

**✅ Good Practices:**
```python
import asyncio

async def fetch_data(url: str) -> dict:
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            return await response.json()

# Gather multiple async operations
results = await asyncio.gather(
    fetch_data(url1),
    fetch_data(url2),
    fetch_data(url3)
)
```

**❌ Anti-Patterns:**
```python
# DON'T: Mix sync and async incorrectly
async def bad_async():
    time.sleep(1)  # ❌ Blocks entire event loop, use await asyncio.sleep(1)

# DON'T: Forget await
async def bad_await():
    result = fetch_data()  # ❌ Returns coroutine, use await fetch_data()
```

## Common Python Review Checklist

When reviewing Python code, check for:

- [ ] PEP 8 naming conventions followed
- [ ] Type hints used for function signatures
- [ ] Context managers used for resources (with statements)
- [ ] Specific exceptions caught, not bare except
- [ ] Parameterized queries used, no SQL injection
- [ ] Passwords hashed with bcrypt/argon2, not MD5/SHA
- [ ] Secrets loaded from environment, not hardcoded
- [ ] List comprehensions are readable (not overly complex)
- [ ] No mutable default arguments
- [ ] Built-in functions used (sum, any, all, etc.)
- [ ] f-strings used for formatting (Python 3.6+)
- [ ] Imports organized: stdlib, third-party, local
- [ ] No wildcard imports (from x import *)
- [ ] Async functions use await, not blocking calls
- [ ] Proper error logging, not silent failures
