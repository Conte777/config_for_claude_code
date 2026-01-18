# Claude Code Configuration Repository

This repository contains configuration files for Claude Code CLI, managed through symbolic links for easy version control and synchronization.

## Structure

```
config_for_claude_code/
├── src/
│   ├── .mcp.json                    # MCP server configurations
│   ├── settings.json                # Claude Code settings
│   ├── CLAUDE.md                    # Global instructions
│   ├── statusline.ps1               # Custom status line script
│   ├── commands/                    # Custom slash commands
│   │   ├── branch.md                # Create branch from ticket ID
│   │   ├── commit.md                # Commit with ticket ID
│   │   └── fix-ci.md                # CI/CD trace analysis
│   └── skills/                      # Skill packages
│       ├── commit-msg/              # Commit message generation
│       ├── command-development/     # Slash command creation guide
│       ├── go-microservice/         # Go microservice development
│       ├── hook-development/        # Claude Code hooks creation
│       ├── mcp-integration/         # MCP server integration
│       └── skill-development/       # Skill creation guide
├── setup.bat                        # Installation script
├── cleanup.bat                      # Uninstallation script
├── CLAUDE.md                        # Project-specific instructions
├── README.md
└── .gitignore
```

## Installation

### Prerequisites

- Windows operating system
- Claude Code CLI installed
- Administrator privileges (required for creating symbolic links)

### Steps

1. Clone or download this repository to your desired location
2. Right-click on `setup.bat` and select **"Run as administrator"**
3. Follow the on-screen instructions

The script will create symbolic links from the standard Claude Code configuration locations to the files in this repository:

- `%USERPROFILE%\.claude\settings.json` → `src\settings.json`
- `%USERPROFILE%\.claude\CLAUDE.md` → `src\CLAUDE.md`
- `%USERPROFILE%\.claude\statusline.ps1` → `src\statusline.ps1`
- `%USERPROFILE%\.claude\commands` → `src\commands`
- `%USERPROFILE%\.claude\skills` → `src\skills`

### Important Notes

- The setup script will **not** overwrite existing files. If configuration files already exist, you'll need to back them up or remove them manually before running the script.
- After installation, any changes made through Claude Code will be automatically saved to this repository.

## Uninstallation

To remove the symbolic links and restore your system to its original state:

1. Right-click on `cleanup.bat` and select **"Run as administrator"**
2. Confirm the removal when prompted

The script will remove all symbolic links created by `setup.bat`. The `.claude` directory itself will not be removed automatically.

## Usage

After installation, you can:

### Edit Configuration

Simply edit the files in the `src/` directory. Changes will be immediately reflected in Claude Code since symbolic links are used.

### Version Control

Commit your changes to track configuration history:

```bash
git add src/
git commit -m "Update Claude configuration"
```

### Sync Across Machines

1. Push your changes to a remote repository
2. Clone the repository on another machine
3. Run `setup.bat` as administrator

### Add New Commands

1. Create a new `.md` file in `src/commands/`
2. Add YAML frontmatter with `description` field
3. The command will be automatically available in Claude Code

### Add New Skills

1. Create a new directory in `src/skills/` with the skill name
2. Create `SKILL.md` with YAML frontmatter (name, description)
3. Optionally add `references/`, `examples/`, `scripts/` subdirectories
4. The skill will be automatically available in Claude Code

## Troubleshooting

### "Access Denied" Error

Make sure you're running the `.bat` scripts as administrator. Symbolic links on Windows require elevated privileges.

### Files Already Exist

If you see warnings about existing files:

1. Backup your current configuration
2. Manually remove the existing files/directories listed in the warning
3. Run `setup.bat` again

### Symbolic Links Not Working

Verify that symbolic links were created correctly:

```cmd
dir %USERPROFILE%\.claude /AL
```

This should show symbolic links (indicated by `<SYMLINK>` or `<SYMLINKD>`).

## Configuration Files

### .mcp.json

MCP (Model Context Protocol) server configurations:
- **context7**: HTTP-based documentation server (requires API key from https://context7.com)
- **sequential-thinking**: Advanced reasoning tool via NPX

### settings.json

Claude Code CLI settings:
- **Tool permissions**: Allow/deny/ask lists for tools and bash commands
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Default model**: Opus
- **Default mode**: Plan mode
- **Status line**: Custom PowerShell script
- **Plugins**: code-simplifier, gopls-lsp

### CLAUDE.md (src/)

Global instructions for all Claude Code sessions:
- Language preferences (Russian for communication, English for code artifacts)
- Context7 integration guidelines
- Code style preferences (self-documenting code)
- Terminal command syntax (PowerShell with bash aliases)

### Custom Commands

Located in `src/commands/`:
- **branch.md**: Create and switch to a new git branch from Jira ticket ID
- **commit.md**: Create a commit using the commit-msg skill for message generation
- **fix-ci.md**: Analyze CI/CD trace output to identify failing stages and provide fixing plans

### Skills

Located in `src/skills/`. Each skill is a directory containing:
- `SKILL.md` — main file with YAML frontmatter and instructions
- `references/` — detailed documentation (loaded as needed)
- `examples/` — working code examples
- `scripts/` — utility scripts

**Available skills:**

| Skill | Description |
|-------|-------------|
| **commit-msg** | Generates Conventional Commits messages with ticket ID extraction from branch name |
| **command-development** | Guidance for creating Claude Code slash commands with YAML frontmatter |
| **go-microservice** | Go microservice development with Uber FX, DDD patterns, internal packages |
| **hook-development** | Creating Claude Code hooks (PreToolUse, PostToolUse, Stop, etc.) |
| **mcp-integration** | Integrating MCP servers (stdio, SSE, HTTP) into plugins |
| **skill-development** | Creating new skills with progressive disclosure pattern |

## License

This is a personal configuration repository. Feel free to use and modify as needed.
