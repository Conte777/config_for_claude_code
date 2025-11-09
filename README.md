# Claude Code Configuration Repository

This repository contains configuration files for Claude Code CLI, managed through symbolic links for easy version control and synchronization.

## Structure

```
config_for_claude_code/
├── src/
│   ├── .mcp.json                    # MCP server configurations
│   ├── settings.json                # Claude Code settings
│   ├── CLAUDE.md                    # Global instructions
│   ├── commands/                    # Custom slash commands
│   │   ├── commit-msg.md
│   │   └── fix-trace.md
│   └── agents/                      # Custom subagents
│       ├── code-reviewer/           # Code review agent
│       │   ├── code-reviewer.md
│       │   ├── language-specific/
│       │   │   ├── go-review.md
│       │   │   ├── java-review.md
│       │   │   ├── python-review.md
│       │   │   └── typescript-review.md
│       │   └── review-checklists/
│       │       ├── performance-checklist.md
│       │       ├── quality-checklist.md
│       │       └── security-checklist.md
│       └── code-writer/             # Code writing agent
│           ├── code-writer.md
│           ├── design-patterns/
│           │   ├── common-principles.md
│           │   ├── gof-patterns.md
│           │   └── solid-principles.md
│           ├── language-guides/
│           │   ├── go-guide.md
│           │   ├── java-guide.md
│           │   └── python-guide.md
│           └── libraries/
│               ├── go-libraries.md
│               ├── java-libraries.md
│               └── python-libraries.md
├── setup.bat                         # Installation script
├── cleanup.bat                       # Uninstallation script
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

1. Create a new directory in `src/agents/` with the agent name
2. Create the main agent file (e.g., `agent-name.md`) with YAML frontmatter
3. Optionally add supporting materials in subdirectories
4. The agent will be automatically available in Claude Code

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

MCP (Model Context Protocol) server configurations containing:
- **context7**: HTTP-based documentation server (requires API key)
- **sequential-thinking**: Advanced reasoning tool via NPX
- **vscode-mcp**: VS Code integration for LSP diagnostics and code navigation

### settings.json

Claude Code CLI settings including:
- Tool permissions (allow/deny lists)
- Always-thinking mode configuration
- Security restrictions for sensitive files
- Automatic approvals for web search, file operations, git commands

### CLAUDE.md

Global instructions that apply to all Claude Code sessions. Contains:
- Language preferences (Russian for communication, English for documentation)
- Context7 integration guidelines
- VSCode diagnostics usage instructions
- Code navigation with LSP symbols
- Code style preferences

### Custom Commands

Located in `src/commands/`:
- **commit-msg.md**: Generate Conventional Commits messages for staged changes
- **fix-trace.md**: Analyze and fix errors from VS Code diagnostics

### Custom Agents

Located in `src/agents/`:

#### code-reviewer
Expert code reviewer specializing in code quality, security vulnerabilities, and best practices across multiple languages (Go, Java, Python, TypeScript, Rust).

**Features:**
- VSCode LSP integration for type analysis and diagnostics
- Context7 integration for automatic library documentation fetching
- Progressive disclosure with language-specific review patterns
- Severity-ranked issue reporting (CRITICAL/HIGH/MEDIUM/LOW)
- Comprehensive checklists for security, performance, and quality

**Supporting Materials:**
- Language-specific review guides (Go, Java, Python, TypeScript)
- Specialized checklists (performance, quality, security)

#### code-writer
Expert code writer specializing in Go, Java, and Python with deep knowledge of best practices, design patterns, and idiomatic language features.

**Features:**
- Automatic language detection
- Progressive loading of style guides and conventions
- SOLID principles and GoF design patterns
- Context7 integration for up-to-date library documentation
- Clean architecture and self-documenting code principles
- Security-focused (prevents SQL injection, XSS, OWASP Top 10)

**Supporting Materials:**
- Language-specific guides (Go, Java, Python)
- Design pattern references (SOLID, GoF, common principles)
- Library-specific documentation (Go, Java, Python libraries)

## License

This is a personal configuration repository. Feel free to use and modify as needed.

## Contributing

Since this is a personal configuration repository, it's not accepting contributions. However, feel free to fork it and create your own version!
