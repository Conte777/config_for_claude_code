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
- `%USERPROFILE%\.claude\agents` → `src\agents`

This allows editing files in `src/` while Claude Code reads from the standard locations.

### Directory Structure

```
src/
├── .mcp.json          # MCP server configurations
├── settings.json      # Claude Code settings (permissions, model, status line)
├── CLAUDE.md          # Global Claude Code instructions
├── statusline.ps1     # PowerShell script for custom status line
├── commands/          # Custom slash commands (.md files)
│   ├── fix-ci.md      # CI/CD trace analysis and error fixing
│   └── fix-trace.md   # VS Code diagnostics error fixing
└── agents/            # Custom subagents
    └── code-reviewer.md  # Multi-language code review agent
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

- **fix-ci.md**: Analyzes CI/CD trace output to identify failing stages, determine root causes, and provide actionable fixing plans
- **fix-trace.md**: Analyzes and fixes errors from VS Code diagnostics

### Custom Agents (src/agents/)

- **code-reviewer.md**: Expert code reviewer for quality assurance across multiple languages (Go, Java, Python, TypeScript, Rust, C/C++). Reviews for logical errors, race conditions, security vulnerabilities, and language-specific conventions. Uses Context7 for library docs and LSP for code analysis.

### Settings (settings.json)

Key configurations:
- **Tool permissions**: Allow/deny lists for tools and bash commands
- **Security restrictions**: Blocks access to secrets, .env files
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Default model**: Opus
- **Status line**: Custom PowerShell script
- **Plugins**: gopls-lsp enabled

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

### Agents

Markdown files with YAML frontmatter in `src/agents/`:

```markdown
---
name: agent-name
description: Agent description and invocation examples
tools: Tool1, Tool2, Tool3
model: sonnet|opus|haiku (optional)
color: red|green|blue (optional)
---

Agent prompt and instructions...
```

### Status Line (src/statusline.ps1)

PowerShell script providing real-time status: `directory | branch !? | Model`
- Receives JSON via stdin with model, workspace, session data
- Color coded: cyan (directory), green (branch), magenta (model)

### Hooks

Hook configuration is supported in `settings.json` but no hooks are currently active. To add hooks:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "ToolName",
        "hooks": [{ "type": "command", "command": "script.py" }]
      }
    ]
  }
}
```

## Validation

- Symbolic links require administrator privileges on Windows
- Verify symlinks: `dir %USERPROFILE%\.claude /AL`
