#!/usr/bin/env bash
# Wrapper around `uvx mcp-grafana`: Pomerium intercepts /api/* too, so the service account
# token never reaches Grafana — the proxy answers 302 to SSO and mcp-grafana parses that
# HTML as JSON. Borrow the browser's Pomerium cookie to pass the proxy as the user.
# stdout is the MCP JSON-RPC stream — diagnostics go to stderr, the cookie value nowhere.
set -uo pipefail

log() { printf 'grafana-mcp: %s\n' "$*" >&2; }

run() { exec uvx mcp-grafana "$@"; }

if [[ -z "${GRAFANA_URL:-}" ]]; then
    log "GRAFANA_URL is not set — starting without a Pomerium cookie"
    run "$@"
fi

base=${GRAFANA_URL%/}
host=${base#*://}
host=${host%%/*}
host=${host%%:*}

# Firefox-family (incl. Zen) keeps cookies unencrypted in sqlite. cookies.sqlite is
# WAL-mode and locked while the browser runs, so copy db+wal aside and let SQLite replay
# the WAL — a just-refreshed cookie may live only there. `immutable=1` skips the WAL and
# is the fallback for when the copy fails.
cookie=$(GRAFANA_HOST="$host" python3 - <<'PY'
import glob, os, shutil, sqlite3, sys, tempfile

host = os.environ["GRAFANA_HOST"]

def read(path):
    tmp = tempfile.mkdtemp()
    try:
        dst = os.path.join(tmp, "cookies.sqlite")
        for suffix in ("", "-wal", "-shm"):
            if os.path.exists(path + suffix):
                shutil.copy2(path + suffix, dst + suffix)
        uris = [dst, f"file:{path}?mode=ro&immutable=1"]
        for uri in uris:
            try:
                db = sqlite3.connect(uri, uri=uri.startswith("file:"))
                try:
                    return db.execute(
                        "SELECT host, value, creationTime FROM moz_cookies WHERE name = '_pomerium'"
                    ).fetchall()
                finally:
                    db.close()
            except sqlite3.Error:
                continue
        return []
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def matches(cookie_host):
    cookie_host = cookie_host.lstrip(".")
    return host == cookie_host or host.endswith("." + cookie_host)

best = None
profiles = []
for app in ("zen", "Firefox"):
    profiles += glob.glob(
        os.path.expanduser(f"~/Library/Application Support/{app}/Profiles/*/cookies.sqlite")
    )

for path in profiles:
    for cookie_host, value, created in read(path):
        if matches(cookie_host) and (best is None or created > best[0]):
            best = (created, value)

if best is None:
    print(f"grafana-mcp: no _pomerium cookie for {host} in {len(profiles)} browser profile(s)", file=sys.stderr)
else:
    sys.stdout.write(best[1])
PY
)

if [[ -n "$cookie" ]]; then
    export GRAFANA_EXTRA_HEADERS
    GRAFANA_EXTRA_HEADERS=$(COOKIE="$cookie" python3 -c \
        'import json, os; print(json.dumps({"Cookie": "_pomerium=" + os.environ["COOKIE"]}))')
fi

# Pomerium answers a stale session with a 302 to the SSO login page, and an unreachable
# host answers nothing at all. Either way mcp-grafana would start and then fail to
# unmarshal HTML on every single call, which explains nothing — refuse to start instead,
# so /mcp shows this server as failed with the reason. curl reads the secrets from stdin
# so they stay out of the process arguments.
if command -v curl >/dev/null 2>&1; then
    status=$({
        [[ -n "$cookie" ]] && printf 'header = "Cookie: _pomerium=%s"\n' "$cookie"
        [[ -n "${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}" ]] &&
            printf 'header = "Authorization: Bearer %s"\n' "$GRAFANA_SERVICE_ACCOUNT_TOKEN"
    } | curl -sS --config - --max-time 10 -o /dev/null -w '%{http_code}' "$base/api/health" 2>/dev/null)

    case "$status" in
        2*) ;;
        3*) log "not starting: Pomerium session expired (HTTP $status). Open $base in the browser to refresh SSO, then reconnect this MCP server"
            exit 1 ;;
        "") log "not starting: cannot reach $base. Turn the VPN on, open $base in the browser, then reconnect this MCP server"
            exit 1 ;;
        *)  log "health check returned HTTP $status — starting anyway" ;;
    esac
elif [[ -z "$cookie" ]]; then
    log "starting anyway — no _pomerium cookie and no curl to check with; Grafana tools will fail until you open $base in the browser and reconnect this MCP server"
fi

run "$@"
