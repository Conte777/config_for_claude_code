# Python + FastAPI Patterns Reference

Паттерны и anti-patterns для FastAPI.

## Dependency Injection

### 1. Basic Dependencies

**Anti-pattern:**
```python
# BAD: Creating database session in each endpoint
@app.get("/users/{user_id}")
async def get_user(user_id: int):
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).first()
        return user
    finally:
        db.close()
```

**Pattern:**
```python
# GOOD: Use Depends for database session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/users/{user_id}")
async def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    return user
```

**Severity:** 🟠 HIGH

### 2. Yield Dependencies Cleanup

**Anti-pattern:**
```python
# BAD: Exception in cleanup not handled
def get_resource():
    resource = acquire_resource()
    yield resource
    resource.close()  # Not called if endpoint raises!
```

**Pattern:**
```python
# GOOD: try/finally for cleanup
def get_resource():
    resource = acquire_resource()
    try:
        yield resource
    finally:
        resource.close()

# GOOD: With exception handling
def get_resource():
    resource = acquire_resource()
    try:
        yield resource
    except Exception:
        log.error("Error during request")
        raise
    finally:
        resource.close()
```

**Severity:** 🟠 HIGH

### 3. Nested Dependencies

**Pattern:**
```python
# GOOD: Dependencies can depend on other dependencies
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    user = authenticate(token, db)
    if not user:
        raise HTTPException(status_code=401)
    return user

@app.get("/me")
async def read_users_me(user: User = Depends(get_current_user)):
    return user
```

**Severity:** 💡 INFO

## Async Endpoint Pitfalls

### 1. Blocking Calls in Async Endpoints

**Anti-pattern:**
```python
# BAD: Blocking I/O in async endpoint
@app.get("/data")
async def get_data():
    # requests is synchronous - blocks event loop!
    response = requests.get("https://api.example.com/data")
    return response.json()

# BAD: Synchronous file I/O
@app.get("/file")
async def read_file():
    with open("large_file.txt") as f:
        return f.read()  # Blocks!
```

**Pattern:**
```python
# GOOD: Use httpx async client
import httpx

@app.get("/data")
async def get_data():
    async with httpx.AsyncClient() as client:
        response = await client.get("https://api.example.com/data")
        return response.json()

# GOOD: Use aiofiles for file I/O
import aiofiles

@app.get("/file")
async def read_file():
    async with aiofiles.open("large_file.txt") as f:
        return await f.read()

# GOOD: Or use sync endpoint if blocking is unavoidable
@app.get("/sync-data")
def get_data():  # Note: def, not async def
    response = requests.get("https://api.example.com/data")
    return response.json()
```

**Severity:** 🟠 HIGH

### 2. CPU-Intensive Operations

**Anti-pattern:**
```python
# BAD: CPU-intensive in async endpoint
@app.get("/compute")
async def compute():
    result = heavy_computation()  # Blocks event loop!
    return {"result": result}
```

**Pattern:**
```python
# GOOD: Run in thread pool
from concurrent.futures import ThreadPoolExecutor
import asyncio

executor = ThreadPoolExecutor(max_workers=4)

@app.get("/compute")
async def compute():
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(executor, heavy_computation)
    return {"result": result}

# GOOD: Or use sync endpoint
@app.get("/compute")
def compute():  # FastAPI runs this in thread pool automatically
    result = heavy_computation()
    return {"result": result}
```

**Severity:** 🟠 HIGH

### 3. Background Tasks

**Pattern:**
```python
# GOOD: Use BackgroundTasks for fire-and-forget
from fastapi import BackgroundTasks

def send_email(email: str, message: str):
    # Slow operation
    email_service.send(email, message)

@app.post("/users")
async def create_user(
    user: UserCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    db_user = create_user_db(db, user)
    background_tasks.add_task(send_email, user.email, "Welcome!")
    return db_user
```

**Severity:** 💡 INFO

## Pydantic Validation

### 1. Request Validation

**Anti-pattern:**
```python
# BAD: Manual validation
@app.post("/users")
async def create_user(data: dict):
    if "email" not in data:
        raise HTTPException(400, "Email required")
    if "@" not in data["email"]:
        raise HTTPException(400, "Invalid email")
    # ...
```

**Pattern:**
```python
# GOOD: Pydantic model validation
from pydantic import BaseModel, EmailStr, Field

class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(..., min_length=2, max_length=100)
    age: int = Field(..., ge=0, le=150)

@app.post("/users")
async def create_user(user: UserCreate):
    # Validation happens automatically
    return create_user_db(user)
```

**Severity:** 🟡 MEDIUM

### 2. Response Model

**Anti-pattern:**
```python
# BAD: Returning internal model with sensitive data
@app.get("/users/{user_id}")
async def get_user(user_id: int, db: Session = Depends(get_db)):
    return db.query(User).get(user_id)  # password_hash exposed!
```

**Pattern:**
```python
# GOOD: Response model filters output
class UserResponse(BaseModel):
    id: int
    email: str
    name: str

    class Config:
        from_attributes = True

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: Session = Depends(get_db)):
    return db.query(User).get(user_id)  # Only id, email, name returned
```

**Severity:** 🔴 CRITICAL

## Security Patterns

### 1. OAuth2 Implementation

**Anti-pattern:**
```python
# BAD: No token validation
@app.get("/protected")
async def protected(token: str = Header()):
    if token:
        return {"data": "secret"}
    raise HTTPException(401)
```

**Pattern:**
```python
# GOOD: Proper OAuth2 with JWT
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise HTTPException(401, "Invalid token")
    except JWTError:
        raise HTTPException(401, "Invalid token")

    user = get_user(username)
    if user is None:
        raise HTTPException(401, "User not found")
    return user

@app.get("/protected")
async def protected(user: User = Depends(get_current_user)):
    return {"data": "secret", "user": user.username}
```

**Severity:** 🔴 CRITICAL

### 2. CORS Configuration

**Anti-pattern:**
```python
# BAD: Allow all origins
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Dangerous in production!
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Pattern:**
```python
# GOOD: Specific origins
from fastapi.middleware.cors import CORSMiddleware

origins = [
    "https://myapp.com",
    "https://admin.myapp.com",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
```

**Severity:** 🟠 HIGH

## Performance Patterns

### 1. Response Streaming

**Anti-pattern:**
```python
# BAD: Loading large file into memory
@app.get("/download")
async def download():
    with open("large_file.zip", "rb") as f:
        content = f.read()  # Entire file in memory!
    return Response(content, media_type="application/zip")
```

**Pattern:**
```python
# GOOD: Stream response
from fastapi.responses import StreamingResponse

@app.get("/download")
async def download():
    def iter_file():
        with open("large_file.zip", "rb") as f:
            while chunk := f.read(8192):
                yield chunk

    return StreamingResponse(
        iter_file(),
        media_type="application/zip"
    )
```

**Severity:** 🟡 MEDIUM

### 2. Connection Pooling

**Anti-pattern:**
```python
# BAD: New connection per request
async def fetch_external():
    async with httpx.AsyncClient() as client:  # New connection each time
        return await client.get("https://api.example.com")
```

**Pattern:**
```python
# GOOD: Reuse client with connection pooling
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = httpx.AsyncClient()
    yield
    await app.state.http_client.aclose()

app = FastAPI(lifespan=lifespan)

@app.get("/data")
async def get_data(request: Request):
    client = request.app.state.http_client
    response = await client.get("https://api.example.com")
    return response.json()
```

**Severity:** 🟡 MEDIUM
