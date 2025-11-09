# Go Libraries Quick Reference

## Web Frameworks

### Gin
**Purpose**: High-performance HTTP web framework
**Best For**: REST APIs, microservices

```go
package main

import "github.com/gin-gonic/gin"

func main() {
    r := gin.Default()

    // GET endpoint
    r.GET("/users/:id", func(c *gin.Context) {
        id := c.Param("id")
        c.JSON(200, gin.H{"id": id})
    })

    // POST with JSON binding
    r.POST("/users", func(c *gin.Context) {
        var user User
        if err := c.ShouldBindJSON(&user); err != nil {
            c.JSON(400, gin.H{"error": err.Error()})
            return
        }
        c.JSON(201, user)
    })

    r.Run(":8080")
}
```

### Echo
**Purpose**: Minimalist, fast HTTP framework
**Best For**: RESTful APIs, real-time applications

```go
package main

import (
    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"
)

func main() {
    e := echo.New()
    e.Use(middleware.Logger())
    e.Use(middleware.Recover())

    e.GET("/users/:id", getUser)
    e.POST("/users", createUser)

    e.Start(":8080")
}

func getUser(c echo.Context) error {
    id := c.Param("id")
    return c.JSON(200, map[string]string{"id": id})
}
```

## ORM / Database

### GORM
**Purpose**: Full-featured ORM for Go
**Best For**: Complex database operations, migrations

```go
import (
    "gorm.io/driver/postgres"
    "gorm.io/gorm"
)

// Model definition
type User struct {
    ID    uint   `gorm:"primaryKey"`
    Name  string `gorm:"size:100;not null"`
    Email string `gorm:"uniqueIndex;not null"`
}

// Connection
dsn := "host=localhost user=gorm password=gorm dbname=gorm port=5432"
db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})

// Auto-migration
db.AutoMigrate(&User{})

// CRUD operations
db.Create(&User{Name: "John", Email: "john@example.com"})
db.First(&user, "email = ?", "john@example.com")
db.Model(&user).Update("Name", "Jane")
db.Delete(&user)
```

## CLI Applications

### Cobra
**Purpose**: CLI application framework
**Best For**: Command-line tools, CLIs with subcommands

```go
package main

import (
    "github.com/spf13/cobra"
)

func main() {
    var rootCmd = &cobra.Command{
        Use:   "myapp",
        Short: "My application",
    }

    var createCmd = &cobra.Command{
        Use:   "create [name]",
        Short: "Create a new resource",
        Args:  cobra.ExactArgs(1),
        Run: func(cmd *cobra.Command, args []string) {
            name := args[0]
            // Create logic
        },
    }

    rootCmd.AddCommand(createCmd)
    rootCmd.Execute()
}
```

## Testing

### Testify
**Purpose**: Testing toolkit with assertions and mocks
**Best For**: Unit tests with readable assertions

```go
import (
    "testing"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

// Assertions
func TestSum(t *testing.T) {
    result := Sum(2, 3)
    assert.Equal(t, 5, result)
    assert.NotNil(t, result)
}

// Mocking
type MockRepository struct {
    mock.Mock
}

func (m *MockRepository) FindByID(id int) (*User, error) {
    args := m.Called(id)
    return args.Get(0).(*User), args.Error(1)
}

func TestUserService(t *testing.T) {
    mockRepo := new(MockRepository)
    mockRepo.On("FindByID", 1).Return(&User{ID: 1}, nil)

    service := NewUserService(mockRepo)
    user, err := service.GetUser(1)

    assert.NoError(t, err)
    assert.Equal(t, 1, user.ID)
    mockRepo.AssertExpectations(t)
}
```

## Configuration

### Viper
**Purpose**: Configuration management
**Best For**: 12-factor apps, multi-format config

```go
import "github.com/spf13/viper"

viper.SetConfigName("config")
viper.SetConfigType("yaml")
viper.AddConfigPath(".")

viper.ReadInConfig()

// Get values
dbHost := viper.GetString("database.host")
port := viper.GetInt("server.port")
```

## Logging

### Zap
**Purpose**: Structured, fast logging
**Best For**: Production logging, high-performance apps

```go
import "go.uber.org/zap"

logger, _ := zap.NewProduction()
defer logger.Sync()

logger.Info("User created",
    zap.String("email", "john@example.com"),
    zap.Int("id", 123),
)

logger.Error("Failed to create user",
    zap.Error(err),
)
```

## HTTP Client

### Resty
**Purpose**: Simple HTTP client
**Best For**: REST API consumption

```go
import "github.com/go-resty/resty/v2"

client := resty.New()

resp, err := client.R().
    SetHeader("Content-Type", "application/json").
    SetBody(user).
    Post("https://api.example.com/users")

var result User
resp, err := client.R().
    SetResult(&result).
    Get("https://api.example.com/users/1")
```
