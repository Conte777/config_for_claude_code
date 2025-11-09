# TypeScript/JavaScript Code Review Guide

This guide provides TypeScript and JavaScript-specific patterns, idioms, anti-patterns, and best practices for code review.

## TypeScript Type Safety

### Type Annotations

**✅ Good Practices:**
```typescript
// Explicit function signatures
function getUserById(id: number): Promise<User | null> {
    return userRepository.findById(id);
}

// Interface for objects
interface User {
    id: number;
    name: string;
    email: string;
    roles: string[];
}

// Type for unions
type Status = 'pending' | 'approved' | 'rejected';

// Generic constraints
function getProperty<T, K extends keyof T>(obj: T, key: K): T[K] {
    return obj[key];
}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Use `any`
function processData(data: any) {  // ❌ Defeats type safety
    return data.whatever;
}

// DON'T: Implicit any
function calculate(a, b) {  // ❌ Missing types
    return a + b;
}

// DON'T: Type assertions without validation
const user = data as User;  // ❌ Unsafe if data shape is wrong
```

### Null/Undefined Handling

**✅ Good Practices:**
```typescript
// Enable strict null checks in tsconfig.json
// "strictNullChecks": true

// Optional chaining
const city = user?.address?.city;

// Nullish coalescing
const displayName = user.name ?? 'Anonymous';

// Type narrowing
function processUser(user: User | null) {
    if (user === null) {
        return;
    }
    // TypeScript knows user is not null here
    console.log(user.name);
}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Non-null assertion without checking
const user = getUser()!;  // ❌ Crashes if null
user.name;

// DON'T: Using || for default values with falsy values
const count = user.count || 0;  // ❌ 0 is falsy, use ?? instead
```

### Discriminated Unions

**✅ Good Practices:**
```typescript
// Type-safe state machine
type Result<T> =
    | { status: 'loading' }
    | { status: 'success'; data: T }
    | { status: 'error'; error: Error };

function handleResult<T>(result: Result<T>) {
    switch (result.status) {
        case 'loading':
            return 'Loading...';
        case 'success':
            return result.data;  // TypeScript knows data exists
        case 'error':
            return result.error.message;  // TypeScript knows error exists
    }
}
```

## Modern JavaScript/TypeScript Patterns

### Async/Await

**✅ Good Practices:**
```typescript
// Async/await instead of promise chains
async function fetchUserData(userId: number): Promise<UserData> {
    try {
        const user = await userApi.getUser(userId);
        const posts = await postApi.getUserPosts(userId);
        return { user, posts };
    } catch (error) {
        logger.error('Failed to fetch user data', error);
        throw new DataFetchError('User data unavailable', { cause: error });
    }
}

// Promise.all for parallel requests
async function fetchAllData() {
    const [users, posts, comments] = await Promise.all([
        fetchUsers(),
        fetchPosts(),
        fetchComments()
    ]);
    return { users, posts, comments };
}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Mix async/await with .then()
async function getData() {
    const result = await fetchData().then(data => data);  // ❌ Redundant

    return fetch('/api/data')
        .then(res => res.json());  // ❌ Use await
}

// DON'T: Not handling promise rejection
async function riskyOperation() {
    await mightFail();  // ❌ Unhandled rejection
}

// DON'T: Async without await (unless intentional fire-and-forget)
async function process() {
    fetch('/api/log');  // ❌ Promise not awaited
    return;
}
```

### Array Methods

**✅ Good Practices:**
```typescript
// map, filter, reduce
const activeUserNames = users
    .filter(user => user.isActive)
    .map(user => user.name);

// find vs filter
const firstAdmin = users.find(user => user.role === 'admin');  // Returns first match
const allAdmins = users.filter(user => user.role === 'admin');  // Returns all matches

// some and every
const hasAdmin = users.some(user => user.role === 'admin');
const allActive = users.every(user => user.isActive);
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Use for loop when array method fits
const names: string[] = [];
for (let i = 0; i < users.length; i++) {
    names.push(users[i].name);  // ❌ Use map()
}

// DON'T: Mutate in map/filter
users.map(user => {
    user.processed = true;  // ❌ Side effect, use forEach
    return user;
});
```

### Destructuring

**✅ Good Practices:**
```typescript
// Object destructuring
const { id, name, email } = user;

// Array destructuring
const [first, second, ...rest] = items;

// Function parameter destructuring
function createUser({ name, email, age }: UserInput) {
    // Use name, email, age directly
}

// Nested destructuring
const { address: { city, country } } = user;
```

### Arrow Functions

**✅ Good Practices:**
```typescript
// Arrow functions for callbacks
users.map(user => user.name);

// Multi-line arrow functions
const processUser = (user: User) => {
    validate(user);
    return transform(user);
};

// Use regular functions when you need `this`
class UserService {
    constructor(private db: Database) {}

    getUser(id: number) {  // Regular method keeps correct `this`
        return this.db.query('users', id);
    }
}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Arrow function as method when you need `this`
class Counter {
    count = 0;
    increment = () => {  // ❌ Creates new function per instance
        this.count++;
    };
}

// DON'T: Unnecessarily verbose arrow functions
const double = (x: number): number => { return x * 2; };  // ❌
const double = (x: number) => x * 2;  // ✅ Concise
```

## TypeScript/JavaScript Security

### XSS Prevention

**✅ Good Practices:**
```typescript
// Use framework's escaping (React, Vue, Angular)
function UserProfile({ name }: { name: string }) {
    return <div>{name}</div>;  // ✅ Auto-escaped by React
}

// Sanitize HTML if you must use dangerouslySetInnerHTML
import DOMPurify from 'dompurify';

function SafeHTML({ html }: { html: string }) {
    const clean = DOMPurify.sanitize(html);
    return <div dangerouslySetInnerHTML={{ __html: clean }} />;
}

// Validate and sanitize user input
function validateEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: innerHTML with user input
element.innerHTML = userInput;  // ❌ XSS vulnerability

// DON'T: eval() with user input
eval(userCode);  // ❌ Never use eval with user input

// DON'T: Unescaped user content in React
<div dangerouslySetInnerHTML={{ __html: userInput }} />  // ❌ XSS
```

### API Security

**✅ Good Practices:**
```typescript
// Validate input
import { z } from 'zod';

const UserSchema = z.object({
    name: z.string().min(2).max(50),
    email: z.string().email(),
    age: z.number().int().positive()
});

function createUser(input: unknown) {
    const validated = UserSchema.parse(input);  // Throws if invalid
    return userService.create(validated);
}

// Use HTTPS for API calls
const apiClient = axios.create({
    baseURL: 'https://api.example.com',  // ✅ HTTPS
    timeout: 5000
});

// Include CSRF token
await fetch('/api/update', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': getCsrfToken()
    },
    body: JSON.stringify(data)
});
```

### Authentication Tokens

**✅ Good Practices:**
```typescript
// Store tokens securely (httpOnly cookies preferred)
// DON'T store in localStorage for sensitive apps

// Include tokens in requests
const api = axios.create({
    baseURL: 'https://api.example.com',
    headers: {
        Authorization: `Bearer ${getAccessToken()}`
    }
});

// Refresh token handling
async function fetchWithAuth(url: string) {
    let token = getAccessToken();

    if (isTokenExpired(token)) {
        token = await refreshAccessToken();
    }

    return fetch(url, {
        headers: { Authorization: `Bearer ${token}` }
    });
}
```

## React-Specific Patterns (if applicable)

### Hooks

**✅ Good Practices:**
```typescript
// useState with proper types
const [user, setUser] = useState<User | null>(null);

// useEffect cleanup
useEffect(() => {
    const subscription = subscribe();
    return () => subscription.unsubscribe();  // Cleanup
}, []);

// useMemo for expensive computations
const sortedUsers = useMemo(
    () => users.sort((a, b) => a.name.localeCompare(b.name)),
    [users]
);

// useCallback for stable function references
const handleClick = useCallback(() => {
    doSomething(value);
}, [value]);
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Missing dependencies in useEffect
useEffect(() => {
    fetchData(userId);  // ❌ userId should be in deps
}, []);

// DON'T: Unnecessary useCallback/useMemo
const onClick = useCallback(() => {
    console.log('clicked');
}, []);  // ❌ No dependencies, not needed
```

### Component Patterns

**✅ Good Practices:**
```typescript
// Props interface
interface ButtonProps {
    label: string;
    onClick: () => void;
    variant?: 'primary' | 'secondary';
    disabled?: boolean;
}

// Functional component with proper types
const Button: React.FC<ButtonProps> = ({
    label,
    onClick,
    variant = 'primary',
    disabled = false
}) => {
    return (
        <button
            onClick={onClick}
            disabled={disabled}
            className={`btn btn-${variant}`}
        >
            {label}
        </button>
    );
};
```

## Performance Patterns

### Avoid Unnecessary Re-renders

**✅ Good Practices:**
```typescript
// React.memo for expensive components
export const ExpensiveComponent = React.memo(({ data }: Props) => {
    return <div>{/* Complex rendering */}</div>;
});

// Use keys in lists
{users.map(user => (
    <UserCard key={user.id} user={user} />  // ✅ Stable key
))}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Index as key (if list can change)
{users.map((user, index) => (
    <UserCard key={index} user={user} />  // ❌ Index can change
))}

// DON'T: Create objects/arrays in render
function Component() {
    return <Child config={{ option: true }} />;  // ❌ New object each render
}
```

### Bundle Size

**✅ Good Practices:**
```typescript
// Tree-shakeable imports
import { debounce } from 'lodash-es';  // ✅ Only imports debounce

// Dynamic imports for code splitting
const HeavyComponent = React.lazy(() => import('./HeavyComponent'));

function App() {
    return (
        <Suspense fallback={<Loading />}>
            <HeavyComponent />
        </Suspense>
    );
}
```

**❌ Anti-Patterns:**
```typescript
// DON'T: Import entire library
import _ from 'lodash';  // ❌ Imports all of lodash
```

## Common TypeScript/JavaScript Review Checklist

When reviewing TypeScript/JavaScript code, check for:

- [ ] Strict type checking enabled (strictNullChecks, strictFunctionTypes)
- [ ] No `any` types (use `unknown` if truly dynamic)
- [ ] Proper null/undefined handling (optional chaining, nullish coalescing)
- [ ] async/await used consistently (not mixed with .then())
- [ ] Promise rejections handled (try/catch in async functions)
- [ ] Array methods used appropriately (map, filter, find)
- [ ] No XSS vulnerabilities (innerHTML, dangerouslySetInnerHTML)
- [ ] User input validated and sanitized
- [ ] HTTPS used for API calls
- [ ] Tokens stored securely (not localStorage for sensitive data)
- [ ] useEffect dependencies correct (React)
- [ ] Stable keys in lists (React)
- [ ] No unnecessary re-renders (React.memo, useMemo, useCallback)
- [ ] Tree-shakeable imports for large libraries
- [ ] Code splitting for large components
- [ ] Error boundaries implemented (React)
