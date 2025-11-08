---
name: docker-configuration
description: Create and optimize Dockerfiles, docker-compose.yml files, multi-stage builds, and container configurations. Use when user mentions Docker, containers, Dockerfile, docker-compose, containerization, image optimization, or asks to dockerize an application.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(docker build:*), Bash(docker-compose:*), Bash(docker images:*), Bash(docker ps:*), mcp__context7__resolve-library-id, mcp__context7__get-library-docs
---

# Docker Configuration Skill

Expert Docker containerization with best practices from Context7, including Dockerfile optimization, multi-stage builds, and docker-compose configurations.

## Workflow

### 1. Research Best Practices

Use Context7 for up-to-date Docker best practices:
- Resolve library ID for Docker documentation
- Get current best practices for multi-stage builds, security, optimization

### 2. Create Dockerfile

Create optimized Dockerfile following key principles:

**Multi-Stage Builds:**
- Separate build and runtime environments
- Reduces image size by 10x+ typically
- Build tools stay in builder stage, not in production image

**Layer Optimization:**
- Order instructions from least to most frequently changing
- Dependencies before application code
- Combine RUN commands to reduce layers

**Security:**
- Use official base images with specific versions (not `latest`)
- Run as non-root user
- Use minimal base images (alpine, distroless)
- Don't store secrets in images

**Size Reduction:**
- Use alpine or distroless base images
- Remove package manager caches
- Multi-stage builds
- Clean up in same layer

For detailed best practices, see [reference.md](reference.md)

For complete Dockerfile examples (Go, Node.js, Python), see [examples.md](examples.md)

### 3. Create .dockerignore

Always create .dockerignore to exclude:
- `.git`, `.env`, IDE files
- `node_modules`, build artifacts
- Documentation, test files
- Docker files themselves

Prevents secrets exposure and reduces build context size.

For complete .dockerignore template, see [examples.md](examples.md#dockerignore)

### 4. Create docker-compose.yml (for multi-container apps)

docker-compose for orchestrating multiple containers:

**Key features:**
- Define all services in one file
- Network isolation between services
- Named volumes for data persistence
- Health checks and dependencies
- Environment variable management

**Best practices:**
- Use version 3.8+
- Store secrets in .env file (not committed)
- Use named volumes (not bind mounts for data)
- Configure health checks
- Set resource limits
- Use proper restart policies

For docker-compose examples, see [examples.md](examples.md#docker-composeyml)

### 5. Add Health Checks

Health checks monitor container health:

**In Dockerfile:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost/health || exit 1
```

**In docker-compose:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

For health check patterns, see [reference.md](reference.md#health-checks)

### 6. Validation and Testing

**Build and test:**
```bash
# Build image
docker build -t app:test .

# Check image size
docker images app:test

# Test run
docker run --rm -p 8080:8080 app:test
```

**Validate docker-compose:**
```bash
docker-compose config
docker-compose up --dry-run
```

**Optional - Lint and scan:**
```bash
hadolint Dockerfile  # Lint
docker scan app:test  # Vulnerability scan
trivy image app:test  # Alternative scanner
```

If build fails:
- Review error messages
- Fix issues
- Rebuild
- Repeat until successful

For validation details, see [reference.md](reference.md#validation-and-testing)

## Common Patterns

**Stateless Web Application:**
- Multi-stage Dockerfile
- Non-root user
- Health check endpoint
- Minimal base image (alpine)

**Full Stack Application:**
- docker-compose with frontend, backend, database
- Network isolation
- Named volumes for persistence
- Health checks for dependencies

**Development Environment:**
- Volume mounts for hot reload
- Development stage in multi-stage Dockerfile
- Override command for dev mode

For pattern examples, see [examples.md](examples.md)

## Quality Checklist

Before marking task complete:
- [ ] Dockerfile builds successfully
- [ ] Multi-stage build used (when applicable)
- [ ] Base image is minimal (alpine/distroless)
- [ ] Specific version tags (not `latest`)
- [ ] Runs as non-root user
- [ ] .dockerignore created
- [ ] Health check added (for services)
- [ ] Image size is optimized
- [ ] No secrets hardcoded
- [ ] docker-compose validates (if created)
- [ ] Resource limits set (if using compose)

## Reference Materials

- [reference.md](reference.md) - Comprehensive Docker guide
  - Multi-stage builds
  - Layer optimization techniques
  - Security hardening
  - Image size reduction
  - Build cache optimization
  - docker-compose best practices
  - Health checks
  - Validation and testing

- [examples.md](examples.md) - Complete examples
  - Go, Node.js, Python Dockerfiles
  - .dockerignore template
  - docker-compose configurations
  - Health check examples
  - Multi-architecture builds
  - Development vs Production stages

## Dependencies

- Docker installed
- docker-compose installed (for multi-container apps)
- Context7 MCP server configured
- hadolint (optional, for linting)
