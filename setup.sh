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
    "$TARGET_DIR/mcp"
    "$TARGET_DIR/statusline.sh"
    "$TARGET_DIR/plugins"
    "$TARGET_DIR/keybindings.json"
    "$TARGET_DIR/workflows"
    "$TARGET_DIR/rules"
)

declare -a LINK_SOURCES=(
    "$SRC_DIR/settings.json"
    "$SRC_DIR/CLAUDE.md"
    "$SRC_DIR/commands"
    "$SRC_DIR/agents"
    "$SRC_DIR/skills"
    "$SRC_DIR/hooks"
    "$SRC_DIR/mcp"
    "$SRC_DIR/statusline.sh"
    "$SRC_DIR/plugins"
    "$SRC_DIR/keybindings.json"
    "$SRC_DIR/workflows"
    "$SRC_DIR/rules"
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

# Install plugins from declaration. Claude Code does NOT auto-install from
# enabledPlugins in settings.json — it only enables already-installed plugins.
# installed_plugins.json/known_marketplaces.json are runtime state (abs paths,
# timestamps) and are gitignored, so plugins must be reinstalled here.
echo ""
echo "Installing plugins..."
echo ""
if command -v claude >/dev/null 2>&1; then
    # claude-plugins-official is built-in; add explicitly for first-run safety
    claude plugin marketplace add anthropics/claude-plugins-official --scope user || true
    claude plugin marketplace add DietrichGebert/ponytail --scope user || true
    for plugin in \
        gopls-lsp@claude-plugins-official \
        clangd-lsp@claude-plugins-official \
        pyright-lsp@claude-plugins-official \
        security-guidance@claude-plugins-official \
        context7@claude-plugins-official \
        github@claude-plugins-official \
        ponytail@ponytail; do
        echo "  - $plugin"
        claude plugin install "$plugin" --scope user || warn "failed to install $plugin"
    done
    success "Plugin installation attempted."
else
    warn "claude CLI not found in PATH — skipping plugin install."
    echo "Run the plugin install commands manually once 'claude' is available."
fi

# Register the git MCP server (user scope, all projects). ~/.claude.json is
# stateful and can't be symlinked, so register idempotently via the CLI. The
# server itself lives at the symlinked ~/.claude/mcp/git-mcp/server.py.
echo ""
echo "Registering git MCP server (user scope)..."
if command -v claude >/dev/null 2>&1; then
    if claude mcp get git >/dev/null 2>&1; then
        echo "  - already registered, skipping"
    else
        claude mcp add --scope user git -- bash -c 'uv run $HOME/.claude/mcp/git-mcp/server.py' \
            && success "  - registered" || warn "failed to register git MCP server"
    fi
else
    warn "claude CLI not found — skipping git MCP registration."
fi

echo ""
echo "============================================"
success "SUCCESS: All symbolic links created!"
echo "============================================"
echo ""
echo "Claude Code will now use configuration from:"
echo "$REPO_DIR"
