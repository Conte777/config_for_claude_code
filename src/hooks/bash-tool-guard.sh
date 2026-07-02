#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks plain single cat/head/tail/grep/find/ls
# calls in favor of Read/Grep/Glob (leaner context + keeps the harness's
# "file has been read" tracking intact for Edit/Write). Anything compound —
# pipes, &&, ;, &, redirects, substitutions, multiline — passes through.
# Also routes raw git commit/branch to mcp__git__ and kubectl reads to
# mcp__kubernetes__ (read-only server pinned to the az-cp-dev kubeconfig).
set -euo pipefail

is_simple_read() { # <command> -> 0 if it should be blocked
  local c="$1"
  case "$c" in
    *'|'*|*'&'*|*';'*|*'>'*|*'<'*|*'$('*|*'`'*|*$'\n'*) return 1 ;;
  esac
  # ponytail: tail -f follows a live file — Read can't; let it through
  [[ "$c" =~ ^[[:space:]]*tail[[:space:]].*-[A-Za-z]*f ]] && return 1
  [[ "$c" =~ ^[[:space:]]*(cat|head|tail|grep|egrep|fgrep|find|ls)([[:space:]]|$) ]]
}

is_kubectl_read() { # <command> -> 0 if the read has an mcp__kubernetes__ equivalent
  local c="$1"
  printf '%s' "$c" | grep -qE '(^|[[:space:]])kubectl([[:space:]]|$)' || return 1
  # ponytail: logs -f follows a live stream — the MCP can't; let it through
  printf '%s' "$c" | grep -qE '(^|[[:space:]])(-f|--follow)([[:space:]]|$)' && return 1
  # first non-flag token after kubectl; a valueless flag swallows the next token
  local verb
  verb=$(printf '%s' "$c" | sed 's/.*kubectl//' \
    | awk '{for(i=1;i<=NF;i++){t=$i; if(t~/^-/){if(t!~/=/)i++; continue} print t; exit}}')
  case "$verb" in
    get|describe|logs|top|events) return 0 ;;
    *) return 1 ;;
  esac
}

# ponytail: self-check for the classifier (the non-trivial part).
# Run: BASH_GUARD_SELFTEST=1 bash src/hooks/bash-tool-guard.sh
if [[ "${BASH_GUARD_SELFTEST:-}" == 1 ]]; then
  blocked=(
    'cat README.md'
    '  head -20 src/main.go'
    'tail -n 50 app.log'
    'grep -rn TODO src'
    'find . -name "*.ts"'
    'ls -la src/hooks'
    'ls'
  )
  passed=(
    'cat x | grep y'
    'ls -la && pwd'
    'grep foo bar > out.txt'
    'find . -name "*.pyc" -exec rm {} \;'
    'tail -f app.log'
    'echo cat'
    'cat <<EOF
hi
EOF'
    'files=$(ls src)'
    ''
  )
  for c in "${blocked[@]}"; do
    is_simple_read "$c" || { echo "FAIL: should block: $c"; exit 1; }
  done
  for c in "${passed[@]}"; do
    is_simple_read "$c" && { echo "FAIL: should pass: $c"; exit 1; }
  done
  blocked_k8s=(
    'kubectl get pods -n auth'
    'kubectl --kubeconfig ~/.kube/az-cp-dev-k8s.yaml get deploy -o wide'
    'kubectl -n auth get pods'
    'kubectl describe deploy order-service'
    'kubectl logs order-service-abc123 -n auth'
    'kubectl top pods'
    'kubectl get deploy -o json | jq ".items[].spec"'
  )
  passed_k8s=(
    'kubectl logs -f order-service-abc123'
    'kubectl apply -f deploy.yaml'
    'kubectl delete pod x'
    'kubectl exec -it pod-x -- sh'
    'kubectl rollout restart deploy/order-service'
    'kubectl explain pods.spec'
    'echo kubectl'
  )
  for c in "${blocked_k8s[@]}"; do
    is_kubectl_read "$c" || { echo "FAIL: should block k8s: $c"; exit 1; }
  done
  for c in "${passed_k8s[@]}"; do
    is_kubectl_read "$c" && { echo "FAIL: should pass k8s: $c"; exit 1; }
  done
  echo "bash-tool-guard selftest OK"; exit 0
fi

cmd=$(cat | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Raw git commit / branch creation -> route to mcp__git__ (server generates the msg).
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+(commit([[:space:]]|$)|checkout[[:space:]]+-b|switch[[:space:]]+-[cC]([[:space:]]|$)|branch[[:space:]]+[^-[:space:]])'; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Raw git commit / branch creation is blocked. Use mcp__git__commit / mcp__git__branch instead (the server generates the commit message — never pass your own)."}}'
  exit 0
fi

if is_kubectl_read "$cmd"; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"kubectl reads are blocked: use the mcp__kubernetes__ tools instead (read-only, pinned to the az-cp-dev kubeconfig) — pods_list, pods_log, pods_top, resources_list/resources_get, events_list. kubectl writes, logs -f and other clusters still go through Bash."}}'
  exit 0
fi

if is_simple_read "$cmd"; then
  first=$(printf '%s' "$cmd" | awk '{print $1}')
  case "$first" in
    cat|head|tail)   hint="Read (supports offset/limit)" ;;
    grep|egrep|fgrep) hint="Grep" ;;
    find|ls)         hint="Glob" ;;
  esac
  echo "Plain '$first' via Bash is blocked: use the $hint tool instead — it keeps context lean and marks files as read for Edit/Write." >&2
  exit 2
fi
exit 0
