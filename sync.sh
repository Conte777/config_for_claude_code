#!/usr/bin/env bash
# Pulls live state back into the repo.
#
#   ./sync.sh export-mcp   ~/.claude.json mcpServers -> src/mcp/servers.json,
#                          with values from ~/.claude/.env folded back into
#                          ${VAR} placeholders.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DECL="$REPO_DIR/src/mcp/servers.json"
STATE="$HOME/.claude.json"
ENV_FILE="$HOME/.claude/.env"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
warn()    { echo -e "${YELLOW}WARNING: $*${NC}"; }
error()   { echo -e "${RED}ERROR: $*${NC}" >&2; }
success() { echo -e "${GREEN}$*${NC}"; }

usage() { echo "usage: $0 export-mcp"; exit 2; }

export_mcp() {
    [ -f "$STATE" ] || { error "$STATE not found"; exit 1; }

    # var -> value map, longest value first so a value that contains another
    # (a host inside a URL) is folded before its substring is.
    local map='[]'
    if [ -f "$ENV_FILE" ]; then
        map=$(grep -vE '^[[:space:]]*(#|$)' "$ENV_FILE" \
            | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//' \
            | while IFS='=' read -r k v; do
                  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
                  if [ -n "$k" ] && [ -n "$v" ]; then
                      jq -nc --arg var "$k" --arg val "$v" '$ARGS.named'
                  fi
              done \
            | jq -sc 'sort_by(-(.val | length))')
    else
        warn "$ENV_FILE not found — nothing to fold back into placeholders"
    fi

    local out
    out=$(jq --argjson map "$map" '
        def fold($m): reduce $m[] as $e (.;
            if index($e.val) == null then . else split($e.val) | join("${" + $e.var + "}") end);
        # same normalisation reconcile-mcp.sh compares against, so a re-export
        # of untouched state is a no-op diff
        def norm:
            (if (.env? // {}) == {} then del(.env) else . end)
          | (if (.headers? // {}) == {} then del(.headers) else . end)
          | (if has("command") then .type = (.type? // "stdio") else . end);
        { mcpServers: ((.mcpServers // {}) | to_entries | sort_by(.key)
                       | map(.value |= norm) | from_entries) }
        | walk(if type == "string" then fold($map) else . end)
    ' "$STATE")

    local leaks
    leaks=$(grep -oE 'glpat-|glsa_|ctx7sk-|keen_|ghp_|github_pat_|AKIA|[0-9a-f]{32,}' <<<"$out" | sort -u || true)
    if [ -n "$leaks" ]; then
        error "refusing to write $DECL — secret-looking strings survived placeholder folding:"
        printf '  %s\n' $leaks >&2
        echo "Add the corresponding variables to $ENV_FILE and re-run." >&2
        exit 1
    fi

    printf '%s\n' "$out" > "$DECL"
    success "wrote $DECL"
    jq -r '.mcpServers | keys[] | "  " + .' "$DECL"
}

case "${1:-}" in
    export-mcp) export_mcp ;;
    *) usage ;;
esac
