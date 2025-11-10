# Docker Configuration Reference

## Table of Contents
- [Multi-Stage Builds](#multi-stage-builds)
- [Layer Optimization](#layer-optimization)
- [Security Best Practices](#security-best-practices)
- [Image Size Reduction](#image-size-reduction)
- [Build Cache Optimization](#build-cache-optimization)
- [docker-compose Best Practices](#docker-compose-best-practices)
- [Health Checks](#health-checks)

## Multi-Stage Builds

Multi-stage builds reduce final image size by separating build and runtime environments.

### Benefits
- Smaller production images (10x+ reduction common)
- Build tools not included in final image
- Improved security (fewer attack vectors)
- Faster deployment and pull times

### Pattern

```dockerfile
# Stage 1: Build
FROM build-image AS builder
WORKDIR /app
# Install build dependencies
# Copy source
# Build application

# Stage 2: Production
FROM minimal-image
# Copy only artifacts from builder
# Run application
```

### Key Principles
- Use descriptive stage names (builder, production, development)
- Copy only necessary artifacts between stages
- Use minimal base images for final stage (alpine, distroless)
- Build dependencies stay in builder stage

## Layer Optimization

Each Dockerfile instruction creates a layer. Optimize for:
- Smaller total size
- Better cache utilization
- Faster builds

### Order Instructions by Change Frequency

```dockerfile
# Least frequently changed (cached longest)
FROM node:18-alpine

# Package dependencies (change occasionally)
COPY package*.json ./
RUN npm ci --only=production

# Application code (changes frequently)
COPY . .

# Runtime configuration
CMD ["node", "server.js"]
```

### Combine RUN Commands

**Bad:**
```dockerfile
RUN apt-get update
RUN apt-get install -y package1
RUN apt-get install -y package2
RUN rm -rf /var/lib/apt/lists/*
```

**Good:**
```dockerfile
RUN apt-get update && \
    apt-get install -y package1 package2 && \
    rm -rf /var/lib/apt/lists/*
```

### Use .dockerignore

Prevent unnecessary files from being sent to build context:
- Reduces build time
- Prevents secrets from being copied
- Smaller context size

## Security Best Practices

### 1. Use Official Base Images

```dockerfile
# Good
FROM node:18-alpine

# Bad
FROM random-user/node
```

### 2. Specify Exact Versions

```dockerfile
# Good - reproducible builds
FROM node:18.17.1-alpine3.18

# Bad - unpredictable
FROM node:latest
```

### 3. Run as Non-Root User

```dockerfile
# Create user
RUN adduser -D -u 1000 appuser

# Switch to user
USER appuser

# Or use built-in nobody
USER nobody
```

### 4. Use Minimal Base Images

**Image size comparison:**
- `ubuntu`: ~70MB
- `alpine`: ~5MB
- `distroless`: ~2MB
- `scratch`: 0MB (empty)

```dockerfile
# For Go (static binaries)
FROM scratch
COPY app /app
CMD ["/app"]

# For most apps
FROM alpine:3.18
```

### 5. Don't Store Secrets in Images

**Bad:**
```dockerfile
ENV API_KEY=secret123
```

**Good:**
```dockerfile
# Use environment variables at runtime
# Or Docker secrets
```

### 6. Scan for Vulnerabilities

```bash
docker scan myimage:latest
trivy image myimage:latest
```

### 7. Read-Only Filesystem

```dockerfile
# In Dockerfile
USER nobody

# In docker-compose
services:
  app:
    read_only: true
    tmpfs:
      - /tmp
```

### 8. Drop Capabilities

```yaml
services:
  app:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # Only if needed
```

## Image Size Reduction

### Techniques

**1. Multi-stage builds** (biggest impact)

**2. Use alpine/distroless base images**

**3. Remove package manager caches**
```dockerfile
RUN apk add --no-cache package-name
# Or
RUN apt-get update && \
    apt-get install -y package && \
    rm -rf /var/lib/apt/lists/*
```

**4. Don't install unnecessary packages**
```dockerfile
# Use --no-install-recommends for apt
RUN apt-get install -y --no-install-recommends package
```

**5. Clean up in same layer**
```dockerfile
# Bad - creates large layer
RUN wget large-file.tar.gz
RUN tar -xzf large-file.tar.gz
RUN rm large-file.tar.gz

# Good - cleaned in same layer
RUN wget large-file.tar.gz && \
    tar -xzf large-file.tar.gz && \
    rm large-file.tar.gz
```

### Size Comparison Example

Before optimization:
```dockerfile
FROM node:18
WORKDIR /app
COPY . .
RUN npm install
CMD ["node", "server.js"]
# Result: ~1GB
```

After optimization:
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app .
USER node
CMD ["node", "server.js"]
# Result: ~150MB
```

## Build Cache Optimization

Docker caches each layer. Optimize cache hits:

### 1. Copy Dependencies First

```dockerfile
# Dependencies change less frequently than code
COPY package*.json ./
RUN npm ci

# Code changes frequently
COPY . .
```

### 2. Use BuildKit Cache Mounts

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:1.21-alpine

# Cache go modules
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Cache build cache
RUN --mount=type=cache,target=/root/.cache/go-build \
    go build -o app
```

Enable BuildKit:
```bash
DOCKER_BUILDKIT=1 docker build .
```

### 3. Order by Change Frequency

Least changing → Most changing:
1. Base image
2. System packages
3. Dependencies
4. Application code
5. Configuration

## docker-compose Best Practices

### 1. Use Version 3.8+

```yaml
version: '3.8'
```

### 2. Environment Variables

Use .env file for secrets:
```yaml
services:
  db:
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
```

.env file (not committed to git):
```
DB_PASSWORD=secret123
```

### 3. Named Volumes

```yaml
volumes:
  postgres-data:  # Named volume, managed by Docker
  redis-data:
```

### 4. Networks

Isolate services:
```yaml
services:
  frontend:
    networks:
      - frontend-network

  backend:
    networks:
      - frontend-network
      - backend-network

  database:
    networks:
      - backend-network  # Not accessible from frontend

networks:
  frontend-network:
  backend-network:
```

### 5. Health Checks

```yaml
services:
  app:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  db:
    depends_on:
      app:
        condition: service_healthy  # Wait for health check
```

### 6. Resource Limits

```yaml
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

### 7. Restart Policies

```yaml
services:
  app:
    restart: unless-stopped  # Recommended for most services

  worker:
    restart: on-failure  # For jobs that should complete
```

### 8. Logging Configuration

```yaml
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

## Health Checks

Health checks determine if container is functioning correctly.

### Dockerfile Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

Parameters:
- `--interval`: Time between checks (default: 30s)
- `--timeout`: Max time for check (default: 30s)
- `--start-period`: Initialization time (default: 0s)
- `--retries`: Consecutive failures before unhealthy (default: 3)

### docker-compose Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### Health Check Commands

**HTTP endpoint:**
```dockerfile
HEALTHCHECK CMD curl -f http://localhost/health || exit 1
HEALTHCHECK CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1
```

**Database:**
```dockerfile
# PostgreSQL
HEALTHCHECK CMD pg_isready -U postgres || exit 1

# MySQL
HEALTHCHECK CMD mysqladmin ping -h localhost || exit 1

# Redis
HEALTHCHECK CMD redis-cli ping || exit 1
```

**Process check:**
```dockerfile
HEALTHCHECK CMD pgrep -f myapp || exit 1
```

## Validation and Testing

### Build Image
```bash
docker build -t myapp:test .
```

### Check Image Size
```bash
docker images myapp:test
```

### Scan for Vulnerabilities
```bash
docker scan myapp:test
trivy image myapp:test
```

### Lint Dockerfile
```bash
hadolint Dockerfile
```

### Test Container
```bash
docker run --rm -p 8080:8080 myapp:test
curl http://localhost:8080/health
```

### docker-compose Validation
```bash
docker-compose config  # Validate syntax
docker-compose up --dry-run  # Test without starting
```

## Common Pitfalls

### 1. Using Latest Tag
- Unpredictable builds
- Hard to reproduce issues
- Always use specific versions

### 2. Running as Root
- Security risk
- Always create and use non-root user

### 3. Not Using .dockerignore
- Large build context
- Slow builds
- Potential secret exposure

### 4. Installing Build Tools in Production
- Bloated images
- Security risk
- Use multi-stage builds

### 5. Not Combining RUN Commands
- Extra layers
- Larger image size
- Slower builds

### 6. Copying Everything
```dockerfile
# Bad
COPY . .

# Good
COPY package*.json ./
RUN npm ci
COPY src/ ./src/
```

## Optimization Checklist

- [ ] Multi-stage build used
- [ ] Minimal base image (alpine/distroless)
- [ ] Specific image versions (not latest)
- [ ] Non-root user configured
- [ ] .dockerignore created
- [ ] Dependencies copied before code
- [ ] RUN commands combined where appropriate
- [ ] Package manager caches cleaned
- [ ] Health check added
- [ ] Image scanned for vulnerabilities
- [ ] Final image size reasonable
- [ ] Build time acceptable

## Troubleshooting

### Build Issues

**"no such file or directory" during COPY**
- Check file exists in build context
- Verify path is relative to Dockerfile location
- Check .dockerignore isn't excluding the file
- Ensure file wasn't deleted in previous layer

**"failed to solve with frontend dockerfile.v0"**
- Check Dockerfile syntax
- Verify all closing brackets/quotes
- Check for typos in instructions
- Try `DOCKER_BUILDKIT=0` to see detailed errors

**Build cache not working**
```bash
# Force rebuild without cache
docker build --no-cache -t myapp .

# Clear build cache
docker builder prune
```

**"invalid reference format"**
- Check image name format (lowercase, no special chars)
- Format: `registry/repository:tag`
- Valid: `myapp:v1.0`, `docker.io/user/app:latest`
- Invalid: `MyApp:v1.0`, `app:v1.0!`

### Image Issues

**Image too large**
- Use multi-stage builds
- Switch to alpine or distroless base
- Remove package manager caches: `rm -rf /var/lib/apt/lists/*`
- Combine RUN commands
- Use .dockerignore
- Don't install development dependencies in production

**"exec format error"**
- Architecture mismatch (building arm64 on amd64 or vice versa)
- Build for correct platform: `docker build --platform linux/amd64`
- Use multi-architecture builds

**Cannot pull image**
```bash
# Check image exists
docker search <image-name>

# Login to registry
docker login registry.example.com

# Check network connectivity
ping registry.example.com

# Try different registry mirror
```

### Container Runtime Issues

**Container exits immediately**
```bash
# Check logs
docker logs <container-id>

# Check exit code
docker inspect <container-id> --format='{{.State.ExitCode}}'

# Common causes:
# Exit code 0: Command completed successfully
# Exit code 1: Application error
# Exit code 137: OOM killed (out of memory)
# Exit code 139: Segmentation fault
# Exit code 143: SIGTERM (graceful shutdown)
```

**Container keeps restarting**
- Check logs: `docker logs <container-id>`
- Review restart policy
- Check health check configuration
- Verify application isn't crashing on startup
- Check for port conflicts

**Permission denied errors**
```bash
# Check user
docker exec <container-id> whoami

# Run as root temporarily to debug
docker run --user root -it <image> sh

# Fix permissions in Dockerfile
RUN chown -R appuser:appgroup /app
USER appuser
```

**Port already allocated**
```bash
# Check what's using the port
netstat -tulpn | grep <port>  # Linux
lsof -i :<port>  # Mac

# Kill process or use different port
docker run -p 8081:8080 myapp
```

### docker-compose Issues

**"service 'X' depends on service 'Y' which is undefined"**
- Check service name spelling in depends_on
- Verify service exists in docker-compose.yml
- Check YAML indentation

**Services can't communicate**
```bash
# Check network
docker-compose ps
docker network ls

# Verify services are on same network
docker network inspect <network-name>

# Use service name as hostname
# Not: http://localhost:8080
# But: http://service-name:8080
```

**Environment variables not loading**
```bash
# Check .env file exists
ls -la .env

# Check variable syntax in docker-compose.yml
${VAR_NAME}  # Correct
$VAR_NAME    # Also works
{VAR_NAME}   # Incorrect

# Debug values
docker-compose config
```

**Volume mount not working**
- Check path syntax (absolute paths or ./ for relative)
- Windows: Use forward slashes `/c/Users/...`
- Verify directory exists on host
- Check permissions
- On Docker Desktop: ensure path is in shared directories

**"invalid interpolation format"**
- Escape dollar signs: `$$` instead of `$`
- Use quotes: `"${VAR}"`
- Check for unmatched braces

### Health Check Issues

**Container unhealthy**
```bash
# Check health status
docker inspect --format='{{json .State.Health}}' <container-id>

# Common causes:
# - Health check endpoint doesn't exist
# - Timeout too short
# - Application not ready during initialDelaySeconds
# - Wrong port in health check

# Test health check manually
docker exec <container-id> curl -f http://localhost/health
```

**Health check never succeeds**
- Increase `start_period` for slow-starting apps
- Check `timeout` is sufficient
- Verify health endpoint returns 200 status
- Check if curl/wget is installed in image

### Network Issues

**Cannot connect to external services**
- Check container DNS: `docker exec <container-id> nslookup google.com`
- Verify firewall rules
- Check if proxy settings needed
- Use `--network host` for testing (not for production)

**Cannot access container from host**
```bash
# Check port mapping
docker port <container-id>

# Verify service is listening
docker exec <container-id> netstat -tulpn

# Check firewall
# Check if bound to localhost only (should be 0.0.0.0)
```

### Security Issues

**Vulnerability scan failures**
```bash
# Scan image
docker scan myapp:latest
trivy image myapp:latest

# Solutions:
# - Update base image to latest patch version
# - Use distroless or alpine
# - Remove unnecessary packages
# - Pin versions and update regularly
```

**Cannot run as non-root**
- Check file ownership: `RUN chown -R user:group /app`
- Create writable directories: `RUN mkdir -p /app/tmp && chown user:group /app/tmp`
- Use volumes for writable directories
- Adjust permissions in image build

### Build Performance

**Slow builds**
- Enable BuildKit: `DOCKER_BUILDKIT=1`
- Use cache mounts: `RUN --mount=type=cache,target=/root/.cache`
- Order layers by change frequency
- Parallelize multi-stage builds
- Use smaller base images
- Clean up in same layer

**Build context too large**
```bash
# Check context size
docker build --progress=plain .

# Solutions:
# - Add .dockerignore
# - Exclude node_modules, .git, etc.
# - Build from subdirectory if needed
```

### Common Error Messages

**"manifest unknown"**
- Image doesn't exist in registry
- Wrong image tag
- Not authenticated: `docker login`

**"denied: requested access to the resource is denied"**
- Need to login: `docker login`
- Check image name includes registry
- Verify push permissions

**"Error response from daemon: conflict"**
- Container name already in use
- Use `--rm` flag or remove old container
- `docker rm <container-name>`

**"no space left on device"**
```bash
# Clean up
docker system prune -a  # Remove unused images, containers, networks
docker volume prune     # Remove unused volumes

# Check disk usage
docker system df
```

### Debug Commands

**Inspect image layers**
```bash
docker history myapp:latest
docker inspect myapp:latest
```

**Debug running container**
```bash
# Execute shell
docker exec -it <container-id> sh

# Check processes
docker top <container-id>

# View stats
docker stats <container-id>

# Copy files from container
docker cp <container-id>:/app/log.txt ./log.txt
```

**Test without starting**
```bash
# Validate docker-compose
docker-compose config

# Dry run
docker-compose up --no-start
```
