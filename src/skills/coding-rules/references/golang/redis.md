# Go + Redis Patterns Reference

Паттерны и anti-patterns для Redis в Go (go-redis/redis).

**See also:**
- `patterns.md` — общие Go паттерны
- `uber-fx.md` — Uber FX lifecycle, DI

## Connection & Lifecycle

### 1. Missing Ping on Startup

**Проблема:** Сервис стартует без проверки Redis — падает при первом запросе.

**Anti-pattern:**
```go
// BAD: No connectivity check — fails on first request
func NewRedis(cfg *Config) *redis.Client {
    return redis.NewClient(&redis.Options{
        Addr: cfg.RedisAddr,
    })
}
```

**Pattern:**
```go
// GOOD: Ping in OnStart, Close in OnStop
func NewRedis(lc fx.Lifecycle, cfg *Config) *redis.Client {
    client := redis.NewClient(&redis.Options{
        Addr:         cfg.RedisAddr,
        Password:     cfg.RedisPassword,
        DB:           cfg.RedisDB,
        DialTimeout:  5 * time.Second,
        ReadTimeout:  3 * time.Second,
        WriteTimeout: 3 * time.Second,
    })

    lc.Append(fx.Hook{
        OnStart: func(ctx context.Context) error {
            return client.Ping(ctx).Err()
        },
        OnStop: func(ctx context.Context) error {
            return client.Close()
        },
    })

    return client
}
```

**Severity:** 🟠 HIGH

### 2. Missing Close on Shutdown

**Проблема:** Без `Close()` соединения утекают — connection pool исчерпан.

**Anti-pattern:**
```go
// BAD: No Close — connection leak
lc.Append(fx.Hook{
    OnStart: func(ctx context.Context) error {
        return client.Ping(ctx).Err()
    },
    // No OnStop!
})
```

**Pattern:**
```go
// GOOD: Always close in OnStop
lc.Append(fx.Hook{
    OnStart: func(ctx context.Context) error {
        return client.Ping(ctx).Err()
    },
    OnStop: func(ctx context.Context) error {
        return client.Close()
    },
})
```

**Severity:** 🟡 MEDIUM

## Cache Patterns

### 3. Ignoring redis.Nil

**Проблема:** `redis.Nil` означает "ключ не найден", но обрабатывается как ошибка.

**Anti-pattern:**
```go
// BAD: Treats cache miss as error
func (r *Repo) GetUser(ctx context.Context, id string) (*User, error) {
    data, err := r.redis.Get(ctx, "user:"+id).Bytes()
    if err != nil {
        return nil, err // redis.Nil treated as error!
    }
    var user User
    json.Unmarshal(data, &user)
    return &user, nil
}
```

**Pattern:**
```go
// GOOD: Handle redis.Nil separately
func (r *Repo) GetUser(ctx context.Context, id string) (*User, error) {
    data, err := r.redis.Get(ctx, "user:"+id).Bytes()
    if err != nil {
        if errors.Is(err, redis.Nil) {
            return nil, nil // Cache miss — not an error
        }
        return nil, fmt.Errorf("redis get user:%s: %w", id, err)
    }
    var user User
    if err := json.Unmarshal(data, &user); err != nil {
        return nil, fmt.Errorf("unmarshal user: %w", err)
    }
    return &user, nil
}
```

**Severity:** 🟠 HIGH

### 4. Thundering Herd (Cache Stampede)

**Проблема:** При истечении TTL все горутины идут в БД одновременно.

**Anti-pattern:**
```go
// BAD: All goroutines hit DB on cache miss
func (s *Service) GetProduct(ctx context.Context, id string) (*Product, error) {
    cached, err := s.cache.Get(ctx, "product:"+id)
    if err == nil {
        return cached, nil
    }
    // 100 goroutines all hit DB simultaneously
    product, err := s.repo.GetProduct(ctx, id)
    if err != nil {
        return nil, err
    }
    s.cache.Set(ctx, "product:"+id, product, 5*time.Minute)
    return product, nil
}
```

**Pattern:**
```go
// GOOD: singleflight prevents stampede
import "golang.org/x/sync/singleflight"

type Service struct {
    cache *redis.Client
    repo  deps.Repository
    sf    singleflight.Group
}

func (s *Service) GetProduct(ctx context.Context, id string) (*Product, error) {
    cacheKey := "product:" + id

    data, err := s.cache.Get(ctx, cacheKey).Bytes()
    if err == nil {
        var p Product
        json.Unmarshal(data, &p)
        return &p, nil
    }

    // Only one goroutine fetches from DB
    result, err, _ := s.sf.Do(cacheKey, func() (interface{}, error) {
        product, err := s.repo.GetProduct(ctx, id)
        if err != nil {
            return nil, err
        }
        data, _ := json.Marshal(product)
        s.cache.Set(ctx, cacheKey, data, 5*time.Minute)
        return product, nil
    })
    if err != nil {
        return nil, err
    }
    return result.(*Product), nil
}
```

**Severity:** 🟠 HIGH

### 5. Missing TTL on Cache Keys

**Проблема:** Кэш без TTL растёт бесконечно и никогда не инвалидируется.

**Anti-pattern:**
```go
// BAD: No TTL — cache grows forever, stale data
s.redis.Set(ctx, "user:"+id, data, 0) // 0 = no expiration
```

**Pattern:**
```go
// GOOD: Always set TTL
s.redis.Set(ctx, "user:"+id, data, 15*time.Minute)

// GOOD: Different TTL strategies
const (
    shortTTL  = 5 * time.Minute   // frequently changing data
    mediumTTL = 30 * time.Minute  // moderately stable data
    longTTL   = 24 * time.Hour    // rarely changing data
)
```

**Severity:** 🟡 MEDIUM

## Key Naming

### 6. Flat Key Namespace

**Проблема:** Неструктурированные ключи — коллизии, сложно дебажить.

**Anti-pattern:**
```go
// BAD: Flat keys — collision risk, hard to debug
s.redis.Set(ctx, id, data, ttl)
s.redis.Set(ctx, "lock_"+id, "1", ttl)
```

**Pattern:**
```go
// GOOD: Structured keys with service:entity:id pattern
const (
    keyPrefix = "payment-service"
)

func userCacheKey(id string) string {
    return fmt.Sprintf("%s:user:%s", keyPrefix, id)
}

func orderCacheKey(id string) string {
    return fmt.Sprintf("%s:order:%s", keyPrefix, id)
}

func lockKey(resource, id string) string {
    return fmt.Sprintf("%s:lock:%s:%s", keyPrefix, resource, id)
}
```

**Severity:** 🟡 MEDIUM

## Distributed Lock

### 7. Lock Without Owner Check

**Проблема:** `DEL` для разблокировки может удалить чужой lock (если TTL истёк и другой процесс занял lock).

**Anti-pattern:**
```go
// BAD: DEL may release someone else's lock
func (l *Lock) Acquire(ctx context.Context, key string) error {
    return l.redis.SetNX(ctx, key, "locked", 10*time.Second).Err()
}

func (l *Lock) Release(ctx context.Context, key string) error {
    return l.redis.Del(ctx, key).Err() // May delete another holder's lock!
}
```

**Pattern:**
```go
// GOOD: SET NX EX with owner check via Lua
func (l *Lock) Acquire(ctx context.Context, key string, ttl time.Duration) (string, error) {
    owner := uuid.New().String()
    ok, err := l.redis.SetNX(ctx, key, owner, ttl).Result()
    if err != nil {
        return "", fmt.Errorf("acquire lock %s: %w", key, err)
    }
    if !ok {
        return "", ErrLockHeld
    }
    return owner, nil
}

// Lua script: only delete if we own the lock
var releaseLockScript = redis.NewScript(`
    if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
    end
    return 0
`)

func (l *Lock) Release(ctx context.Context, key, owner string) error {
    result, err := releaseLockScript.Run(ctx, l.redis, []string{key}, owner).Int64()
    if err != nil {
        return fmt.Errorf("release lock %s: %w", key, err)
    }
    if result == 0 {
        return ErrLockNotOwned
    }
    return nil
}
```

**Severity:** 🔴 CRITICAL

### 8. Lock Without TTL

**Проблема:** Lock без TTL — при crash процесса ресурс заблокирован навечно.

**Anti-pattern:**
```go
// BAD: No TTL — deadlock on crash
l.redis.SetNX(ctx, "lock:order:123", "1", 0)
```

**Pattern:**
```go
// GOOD: Always set TTL on locks
l.redis.SetNX(ctx, "lock:order:123", owner, 30*time.Second)
```

**Severity:** 🟠 HIGH

## Pipeline & Batch

### 9. N Individual GET Calls

**Проблема:** N отдельных GET вместо одного MGET/Pipeline — N roundtrip к Redis.

**Anti-pattern:**
```go
// BAD: N roundtrips
func (r *Repo) GetUsers(ctx context.Context, ids []string) ([]*User, error) {
    users := make([]*User, 0, len(ids))
    for _, id := range ids {
        data, err := r.redis.Get(ctx, "user:"+id).Bytes()
        if err != nil {
            continue
        }
        var u User
        json.Unmarshal(data, &u)
        users = append(users, &u)
    }
    return users, nil
}
```

**Pattern:**
```go
// GOOD: Single MGET roundtrip
func (r *Repo) GetUsers(ctx context.Context, ids []string) ([]*User, error) {
    keys := make([]string, len(ids))
    for i, id := range ids {
        keys[i] = "user:" + id
    }

    results, err := r.redis.MGet(ctx, keys...).Result()
    if err != nil {
        return nil, fmt.Errorf("mget users: %w", err)
    }

    users := make([]*User, 0, len(ids))
    for _, result := range results {
        if result == nil {
            continue // Cache miss
        }
        var u User
        if err := json.Unmarshal([]byte(result.(string)), &u); err != nil {
            continue
        }
        users = append(users, &u)
    }
    return users, nil
}
```

**Severity:** 🟡 MEDIUM

### 10. Mixed Operations Without Pipeline

**Проблема:** Несколько разнотипных команд (SET + EXPIRE + INCR) — каждая отдельный roundtrip.

**Anti-pattern:**
```go
// BAD: 3 roundtrips
r.redis.Set(ctx, key, value, 0)
r.redis.Expire(ctx, key, ttl)
r.redis.Incr(ctx, counterKey)
```

**Pattern:**
```go
// GOOD: Pipeline batches commands in one roundtrip
pipe := r.redis.Pipeline()
pipe.Set(ctx, key, value, ttl)
pipe.Incr(ctx, counterKey)
_, err := pipe.Exec(ctx)
if err != nil {
    return fmt.Errorf("pipeline exec: %w", err)
}
```

**Severity:** 🟡 MEDIUM
