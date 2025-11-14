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

### Automated Workflow System

This configuration uses a hook-based system to automate workflow progression through four stages:

**Workflow Stages**:

1. **Stage 1→2 (post_todowrite.py)**: When all tasks are marked as `completed`, automatically injects prompt for diagnostics check
2. **Stage 2→3 (post_diagnostics.py)**: When diagnostics are clean (0 critical issues), automatically injects prompt for code-reviewer invocation
3. **Stage 3→4 (post_code_review.py)**: When code-reviewer completes, automatically injects prompt for final summary report
4. **Stage 4**: Final report generation (follows automated prompt)

**Diagnostics Tools**:

- **Primary**: `mcp__vscode-mcp__get_diagnostics` (VSCode MCP)
- **Fallback**: Language-specific CLI tools:
  - TypeScript: `npx tsc --noEmit && npx eslint .`
  - Python: `python -m mypy . && python -m pylint .`
  - Go: `go build ./... && go vet ./...`
  - Java: `mvn compile && mvn checkstyle:check`

**Priority Levels**:

- ERROR (severity 0): Must fix before proceeding
- WARNING (severity 1): Should fix before deployment
- INFO/HINT (severity 2-3): Optional improvements

When diagnostics are clean (0 errors), the workflow automatically proceeds to code review via `post_diagnostics.py` hook injection.

### Code Review (Automated)

After diagnostics are clean, the workflow automatically triggers code review invocation via `post_diagnostics.py` hook injection.

**What to Provide to code-reviewer**:

- **Complete file list**: All files created/modified during task execution
- **Complete component list**: All functions, classes, methods changed
- **Consolidated scope**: Overall description of implementation across all tasks
- **Cross-task context**: How different tasks relate to each other, dependencies
- **Skip diagnostics flag**: Instruct to skip diagnostic tools (already performed)

**Review Focus**:

The code-reviewer analyzes:
- ALL changes comprehensively as a cohesive unit
- Consistency across all task implementations
- Integration points between components
- Code quality, security, and best practices

When code review completes, the workflow automatically proceeds to final report via `post_code_review.py` hook injection.

### Final Summary Report (Automated)

After code review completes, the workflow automatically triggers final report generation via `post_code_review.py` hook injection.

**What to Include**:

- Summary of all completed tasks from the todo list
- Aggregated list of all files created/modified
- Consolidated implementation details from all task executions
- Comprehensive review results from code-reviewer
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
