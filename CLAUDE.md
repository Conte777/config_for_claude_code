# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository manages Claude Code CLI configuration files through symbolic links, enabling version control and cross-machine synchronization of Claude Code settings.

## Architecture

### Symbolic Link Strategy

The repository uses symbolic links to connect the standard Claude Code configuration locations to version-controlled files in `src/`:

- `~/.claude/settings.json` → `src/settings.json`
- `~/.claude/CLAUDE.md` → `src/CLAUDE.md`
- `~/.claude/statusline.sh` → `src/statusline.sh`
- `~/.claude/commands` → `src/commands`
- `~/.claude/skills` → `src/skills`
- `~/.claude/hooks` → `src/hooks`
- `~/.claude/plugins` → `src/plugins`
- `~/.claude/keybindings.json` → `src/keybindings.json`
- `~/.claude/rules` → `src/rules`

This allows editing files in `src/` while Claude Code reads from the standard locations.

### Directory Structure

```
src/
├── .mcp.json          # MCP server configurations
├── settings.json      # Claude Code settings
├── CLAUDE.md          # Global Claude Code instructions
├── statusline.sh      # Bash script for custom status line
├── keybindings.json   # Custom keyboard shortcuts
├── plugins/           # Plugin configs (cache/data gitignored)
│   ├── .gitignore
│   ├── installed_plugins.json
│   ├── blocklist.json
│   └── known_marketplaces.json
├── agents/            # Custom subagents for Task tool
│   ├── code-reviewer.md
│   └── kubectl-log-fetcher.md
├── hooks/             # Hook scripts for tool events
│   ├── format-and-lint.sh
│   └── lint-project.sh
├── commands/          # Custom slash commands
│   ├── branch.md      # Create branch from ticket ID
│   ├── commit.md      # Commit with ticket ID from branch
│   └── fix-ci.md      # CI/CD trace analysis
├── rules/             # Language-specific coding rules (shared across skills)
│   ├── common.md
│   ├── golang/
│   │   ├── patterns.md
│   │   ├── uber-fx.md
│   │   └── clean-architecture.md
│   ├── java/
│   │   ├── patterns.md
│   │   └── spring.md
│   └── python/
│       ├── patterns.md
│       └── fastapi.md
└── skills/            # Skill packages (see Skills section)
    ├── check-di/
    ├── code-review/
    ├── commit-msg/
    ├── command-development/
    ├── go-microservice/
    ├── hook-development/
    ├── mcp-integration/
    ├── skill-development/
    └── verify/
```

## Setup and Cleanup

### Installation

Run `setup.sh` to create symbolic links:
- Checks for conflicts with existing files/directories
- Creates `~/.claude` if needed
- Validates source files before creating links
- Rolls back on error

### Uninstallation

Run `cleanup.sh` to remove symbolic links:
- Prompts for confirmation before removal
- Removes only symbolic links (preserves `.claude` directory)

## Configuration Components

### MCP Servers (.mcp.json)

> Note: `.mcp.json` lives in `src/` for reference but is **not** symlinked by `setup.sh`. It must be placed manually or configured per-project.

- **context7**: HTTP-based documentation server (requires API key from https://context7.com)
- **sequential-thinking**: NPX-based advanced reasoning tool
- **db-view-mcp**: Stdio-based database access tool via npx @conte777/db-view-mcp (query, schema, performance analysis)

### Rules (src/rules/)

Language-specific coding rules shared across skills. Contains patterns, anti-patterns, and best practices organized by language:
- **common.md** — Security, race conditions, resource management, error handling, performance
- **golang/** — Go patterns, Uber FX patterns, Clean Architecture/DDD layers
- **java/** — Java patterns, Spring Framework patterns
- **python/** — Python patterns, FastAPI patterns

Referenced by `code-review` and `go-microservice` skills via relative paths.

### Custom Commands (src/commands/)

- **branch.md**: Creates git branch from Jira ticket ID
- **commit.md**: Creates commit using commit-msg skill for message generation
- **fix-ci.md**: Analyzes CI/CD trace output to identify failing stages and provide fixing plans

### Skills (src/skills/)

Skills are modular packages extending Claude's capabilities with specialized knowledge and workflows. Each skill has:
- `SKILL.md` — main file with YAML frontmatter (name, description) and instructions
- `references/` — detailed documentation loaded as needed
- `examples/` — working code examples
- `scripts/` — utility scripts

**Available skills:**
- **code-review**: Code review for Go, Java, Python with framework-specific checks (Uber FX, Spring, FastAPI)
- **commit-msg**: Generates Conventional Commits messages with ticket ID extraction
- **command-development**: Guidance for creating Claude Code slash commands
- **go-microservice**: Go microservice development with Uber FX, DDD patterns
- **hook-development**: Creating Claude Code hooks (PreToolUse, PostToolUse, etc.)
- **mcp-integration**: Integrating MCP servers into plugins
- **skill-development**: Creating new skills for Claude Code plugins
- **verify**: Multi-language project verification (tests + static analysis + DI validation for Go/Python/Java)
- **check-di**: Uber FX dependency injection graph validation for Go projects

### Hooks (src/hooks/)

- **format-and-lint.sh**: PostToolUse hook triggered on Edit/Write — runs language-specific formatters then linters in a single script to guarantee execution order (`gofmt` + `golangci-lint` for `.go`, `uv run ruff format` + `uv run ruff check` for `.py`, `google-java-format` for `.java`), finds the nearest project root automatically
- **lint-project.sh**: SubagentStart hook triggered on code-reviewer — runs project-wide linting before code review (`golangci-lint` for Go projects with `go.mod`, `ruff` for Python projects with `pyproject.toml`/`ruff.toml`)
- **service-context.sh**: SessionStart hook triggered on startup — auto-detects microservice in `friday_releases/` monorepo, parses `env.dev.yaml` config, and injects context about gRPC deps, RabbitMQ exchanges, Kafka topics, TLS clients, exchange neighbors, and migrations

### Custom Agents (src/agents/)

Markdown files defining specialized subagents for the Task tool:
- **code-reviewer.md**: Code review agent with language-specific checks (Go, Java, Python)
- **kubectl-log-fetcher.md**: Agent for retrieving and filtering Kubernetes pod logs

### Settings (settings.json)

Key configurations:
- **Tool permissions**: Allow/deny/ask lists for tools and bash commands
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Default model**: Opus (haiku overridden to sonnet via `ANTHROPIC_DEFAULT_HAIKU_MODEL` env)
- **Default mode**: Plan mode
- **Language**: Russian
- **Sandbox**: Enabled with `autoAllowBashIfSandboxed`
- **Status line**: Custom bash script
- **Plugins**: gopls-lsp, document-skills

### Global Instructions (src/CLAUDE.md)

User-specific instructions for all Claude Code sessions:
- **Language preferences**: Russian for communication, English for code artifacts
- **Context7 integration**: Fetch library docs before writing code
- **Code style**: Self-documenting code, minimal comments

## Custom Development

### Slash Commands

Markdown files with YAML frontmatter in `src/commands/`:

```markdown
---
description: Command description shown in /help
model: sonnet|opus|haiku (optional)
allowed-tools: Tool1, Tool2 (optional)
argument-hint: <hint-for-arguments> (optional)
---

Command prompt...
```

### Skills

Skills are organized in `src/skills/skill-name/` directories:

```
skill-name/
├── SKILL.md           # Required: frontmatter + instructions
├── references/        # Optional: detailed docs
├── examples/          # Optional: working examples
└── scripts/           # Optional: utility scripts
```

**SKILL.md frontmatter:**
```yaml
---
name: skill-name
description: This skill should be used when the user asks to "trigger phrase 1", "trigger phrase 2"...
version: 0.1.0
---
```

Use the `skill-development` skill for guidance on creating new skills.

### Status Line (src/statusline.sh)

Bash script providing real-time status: `Model on directory branch context`
- Receives JSON via stdin with model, workspace, context_window data
- ANSI RGB colors, Nerd Font icons
- No external dependencies (JSON parsing via grep/sed)

## Validation

- Verify symlinks: `ls -la ~/.claude/`
