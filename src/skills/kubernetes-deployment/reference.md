# Kubernetes Reference Guide

## Table of Contents
- [Resource Limits and Requests](#resource-limits-and-requests)
- [Health Checks](#health-checks)
- [Security Best Practices](#security-best-practices)
- [Labels and Selectors](#labels-and-selectors)
- [ConfigMaps and Secrets](#configmaps-and-secrets)
- [Service Types](#service-types)
- [Deployment Strategies](#deployment-strategies)
- [Helm Charts](#helm-charts)
- [Security Hardening](#security-hardening)

## Resource Limits and Requests

Always set both requests and limits:

- **Requests**: Guaranteed resources that Kubernetes reserves
- **Limits**: Maximum resources the pod can consume

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

**Guidelines:**
- Set requests based on typical usage
- Set limits to prevent resource exhaustion
- Monitor actual usage and adjust
- Use ResourceQuota at namespace level

## Health Checks

### Liveness Probe
Determines if container should be restarted:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Readiness Probe
Determines if pod should receive traffic:
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Guidelines:**
- Liveness checks basic application health
- Readiness checks if app is ready to serve
- Use different endpoints
- Set appropriate initialDelaySeconds
- Avoid expensive operations in checks

## Security Best Practices

### Security Context (Pod-level)
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
```

### Security Context (Container-level)
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
    - ALL
    add:
    - NET_BIND_SERVICE
```

**Key Principles:**
- Always run as non-root user
- Use read-only root filesystem
- Drop all capabilities, add only required
- Disable privilege escalation
- Apply seccomp profile

## Labels and Selectors

Use consistent labeling strategy:

```yaml
labels:
  app: app-name
  component: backend
  version: v1.0.0
  environment: production
  managed-by: helm
  tier: application
```

**Recommended labels:**
- `app`: Application name
- `component`: Component type
- `version`: Application version
- `environment`: Environment name
- `managed-by`: Management tool
- `tier`: Infrastructure tier

## ConfigMaps and Secrets

### ConfigMaps
For non-sensitive configuration:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_HOST: "db.example.com"
  app.conf: |
    setting1=value1
```

### Secrets
For sensitive data (base64 encoded):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  db-password: cGFzc3dvcmQ=
```

**Guidelines:**
- Never hardcode sensitive data
- Use Secrets for passwords, tokens
- Consider external secret management (Vault, Sealed Secrets)
- Limit access with RBAC

## Service Types

### ClusterIP (Default)
Internal service only:
```yaml
spec:
  type: ClusterIP
```

### NodePort
Exposes on each node:
```yaml
spec:
  type: NodePort
  ports:
  - nodePort: 30080
```

### LoadBalancer
Provisions external load balancer:
```yaml
spec:
  type: LoadBalancer
```

**Guidelines:**
- Use ClusterIP for internal services
- Use Ingress for HTTP/HTTPS instead of LoadBalancer
- NodePort for debugging only
- LoadBalancer for non-HTTP external services

## Deployment Strategies

### Rolling Update
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

### Recreate
```yaml
spec:
  strategy:
    type: Recreate
```

**Guidelines:**
- Use RollingUpdate for zero-downtime
- Set maxUnavailable: 0 for high availability
- Use Recreate when app can't run multiple versions

## Helm Charts

### Chart Structure Best Practices

**values.yaml organization:**
- Group related settings
- Provide sensible defaults
- Document all values with comments
- Use nested structure for clarity

**Template best practices:**
- Use _helpers.tpl for common functions
- Keep templates DRY
- Add conditional rendering
- Use consistent resource naming

**Multiple environments:**
```bash
helm install app ./chart -f values-prod.yaml
```

**Validation commands:**
```bash
helm lint ./chart
helm template app ./chart --debug
helm install app ./chart --dry-run --debug
```

## Security Hardening

### Network Policies

**Default deny all:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Allow specific traffic:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
```

### RBAC

**ServiceAccount:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
```

**Role:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
```

**RoleBinding:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-binding
subjects:
- kind: ServiceAccount
  name: app-sa
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

### Pod Security Standards

**Restricted namespace:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
```

### Image Security

**Best practices:**
- Use specific image tags (not `latest`)
- Use minimal base images (alpine, distroless)
- Scan images for vulnerabilities
- Implement image signing
- Use private registries with authentication

**Image pull policy:**
```yaml
image: registry/app:v1.0.0
imagePullPolicy: IfNotPresent
```

### Resource Limits (Security)

**LimitRange:**
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - default:
      memory: 512Mi
      cpu: 500m
    defaultRequest:
      memory: 256Mi
      cpu: 250m
    type: Container
```

**ResourceQuota:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    pods: "50"
```

## Validation Commands

### kubectl validation
```bash
# Dry-run validation
kubectl apply -f manifest.yaml --dry-run=client -o yaml

# Server-side validation
kubectl apply -f manifest.yaml --dry-run=server

# Validate all manifests in directory
kubectl apply -f ./k8s/ --dry-run=client
```

### Helm validation
```bash
# Lint chart
helm lint ./chart

# Render templates
helm template release-name ./chart

# Debug output
helm template release-name ./chart --debug

# Dry-run install
helm install release-name ./chart --dry-run
```

## Quality Checklist

Before deployment:
- [ ] Resource limits and requests set
- [ ] Liveness and readiness probes configured
- [ ] Security context defined (non-root)
- [ ] All capabilities dropped
- [ ] Read-only root filesystem (when possible)
- [ ] Labels follow consistent pattern
- [ ] ConfigMaps used for configuration
- [ ] Secrets properly handled
- [ ] Network policies defined
- [ ] RBAC configured with least privilege
- [ ] Image tags are specific (not latest)
- [ ] Manifests validate with dry-run

## Troubleshooting

### Pod Issues

**Pod stuck in Pending**
```bash
# Check pod events
kubectl describe pod <pod-name>

# Common causes:
# - Insufficient resources (check node capacity)
# - Volume mount issues
# - Image pull errors
# - Node selector mismatch

# Check node resources
kubectl top nodes
kubectl describe nodes
```

**Pod in CrashLoopBackOff**
```bash
# Check logs
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # Previous container logs

# Check events
kubectl describe pod <pod-name>

# Common causes:
# - Application crashes on startup
# - Liveness probe failing too quickly
# - Missing environment variables
# - Permission issues
```

**ImagePullBackOff**
```bash
# Check image pull errors
kubectl describe pod <pod-name>

# Common causes:
# - Image doesn't exist
# - Wrong image tag
# - Authentication required (missing imagePullSecrets)
# - Registry unreachable

# Check image pull secret
kubectl get secrets
kubectl describe secret <registry-secret>
```

**Pod not receiving traffic**
- Check readiness probe is passing
- Verify Service selector matches Pod labels
- Check if endpoints exist: `kubectl get endpoints <service-name>`
- Verify NetworkPolicy allows traffic

### Service and Networking

**Cannot connect to Service**
```bash
# Check service exists
kubectl get svc <service-name>

# Check endpoints
kubectl get endpoints <service-name>

# Verify selector matches pods
kubectl get pods --show-labels
kubectl describe svc <service-name>

# Test from within cluster
kubectl run debug --rm -it --image=busybox -- sh
wget -O- http://service-name:port
```

**Ingress not working**
- Verify Ingress controller is running
- Check Ingress resource: `kubectl describe ingress <name>`
- Verify DNS points to LoadBalancer IP
- Check TLS certificate if using HTTPS
- Review Ingress controller logs

**DNS resolution failing**
```bash
# Test DNS
kubectl run debug --rm -it --image=busybox -- nslookup service-name

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Resource Issues

**OOMKilled (Out of Memory)**
```bash
# Check pod status
kubectl describe pod <pod-name>

# Solutions:
# - Increase memory limit
# - Fix memory leak in application
# - Add resource requests/limits if missing
```

**CPU throttling**
```bash
# Check metrics
kubectl top pods

# Solutions:
# - Increase CPU limit
# - Optimize application performance
# - Scale horizontally (more replicas)
```

**Insufficient resources**
- Check node capacity: `kubectl describe nodes`
- Scale cluster (add more nodes)
- Reduce resource requests
- Use HorizontalPodAutoscaler for auto-scaling

### ConfigMap and Secret Issues

**Changes not reflected in pod**
- ConfigMaps/Secrets are not auto-reloaded
- Need to restart pod: `kubectl rollout restart deployment <name>`
- Or use init container to detect changes
- Consider using configuration management tools

**Secret not found**
```bash
# Check secret exists in correct namespace
kubectl get secrets -n <namespace>

# Verify secret name in pod spec matches
kubectl describe pod <pod-name>
```

### Storage Issues

**PVC stuck in Pending**
```bash
# Check PVC
kubectl describe pvc <pvc-name>

# Common causes:
# - No StorageClass available
# - StorageClass doesn't exist
# - Insufficient storage on cluster
# - Wrong access mode (ReadWriteOnce vs ReadWriteMany)
```

**Volume mount permission denied**
- Check fsGroup in securityContext
- Verify runAsUser has permissions
- Check volume ownership and permissions

### Helm Issues

**Helm install fails**
```bash
# Debug template rendering
helm template release-name ./chart --debug

# Check for errors
helm lint ./chart

# Verbose output
helm install release-name ./chart --debug --dry-run
```

**Helm upgrade fails**
```bash
# Check release history
helm history release-name

# Rollback if needed
helm rollback release-name <revision>

# Force upgrade
helm upgrade release-name ./chart --force
```

**Values not applied**
- Check values file syntax (YAML indentation)
- Verify values file is specified: `helm install -f values.yaml`
- Debug with: `helm get values release-name`

### Security Issues

**Pod Security admission denied**
- Check namespace pod security standard
- Adjust securityContext in pod spec
- Ensure running as non-root
- Drop unnecessary capabilities

**RBAC permission denied**
```bash
# Check service account
kubectl describe sa <service-account>

# Check role bindings
kubectl describe rolebinding <binding-name>

# Test permissions
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa-name>
```

### Deployment Issues

**Rolling update stuck**
```bash
# Check deployment status
kubectl rollout status deployment/<name>

# Check events
kubectl describe deployment/<name>

# Common causes:
# - Readiness probe failing
# - Insufficient resources
# - ImagePullBackOff

# Rollback if needed
kubectl rollout undo deployment/<name>
```

**Too many replicas unavailable**
- Check maxUnavailable in rolling update strategy
- Verify resources available
- Check pod logs for errors

### Debug Commands

**General debugging**
```bash
# Get all resources
kubectl get all -n <namespace>

# Watch resources
kubectl get pods -w

# Execute command in pod
kubectl exec -it <pod-name> -- /bin/sh

# Port forward for testing
kubectl port-forward <pod-name> 8080:8080

# Copy files
kubectl cp <pod-name>:/path/to/file ./local-file
```

**Events and logs**
```bash
# Get events
kubectl get events --sort-by=.metadata.creationTimestamp

# Logs from all pods in deployment
kubectl logs -l app=myapp --all-containers=true

# Follow logs
kubectl logs -f <pod-name>
```
