---
name: grafana
description: Inspect or edit the dev Grafana — dashboards, datasources, alert rules, and PromQL/LogQL/TraceQL queries over Prometheus, Loki and Tempo. Use for metric or log history that outlives a pod, and for anything that would otherwise be a visit to the Grafana UI.
allowed-tools: Bash(gcx:*), Bash(kubectl port-forward:*)
---

# Grafana work

`gcx` is the CLI for everything here. `gcx help-tree` prints the command tree and
`gcx <command> --help` the flags — read those rather than guess at a command.

## Connect

Pomerium fronts the instance and intercepts `/api/*`, meeting a service account token
with a 302 to SSO. The token works against the pod, so reach it through a port-forward.
Start it as a background Bash command (`run_in_background: true`), which leaves the
session free while it runs:

```bash
kubectl --kubeconfig "$KUBECONFIG_DEV" -n "$GRAFANA_K8S_NAMESPACE" \
  port-forward "svc/$GRAFANA_K8S_SERVICE" 13000:80
```

Bind the credentials in the same shell as every `gcx` call:

```bash
set -a; . ~/.claude/.env; set +a
export GRAFANA_SERVER=http://localhost:13000 GRAFANA_ORG_ID=1 \
       GRAFANA_TOKEN="$GRAFANA_SERVICE_ACCOUNT_TOKEN"
```

Any of those `.env` names empty → stop and say which one. A guessed token or namespace
is a wrong answer wearing the shape of a working one.

Keep the token in the environment: it overrides the context in memory and persists
nothing. `gcx config set` writes it to the config file and the Keychain instead.

Confirm the link with `gcx config check` — it prints connectivity, auth method and
Grafana version, and is the first thing to run when a call behaves oddly.

## Read

```bash
gcx dashboards list
gcx dashboards get <uid>
gcx datasources list
gcx metrics query '<promql>' -d <uid> --since 1h
gcx logs query '<logql>' -d <uid> --since 1h
gcx alert rules list
gcx api GET /api/<path>          # for what has no command of its own
```

Resolve datasource uids with `gcx datasources list` each session — the instance carries
one Prometheus, one Loki and one Tempo, and the uids are generated, not stable.

Output arrives as JSON, and `gcx` states on every call how to narrow it. Take the offer:
`--json list` prints the field paths, `--json a,b` selects them, `--jq` transforms; the two
flags are mutually exclusive, so pick one per call. The
wrapper differs per command — `.items[]` for dashboards, `.datasources[]` for
datasources, `.data.result[]` for a query — so read the paths rather than assume one.

## Change

Grafana is shared. `dashboards create/update/delete`, `datasources create/update/delete`,
`resources push` and `resources delete` land in an environment other people are reading
right now, and `dev` in the name does not make it yours. Name what will change and get
the user's word for it, every time, for each object.

Two things the instance may refuse: writing Grafana-managed alert rules needs Grafana 13
or newer, and every Cloud command group (`slo`, `irm`, `k6`, `fleet`, `kg`, `appo11y`,
`assistant`, the `adaptive` subtrees) has no backend behind a self-hosted install.
`gcx config check` prints the version actually running.

Keep `--insecure-log-http-payload` out of every invocation: it writes the service
account token into the log.

## Put it back

The forward is this skill's one piece of leftover state — kill it before reporting.
Then say which Grafana objects were changed and which were only read.
