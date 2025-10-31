# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository manages Claude Code CLI configuration files through symbolic links, enabling version control and cross-machine synchronization of Claude Code settings.

## Architecture

### Symbolic Link Strategy

The repository uses Windows symbolic links to connect the standard Claude Code configuration locations to version-controlled files in `src/`:

- `%USERPROFILE%\.claude\settings.json` → `src\settings.json`
- `%USERPROFILE%\.claude\CLAUDE.md` → `src\CLAUDE.md`
- `%USERPROFILE%\.claude\commands` → `src\commands`
- `%USERPROFILE%\.claude\agents` → `src\agents`

This allows editing files in `src/` while Claude Code reads from the standard locations.

### Directory Structure

```
src/
├── .mcp.json          # MCP server configurations (Context7, sequential-thinking)
├── settings.json      # Claude Code settings (permissions, features)
├── CLAUDE.md         # Global Claude Code instructions
├── commands/         # Custom slash commands (.md files)
└── agents/           # Custom subagents (.md files)
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
- Reports warnings if removal fails

## Configuration Components

### MCP Servers (.mcp.json)

- **context7**: HTTP-based documentation server (requires API key placeholder)
- **sequential-thinking**: NPX-based reasoning tool

### Custom Agents (src/agents/)

Specialized subagents for automated workflows:
- **error-fixer.md**: Diagnoses and fixes terminal command errors
- **go-refactor.md**: Structured refactoring for Go code
- **go-reviewer.md**: Comprehensive Go code review
- **go-security.md**: Security vulnerability analysis for Go

### Custom Commands (src/commands/)

- **commit-msg.md**: Generates Conventional Commits messages for staged changes

### Settings (settings.json)

Defines:
- Tool permissions (allow/deny lists)
- Always-thinking mode enablement
- Security restrictions (secrets, .env files)

## Working with Configuration

### Modifying Configuration

Edit files directly in `src/` - changes apply immediately through symbolic links.

### Version Control Workflow

After modifying configuration:
```bash
git add src/
git commit -m "Update configuration"
```

### Syncing to New Machine

1. Clone repository
2. Run `setup.bat` as administrator

## Validation Notes

- Symbolic links require administrator privileges on Windows
- `setup.bat` will not overwrite existing files - manual removal required
- Verify symlinks with: `dir %USERPROFILE%\.claude /AL`
