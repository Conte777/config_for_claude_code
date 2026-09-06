#!/usr/bin/env bash
# Removes the symlinks setup.sh created in ~/.claude. Leaves installed plugins,
# registered MCP servers, ~/.claude/.env and ~/.claude itself alone.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}$*${NC}"; }
warn()    { echo -e "${YELLOW}WARNING: $*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }

TARGET_DIR="$HOME/.claude"
AUTOGIT_LINK="$HOME/.config/autogit/config.json"

# Current links, plus names earlier versions of setup.sh linked.
NAMES=(
    settings.json
    CLAUDE.md
    statusline.sh
    keybindings.json
    commands
    agents
    skills
    hooks
    mcp
    workflow-scripts
    plugins
    rules
    scripts
    output-styles
)

echo "============================================"
info "Claude Code Configuration Cleanup"
echo "============================================"
echo ""
echo "Symlinks under $TARGET_DIR that will be removed:"
for name in "${NAMES[@]}"; do
    [ -L "$TARGET_DIR/$name" ] && echo "  - $name"
done
[ -L "$AUTOGIT_LINK" ] && echo "  - $AUTOGIT_LINK"
echo ""

read -rp "Continue? (y/N): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
echo ""

ERRORS=0
for name in "${NAMES[@]}"; do
    target="$TARGET_DIR/$name"
    if [ -L "$target" ]; then
        rm "$target" && info "  removed $name" || { warn "could not remove $name"; ERRORS=$((ERRORS + 1)); }
    elif [ -e "$target" ]; then
        warn "  skipped $name (not a symlink)"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ -L "$AUTOGIT_LINK" ]; then
    rm "$AUTOGIT_LINK" && info "  removed $AUTOGIT_LINK" || { warn "could not remove $AUTOGIT_LINK"; ERRORS=$((ERRORS + 1)); }
elif [ -e "$AUTOGIT_LINK" ]; then
    warn "  skipped $AUTOGIT_LINK (not a symlink)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "============================================"
if [ "$ERRORS" -eq 0 ]; then
    success "All symlinks removed."
else
    warn "Finished with $ERRORS item(s) left in place — see the messages above."
fi
echo "============================================"
echo ""
echo "Left untouched: $TARGET_DIR itself, ~/.claude/.env, installed plugins and"
echo "registered MCP servers. Remove those with 'claude plugin uninstall' /"
echo "'claude mcp remove', or delete $TARGET_DIR to wipe everything."
