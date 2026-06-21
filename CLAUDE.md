# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repo version-controls Claude Code config and deploys it via symlinks (`setup.sh` creates them, `cleanup.sh` removes them). It has no build/test/lint pipeline — it's bash + markdown + json.

## Editing rules

- Edit the canonical files under `src/`. The `~/.claude/*` paths are symlinks back into `src/`, so editing either edits the same file — but new config files must be created under `src/` to be version-controlled.
- Editing an existing symlinked file takes effect immediately. Re-run `./setup.sh` **only** after adding a new top-level entry to the symlink list in `setup.sh` (e.g. a new `agents/` or top-level file).
- `src/.mcp.json` is **not** symlinked by `setup.sh` — it's reference only. Changes there don't take effect until placed/configured manually per-project.

## Two different CLAUDE.md files — don't confuse them

- Root `CLAUDE.md` (this file): instructions for working **on this repo**.
- `src/CLAUDE.md`: the global user instructions that get deployed to `~/.claude/CLAUDE.md` and apply to **every** project. Edit this when changing global Claude behavior, not repo behavior.

## Skills

Skills live in `src/skills/<name>/SKILL.md` with `name` / `description` frontmatter. Optional `references/`, `examples/`, `scripts/` subdirs are loaded on demand.
