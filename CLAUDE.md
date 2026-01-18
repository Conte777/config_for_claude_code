# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository manages Claude Code CLI configuration files through symbolic links, enabling version control and cross-machine synchronization of Claude Code settings.

## Architecture

### Symbolic Link Strategy

The repository uses Windows symbolic links to connect the standard Claude Code configuration locations to version-controlled files in `src/`:

- `%USERPROFILE%\.claude\settings.json` → `src\settings.json`
- `%USERPROFILE%\.claude\CLAUDE.md` → `src\CLAUDE.md`
- `%USERPROFILE%\.claude\statusline.ps1` → `src\statusline.ps1`
- `%USERPROFILE%\.claude\commands` → `src\commands`
- `%USERPROFILE%\.claude\skills` → `src\skills`

This allows editing files in `src/` while Claude Code reads from the standard locations.

### Directory Structure

```
src/
├── .mcp.json          # MCP server configurations
├── settings.json      # Claude Code settings
├── CLAUDE.md          # Global Claude Code instructions
├── statusline.ps1     # PowerShell script for custom status line
├── agents/            # Custom subagents for Task tool
│   └── code-reviewer.md
├── commands/          # Custom slash commands
│   ├── branch.md      # Create branch from ticket ID
│   ├── commit.md      # Commit with ticket ID from branch
│   └── fix-ci.md      # CI/CD trace analysis
└── skills/            # Skill packages (see Skills section)
    ├── code-review/
    ├── commit-msg/
    ├── command-development/
    ├── go-microservice/
    ├── hook-development/
    ├── mcp-integration/
    └── skill-development/
```

## Setup and Cleanup

### Installation

Run `setup.bat` as administrator to create symbolic links:
- Requires administrator privileges (Windows symlink requirement)
- Checks for conflicts with existing files/directories
- Creates `%USERPROFILE%\.claude` if needed
- Validates source files before creating links
- Rolls back on error

### Uninstallation

Run `cleanup.bat` as administrator to remove symbolic links:
- Prompts for confirmation before removal
- Removes only symbolic links (preserves `.claude` directory)

## Configuration Components

### MCP Servers (.mcp.json)

- **context7**: HTTP-based documentation server (requires API key from https://context7.com)
- **sequential-thinking**: NPX-based advanced reasoning tool

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

### Settings (settings.json)

Key configurations:
- **Tool permissions**: Allow/deny/ask lists for tools and bash commands
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Default model**: Opus
- **Default mode**: Plan mode
- **Status line**: Custom PowerShell script
- **Plugins**: code-simplifier, gopls-lsp

### Global Instructions (src/CLAUDE.md)

User-specific instructions for all Claude Code sessions:
- **Language preferences**: Russian for communication, English for code artifacts
- **Context7 integration**: Fetch library docs before writing code
- **Code style**: Self-documenting code, minimal comments
- **Terminal**: PowerShell syntax with bash-compatible aliases

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

### Status Line (src/statusline.ps1)

PowerShell script providing real-time status: `directory | branch !? | Model`
- Receives JSON via stdin with model, workspace, session data
- Color coded: cyan (directory), green (branch), magenta (model)

## Validation

- Symbolic links require administrator privileges on Windows
- Verify symlinks: `dir %USERPROFILE%\.claude /AL`
