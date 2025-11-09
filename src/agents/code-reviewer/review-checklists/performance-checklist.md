# Performance Review Checklist

This checklist covers common performance issues and optimization opportunities.

## 1. Database Query Optimization

### N+1 Query Problem

**Check for:**
- [ ] Lazy loading causing multiple queries in loops
- [ ] Eager loading used when fetching related data
- [ ] Query count monitored in development

**Red flags:**
```
# N+1 problem example
for user in users:  # 1 query to get users
    print(user.posts)  # N queries, one per user

# Fix with eager loading
users = User.query.options(joinedload(User.posts)).all()  # 1 or 2 queries total
```

**Impact: CRITICAL** - Can cause 100x slowdown

### Missing Indexes

**Check for:**
- [ ] Indexes on frequently queried columns
- [ ] Indexes on foreign keys
- [ ] Composite indexes for multi-column queries
- [ ] No over-indexing (too many indexes slow writes)

**Columns that need indexes:**
- Foreign keys
- Columns in WHERE clauses
- Columns in ORDER BY
- Columns in JOIN conditions

### Query Inefficiency

**Check for:**
- [ ] SELECT * avoided (fetch only needed columns)
- [ ] LIMIT/OFFSET used for pagination
- [ ] Aggregations (COUNT, SUM) done in database, not application
- [ ] Subqueries optimized or replaced with JOINs

**Red flags:**
```sql
-- Fetching unnecessary data
SELECT * FROM large_table;  -- Only need 2-3 columns

-- Inefficient pagination
SELECT * FROM posts OFFSET 10000 LIMIT 10;  -- Slow for large offsets

-- Application-side aggregation
posts = get_all_posts()
count = len(posts)  -- Should be: SELECT COUNT(*) FROM posts
```

### Connection Pooling

**Check for:**
- [ ] Database connection pool configured
- [ ] Pool size appropriate for load
- [ ] Connections properly closed/returned to pool
- [ ] No connection leaks

## 2. Caching Strategy

### Cache Opportunities

**Check for:**
- [ ] Expensive computations cached
- [ ] Frequently accessed data cached
- [ ] External API responses cached
- [ ] Database query results cached

**Cache levels:**
- Application-level (in-memory: dict, LRU cache)
- Distributed cache (Redis, Memcached)
- CDN for static assets
- Browser caching (HTTP headers)

### Cache Invalidation

**Check for:**
- [ ] Cache expiration strategy defined (TTL)
- [ ] Stale data handling (cache invalidation on updates)
- [ ] Cache keys properly namespaced
- [ ] Cache stampede prevention (lock/semaphore)

**Red flags:**
```
Missing cache invalidation:
- Cached data never expires
- Updates don't invalidate related cache
- No versioning in cache keys
```

## 3. Algorithm Complexity

### Time Complexity

**Check for:**
- [ ] No O(n²) algorithms for large datasets
- [ ] Nested loops reviewed for optimization
- [ ] Appropriate data structures used (hash maps vs arrays)
- [ ] Sorting algorithms appropriate for data size

**Red flags:**
```python
# O(n²) - nested loops
for item1 in items:
    for item2 in items:
        if item1.id == item2.id:  # Use hash map instead

# O(n) lookup in list
if item in large_list:  # Use set: if item in large_set
    pass
```

**Impact:**
- O(1) → O(n): 1000x slowdown for 1000 items
- O(n) → O(n²): 1,000,000x slowdown for 1000 items

### Space Complexity

**Check for:**
- [ ] Memory usage appropriate for data size
- [ ] No unnecessary data copying
- [ ] Streaming used for large datasets
- [ ] Memory leaks prevented

## 4. Network Optimization

### API Calls

**Check for:**
- [ ] Batch API calls instead of multiple individual calls
- [ ] Parallel requests when possible
- [ ] Request timeouts configured
- [ ] Connection reuse (HTTP keep-alive)
- [ ] Response compression enabled (gzip)

**Red flags:**
```python
# Sequential API calls (slow)
for user_id in user_ids:
    response = api.get_user(user_id)  # 100 sequential calls

# Better: Batch request
response = api.get_users(user_ids)  # 1 call
```

### Payload Size

**Check for:**
- [ ] Large payloads paginated
- [ ] Unnecessary data not included in responses
- [ ] GraphQL used to fetch only needed fields
- [ ] File uploads/downloads chunked

## 5. Frontend Performance

### Render Performance

**Check for:**
- [ ] Unnecessary re-renders prevented (React.memo, useMemo)
- [ ] Virtual scrolling for long lists
- [ ] Debouncing/throttling for frequent events
- [ ] Lazy loading for images and components

**Red flags:**
```javascript
// React: Unnecessary re-renders
function Component() {
    return <Child config={{ option: true }} />;  // New object each render
}

// No debouncing on input
<input onChange={(e) => handleSearch(e.target.value)} />  // Fires on every keystroke
```

### Bundle Size

**Check for:**
- [ ] Code splitting implemented
- [ ] Tree shaking enabled
- [ ] Unused dependencies removed
- [ ] Heavy libraries lazy-loaded
- [ ] Minification enabled in production

**Tools:**
- webpack-bundle-analyzer
- source-map-explorer

### Asset Optimization

**Check for:**
- [ ] Images compressed and optimized
- [ ] Appropriate image formats (WebP, AVIF)
- [ ] Responsive images (srcset)
- [ ] SVG used for icons
- [ ] Fonts optimized (subset, woff2)
- [ ] CSS/JS minified

## 6. Concurrency and Parallelism

### Parallel Processing

**Check for:**
- [ ] Independent tasks run in parallel
- [ ] Thread pools/worker pools used
- [ ] Async I/O for network/disk operations
- [ ] CPU-bound tasks use multiprocessing

**Examples:**
```python
# Sequential (slow)
results = []
for url in urls:
    results.append(fetch(url))  # 10 seconds each = 100 seconds total

# Parallel (fast)
import asyncio
results = await asyncio.gather(*[fetch(url) for url in urls])  # ~10 seconds total
```

### Blocking Operations

**Check for:**
- [ ] No blocking I/O in async functions
- [ ] Long operations moved to background jobs
- [ ] User-facing operations respond quickly (<200ms)

**Red flags:**
```python
# Blocking async operation
async def process():
    time.sleep(5)  # Blocks entire event loop, use await asyncio.sleep(5)

# Long synchronous operation in request handler
def api_handler():
    heavy_computation()  # Should be background job
    return response
```

## 7. Memory Management

### Memory Leaks

**Check for:**
- [ ] Event listeners removed when no longer needed
- [ ] Large objects released after use
- [ ] Circular references avoided
- [ ] Closures don't capture unnecessary data

**Red flags:**
```javascript
// Memory leak: event listener not removed
function component() {
    window.addEventListener('resize', handler);
    // Missing: window.removeEventListener('resize', handler)
}

// Memory leak: closure captures large data
function processData(largeData) {
    return function() {
        console.log(largeData.length);  // Keeps entire largeData in memory
    };
}
```

### Resource Pooling

**Check for:**
- [ ] Object pools for frequently created/destroyed objects
- [ ] Connection pools for databases
- [ ] Thread pools for concurrent operations
- [ ] Buffer reuse instead of allocation

## 8. Lazy Loading and Pagination

### Data Loading

**Check for:**
- [ ] Infinite scroll or pagination for large datasets
- [ ] Lazy loading for images (loading="lazy")
- [ ] Component lazy loading (React.lazy, dynamic imports)
- [ ] Data prefetching for predicted actions

### Eager Loading Anti-pattern

**Red flags:**
```
Loading all data upfront:
- SELECT * FROM million_row_table
- Fetching all records without pagination
- Loading all images on page load
- No virtualization for long lists
```

## 9. String and Collection Operations

### String Operations

**Check for:**
- [ ] StringBuilder/StringBuffer for concatenation in loops
- [ ] String interning considered for many repeated strings
- [ ] Regular expressions compiled once, not per use

**Red flags:**
```python
# Slow string concatenation
result = ""
for s in strings:
    result += s  # Creates new string each time

# Better
result = "".join(strings)
```

### Collection Operations

**Check for:**
- [ ] Appropriate initial capacity for collections
- [ ] Right collection type (HashMap vs TreeMap, Set vs List)
- [ ] Unnecessary array/list copying avoided

## 10. Profiling and Monitoring

### Performance Monitoring

**Check for:**
- [ ] Performance metrics tracked (response time, throughput)
- [ ] Slow query logging enabled
- [ ] APM (Application Performance Monitoring) integrated
- [ ] Performance budgets defined

**Tools:**
- Backend: New Relic, Datadog, Prometheus
- Frontend: Lighthouse, WebPageTest, Chrome DevTools
- Database: EXPLAIN ANALYZE, slow query log

### Profiling

**Check for:**
- [ ] CPU profiling done for hot paths
- [ ] Memory profiling for leak detection
- [ ] Database query analysis (EXPLAIN plans)

**Tools:**
- Python: cProfile, memory_profiler
- Node.js: clinic.js, node --inspect
- Java: JProfiler, YourKit
- Go: pprof

## Performance Issue Severity

**CRITICAL** (>1 second delay or >10x resource usage):
- N+1 query problems
- Missing database indexes on large tables
- O(n²) algorithms on large datasets
- Blocking I/O in async code
- Memory leaks in long-running processes

**HIGH** (200-1000ms delay or 3-10x resource usage):
- No caching for expensive operations
- Sequential API calls that could be parallel
- Large payloads without pagination
- No code splitting on frontend
- Unnecessary re-renders

**MEDIUM** (50-200ms delay or 2-3x resource usage):
- Inefficient string operations
- Missing connection pooling
- No compression on responses
- Unoptimized images
- No debouncing on frequent events

**LOW** (<50ms delay or <2x resource usage):
- Minor algorithm improvements
- Collection capacity optimization
- Asset minification
- Font optimization

## Quick Performance Checklist

- [ ] **Database**: Indexes on foreign keys? No N+1? Connection pool?
- [ ] **Caching**: Expensive operations cached? Cache invalidation strategy?
- [ ] **Algorithms**: No O(n²) on large data? Right data structures?
- [ ] **Network**: Batch requests? Parallel calls? Compression?
- [ ] **Frontend**: Code splitting? Image optimization? React.memo?
- [ ] **Concurrency**: Async for I/O? Parallel for independent tasks?
- [ ] **Memory**: No leaks? Resources released?
- [ ] **Monitoring**: Performance tracked? Profiling done?
