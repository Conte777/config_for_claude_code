# Global Instructions

## Language

Always respond to the user in Russian language for all interactions and explanations.

However, when creating or editing internal documentation and instructions (CLAUDE.md files, agent prompts in src/agents/, slash command prompts in src/commands/, and any other configuration files), ALWAYS use English exclusively.

## Code Style

### Comments

**CRITICAL RULE**: Write comments in code only when:
- Variable or function names don't fully reflect their purpose
- Code behavior is not obvious from the context

In all other cases, avoid writing comments. Prefer self-documenting code with clear, descriptive names for variables, functions, and classes.


### Terminal Commands in Communication

When suggesting terminal commands to the user, always use PowerShell syntax. Prefer bash-compatible PowerShell aliases where available instead of full cmdlet names:

**Common bash-compatible aliases:**
- `ls` (Get-ChildItem)
- `cd` (Set-Location)
- `cat` (Get-Content)
- `rm` (Remove-Item)
- `cp` (Copy-Item)
- `mv` (Move-Item)
- `mkdir` (New-Item -Type Directory)
- `pwd` (Get-Location)

**Commands without direct aliases (use PowerShell equivalents):**
- `grep` → `Select-String` or `findstr`
- `find` → `Get-ChildItem -Recurse` or `ls -Recurse`
- `touch` → `New-Item` or `ni`

Use PowerShell pipes and operators for data processing. This ensures commands are concise, familiar, and work correctly on Windows systems.


## Code Writing Workflow

### Sequential Task Execution

**Process**:

1. **Fetch Documentation**: Use Context7 MCP before writing code to understand best practices
2. **Implement Solution**: Write or edit code using Write/Edit tools
3. **Mark Task Completed**: Update task status to `completed` using TodoWrite
4. **Move to Next Task**: Return to step 1 until all tasks are completed
