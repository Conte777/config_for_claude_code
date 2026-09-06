---
name: k8s
description: Inspect or poke a service in the dev/stage Kubernetes cluster — pods, logs, config maps, restarts, port-forwards to gRPC or metrics endpoints. Use for anything that would otherwise be a raw kubectl invocation.
allowed-tools: Bash(kubectl:*), Bash(grpcurl:*)
---

# Kubernetes work

## Pick the environment first

Two environments, each with its own kubeconfig and namespace, both read from `~/.claude/.env`:

| Environment | Kubeconfig | Namespace |
| --- | --- | --- |
| dev | `$KUBECONFIG_DEV` | `$K8S_NAMESPACE_DEV` |
| stage | `$KUBECONFIG_STAGE` | `$K8S_NAMESPACE_STAGE` |

Bind them once per session and reuse them:

```bash
KC="$KUBECONFIG_DEV" NS="$K8S_NAMESPACE_DEV"
```

Every command below is then:

```bash
kubectl --kubeconfig "$KC" -n "$NS" ...
```

Never `export KUBECONFIG`, never a bare `kubectl` — an unset kubeconfig silently falls through to whatever cluster the machine's default context points at.

Either variable empty → stop, and tell the user that `~/.claude/.env` has no value for that name. Do not guess a path, a context or a namespace.

The user says only "dev" or "stage" most of the time. When they say neither and the task does not imply one, ask.

## Find the workload

Services are labelled `app=<service>`:

```bash
kubectl --kubeconfig "$KC" -n "$NS" get pods -l app=<service>
kubectl --kubeconfig "$KC" -n "$NS" get pods -l app=<service> \
  -o jsonpath='{.items[0].metadata.name}'
```

Prefer the label selector over a pod name everywhere it is accepted — pod names change on every restart, and a name captured earlier in the session is usually already stale.

## Logs

```bash
kubectl --kubeconfig "$KC" -n "$NS" logs -l app=<service> --tail=200
kubectl --kubeconfig "$KC" -n "$NS" logs -l app=<service> --since=15m
kubectl --kubeconfig "$KC" -n "$NS" logs -l app=<service> --previous
```

`--previous` is the one that survives a crash loop. For a container that restarts faster than it logs, `kubectl describe pod` plus `get events --sort-by=.lastTimestamp` say more than the log does.

## Port-forward, then talk to the service

Start the forward as a background Bash command (`run_in_background: true`), not with a trailing `&` — a foreground forward blocks the session until it is killed.

```bash
kubectl --kubeconfig "$KC" -n "$NS" port-forward svc/<service> 50051:50051
```

Then, against `localhost`:

```bash
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext -d '{"...":"..."}' localhost:50051 <package>.<Service>/<Method>
curl -s localhost:<metrics-port>/metrics | grep <metric>
```

Kill the background forward as soon as the check is done.

## Change config

```bash
kubectl --kubeconfig "$KC" -n "$NS" get configmap <name> -o yaml
kubectl --kubeconfig "$KC" -n "$NS" patch configmap <name> \
  --type merge -p '{"data":{"<key>":"<value>"}}'
kubectl --kubeconfig "$KC" -n "$NS" rollout restart deployment/<service>
```

A config map edit reaches the process only after the restart. Save the original value before patching — it is the only way to put it back.

## Wait for something, without sleeping

```bash
kubectl --kubeconfig "$KC" -n "$NS" rollout status deployment/<service> --timeout=180s
kubectl --kubeconfig "$KC" -n "$NS" wait --for=condition=Ready pod -l app=<service> --timeout=120s
```

These block until the condition holds or the timeout fires. Do not poll with `sleep` — foreground `sleep` is blocked in this harness anyway.

## Before reporting: put it back

Every manual change is temporary unless the user asked for it to stay. Walk the list at the end of the task:

- config map keys patched → restore the saved value and restart again;
- replicas scaled → scale back to the original count;
- background port-forwards → killed;
- anything else created for the check (a debug pod, a temporary secret) → deleted.

Then list in the report what was changed, what was restored, and anything left in place on purpose. A change that outlives the session is other people's broken environment.
