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
- `%USERPROFILE%\.claude\hooks` → `src\hooks`

This allows editing files in `src/` while Claude Code reads from the standard locations.

### Directory Structure

```
src/
├── .mcp.json          # MCP server configurations
├── settings.json      # Claude Code settings (permissions, features, hooks)
├── CLAUDE.md         # Global Claude Code instructions
├── statusline.ps1    # PowerShell script for custom status line
├── commands/         # Custom slash commands (.md files)
├── agents/           # Custom subagents
│   ├── code-reviewer/    # Code review agent with language-specific checklists
│   └── code-writer/      # Code writing agent with design patterns and guides
└── hooks/            # Hooks for tool events
    └── post_todowrite.py # PostToolUse hook for TodoWrite completion
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

### Custom Agents (src/agents/)

- **code-reviewer/**: Expert code reviewer specializing in code quality, security vulnerabilities, and best practices across multiple languages (Go, Java, Python, TypeScript, Rust). Integrates with VSCode LSP for diagnostics and Context7 for library documentation. Uses progressive disclosure with language-specific review checklists (performance, security, quality).

- **code-writer/**: Expert code writer specializing in Go, Java, and Python with deep knowledge of best practices, design patterns (SOLID, GoF), and idiomatic language features. Automatically fetches library documentation via Context7 and applies progressive disclosure strategy with language-specific guides, design pattern references, and library-specific documentation.

### Hooks (src/hooks/)

Custom hooks are scripts that execute in response to tool events. Configured in `settings.json` under the `hooks` section.

- **post_todowrite.py**: PostToolUse hook for TodoWrite tool
  - **Purpose**: Automatically detects when all tasks in the todo list are completed
  - **Trigger**: After every TodoWrite tool execution
  - **Action**: Injects a prompt reminder to execute the final workflow steps:
    1. Run project-wide diagnostics (VSCode MCP or fallback methods)
    2. Fix all diagnostic issues
    3. Invoke code-reviewer sub-agent for consolidated review
    4. Generate final summary report
  - **Implementation**: Parses session transcript to analyze todo list state, uses `decision: "block"` to inject prompt into Claude Code dialog
  - **Configuration**: Defined in `settings.json` under `hooks.PostToolUse` with matcher `"TodoWrite"`

### Settings (settings.json)

Defines:
- **Tool permissions**: Allow/deny lists for tools and bash commands
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Security restrictions**: Blocks access to secrets, .env files
- **Automatic approvals**: Pre-approved tools include web search/fetch, read operations, git commands, and MCP integrations
- **Hooks**: PostToolUse hook for TodoWrite to automate workflow completion

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

## Custom Development

### Slash Commands

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

### Agents

Custom agents are specialized subagents with YAML frontmatter:

```markdown
---
name: agent-name
description: Agent description and capabilities
tools: Tool1, Tool2, Tool3
model: sonnet|opus|haiku (optional)
---

Agent prompt and instructions...
```

Agents support progressive disclosure patterns - loading reference materials (language guides, checklists, design patterns) only when needed to optimize token usage. Each agent can have supporting materials in subdirectories that are read on-demand.

### Hooks

Custom hooks are executable scripts (Python, PowerShell, Bash) that respond to tool execution events. Hooks are configured in `settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "ToolName",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"%USERPROFILE%\\.claude\\hooks\\hook_script.py\""
          }
        ]
      }
    ]
  }
}
```

**Hook Input** (via stdin as JSON):
- `tool_name`: Name of the tool that was executed
- `tool_input`: Input parameters passed to the tool
- `tool_response`: Tool execution result
- `transcript_path`: Path to session transcript (JSONL format)
- `session_id`, `cwd`, `permission_mode`: Session metadata

**Hook Output** (stdout as JSON):
- `decision: "block"` + `reason: "message"`: Injects prompt into Claude dialog (blocks until acknowledged)
- `decision: "allow"`: Continues without interruption
- Exit code 0: Success (stdout visible to user, NOT Claude)
- Exit code 2: Blocks and sends stderr to Claude as prompt

**Use Cases**:
- Workflow automation (e.g., trigger actions when tasks complete)
- Validation and enforcement (e.g., code formatting checks)
- Notifications and logging
- Auto-commit after file changes

When creating new hooks in `src/hooks/`, update `settings.json` to register them.

### Status Line (src/statusline.ps1)

Custom PowerShell script that provides real-time status information in Claude Code's status line.

**Features**:
- **Current directory**: Displays the basename of the current working directory
- **Git integration**: Shows current branch name and status indicators
  - `!` - Modified files (uncommitted changes)
  - `?` - Untracked files
- **Model display**: Shows the current Claude model name
- **ANSI colors**: Uses color coding for visual clarity (cyan for directory, green for branch, magenta for model)

**Display Format**: `directory | branch !? | Model Name`

**Configuration**:
- Defined in `settings.json` under `statusLine.command`
- Receives JSON input via stdin with model, workspace, and session data
- Updates automatically when conversation state changes (max 300ms interval)

**Customization**:
- Edit `src/statusline.ps1` to modify display format or add new information
- Changes apply immediately through symbolic link
- Supports adding custom data from JSON input (cost, duration, transcript path)

## MCP Configuration Notes

### Context7 Setup
Edit `src/.mcp.json` and replace `{API_KEY}` with your Context7 API key from https://context7.com

### VSCode MCP
Enabled tools: `get_symbol_lsp_info`, `get_diagnostics`, `get_references`, `health_check`

## Validation Notes

- Symbolic links require administrator privileges on Windows
- `setup.bat` will not overwrite existing files - manual removal required
- Verify symlinks with: `dir %USERPROFILE%\.claude /AL`
