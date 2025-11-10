---
name: kubernetes-deployment
description: Create and manage Kubernetes manifests (Deployment, Service, ConfigMap, Secret, Ingress, StatefulSet, DaemonSet, Job, CronJob, NetworkPolicy, ServiceAccount, RBAC, PV, PVC), Helm charts, Kustomize overlays, validate with kubectl dry-run, troubleshoot deployments, configure autoscaling (HPA, VPA), resource limits and requests, health checks (liveness, readiness, startup probes), security contexts, network policies, rolling updates and rollbacks. Use when user mentions Kubernetes, K8s, kubectl, Helm, Kustomize, deployments, services, pods, container orchestration, cluster config, microservices, cloud native, deploy to Kubernetes, create k8s manifests, write YAML configs, ingress controller, load balancer, secrets, persistent storage, health checks, scale apps, troubleshoot pods, debug deployments, namespaces, RBAC permissions, service discovery, stateful apps, cron jobs, daemon sets, resource quotas, pod security policies, cert-manager, autoscaling, rolling updates, rollbacks, or .yaml/.yml files.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(kubectl:*), Bash(helm:*), mcp__context7__resolve-library-id, mcp__context7__get-library-docs
---

# Kubernetes Deployment Skill

Expert Kubernetes configuration with best practices from Context7, including manifest creation, Helm charts, and deployment validation.

## Workflow

### 1. Research Best Practices

Use Context7 for up-to-date Kubernetes best practices:
- Resolve library ID for Kubernetes documentation
- Get current best practices for resource limits, health checks, security contexts

### 2. Create Manifests

Create Kubernetes manifests following best practices:

**Essential components:**
- **Deployment**: Application pods with replicas, health checks, resource limits
- **Service**: Network access to pods (ClusterIP, NodePort, LoadBalancer)
- **ConfigMap**: Non-sensitive configuration data
- **Secret**: Sensitive data (passwords, tokens)
- **Ingress**: HTTP/HTTPS routing with TLS (optional)

**Key requirements:**
- Set resource requests and limits
- Configure liveness and readiness probes
- Use security context (non-root user, read-only filesystem)
- Apply consistent labels
- Use specific image tags (not `latest`)

For detailed manifest structure and examples, see [examples.md](examples.md)

### 3. Apply Best Practices

**Security:**
- Run as non-root user
- Read-only root filesystem when possible
- Drop all capabilities, add only required
- Use SecurityContext and PodSecurityPolicy

**Resource Management:**
- Always set requests (guaranteed resources)
- Always set limits (maximum allowed)
- Prevents resource starvation

**Health Checks:**
- Liveness probe: Restart if unhealthy
- Readiness probe: Remove from endpoints if not ready
- Use different endpoints for each

**Labels and Organization:**
- Consistent labeling: app, component, version, environment
- Use namespaces for logical separation
- Organize manifests by environment or resource type

For comprehensive best practices, see [reference.md](reference.md)

### 4. Helm Charts (when needed)

Create Helm charts for parameterized deployments:

**Structure:**
```
chart-name/
├── Chart.yaml (metadata)
├── values.yaml (configuration)
├── templates/ (manifest templates)
└── _helpers.tpl (template functions)
```

**Benefits:**
- Parameterized configurations
- Multiple environments with different values files
- Template reusability
- Version management

For Helm chart guide and examples, see [reference.md](reference.md#helm-charts) and [examples.md](examples.md#helm-chart-structure)

### 5. Validation

**Always validate before applying:**

kubectl validation:
```bash
kubectl apply -f deployment.yaml --dry-run=client -o yaml
kubectl apply -f service.yaml --dry-run=client
```

Helm validation:
```bash
helm lint ./chart-name
helm template release-name ./chart-name --debug
```

**If validation fails:**
- Review error messages
- Fix YAML syntax or validation issues
- Re-run validation
- Repeat until successful

### 6. Organization Patterns

**Option 1: Kustomize (recommended for multiple environments)**
```
k8s/
├── base/ (common manifests)
└── overlays/ (environment-specific patches)
    ├── dev/
    ├── staging/
    └── production/
```

**Option 2: Helm (recommended for complex applications)**
```
helm/
└── chart-name/
    ├── Chart.yaml
    ├── values.yaml
    ├── templates/
    └── values/ (multiple values files)
```

## Common Use Cases

**Stateless Application:**
- Deployment with multiple replicas
- ClusterIP Service
- ConfigMap for configuration
- HorizontalPodAutoscaler (optional)

**Stateful Application:**
- StatefulSet with persistent volumes
- Headless Service
- VolumeClaimTemplates

**Scheduled Jobs:**
- CronJob for periodic tasks
- Job for one-time tasks

For examples of each pattern, see [examples.md](examples.md)

## Quality Checklist

Before marking task complete:
- [ ] All manifests validate with kubectl dry-run
- [ ] Resource limits and requests set
- [ ] Liveness and readiness probes configured
- [ ] Security context defined (non-root user)
- [ ] Labels follow consistent pattern
- [ ] ConfigMaps used for configuration (not hardcoded)
- [ ] Secrets properly handled (not in plain text)
- [ ] Image tags are specific (not `latest`)
- [ ] Helm chart validates (if using Helm)

## Reference Materials

- [reference.md](reference.md) - Comprehensive best practices guide
  - Resource limits and health checks
  - Security hardening and RBAC
  - Helm charts and templates
  - Network policies
  - Validation commands

- [examples.md](examples.md) - Complete manifest examples
  - Basic deployment (Deployment, Service, ConfigMap, Secret)
  - StatefulSet for stateful apps
  - Ingress with TLS
  - CronJob for scheduled tasks
  - Helm chart structure
  - Kustomize organization

## Dependencies

- kubectl installed (optional for validation)
- helm installed (optional for Helm charts)
- Context7 MCP server configured
