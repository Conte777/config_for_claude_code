# Python Libraries Quick Reference

## FastAPI

### Basic Application
```python
from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel, EmailStr, Field

app = FastAPI(title="My API", version="1.0.0")

class UserCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr

class UserResponse(BaseModel):
    id: int
    name: str
    email: str

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

# Run: uvicorn main:app --reload
```

### Dependency Injection
```python
from sqlalchemy.orm import Session

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_user_service(db: Session = Depends(get_db)) -> UserService:
    return UserService(db)

@app.get("/users/{user_id}")
async def get_user(
    user_id: int,
    service: UserService = Depends(get_user_service)
):
    return service.get_user(user_id)
```

## Django

### Models
```python
from django.db import models

class User(models.Model):
    name = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'users'
        ordering = ['-created_at']

    def __str__(self):
        return self.name
```

### Views
```python
from django.views.generic import ListView, CreateView
from django.urls import reverse_lazy

class UserListView(ListView):
    model = User
    template_name = 'users/list.html'
    context_object_name = 'users'
    paginate_by = 20

class UserCreateView(CreateView):
    model = User
    fields = ['name', 'email']
    template_name = 'users/create.html'
    success_url = reverse_lazy('user-list')
```

## SQLAlchemy

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
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)
```

### CRUD Operations
```python
from sqlalchemy.orm import Session

class UserRepository:
    def __init__(self, db: Session):
        self.db = db

    def find_by_id(self, user_id: int) -> Optional[User]:
        return self.db.query(User).filter(User.id == user_id).first()

    def create(self, user: User) -> User:
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def update(self, user: User) -> User:
        self.db.commit()
        self.db.refresh(user)
        return user
```

## Pydantic

### Validation
```python
from pydantic import BaseModel, EmailStr, Field, validator

class UserCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    age: int = Field(..., ge=18, le=150)

    @validator('name')
    def name_must_not_be_blank(cls, v):
        if not v.strip():
            raise ValueError('Name cannot be blank')
        return v.strip()

    class Config:
        schema_extra = {
            "example": {
                "name": "John Doe",
                "email": "john@example.com",
                "age": 30
            }
        }
```

## pytest

### Basic Tests
```python
import pytest
from myapp.services import UserService

def test_create_user_with_valid_data():
    # Arrange
    service = UserService()
    user_data = {"name": "John", "email": "john@example.com"}

    # Act
    user = service.create(user_data)

    # Assert
    assert user.name == "John"
    assert user.email == "john@example.com"

def test_create_user_with_duplicate_email_raises_error():
    service = UserService()
    service.create({"name": "John", "email": "john@example.com"})

    with pytest.raises(ValidationError) as exc_info:
        service.create({"name": "Jane", "email": "john@example.com"})

    assert "already exists" in str(exc_info.value)
```

### Fixtures
```python
import pytest

@pytest.fixture
def db_session():
    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()

@pytest.fixture
def user_repository(db_session):
    return UserRepository(db_session)

@pytest.fixture
def sample_user():
    return User(name="John", email="john@example.com")

# Usage
def test_find_user(user_repository, sample_user, db_session):
    db_session.add(sample_user)
    db_session.commit()

    found = user_repository.find_by_email("john@example.com")
    assert found is not None
```

### Parametrized Tests
```python
@pytest.mark.parametrize("email,expected", [
    ("valid@example.com", True),
    ("invalid", False),
    ("@example.com", False),
])
def test_email_validation(email, expected):
    result = EmailValidator.is_valid(email)
    assert result == expected
```

## Requests

### HTTP Client
```python
import requests

# GET request
response = requests.get('https://api.example.com/users/1')
user = response.json()

# POST request
data = {"name": "John", "email": "john@example.com"}
response = requests.post(
    'https://api.example.com/users',
    json=data,
    headers={'Content-Type': 'application/json'}
)

# Error handling
try:
    response = requests.get('https://api.example.com/users/1')
    response.raise_for_status()  # Raises HTTPError for bad status
    user = response.json()
except requests.exceptions.RequestException as e:
    print(f"Error: {e}")
```

## Celery

### Async Tasks
```python
from celery import Celery

app = Celery('tasks', broker='redis://localhost:6379/0')

@app.task
def send_email(email, message):
    # Email sending logic
    return f"Email sent to {email}"

# Call task asynchronously
result = send_email.delay('user@example.com', 'Hello!')

# Get result
result.get(timeout=10)
```

## Pandas

### Data Manipulation
```python
import pandas as pd

# Read data
df = pd.read_csv('users.csv')

# Basic operations
df.head()
df.describe()
df.info()

# Filtering
active_users = df[df['is_active'] == True]
young_users = df[df['age'] < 30]

# Grouping
df.groupby('country')['age'].mean()

# Export
df.to_csv('output.csv', index=False)
df.to_json('output.json', orient='records')
```

## httpx

### Async HTTP Client
```python
import httpx
import asyncio

async def fetch_user(user_id: int):
    async with httpx.AsyncClient() as client:
        response = await client.get(f'https://api.example.com/users/{user_id}')
        return response.json()

async def main():
    users = await asyncio.gather(
        fetch_user(1),
        fetch_user(2),
        fetch_user(3)
    )
    return users

# Run
asyncio.run(main())
```

## python-dotenv

### Environment Variables
```python
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL')
SECRET_KEY = os.getenv('SECRET_KEY')
DEBUG = os.getenv('DEBUG', 'False') == 'True'
```

## Alembic

### Database Migrations
```bash
# Initialize
alembic init alembic

# Create migration
alembic revision --autogenerate -m "Add users table"

# Apply migration
alembic upgrade head

# Rollback
alembic downgrade -1
```

```python
# alembic/env.py
from myapp.models import Base
target_metadata = Base.metadata
```
