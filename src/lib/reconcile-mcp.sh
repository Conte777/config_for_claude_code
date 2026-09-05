#!/usr/bin/env bash
# Brings user-scope MCP servers in line with src/mcp/servers.json.
# ~/.claude.json is stateful and can't be symlinked, so the declaration is
# replayed through the CLI. ${VAR} placeholders are filled from the environment
# (setup.sh sources ~/.claude/.env first); a server whose variables are not all
# set is left alone and reported.
set -euo pipefail

DECL="${1:?usage: reconcile-mcp.sh <servers.json>}"
STATE="$HOME/.claude.json"

YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}$*${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}"; }

if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found in PATH — skipping MCP reconciliation."
    exit 0
fi

# Canonical form for comparison: drop empty env/headers and default stdio, so a
# server the CLI wrote back with its own defaults still compares equal.
JQ_NORM='
def norm:
    (if (.env? // {}) == {} then del(.env) else . end)
  | (if (.headers? // {}) == {} then del(.headers) else . end)
  | (if has("command") then .type = (.type? // "stdio") else . end);
'

# $HOME and friends stay literal — they are expanded by the shell the server
# starts under. Only ${VAR} is substituted here, and only from the environment.
JQ_EXPAND='
def expand:
  walk(if type == "string"
       then gsub("\\$\\{(?<v>[A-Za-z_][A-Za-z0-9_]*)\\}";
                 if (($ENV[.v] // "") == "") then "${" + .v + "}" else $ENV[.v] end)
       else . end);
'

declared_names=$(jq -r '.mcpServers | keys[]' "$DECL")

for name in $declared_names; do
    want=$(jq -c --arg n "$name" "$JQ_EXPAND $JQ_NORM"' .mcpServers[$n] | expand | norm' "$DECL")

    # expand leaves any ${VAR} the environment does not define in place
    missing=$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' <<<"$want" | tr -d '${}' | sort -u | paste -sd, - || true)
    if [ -n "$missing" ]; then
        warn "MCP $name skipped — unset in ~/.claude/.env: $missing"
        continue
    fi

    have=$(jq -c --arg n "$name" "$JQ_NORM"' (.mcpServers // {})[$n] | if . == null then null else norm end' "$STATE" 2>/dev/null || echo null)

    if [ "$have" = null ]; then
        info "  + $name"
        claude mcp add-json "$name" "$want" --scope user >/dev/null || warn "failed to add MCP $name"
    elif [ "$(jq -Sc . <<<"$have")" != "$(jq -Sc . <<<"$want")" ]; then
        info "  ~ $name"
        claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
        claude mcp add-json "$name" "$want" --scope user >/dev/null || warn "failed to update MCP $name"
    fi
done

# Anything user-scope that servers.json no longer declares. Plugin-provided
# servers never land in ~/.claude.json, so they are not seen here.
jq -r '(.mcpServers // {}) | keys[]' "$STATE" 2>/dev/null | while read -r name; do
    [ -n "$name" ] || continue
    grep -qxF "$name" <<<"$declared_names" && continue
    info "  - $name"
    claude mcp remove "$name" --scope user >/dev/null || warn "failed to remove MCP $name"
done
