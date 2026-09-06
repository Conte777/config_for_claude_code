#!/usr/bin/env bash
# Deploys this repo onto the machine: symlinks into ~/.claude, then reconciles
# marketplaces, plugins, external skills and user-scope MCP servers against the
# declarations in src/. Idempotent — re-run it after every pull.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}$*${NC}"; }
warn()    { echo -e "${YELLOW}WARNING: $*${NC}"; }
error()   { echo -e "${RED}ERROR: $*${NC}" >&2; }
success() { echo -e "${GREEN}$*${NC}"; }

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$REPO_DIR/src"
TARGET_DIR="$HOME/.claude"
BACKUP_DIR="$TARGET_DIR/.pre-setup-backup"
ENV_FILE="$TARGET_DIR/.env"

# ~/.claude/<name> -> src/<name>. Everything else under ~/.claude is runtime
# state Claude Code owns (plugins/, projects/, history) and stays out of git.
LINKS=(
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
)

echo "============================================"
info "Claude Code Configuration Setup"
echo "============================================"
echo "Repository: $REPO_DIR"
echo ""

# --- 1. dependencies ----------------------------------------------------------
# Report and stop. Installing them would mean guessing a package manager and
# using sudo, which breaks the machine rather than just the config.
echo "Checking dependencies..."
missing=()
for c in git jq node npx uv gh python3 rtk; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
    error "missing required commands: ${missing[*]}"
    echo "Install them and re-run. Nothing has been changed." >&2
    exit 1
fi
command -v claude >/dev/null 2>&1 \
    || warn "claude CLI not in PATH — symlinks will be created, but plugins and MCP servers will not."
command -v officecli >/dev/null 2>&1 \
    || warn "officecli not in PATH — the officecli skill needs it: curl -fsSL https://d.officecli.ai/install.sh | bash"
# macOS-only, and settings.json calls it by the absolute path adrafinil itself
# writes — anything else and `adrafinil install-hooks` stops recognising its own
# hooks and duplicates them. On Linux those hooks just fail loudly and harmlessly.
command -v adrafinil >/dev/null 2>&1 \
    || warn "adrafinil not found — its 10 hooks in settings.json will error on every run (macOS-only tool)."
success "  all required commands present"

# --- 2. secrets ---------------------------------------------------------------
echo ""
if [ -f "$ENV_FILE" ]; then
    if [ "$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE" 2>/dev/null)" != 600 ]; then
        warn "$ENV_FILE is not mode 600 — fixing"
        chmod 600 "$ENV_FILE"
    fi
    set -a; . "$ENV_FILE"; set +a
    info "Loaded $ENV_FILE"
else
    warn "$ENV_FILE not found — MCP servers that need credentials will be skipped."
    echo "  cp $SRC_DIR/.env.example $ENV_FILE && chmod 600 $ENV_FILE, fill it in, re-run."
fi

# --- 3. symlinks --------------------------------------------------------------
echo ""
echo "Linking into $TARGET_DIR..."
mkdir -p "$TARGET_DIR"

backup() { # <path> — move an unexpected file/link out of the way, once
    if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        error "$BACKUP_DIR already holds files from an earlier run."
        echo "Review and empty it, then re-run setup.sh." >&2
        exit 1
    fi
    mkdir -p "$BACKUP_DIR"
    mv "$1" "$BACKUP_DIR/$(basename "$1")"
    warn "  moved existing $(basename "$1") to $BACKUP_DIR/"
}

for name in "${LINKS[@]}"; do
    src="$SRC_DIR/$name"
    dst="$TARGET_DIR/$name"
    if [ ! -e "$src" ]; then
        error "source missing: $src"
        exit 1
    fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        continue
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then backup "$dst"; fi
    ln -s "$src" "$dst"
    info "  + $name"
done

# autogit reads ~/.config/autogit/config.json, outside ~/.claude, so it gets its
# own link instead of an entry in LINKS.
autogit_src="$SRC_DIR/autogit/config.json"
autogit_dst="$HOME/.config/autogit/config.json"
mkdir -p "$(dirname "$autogit_dst")"
if [ ! -L "$autogit_dst" ] || [ "$(readlink "$autogit_dst")" != "$autogit_src" ]; then
    if [ -e "$autogit_dst" ] || [ -L "$autogit_dst" ]; then backup "$autogit_dst"; fi
    ln -s "$autogit_src" "$autogit_dst"
    info "  + ~/.config/autogit/config.json"
fi
success "  symlinks in place"

# --- 4. repo git hooks --------------------------------------------------------
echo ""
git -C "$REPO_DIR" config core.hooksPath .githooks
success "core.hooksPath = .githooks (secret guard on commit)"

# --- 5. marketplaces and plugins ----------------------------------------------
echo ""
echo "Reconciling marketplaces and plugins..."
bash "$SRC_DIR/lib/reconcile-plugins.sh" "$SRC_DIR/settings.json"
success "  plugins match settings.json"

# --- 6. external skills -------------------------------------------------------
# Skills distributed as a plain git repo rather than a plugin. The clone lands in
# src/skills/.external/<name>; src/skills/<name> is a relative symlink to the skill
# directory inside it, so it shows up under the already-symlinked ~/.claude/skills.
# Both are gitignored.
echo ""
EXTERNAL="$SRC_DIR/skills/external.json"
if [ -f "$EXTERNAL" ]; then
    echo "Syncing external skills..."
    while IFS=$'\t' read -r name repo ref path; do
        [ -n "$name" ] || continue
        stage="$SRC_DIR/skills/.external/$name"
        link="$SRC_DIR/skills/$name"

        if [ -d "$stage/.git" ]; then
            info "  ~ $name"
            git -C "$stage" fetch --depth 1 origin "$ref" --quiet \
                && git -C "$stage" reset --hard FETCH_HEAD --quiet \
                || { warn "failed to update skill $name"; continue; }
        else
            info "  + $name ($repo@$ref)"
            rm -rf "$stage"
            mkdir -p "$(dirname "$stage")"
            # blobless + sparse: the repo around the skill can be far larger than
            # the skill itself
            if [ -n "$path" ]; then
                git clone --depth 1 --branch "$ref" --filter=blob:none --sparse \
                    --quiet "$repo" "$stage" \
                    && git -C "$stage" sparse-checkout set "$path" \
                    || { warn "failed to clone skill $name"; continue; }
            else
                git clone --depth 1 --branch "$ref" --quiet "$repo" "$stage" \
                    || { warn "failed to clone skill $name"; continue; }
            fi
        fi

        if [ ! -d "$stage/$path" ]; then
            warn "skill $name: '$path' not found in $repo — skipping"
            continue
        fi

        want=".external/$name${path:+/$path}"
        if [ "$(readlink "$link" 2>/dev/null)" != "$want" ]; then
            rm -rf "$link"
            ln -s "$want" "$link"
        fi
    done < <(jq -r '
        to_entries[]
        | .key + "\t" + .value.repo + "\t" + (.value.ref // "main") + "\t" + (.value.path // "")
    ' "$EXTERNAL")
    success "  external skills synced"
fi

# --- 7. MCP servers -----------------------------------------------------------
echo ""
echo "Reconciling user-scope MCP servers..."
bash "$SRC_DIR/lib/reconcile-mcp.sh" "$SRC_DIR/mcp/servers.json"
success "  MCP servers match servers.json"

echo ""
echo "============================================"
success "Setup complete."
echo "============================================"
echo "Verify from outside the repo:  cd /tmp && claude plugin list --json && claude mcp list"
