# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo version-controls Claude Code config and deploys it via symlinks (`setup.sh` creates them, `cleanup.sh` removes them), then reconciles plugins and MCP servers against the declarations in `src/`. It has no build/test/lint pipeline — it's bash + markdown + json. Check work with `bash -n` on the scripts and `python3 -m json.tool` on the JSON.

## Editing rules

- Edit the canonical files under `src/`. The `~/.claude/*` paths are symlinks back into `src/`, so editing either edits the same file — but new config files must be created under `src/` to be version-controlled.
- Editing an existing symlinked file takes effect immediately. Re-run `./setup.sh` **only** after adding a new top-level entry to the symlink list in `setup.sh` (e.g. a new `agents/` or top-level file).
- `setup.sh`, `cleanup.sh`, `sync.sh` and `src/lib/` are repo tooling and are not symlinked anywhere.

## Nothing private goes in here

The repo is public. No secret, token, internal domain, absolute `/Users/...` path or Mac-only binary path belongs in a versioned file — those live in `~/.claude/.env` (outside git) and reach the config as `${VAR}` in `src/mcp/servers.json`, as `$HOME` in `settings.json` hook commands, or through the `claude` shell wrapper described in the README. `.githooks/pre-commit` blocks a commit that would publish a value from `~/.claude/.env`.

Two machine-specific binaries are the deliberate exception, and both are called directly rather than through a tolerant wrapper:

- **`rtk`** (`PreToolUse` on Bash) — a hard dependency: `setup.sh` refuses to run without it. Called bare, through `PATH`, so it works wherever it is installed.
- **`adrafinil`** (10 hooks) — called by the absolute path `/Applications/Adrafinil.app/Contents/Helpers/adrafinil`, which is the form `adrafinil install-hooks` writes and looks for. A wrapper or a bare `PATH` call makes adrafinil stop recognising its own hooks and duplicate them on the next `install-hooks`. It is macOS-only; `setup.sh` warns when it is missing, and on Linux those hooks fail loudly without blocking anything.

## Sources of truth

- Plugins and marketplaces: `enabledPlugins` / `extraKnownMarketplaces` in `src/settings.json`. Claude Code maintains both keys itself on install/uninstall; `src/lib/reconcile-plugins.sh` replays them. Claude Code never installs from `enabledPlugins` on its own.
- User-scope MCP servers: `src/mcp/servers.json`, replayed by `src/lib/reconcile-mcp.sh`. Live state lives in `~/.claude.json`, which is stateful and cannot be symlinked; `./sync.sh export-mcp` pulls it back into the repo with secrets folded into `${VAR}`.
- Skills that ship as a plain git repo rather than a plugin: `src/skills/external.json`. The clone itself is gitignored.
- Everything registers at **user** scope. `claude mcp add-json` defaults to `local` — always pass `--scope user`.

## Two different CLAUDE.md files — don't confuse them

- Root `CLAUDE.md` (this file): instructions for working **on this repo**.
- `src/CLAUDE.md`: the global user instructions that get deployed to `~/.claude/CLAUDE.md` and apply to **every** project. Edit this when changing global Claude behavior, not repo behavior.
