# Global Instructions

## Language

Always respond to the user in Russian language for all interactions and explanations.

However, when creating or editing internal documentation and instructions (CLAUDE.md files, agent prompts in src/agents/, slash command prompts in src/commands/, and any other configuration files), ALWAYS use English exclusively.

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

## Code Style

### Comments

Write comments in code only when:
- Variable or function names don't fully reflect their purpose
- Code behavior is not obvious from the context

In all other cases, avoid writing comments. Prefer self-documenting code with clear, descriptive names for variables, functions, and classes.

## Code Writing Workflow

### Sequential Task Execution

**Process**:

1. **Fetch Documentation**: Use Context7 MCP before writing code to understand best practices
2. **Implement Solution**: Write or edit code using Write/Edit tools
3. **Mark Task Completed**: Update task status to `completed` using TodoWrite
4. **Move to Next Task**: Return to step 1 until all tasks are completed

### After All Tasks Completed

**Diagnostics Check Strategy**:

1. **Primary Method**: Use `mcp__vscode-mcp__get_diagnostics` with workspace path to check entire project
2. **Fallback Methods** (if MCP unavailable):
   - **TypeScript**: `npx tsc --noEmit && npx eslint .`
   - **Python**: `python -m mypy . && python -m pylint .`
   - **Go**: `go build ./... && go vet ./...`
   - **Java**: `mvn compile && mvn checkstyle:check`

**Fixing Process**:

1. Check diagnostics for entire project
2. For each file with issues:
   - Fix ERROR (severity 0), WARNING (severity 1), INFO/HINT (severity 2-3)
   - Use Edit tool to apply fixes
   - Re-check that file's diagnostics
3. Repeat until all diagnostics are clean
4. Run final project-wide diagnostics check

### Consolidated Code Review After All Tasks

**CRITICAL RULE**: After ALL tasks from the todo list are completed AND all diagnostics have been checked/fixed via MCP or fallback methods, the `code-reviewer` sub-agent MUST be invoked ONCE to perform a comprehensive review of ALL changes made during task execution.

**Timing**: Code-reviewer is invoked AFTER:
- All tasks in the todo list have been executed and completed
- All tasks are marked as `completed`
- "After All Tasks Completed" section has been fully executed:
  - Project-wide diagnostics check performed (via `mcp__vscode-mcp__get_diagnostics` or fallback methods)
  - All diagnostics issues have been fixed
  - Final project-wide diagnostics check passed
- NOT after each individual task (this is the key difference from previous workflow)

**Pre-Review Preparation**:

Before invoking code-reviewer, you MUST consolidate information from all completed tasks:

1. **Aggregate Modified Files**: Collect all files that were created or modified across ALL tasks
2. **Aggregate Modified Components**: List all functions, classes, methods, and modules changed across ALL tasks
3. **Summarize Scope**: Provide overall scope description covering all changes (e.g., "New feature implementation with authentication, database layer, and API endpoints")
4. **Context Collection**: Gather any important decisions or trade-offs made during implementation

**Invoking code-reviewer**:

Call the Task tool with subagent_type="code-reviewer" and provide:
- **Complete file list**: All files created/modified during task execution
- **Complete component list**: All functions, classes, and code blocks changed during task execution
- **Consolidated scope**: Overall description of what was implemented across all tasks
- **Cross-task context**: How different tasks relate to each other, dependencies between changes
- **Skip diagnostics**: Explicitly instruct the code-reviewer to NOT run diagnostic tools (mcp__vscode-mcp__get_diagnostics, tsc --noEmit, eslint, go vet, etc.) since comprehensive diagnostics were already performed and all issues fixed in the previous step

**Review Focus**:

The code-reviewer will analyze:
- ALL changes comprehensively as a cohesive unit
- Consistency across changes made by different task executions
- Integration points between different parts of implementation
- Overall code quality, security, and best practices across the entire implementation

**Never skip code review** - always invoke the code-reviewer agent after all code-writing tasks are complete.

### Final Summary Report

**CRITICAL RULE**: After ALL tasks are completed and `code-reviewer` completes the consolidated review, you MUST generate a comprehensive final summary report that aggregates results from all task executions and code review.

This report is the primary deliverable to the user and should provide a clear, actionable overview of the entire multi-task implementation and review process.

**When to Generate**:
- After ALL tasks from todo list have been completed through direct task execution
- After project-wide VSCode diagnostics have been checked and fixed
- After consolidated code-reviewer finishes reviewing all changes together
- Before presenting final results to the user
- As the concluding step of the entire code writing workflow

**What to Include**:
- Summary of all completed tasks from the todo list
- Aggregated list of all files created/modified across all tasks
- Consolidated implementation details from all task executions
- Comprehensive review results from code-reviewer (covering all changes)
- Overall status and recommendations

**Report Structure** (target: 800-1200 tokens):

```markdown
# Отчёт о результатах реализации

## Детали реализации

### Изменённые/созданные файлы
- [file1.go](path/to/file1.go) - Описание назначения/функционала
- [file2.java](path/to/file2.java) - Описание назначения/функционала

### Применённые паттерны проектирования
- **Название паттерна**: Где и почему он использован

### Ключевые решения при реализации
- [Важное решение 1]
- [Важное решение 2]

---

## Результаты проверки кода

### Итого

- **Критических**: X проблем (необходимо исправить перед слиянием/развёртыванием)
- **Высокий приоритет**: Y проблем (следует исправить перед развёртыванием)
- **Рекомендации**: Z предложений по улучшению

### Критические проблемы

1. [Название или описание проблемы]
   Подробное объяснение проблемы. Описание воздействия и рисков.
   Предложенные способы исправления или смягчения проблемы.

   Затронутые файлы:
   - path/to/file1.go:123
   - path/to/file2.java:45-67

2. [Вторая критическая проблема]
   Описание и детали.

   Затронутые файлы:
   - path/to/file3.py:89

### Высокий приоритет

1. [Описание проблемы]
   Объяснение и описание воздействия.

   Затронутые файлы:
   - path/to/file4.ts:234
   - path/to/file5.go:145

2. [Вторая проблема высокого приоритета]
   Детали и объяснение.

   Затронутые файлы:
   - path/to/file6.java:12

### Рекомендации

1. [Предложение по улучшению]
   Почему это важно и как это улучшить.

   Затронутые файлы:
   - path/to/file7.py:56
   - path/to/file8.py:67

2. [Вторая рекомендация]
   Детали рекомендации.

   Затронутые файлы:
   - path/to/file9.ts:123

### Положительные наблюдения
- ✅ [Хорошая практика 1]
- ✅ [Хорошая практика 2]

---

## Следующие шаги
- [Что нужно сделать дальше]
- [Соображения по развёртыванию, если применимо]

---

## Общая оценка

2-3 предложения с итоговой оценкой качества кода, готовности к использованию и важных предупреждений или рекомендаций.

```

**Report Requirements**:

- ✅ **Consolidated View**: Combine implementation and review results into one cohesive report
- ✅ **Clear Status**: User should immediately understand if the code is ready for use
- ✅ **Specific Actions**: All issues should have clear prioritized action items
- ✅ **File References**: Use markdown links with line numbers for convenient navigation
- ✅ **Balanced View**: Include both identified issues and positive observations
- ✅ **Concise Format**: Target volume of 800-1200 tokens, without unnecessary repetition
- ✅ **Severity Awareness**: Prioritize highlighting critical/high severity issues
- ✅ **Function-Level Details**: Include signatures of all implemented/modified functions
- ✅ **Visual Clarity**: Use sections, headings, and formatting for easy scanning

**Token Optimization**:
- Reference files through links instead of repeating full paths
- Generalize patterns instead of listing every detail
- Group related issues
- Focus on actionable information
- Include function signatures for implemented code

**Status Indicator Examples**:
- ✅ **Ready for Use**: No critical/high severity issues, implementation complete, tests passing
- ⚠️ **Requires Fixes**: High-priority issues found, fix before deployment
- ❌ **Critical Issues Found**: Security vulnerabilities or critical errors, must fix urgently
