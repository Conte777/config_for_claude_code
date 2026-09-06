# Claude Code configuration

Version-controlled Claude Code configuration, deployed by symlinking `src/` into
`~/.claude`. `setup.sh` also reconciles the machine's marketplaces, plugins and
user-scope MCP servers against the declarations in this repo, so a fresh clone plus
one secrets file gives a working machine.

No secret and no private host is stored here. Everything machine- or account-specific
lives in `~/.claude/.env`, which is outside git.

## Layout

```
src/
  settings.json        Claude Code settings; also the source of truth for
                       enabledPlugins and extraKnownMarketplaces
  CLAUDE.md            global instructions, deployed to ~/.claude/CLAUDE.md
  .env.example         variable names for ~/.claude/.env — names only, no values
  statusline.sh        status line
  keybindings.json     key bindings
  agents/              review-* subagents used by the review-task workflow
  commands/            /branch, /commit, /review-task
  hooks/               hook scripts referenced from settings.json
  mcp/
    servers.json       user-scope MCP servers, with ${VAR} placeholders
    git-mcp/           local git MCP server
    grafana-mcp.sh     Grafana MCP launcher
  skills/
    mr/                own skill
    external.json      skills distributed as a plain git repo rather than a plugin;
                       setup.sh clones each into skills/.external/<name> (sparse)
                       and symlinks skills/<name> at the skill dir inside it —
                       both the clone and the symlink are gitignored
  workflows/           review-task workflow script
  lib/                 reconcilers used by setup.sh
setup.sh               deploy / re-sync
cleanup.sh             remove the symlinks
sync.sh                pull live state back into the repo
.githooks/pre-commit   blocks commits containing a value from ~/.claude/.env
docs/                  notes that outlived the files they came from
```

`src/lib/`, `setup.sh`, `cleanup.sh` and `sync.sh` are repo tooling and are not
symlinked anywhere.

## Install

Supported: macOS and Linux. On Windows use WSL2 — the same bash scripts run unchanged.

1. **Dependencies.** `setup.sh` requires `git`, `jq`, `node`, `npx`, `uv`, `gh` and
   `python3`, and stops with a list if any is missing. It never installs anything:
   guessing a package manager and reaching for `sudo` breaks the machine, not just the
   config. `claude` itself and `officecli` are checked too, but only warned about.

2. **Clone**, anywhere you like:

   ```bash
   git clone git@github.com:Conte777/config_for_claude_code.git
   cd config_for_claude_code
   ```

3. **Secrets.**

   ```bash
   cp src/.env.example ~/.claude/.env
   chmod 600 ~/.claude/.env
   $EDITOR ~/.claude/.env
   ```

   Leave a variable empty and the MCP servers that need it are skipped, with a message
   saying which variable was missing. Everything else still gets set up.

4. **Shell wrapper.** `settings.json` does not expand `${VAR}`, so proxy and credential
   variables have to reach the process from the shell. Add to `~/.zshrc` (or `~/.bashrc`):

   ```zsh
   claude() { set -a; . ~/.claude/.env; set +a; command claude "$@"; }
   ```

5. **Deploy.**

   ```bash
   ./setup.sh
   ```

6. **Verify from outside the repo** — a project-scope registration would look right from
   inside it and be invisible everywhere else:

   ```bash
   cd /tmp && claude plugin list --json && claude mcp list
   ```

## What `setup.sh` does

1. Checks dependencies and stops if any required one is missing.
2. Sources `~/.claude/.env`.
3. Symlinks `settings.json`, `CLAUDE.md`, `statusline.sh`, `keybindings.json`,
   `commands/`, `agents/`, `skills/`, `hooks/`, `mcp/` and `workflows/` into `~/.claude`.
   A correct symlink is left alone; anything else in the way is moved to
   `~/.claude/.pre-setup-backup/` first. If that directory already holds files from an
   earlier run, setup stops and asks you to deal with them.
4. Points the repo's `core.hooksPath` at `.githooks`.
5. Reconciles marketplaces and plugins against `settings.json`
   (`src/lib/reconcile-plugins.sh`).
6. Clones or updates the skills declared in `src/skills/external.json`.
7. Reconciles user-scope MCP servers against `src/mcp/servers.json`
   (`src/lib/reconcile-mcp.sh`).

It is idempotent — run it again after every pull. Everything is registered at **user**
scope, so it works from any directory.

## Day-to-day

**Editing config.** Edit the files under `src/`. `~/.claude/*` are symlinks back into
`src/`, so a change takes effect immediately. Re-run `./setup.sh` only after adding a new
top-level entry to the link list in `setup.sh`.

**Plugins.** Install and remove them normally (`/plugin`, or `claude plugin install`).
Claude Code maintains `enabledPlugins` and `extraKnownMarketplaces` inside
`src/settings.json` itself, so the change is version-controlled the moment you make it.
`setup.sh` replays that list on other machines: Claude Code enables plugins from
`enabledPlugins` but never installs them.

Three states: `true` — installed and enabled; `false` — installed and disabled; key
absent — uninstalled. `setup.sh` removes anything installed at user scope that
`settings.json` no longer lists.

**MCP servers.** Add or change them with `claude mcp add-json <name> <json> --scope user`
(the `--scope user` matters: the default is `local`, which hides the server in whatever
directory you happened to be in), then fold the change back into the repo:

```bash
./sync.sh export-mcp
```

That rewrites `src/mcp/servers.json` from `~/.claude.json`, substituting values found in
`~/.claude/.env` back into `${VAR}` placeholders. It refuses to write the file if anything
that still looks like a token survives.

`$HOME` and other shell variables in a server's `command`/`args` are left literal — only
`${VAR}` is substituted, and only from the environment.

**Secret guard.** `.githooks/pre-commit` blocks a commit whose staged content contains any
value from `~/.claude/.env`, any line from the optional `~/.claude/.secret-patterns`, or a
known token prefix. Both sources are outside git, so the hook itself names nothing. Add
extra strings — a bare internal domain, say — to `~/.claude/.secret-patterns`, one per
line. `git commit --no-verify` bypasses it.

**Proxy.** Configured outside the repo, in `~/.claude/.env`, and reaches Claude Code
through the shell wrapper.

**Machine-specific hook binaries.** `rtk` is a hard dependency — `setup.sh` stops
without it. `adrafinil` is macOS-only and is called by the absolute path its own
`install-hooks` writes, so that it keeps recognising its hooks; `setup.sh` only warns
when it is absent, and elsewhere those hooks fail without blocking anything.

## Uninstall

```bash
./cleanup.sh
```

Removes the symlinks (including ones earlier versions of `setup.sh` created). Installed
plugins, registered MCP servers, `~/.claude/.env` and `~/.claude` itself are left alone.

## License

Personal configuration. Use and modify as you like.
