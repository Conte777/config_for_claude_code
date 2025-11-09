# Security Review Checklist

This checklist covers common security vulnerabilities based on OWASP Top 10 and industry best practices.

## 1. Injection Vulnerabilities

### SQL Injection

**Check for:**
- [ ] All SQL queries use parameterized queries/prepared statements
- [ ] No string concatenation or formatting in SQL queries
- [ ] ORM methods used correctly (not raw queries with user input)
- [ ] Stored procedures use parameters, not dynamic SQL

**Red flags:**
```
String concatenation in SQL:
- "SELECT * FROM users WHERE id = " + userId
- f"SELECT * FROM users WHERE name = '{name}'"
- String.format("SELECT * FROM users WHERE id = %d", userId)
- `SELECT * FROM users WHERE id = ${userId}`

Unparameterized queries:
- db.execute(query) where query contains user input
- cursor.execute(f"SELECT ...")
```

### Command Injection

**Check for:**
- [ ] No user input passed to system/exec/shell commands
- [ ] If shell commands required, use safe APIs (exec with array, not string)
- [ ] Input validated with strict whitelist
- [ ] Avoid os.system(), subprocess.shell=True, exec(), eval()

**Red flags:**
```
Dangerous patterns:
- os.system(user_input)
- subprocess.call(f"command {user_input}", shell=True)
- exec(user_code)
- eval(user_expression)
- Runtime.getRuntime().exec(command + userInput)
```

### NoSQL Injection

**Check for:**
- [ ] MongoDB queries use proper escaping
- [ ] No JavaScript code injection in queries
- [ ] Query operators validated ($where, $regex, etc.)

**Red flags:**
```javascript
// MongoDB injection
db.users.find({ username: userInput })  // If userInput is { $ne: null }
db.users.find({ $where: userCode })  // JavaScript injection
```

## 2. Cross-Site Scripting (XSS)

### Reflected XSS

**Check for:**
- [ ] All user input displayed in HTML is escaped
- [ ] Framework's auto-escaping is enabled (React, Vue, Angular, template engines)
- [ ] No innerHTML/dangerouslySetInnerHTML with user input
- [ ] URL parameters sanitized before display

**Red flags:**
```
Dangerous patterns:
- element.innerHTML = userInput
- <div dangerouslySetInnerHTML={{ __html: userInput }} />
- document.write(userInput)
- eval(userInput)
```

### Stored XSS

**Check for:**
- [ ] User-generated content sanitized before storage
- [ ] Content sanitized when retrieved from database
- [ ] Rich text editors use allowlist for HTML tags

**Sanitization libraries:**
- DOMPurify (JavaScript)
- Bleach (Python)
- OWASP Java HTML Sanitizer (Java)

### DOM-Based XSS

**Check for:**
- [ ] No unsafe DOM manipulation (document.write, innerHTML)
- [ ] URL fragments/hash validated before use
- [ ] window.location properties sanitized

## 3. Authentication & Session Management

### Password Security

**Check for:**
- [ ] Passwords never stored in plaintext
- [ ] Strong hashing used: bcrypt, scrypt, Argon2, PBKDF2
- [ ] NO weak hashing: MD5, SHA1, SHA256 (without salt/iterations)
- [ ] Password complexity enforced (minimum length, character requirements)
- [ ] Rate limiting on login attempts
- [ ] Account lockout after X failed attempts

**Red flags:**
```
Weak password handling:
- user.password = plainPassword (no hashing)
- md5(password) or sha1(password)
- sha256(password) without salt
- password == stored_password (plaintext comparison)
```

### Session Management

**Check for:**
- [ ] Session IDs cryptographically random (crypto.randomBytes, SecureRandom)
- [ ] Sessions expire after inactivity
- [ ] Sessions invalidated on logout
- [ ] Session fixation prevented (regenerate ID after login)
- [ ] Secure and HttpOnly flags set on cookies
- [ ] SameSite attribute set on cookies (Strict or Lax)

**Red flags:**
```
Insecure sessions:
- Session ID generated with Math.random()
- Session cookies without HttpOnly flag
- Session cookies without Secure flag (HTTPS)
- No session expiration
```

### Token Security

**Check for:**
- [ ] JWT tokens validated properly (signature, expiration, audience)
- [ ] Token secrets stored securely (environment variables, key vault)
- [ ] Token secrets are strong (minimum 256 bits for HS256)
- [ ] Refresh tokens used for long-lived sessions
- [ ] Tokens not stored in localStorage (use httpOnly cookies)

## 4. Access Control & Authorization

### Broken Access Control

**Check for:**
- [ ] Authorization checks on every protected endpoint/resource
- [ ] User can only access their own data
- [ ] Privilege escalation prevented
- [ ] IDOR (Insecure Direct Object Reference) prevented

**Red flags:**
```
Missing authorization:
- /api/user/{userId} without checking if current user == userId
- Accessing resources by incrementing IDs
- Admin functions accessible to regular users
```

### Least Privilege Principle

**Check for:**
- [ ] Users have minimum necessary permissions
- [ ] Services run with minimal privileges
- [ ] Database connections use limited privilege accounts
- [ ] File system permissions restricted

## 5. Sensitive Data Exposure

### Data in Transit

**Check for:**
- [ ] HTTPS used for all communication
- [ ] TLS 1.2+ required (no SSL, TLS 1.0, TLS 1.1)
- [ ] HSTS header set (HTTP Strict Transport Security)
- [ ] No sensitive data in URLs (use POST body)

**Required headers:**
```
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

### Data at Rest

**Check for:**
- [ ] Sensitive data encrypted at rest
- [ ] Encryption keys managed securely (not hardcoded)
- [ ] PII (Personally Identifiable Information) minimized
- [ ] Credit card data follows PCI-DSS

### Data in Logs

**Check for:**
- [ ] No passwords in logs
- [ ] No tokens/keys in logs
- [ ] No PII in logs (or properly redacted)
- [ ] Log files access-controlled

**Red flags:**
```
Logging sensitive data:
- logger.info(f"User {username} logged in with password {password}")
- console.log("Token:", authToken)
- print(f"Query: {sql_query}")  // May contain sensitive data
```

## 6. Security Misconfiguration

### Default Credentials

**Check for:**
- [ ] No default passwords (admin/admin, root/root)
- [ ] All default accounts disabled or removed
- [ ] Database default users changed

### Debug Mode

**Check for:**
- [ ] Debug mode disabled in production
- [ ] Stack traces not exposed to users
- [ ] Error messages generic (no technical details)

**Red flags:**
```
Exposed errors:
- app.debug = True (Flask)
- NODE_ENV=development in production
- Detailed exception messages to clients
```

### Security Headers

**Check for:**
- [ ] Content-Security-Policy header set
- [ ] X-Content-Type-Options: nosniff
- [ ] X-Frame-Options: DENY or SAMEORIGIN
- [ ] X-XSS-Protection: 1; mode=block
- [ ] Referrer-Policy set appropriately

## 7. Cross-Site Request Forgery (CSRF)

**Check for:**
- [ ] CSRF tokens on state-changing operations (POST, PUT, DELETE)
- [ ] CSRF tokens validated server-side
- [ ] SameSite cookie attribute set
- [ ] Double-submit cookie pattern or synchronizer token pattern

**Red flags:**
```
Missing CSRF protection:
- State-changing GET requests
- No CSRF token validation
- CSRF protection disabled in framework
```

## 8. Insecure Dependencies

### Vulnerable Libraries

**Check for:**
- [ ] Dependencies regularly updated
- [ ] No known vulnerabilities (run npm audit, pip-audit, OWASP Dependency-Check)
- [ ] Transitive dependencies checked
- [ ] Deprecated libraries replaced

**Commands to run:**
```bash
# Node.js
npm audit
npm audit fix

# Python
pip-audit
safety check

# Java
mvn dependency-check:check

# Go
go list -json -m all | nancy sleuth
```

## 9. Cryptography

### Secure Randomness

**Check for:**
- [ ] Cryptographic random used for security (not Math.random())
- [ ] Sufficient entropy (minimum 128 bits)

**Correct libraries:**
```
- crypto.randomBytes() (Node.js)
- secrets module (Python)
- java.security.SecureRandom (Java)
- crypto/rand (Go)
```

**Red flags:**
```
Insecure randomness:
- Math.random()
- Random() without SecureRandom (Java)
- math/rand (Go) for security purposes
```

### Encryption

**Check for:**
- [ ] Strong algorithms: AES-256, RSA-2048+
- [ ] NO weak algorithms: DES, RC4, MD5
- [ ] Proper key management (not hardcoded)
- [ ] IV (Initialization Vector) is random and unique

## 10. File Upload Security

**Check for:**
- [ ] File type validation (whitelist, not blacklist)
- [ ] File size limits enforced
- [ ] Files stored outside web root
- [ ] File names sanitized (no path traversal)
- [ ] Virus scanning on uploads
- [ ] Content-Type validation

**Red flags:**
```
Insecure file uploads:
- Accepting .exe, .php, .sh files
- Storing files in public web directory
- No file size limits
- File names not sanitized: ../../etc/passwd
```

## 11. API Security

**Check for:**
- [ ] Rate limiting implemented
- [ ] API authentication required
- [ ] Input validation on all endpoints
- [ ] CORS configured properly (not allow-all)
- [ ] API versioning for breaking changes

**Red flags:**
```
Insecure API:
- Access-Control-Allow-Origin: *
- No rate limiting
- No authentication on endpoints
- Accepting any Content-Type
```

## Quick Security Scan Checklist

For every code review, quickly check:

- [ ] **Injection**: Parameterized queries? No exec/eval?
- [ ] **XSS**: Output escaped? No innerHTML with user data?
- [ ] **Auth**: Passwords hashed with bcrypt/argon2?
- [ ] **Sessions**: Secure/HttpOnly cookies? Cryptographic random?
- [ ] **Authorization**: Proper access control checks?
- [ ] **HTTPS**: All endpoints use HTTPS?
- [ ] **Secrets**: No hardcoded keys/passwords?
- [ ] **Logging**: No sensitive data in logs?
- [ ] **CSRF**: CSRF tokens on POST/PUT/DELETE?
- [ ] **Dependencies**: No known vulnerabilities?

## Severity Assignment

**CRITICAL:**
- SQL injection vulnerabilities
- Command injection
- Authentication bypass
- Hardcoded secrets/passwords
- Passwords stored in plaintext

**HIGH:**
- XSS vulnerabilities
- Missing authorization checks
- Weak password hashing (MD5, SHA1)
- CSRF vulnerabilities
- Insecure file uploads

**MEDIUM:**
- Missing security headers
- Insecure session management
- Information disclosure in errors
- Rate limiting not implemented

**LOW:**
- Missing HSTS header
- Verbose error messages
- Deprecated dependencies (no known exploits)
