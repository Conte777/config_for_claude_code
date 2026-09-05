#!/usr/bin/env bash
# Brings installed marketplaces and plugins in line with src/settings.json.
# settings.json is the source of truth: Claude Code maintains extraKnownMarketplaces
# and enabledPlugins itself on /plugin install and /plugin uninstall, but it never
# installs from them on its own.
set -euo pipefail

SETTINGS="${1:?usage: reconcile-plugins.sh <settings.json>}"

YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}$*${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}"; }

# The official marketplace is not declared in extraKnownMarketplaces (Claude Code
# treats it as built-in and does not persist it), but it still has to be added
# before anything can be installed from it. Implicit declaration, never removed.
IMPLICIT_MARKETPLACES=$'claude-plugins-official\tanthropics/claude-plugins-official'

if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found in PATH — skipping plugin reconciliation."
    exit 0
fi

# Read the whole declaration up front: `claude plugin install` rewrites
# settings.json underneath us.
declared_marketplaces=$(jq -r '
    (.extraKnownMarketplaces // {}) | to_entries[]
    | .key + "\t" + (.value.source.repo // .value.source.url // .value.source.path // "")
' "$SETTINGS")
declared_plugins=$(jq -r '(.enabledPlugins // {}) | to_entries[] | .key + "\t" + (.value|tostring)' "$SETTINGS")
declared_marketplaces=$(printf '%s\n%s' "$IMPLICIT_MARKETPLACES" "$declared_marketplaces")

# --- marketplaces: add what is missing ---------------------------------------
known_json=$(claude plugin marketplace list --json 2>/dev/null || echo '[]')
known=$(jq -r '.[].name' <<<"$known_json")

while IFS=$'\t' read -r name source; do
    [ -n "$name" ] || continue
    if [ -z "$source" ]; then
        warn "marketplace $name has no resolvable source in settings.json — skipping"
        continue
    fi
    if grep -qxF "$name" <<<"$known"; then
        # known but its local checkout is gone (a wiped ~/.claude/plugins) — refetch
        loc=$(jq -r --arg n "$name" '.[] | select(.name == $n) | .installLocation // ""' <<<"$known_json")
        if [ -n "$loc" ] && [ ! -d "$loc" ]; then
            info "  ~ marketplace $name (refetching)"
            claude plugin marketplace update "$name" || warn "failed to update marketplace $name"
        fi
        continue
    fi
    info "  + marketplace $name ($source)"
    claude plugin marketplace add "$source" --scope user || warn "failed to add marketplace $name"
done <<<"$declared_marketplaces"

# --- plugins ------------------------------------------------------------------
installed=$(claude plugin list --json 2>/dev/null | jq -r '.[] | select(.scope == "user") | .id + "\t" + (.enabled|tostring)' || true)

while IFS=$'\t' read -r id want; do
    [ -n "$id" ] || continue
    have=$(awk -F'\t' -v k="$id" '$1 == k { print $2 }' <<<"$installed")
    if [ -z "$have" ]; then
        info "  + $id"
        if ! claude plugin install "$id" --scope user -y; then
            warn "failed to install $id"
            continue
        fi
        have=true
    fi
    if [ "$have" != "$want" ]; then
        if [ "$want" = true ]; then
            info "  ~ enable $id"
            claude plugin enable "$id" --scope user || warn "failed to enable $id"
        else
            info "  ~ disable $id"
            claude plugin disable "$id" --scope user || warn "failed to disable $id"
        fi
    fi
done <<<"$declared_plugins"

# --- plugins: remove what settings.json no longer declares ---------------------
declared_ids=$(cut -f1 <<<"$declared_plugins")
while IFS=$'\t' read -r id _; do
    [ -n "$id" ] || continue
    grep -qxF "$id" <<<"$declared_ids" && continue
    info "  - $id"
    claude plugin uninstall "$id" --scope user -y || warn "failed to uninstall $id"
done <<<"$installed"

# --- marketplaces: remove what settings.json no longer declares -----------------
declared_names=$(cut -f1 <<<"$declared_marketplaces")
while read -r name; do
    [ -n "$name" ] || continue
    grep -qxF "$name" <<<"$declared_names" && continue
    info "  - marketplace $name"
    claude plugin marketplace remove "$name" --scope user || warn "failed to remove marketplace $name"
done <<<"$known"
