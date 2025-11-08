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
├── .mcp.json          # MCP server configurations
├── settings.json      # Claude Code settings (permissions, features)
├── CLAUDE.md         # Global Claude Code instructions
├── commands/         # Custom slash commands (.md files)
└── agents/           # Custom subagents directory (currently empty)
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

- **context7**: HTTP-based documentation server (requires API key)
- **sequential-thinking**: NPX-based advanced reasoning tool
- **vscode-mcp**: VSCode integration for LSP information, diagnostics, and code references

### Custom Commands (src/commands/)

- **commit-msg.md**: Generates Conventional Commits messages for staged changes
- **fix-trace.md**: Analyzes and fixes errors from VS Code diagnostics

### Settings (settings.json)

Defines:
- **Tool permissions**: Allow/deny lists for tools and bash commands
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Security restrictions**: Blocks access to secrets, .env files
- **Automatic approvals**: Pre-approved tools include web search/fetch, read operations, git commands, and MCP integrations

### Global Instructions (src/CLAUDE.md)

User-specific instructions applied to all Claude Code sessions:
- **Language preferences**: Russian for user communication, English for documentation
- **Context7 integration**: Automatic library documentation fetching
- **VSCode diagnostics**: Automatic error detection and fixing after code edits
- **Code navigation**: LSP-based symbol lookup and reference finding
- **Code style**: Minimal comments (only when code clarity requires it)

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

## Command Development

Custom slash commands are Markdown files with YAML frontmatter:

```markdown
---
description: Command description shown in /help
model: sonnet|opus|haiku (optional)
allowed-tools: Tool1, Tool2 (optional)
---

Command prompt goes here...
```

When creating new commands in `src/commands/`, they become available immediately as `/command-name`.

## MCP Configuration Notes

### Context7 Setup
Edit `src/.mcp.json` and replace `{API_KEY}` with your Context7 API key from https://context7.com

### VSCode MCP
Enabled tools: `get_symbol_lsp_info`, `get_diagnostics`, `get_references`, `health_check`

## Validation Notes

- Symbolic links require administrator privileges on Windows
- `setup.bat` will not overwrite existing files - manual removal required
- Verify symlinks with: `dir %USERPROFILE%\.claude /AL`
