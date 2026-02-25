# Claude Code Configuration Repository

This repository contains configuration files for Claude Code CLI, managed through symbolic links for easy version control and synchronization.

## Structure

```
config_for_claude_code/
├── src/
│   ├── .mcp.json                    # MCP server configurations
│   ├── settings.json                # Claude Code settings
│   ├── CLAUDE.md                    # Global instructions
│   ├── statusline.sh                # Custom status line script (bash)
│   ├── agents/                      # Custom subagents for Task tool
│   │   ├── code-reviewer.md         # Code review agent
│   │   └── kubectl-log-fetcher.md   # Kubernetes log fetcher agent
│   ├── hooks/                       # Hook scripts for tool events
│   │   ├── lint-go.sh               # Go linter on file edit
│   │   └── lint-project.sh          # Project-wide lint before code review
│   ├── commands/                    # Custom slash commands
│   │   ├── branch.md                # Create branch from ticket ID
│   │   ├── commit.md                # Commit with ticket ID
│   │   └── fix-ci.md                # CI/CD trace analysis
│   └── skills/                      # Skill packages
│       ├── code-review/             # Code review (Go, Java, Python)
│       ├── commit-msg/              # Commit message generation
│       ├── command-development/     # Slash command creation guide
│       ├── go-microservice/         # Go microservice development
│       ├── hook-development/        # Claude Code hooks creation
│       ├── mcp-integration/         # MCP server integration
│       └── skill-development/       # Skill creation guide
├── setup.sh                         # Installation script
├── cleanup.sh                       # Uninstallation script
├── CLAUDE.md                        # Project-specific instructions
├── README.md
└── .gitignore
```

## Installation

### Prerequisites

- macOS (or Linux)
- Claude Code CLI installed

### Steps

1. Clone or download this repository to your desired location
2. Run the setup script:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```
3. Follow the on-screen instructions

The script will create symbolic links from the standard Claude Code configuration locations to the files in this repository:

- `~/.claude/settings.json` → `src/settings.json`
- `~/.claude/CLAUDE.md` → `src/CLAUDE.md`
- `~/.claude/statusline.sh` → `src/statusline.sh`
- `~/.claude/commands` → `src/commands`
- `~/.claude/agents` → `src/agents`
- `~/.claude/skills` → `src/skills`
- `~/.claude/hooks` → `src/hooks`

### Important Notes

- The setup script will **not** overwrite existing files. If configuration files already exist, you'll need to back them up or remove them manually before running the script.
- After installation, any changes made through Claude Code will be automatically saved to this repository.
- `.mcp.json` is **not** symlinked by `setup.sh` — it must be placed manually or configured per-project.

## Uninstallation

To remove the symbolic links and restore your system to its original state:

```bash
./cleanup.sh
```

Confirm the removal when prompted. The script will remove all symbolic links created by `setup.sh`. The `.claude` directory itself will not be removed automatically.

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
3. Run `./setup.sh`

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

### Files Already Exist

If you see warnings about existing files:

1. Backup your current configuration
2. Manually remove the existing files/directories listed in the warning
3. Run `./setup.sh` again

### Symbolic Links Not Working

Verify that symbolic links were created correctly:

```bash
ls -la ~/.claude/
```

Symlinks are indicated by `->` pointing to the source files in this repository.

## Configuration Files

### .mcp.json

MCP (Model Context Protocol) server configurations:
- **context7**: HTTP-based documentation server (requires API key from https://context7.com)
- **sequential-thinking**: Advanced reasoning tool via NPX
- **db-mcp-server**: Stdio-based database access tool (query, schema, performance analysis)

### settings.json

Claude Code CLI settings:
- **Tool permissions**: Allow/deny/ask lists for tools and bash commands
- **Always-thinking mode**: Enabled for enhanced reasoning
- **Default model**: Opus (haiku overridden to sonnet via env)
- **Default mode**: Plan mode
- **Language**: Russian
- **Sandbox**: Enabled with `autoAllowBashIfSandboxed`
- **Status line**: Custom bash script
- **Plugins**: gopls-lsp, document-skills

### CLAUDE.md (src/)

Global instructions for all Claude Code sessions:
- Language preferences (Russian for communication, English for code artifacts)
- Context7 integration guidelines
- Code style preferences (self-documenting code)

### Custom Commands

Located in `src/commands/`:
- **branch.md**: Create and switch to a new git branch from Jira ticket ID
- **commit.md**: Create a commit using the commit-msg skill for message generation
- **fix-ci.md**: Analyze CI/CD trace output to identify failing stages and provide fixing plans

### Hooks

Located in `src/hooks/`:
- **lint-go.sh**: PostToolUse hook (Edit/Write) — runs `golangci-lint` on modified `.go` files
- **lint-project.sh**: SubagentStart hook (code-reviewer) — runs `golangci-lint run ./...` before code review

### Custom Agents

Located in `src/agents/`:
- **code-reviewer.md**: Code review agent with language-specific checks (Go, Java, Python)
- **kubectl-log-fetcher.md**: Agent for retrieving and filtering Kubernetes pod logs

### Skills

Located in `src/skills/`. Each skill is a directory containing:
- `SKILL.md` — main file with YAML frontmatter and instructions
- `references/` — detailed documentation (loaded as needed)
- `examples/` — working code examples
- `scripts/` — utility scripts

**Available skills:**

| Skill | Description |
|-------|-------------|
| **code-review** | Code review for Go, Java, Python with framework-specific checks (Uber FX, Spring, FastAPI) |
| **commit-msg** | Generates Conventional Commits messages with ticket ID extraction from branch name |
| **command-development** | Guidance for creating Claude Code slash commands with YAML frontmatter |
| **go-microservice** | Go microservice development with Uber FX, DDD patterns, internal packages |
| **hook-development** | Creating Claude Code hooks (PreToolUse, PostToolUse, Stop, etc.) |
| **mcp-integration** | Integrating MCP servers (stdio, SSE, HTTP) into plugins |
| **skill-development** | Creating new skills with progressive disclosure pattern |

## License

This is a personal configuration repository. Feel free to use and modify as needed.
