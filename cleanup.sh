#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}$*${NC}"; }
warn()    { echo -e "${YELLOW}WARNING: $*${NC}"; }
error()   { echo -e "${RED}ERROR: $*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }

TARGET_DIR="$HOME/.claude"

# Symlink targets to remove
declare -a LINK_TARGETS=(
    "$TARGET_DIR/settings.json"
    "$TARGET_DIR/CLAUDE.md"
    "$TARGET_DIR/commands"
    "$TARGET_DIR/agents"
    "$TARGET_DIR/skills"
    "$TARGET_DIR/hooks"
    "$TARGET_DIR/statusline.sh"
)

# Header
echo "============================================"
info "Claude Code Configuration Cleanup"
echo "============================================"
echo ""
echo "This script will remove symbolic links created by setup.sh"
echo ""

echo "The following symbolic links will be removed:"
for target in "${LINK_TARGETS[@]}"; do
    echo "  - $target"
done
echo ""

# Confirmation
read -rp "Are you sure you want to continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "Removing symbolic links..."
echo ""

ERROR_COUNT=0

for target in "${LINK_TARGETS[@]}"; do
    if [ -L "$target" ]; then
        echo "Removing: $target"
        if rm "$target" 2>/dev/null; then
            success "  - Removed successfully"
        else
            warn "Failed to remove $target"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    elif [ -e "$target" ]; then
        warn "Skipping: $target (not a symlink, will not remove)"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        echo "Skipping: $target (not found)"
    fi
done

echo ""
echo "============================================"

if [ "$ERROR_COUNT" -eq 0 ]; then
    success "SUCCESS: All symbolic links removed!"
else
    warn "COMPLETED WITH WARNINGS: $ERROR_COUNT item(s) could not be removed."
    echo "Please check the messages above and remove them manually if needed."
fi

echo "============================================"
echo ""
echo "NOTE: The .claude directory itself was not removed."
echo "If you want to remove it completely, delete it manually:"
echo "  rm -rf $TARGET_DIR"
