# Claude Code Configuration Repository

This repository contains configuration files for Claude Code CLI, managed through symbolic links for easy version control and synchronization.

## Structure

```
config_for_claude_code/
├── src/
│   ├── .claude.json         # Main Claude configuration
│   ├── settings.json        # Claude Code settings
│   ├── CLAUDE.md           # Global instructions
│   ├── commands/           # Custom slash commands
│   │   └── commit-msg.md
│   └── agents/             # Custom agents
│       ├── go-refactor.md
│       ├── go-reviewer.md
│       ├── go-security.md
│       └── error-fixer.md
├── setup.bat               # Installation script
├── cleanup.bat             # Uninstallation script
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

- `%USERPROFILE%\.claude.json` → `src\.claude.json`
- `%USERPROFILE%\.claude\settings.json` → `src\settings.json`
- `%USERPROFILE%\.claude\CLAUDE.md` → `src\CLAUDE.md`
- `%USERPROFILE%\.claude\commands` → `src\commands`
- `%USERPROFILE%\.claude\agents` → `src\agents`

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
2. The command will be automatically available in Claude Code

### Add New Agents

1. Create a new `.md` file in `src/agents/`
2. The agent will be automatically available in Claude Code

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

### .claude.json

Main Claude Code configuration file containing project-specific settings and MCP server configurations.

### settings.json

Claude Code CLI settings including editor preferences, output styles, and other user preferences.

### CLAUDE.md

Global instructions that apply to all Claude Code sessions. Contains:
- Context7 integration settings
- Sequential thinking configuration
- Go code review automation
- Error fixing automation

### Custom Commands

Located in `src/commands/`:
- **commit-msg.md**: Generate conventional commit messages

### Custom Agents

Located in `src/agents/`:
- **go-refactor.md**: Structured refactoring for Go code
- **go-reviewer.md**: Comprehensive Go code review
- **go-security.md**: Security vulnerability analysis for Go
- **error-fixer.md**: Automatic error diagnosis and fixing

## License

This is a personal configuration repository. Feel free to use and modify as needed.

## Contributing

Since this is a personal configuration repository, it's not accepting contributions. However, feel free to fork it and create your own version!
