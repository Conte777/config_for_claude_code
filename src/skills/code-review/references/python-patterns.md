# Python Patterns Reference

Паттерны и anti-patterns специфичные для Python.

## GIL Implications

### 1. Threading for CPU-Bound Tasks

**Anti-pattern:**
```python
# BAD: Threading for CPU-bound work
import threading

def cpu_intensive(n):
    return sum(i * i for i in range(n))

threads = [
    threading.Thread(target=cpu_intensive, args=(10_000_000,))
    for _ in range(4)
]
for t in threads:
    t.start()
for t in threads:
    t.join()
# GIL prevents parallel execution - slower than single thread!
```

**Pattern:**
```python
# GOOD: Multiprocessing for CPU-bound
from multiprocessing import Pool

def cpu_intensive(n):
    return sum(i * i for i in range(n))

with Pool(4) as pool:
    results = pool.map(cpu_intensive, [10_000_000] * 4)
# True parallel execution
```

**Severity:** 🟡 MEDIUM

### 2. Threading for I/O-Bound Tasks

**Pattern:**
```python
# GOOD: Threading is fine for I/O
import threading
import requests

def fetch(url):
    return requests.get(url).text

threads = [
    threading.Thread(target=fetch, args=(url,))
    for url in urls
]
# GIL released during I/O - works well

# BETTER: asyncio for many concurrent I/O operations
import asyncio
import aiohttp

async def fetch_all(urls):
    async with aiohttp.ClientSession() as session:
        tasks = [session.get(url) for url in urls]
        return await asyncio.gather(*tasks)
```

**Severity:** 💡 INFO

### 3. Blocking Calls in Async

**Anti-pattern:**
```python
# BAD: Blocking call in async function
import asyncio
import requests

async def fetch_data(url):
    response = requests.get(url)  # Blocks event loop!
    return response.json()
```

**Pattern:**
```python
# GOOD: Use async library
import aiohttp

async def fetch_data(url):
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            return await response.json()

# GOOD: Or run in thread pool
import asyncio
import requests

async def fetch_data(url):
    loop = asyncio.get_event_loop()
    response = await loop.run_in_executor(
        None, requests.get, url
    )
    return response.json()
```

**Severity:** 🟠 HIGH

## Context Managers

### 1. Manual Cleanup

**Anti-pattern:**
```python
# BAD: Manual resource management
def process_file(path):
    f = open(path)
    try:
        data = f.read()
        process(data)
    finally:
        f.close()  # Easy to forget, hard to get right
```

**Pattern:**
```python
# GOOD: Context manager
def process_file(path):
    with open(path) as f:
        data = f.read()
        process(data)
    # Automatically closed, even on exception
```

**Severity:** 🟡 MEDIUM

### 2. Multiple Resources

**Anti-pattern:**
```python
# BAD: Nested with statements (old style)
with open('input.txt') as infile:
    with open('output.txt', 'w') as outfile:
        outfile.write(infile.read())
```

**Pattern:**
```python
# GOOD: Multiple context managers
with open('input.txt') as infile, open('output.txt', 'w') as outfile:
    outfile.write(infile.read())

# GOOD: Parentheses for long lines (Python 3.10+)
with (
    open('input.txt') as infile,
    open('output.txt', 'w') as outfile,
):
    outfile.write(infile.read())
```

**Severity:** 💡 INFO

### 3. Custom Context Managers

**Anti-pattern:**
```python
# BAD: Not using contextlib
class DatabaseConnection:
    def __init__(self):
        self.conn = None

    def connect(self):
        self.conn = create_connection()
        return self

    def close(self):
        self.conn.close()
```

**Pattern:**
```python
# GOOD: contextlib.contextmanager
from contextlib import contextmanager

@contextmanager
def database_connection():
    conn = create_connection()
    try:
        yield conn
    finally:
        conn.close()

# Usage
with database_connection() as conn:
    conn.execute(query)

# GOOD: Class-based context manager
class DatabaseConnection:
    def __enter__(self):
        self.conn = create_connection()
        return self.conn

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.conn.close()
        return False  # Don't suppress exceptions
```

**Severity:** 🟡 MEDIUM

## Type Hints

### 1. Missing Type Hints

**Anti-pattern:**
```python
# BAD: No type information
def process_users(users, filter_fn):
    return [u for u in users if filter_fn(u)]
```

**Pattern:**
```python
# GOOD: With type hints
from typing import Callable

def process_users(
    users: list[User],
    filter_fn: Callable[[User], bool]
) -> list[User]:
    return [u for u in users if filter_fn(u)]
```

**Severity:** 🟡 MEDIUM

### 2. Optional Without Check

**Anti-pattern:**
```python
# BAD: Optional not checked
from typing import Optional

def get_user_name(user: Optional[User]) -> str:
    return user.name  # AttributeError if None!
```

**Pattern:**
```python
# GOOD: Guard clause
def get_user_name(user: Optional[User]) -> str:
    if user is None:
        return "Unknown"
    return user.name

# GOOD: Early return
def process_user(user: Optional[User]) -> None:
    if user is None:
        return
    # Now user is definitely not None
    send_email(user.email)
```

**Severity:** 🟠 HIGH

### 3. Type Narrowing

**Pattern:**
```python
# Using isinstance for type narrowing
from typing import Union

def process(value: Union[str, int]) -> str:
    if isinstance(value, str):
        return value.upper()  # Type checker knows it's str
    return str(value * 2)  # Type checker knows it's int
```

**Severity:** 💡 INFO

## Pythonic Idioms

### 1. LBYL vs EAFP

**Anti-pattern:**
```python
# BAD: LBYL (Look Before You Leap) - not Pythonic
def get_value(d, key):
    if key in d:
        return d[key]
    return None
```

**Pattern:**
```python
# GOOD: EAFP (Easier to Ask Forgiveness than Permission)
def get_value(d, key):
    try:
        return d[key]
    except KeyError:
        return None

# BETTER: Use dict methods
def get_value(d, key):
    return d.get(key)
```

**Severity:** 💡 INFO

### 2. List Comprehensions vs Loops

**Anti-pattern:**
```python
# BAD: Loop for simple transformation
result = []
for item in items:
    if item.active:
        result.append(item.name)
```

**Pattern:**
```python
# GOOD: List comprehension
result = [item.name for item in items if item.active]

# GOOD: Generator for large sequences
result = (item.name for item in items if item.active)
```

**Severity:** 💡 INFO

### 3. String Formatting

**Anti-pattern:**
```python
# BAD: Old-style formatting
message = "Hello, %s! You have %d messages." % (name, count)

# BAD: .format() is verbose
message = "Hello, {}! You have {} messages.".format(name, count)
```

**Pattern:**
```python
# GOOD: f-strings (Python 3.6+)
message = f"Hello, {name}! You have {count} messages."

# GOOD: With expressions
message = f"Total: ${price * quantity:.2f}"
```

**Severity:** 💡 INFO

## Async Patterns

### 1. Missing await

**Anti-pattern:**
```python
# BAD: Forgetting await
async def process():
    result = fetch_data()  # Returns coroutine, not result!
    return result
```

**Pattern:**
```python
# GOOD: Always await coroutines
async def process():
    result = await fetch_data()
    return result
```

**Severity:** 🔴 CRITICAL

### 2. Asyncio.run in Wrong Context

**Anti-pattern:**
```python
# BAD: asyncio.run inside async function
async def main():
    result = asyncio.run(some_coro())  # RuntimeError!
```

**Pattern:**
```python
# GOOD: Use await inside async functions
async def main():
    result = await some_coro()

# GOOD: asyncio.run only at top level
if __name__ == "__main__":
    asyncio.run(main())
```

**Severity:** 🔴 CRITICAL

### 3. Gather Error Handling

**Anti-pattern:**
```python
# BAD: One failure stops all
async def fetch_all(urls):
    tasks = [fetch(url) for url in urls]
    results = await asyncio.gather(*tasks)
    # If one fails, all results lost
```

**Pattern:**
```python
# GOOD: return_exceptions=True
async def fetch_all(urls):
    tasks = [fetch(url) for url in urls]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    for result in results:
        if isinstance(result, Exception):
            log.error(f"Failed: {result}")
        else:
            process(result)
```

**Severity:** 🟡 MEDIUM
