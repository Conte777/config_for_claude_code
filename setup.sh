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

# Paths
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"
TARGET_DIR="$HOME/.claude"

# Symlink definitions: target -> source
declare -a LINK_TARGETS=(
    "$TARGET_DIR/settings.json"
    "$TARGET_DIR/CLAUDE.md"
    "$TARGET_DIR/commands"
    "$TARGET_DIR/agents"
    "$TARGET_DIR/skills"
    "$TARGET_DIR/hooks"
    "$TARGET_DIR/statusline.sh"
)

declare -a LINK_SOURCES=(
    "$SRC_DIR/settings.json"
    "$SRC_DIR/CLAUDE.md"
    "$SRC_DIR/commands"
    "$SRC_DIR/agents"
    "$SRC_DIR/skills"
    "$SRC_DIR/hooks"
    "$SRC_DIR/statusline.sh"
)

# Rollback on error
CREATED_LINKS=()

cleanup_on_error() {
    echo ""
    error "Cleaning up partial installation..."
    for link in "${CREATED_LINKS[@]}"; do
        rm -f "$link" 2>/dev/null || true
    done
    error "Setup failed. Please check the error messages above."
    exit 1
}

trap 'cleanup_on_error' ERR

# Header
echo "============================================"
info "Claude Code Configuration Setup"
echo "============================================"
echo ""
echo "Repository path: $REPO_DIR"
echo ""

# Check for conflicts
CONFLICT=0
for target in "${LINK_TARGETS[@]}"; do
    if [ -e "$target" ] || [ -L "$target" ]; then
        warn "Already exists: $target"
        CONFLICT=1
    fi
done

if [ "$CONFLICT" -eq 1 ]; then
    echo ""
    error "One or more target files/directories already exist."
    echo "Please manually backup or remove existing files before running this script."
    echo "You can use cleanup.sh to remove symbolic links if they were created by this script."
    exit 1
fi

# Check source files exist
echo "Checking source files..."
echo ""
SOURCE_MISSING=0
for source in "${LINK_SOURCES[@]}"; do
    if [ ! -e "$source" ]; then
        error "Source not found: $source"
        SOURCE_MISSING=1
    fi
done

if [ "$SOURCE_MISSING" -eq 1 ]; then
    echo ""
    error "One or more source files/directories are missing."
    echo "Please ensure all required files exist in: $SRC_DIR"
    exit 1
fi

echo "All source files found."

# Create .claude directory if needed
if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

# Create symbolic links
echo ""
echo "Creating symbolic links..."
echo ""

for i in "${!LINK_TARGETS[@]}"; do
    target="${LINK_TARGETS[$i]}"
    source="${LINK_SOURCES[$i]}"
    echo "Creating: $target -> $source"
    ln -s "$source" "$target"
    CREATED_LINKS+=("$target")
    success "  - Created successfully"
done

echo ""
echo "============================================"
success "SUCCESS: All symbolic links created!"
echo "============================================"
echo ""
echo "Claude Code will now use configuration from:"
echo "$REPO_DIR"
