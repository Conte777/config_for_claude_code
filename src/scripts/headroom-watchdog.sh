#!/bin/sh
set -u

PORT=8787
SERVICE="gui/$(id -u)/ai.headroom.proxy"
RSS_GATE_MB=400           # cheap filter: measured ratio is ~3.5x, so 2 GB footprint sits near 590 MB RSS
FOOTPRINT_LIMIT_MB=2048   # above the 1.2 GB working plateau, so idle restarts stay rare
IDLE_SECS=180

# launchd hands over a minimal PATH; pin the system interpreter instead of the uv/brew ones
PY=/usr/bin/python3

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }

# whoever holds the port is the proxy; argv differs between launchd and uv-tool launches
proxy_pid() { lsof -ti ":$PORT" -sTCP:LISTEN 2>/dev/null | head -1; }

restart_proxy() {
    pid=$1
    kill -TERM "$pid" 2>/dev/null
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 30 ]; do
        sleep 1
        i=$((i + 1))
    done
    launchctl kickstart "$SERVICE"
}

pid=$(proxy_pid)

if ! pgrep -x claude >/dev/null 2>&1; then
    if [ -n "$pid" ]; then
        log "no claude clients, stopping proxy (pid $pid)"
        kill -TERM "$pid" 2>/dev/null
    fi
    exit 0
fi

if [ -z "$pid" ]; then
    log "clients present, port $PORT down, kickstarting"
    launchctl kickstart "$SERVICE"
    exit 0
fi

rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
[ -n "$rss_kb" ] || exit 0
[ "$((rss_kb / 1024))" -ge "$RSS_GATE_MB" ] || exit 0

footprint_mb=$(vmmap -summary "$pid" 2>/dev/null | awk -F: '
    /^Physical footprint:/ {
        v = $2; gsub(/[ \t]/, "", v)
        u = substr(v, length(v), 1); n = substr(v, 1, length(v) - 1) + 0
        if (u == "G") n *= 1024; else if (u == "K") n /= 1024
        printf "%d", n; exit
    }')
[ -n "$footprint_mb" ] || exit 0
[ "$footprint_mb" -ge "$FOOTPRINT_LIMIT_MB" ] || exit 0

in_flight=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/debug/warmup" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print(d.get("runtime", {}).get("compression_executor", {}).get("in_flight", -1))
' 2>/dev/null) || exit 0
if [ "$in_flight" != "0" ]; then
    log "footprint ${footprint_mb}MB but $in_flight compressions in flight, deferring"
    exit 0
fi

idle=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/stats-history" | "$PY" -c '
import calendar, json, sys, time
try:
    ts = json.load(sys.stdin)["display_session"]["last_activity_at"]
except Exception:
    sys.exit(1)
print(int(time.time() - calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))))
' 2>/dev/null) || exit 0
if [ "$idle" -lt "$IDLE_SECS" ]; then
    log "footprint ${footprint_mb}MB but active ${idle}s ago, deferring"
    exit 0
fi

log "footprint ${footprint_mb}MB over ${FOOTPRINT_LIMIT_MB}MB, idle ${idle}s, restarting proxy (pid $pid)"
restart_proxy "$pid"
