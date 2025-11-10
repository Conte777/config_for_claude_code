# Global Instructions

## Language

Always respond to the user in Russian language for all interactions and explanations.

However, when creating or editing internal documentation and instructions (CLAUDE.md files, agent prompts in src/agents/, slash command prompts in src/commands/, and any other configuration files), ALWAYS use English exclusively.

## Code Style

### Comments

Write comments in code only when:
- Variable or function names don't fully reflect their purpose
- Code behavior is not obvious from the context

In all other cases, avoid writing comments. Prefer self-documenting code with clear, descriptive names for variables, functions, and classes.

## Code Writing Workflow

### Sequential Task Execution

**CRITICAL RULE**: When a todo list exists with coding tasks, execute them SEQUENTIALLY. Each task must be fully completed, including VSCode diagnostics verification, before starting the next one.

**Prerequisite**: Todo list already exists (created before this workflow starts) with pending tasks.

**Execution Process**:

1. **Select Next Task**: Take the first task with status `pending` from the todo list
2. **Mark In Progress**: Update task status to `in_progress` using TodoWrite tool
3. **Fetch Documentation**: Use Context7 MCP to fetch library/framework documentation:
   - Use `mcp__context7__resolve-library-id` to find library ID
   - Use `mcp__context7__get-library-docs` to fetch documentation
   - Study relevant APIs, best practices, and usage patterns
4. **Implement Solution**: Write or edit code directly using Write/Edit tools:
   - Apply best practices from fetched documentation
   - Follow language-specific idioms and patterns
   - Use clear, self-documenting names for variables and functions
5. **Check VSCode Diagnostics**: Use `mcp__vscode-mcp__get_diagnostics` to check for issues:
   - Check for ERROR level (severity 0) diagnostics
   - Check for WARNING level (severity 1) diagnostics
   - Check for INFO/HINT level (severity 2-3) diagnostics
6. **Fix All Diagnostics**: If any diagnostics found, fix them immediately:
   - Use Edit tool to fix errors, warnings, and hints
   - Re-check diagnostics after each fix
   - Repeat until all diagnostics are resolved
7. **Mark Completed**: Update task status to `completed` using TodoWrite tool only after all diagnostics are clean
8. **Move to Next Task**: If more tasks remain, return to step 1

**CRITICAL**: Execute tasks SEQUENTIALLY, one at a time. Each task must be fully completed (including diagnostic checks and fixes) before moving to the next task.

**Documentation First**: Always fetch relevant documentation via Context7 MCP before writing code to ensure best practices and correct API usage.

### Consolidated Code Review After All Tasks

**CRITICAL RULE**: After ALL tasks from the todo list are completed, the `code-reviewer` sub-agent MUST be invoked ONCE to perform a comprehensive review of ALL changes made during task execution.

**Timing**: Code-reviewer is invoked AFTER:
- All tasks in the todo list have been executed and completed
- All tasks are marked as `completed`
- All VSCode diagnostics have been resolved for each task
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

**Review Focus**:

The code-reviewer will analyze:
- ALL changes comprehensively as a cohesive unit
- Consistency across changes made by different task executions
- Integration points between different parts of implementation
- Overall code quality, security, and best practices across the entire implementation

**Never skip code review** - always invoke the code-reviewer agent after all code-writing tasks are complete.

### Automatic VSCode Diagnostics Fixing

**CRITICAL RULE**: After `code-reviewer` completes the consolidated review of all changes, if VSCode diagnostics contains ERROR level issues (severity 0), automatically fix them directly, then re-run `code-reviewer` for validation.

**Context**: This step occurs AFTER:
- All tasks have been completed and VSCode diagnostics were checked for each task
- Consolidated code-reviewer has analyzed all changes together
- The consolidated review report has been received

**Trigger Condition:**
- VSCode diagnostics shows ERROR level (severity 0) diagnostics from language servers
- Sources: Go compiler errors, Java compiler errors, Python linter errors (pylint, mypy), etc.

**NOT Triggered by:**
- CRITICAL/HIGH severity issues from manual code review
- Security vulnerabilities identified by reviewer
- Logic bugs or best practices violations
- Only VSCode diagnostics warnings/info/hints (severity 1-3)

**Fixing Process:**

1. **Analyze VSCode Diagnostics from Review:**
   - Use `mcp__vscode-mcp__get_diagnostics` to check for ERROR level (severity 0) diagnostics
   - Group by file and source (Go compiler, javac, pylint, mypy, etc.)
   - Ignore warnings, info, hints (severity 1-3)

2. **Fix Errors Directly:**
   - For each ERROR level diagnostic:
     - Read the affected file if needed
     - Use Edit tool to fix the specific error
     - Use Context7 MCP to fetch documentation if needed to understand correct fix
     - Make minimal changes to resolve errors
   - Explicit constraints:
     - Fix ONLY VSCode diagnostic errors
     - Do not fix manual review issues (security, logic, etc.)
     - Do not modify unrelated code
   - Re-check diagnostics after each fix using `mcp__vscode-mcp__get_diagnostics`
   - Repeat until all ERROR level diagnostics are resolved

3. **Re-invoke code-reviewer for Validation:**
   - After all diagnostic errors are fixed:
     - Specify files modified during fixing
     - Scope: "Validation after VSCode diagnostics fixing"
     - Full review including fresh VSCode diagnostics check

4. **Proceed to Final Summary:**
   - Generate Final Summary Report regardless of second review results
   - If VSCode errors remain: include in report
   - If new errors introduced: highlight in report
   - If all resolved: mark diagnostics as clean

### Final Summary Report

**CRITICAL RULE**: After ALL tasks are completed and `code-reviewer` completes the consolidated review, you MUST generate a comprehensive final summary report that aggregates results from all task executions and code review.

This report is the primary deliverable to the user and should provide a clear, actionable overview of the entire multi-task implementation and review process.

**When to Generate**:
- After ALL tasks from todo list have been completed through direct task execution
- After consolidated code-reviewer finishes reviewing all changes together
- After automatic VSCode diagnostics fixing (if triggered)
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
# Итоговый отчет

## Краткая сводка

**Задача**: [Краткое описание запрошенной задачи]
**Статус**: ✅ Готово к использованию | ⚠️ Требует исправлений | ❌ Обнаружены критические проблемы
**Язык программирования**: [Используемый язык программирования]
**Изменено файлов**: X изменено, Y создано

[Обзор реализации и общего качества кода в 2-3 предложениях]

---

## Детали реализации

### Измененные/созданные файлы
- [file1.go](path/to/file1.go) - [назначение]
- [file2.java](path/to/file2.java) - [назначение]

### Реализованные ключевые компоненты

#### [file1.go](path/to/file1.go) - краткое описание

#### [file2.java](path/to/file2.java) - краткое описание

### Примененные паттерны проектирования
- **Название паттерна**: Почему и где был использован

### Ключевые решения при реализации
- [Важное решение 1]
- [Важное решение 2]

---

## Результаты ревью кода

### Сводка по проблемам
- **КРИТИЧЕСКИЕ**: X проблем (требуют немедленного исправления)
- **ВЫСОКИЕ**: Y проблем (следует исправить перед развертыванием)
- **СРЕДНИЕ**: Z проблем (исправить при возможности)
- **НИЗКИЕ**: W проблем (рекомендации по улучшению)

### Критические проблемы (если есть)

#### [Название проблемы] - [file.ext:line](path/to/file.ext#Lline)

**Серьезность**: КРИТИЧЕСКАЯ
**Категория**: Безопасность / Производительность / Качество

**Проблема**: [Четкое описание]
**Риск**: [Что может произойти]
**Решение**: [Конкретное исправление]

### Проблемы высокого приоритета (если есть)

[Тот же формат, что и для критических]

### Положительные наблюдения
- ✅ [Хорошая практика 1]
- ✅ [Хорошая практика 2]

---

## Действия

### Немедленные действия (Критические/Высокий приоритет)
1. [ ] Исправить [конкретную проблему] в [file.ext:line](path/to/file.ext#Lline)
2. [ ] Устранить [конкретную проблему] в [file.ext:line](path/to/file.ext#Lline)

### Рекомендуемые улучшения (Средний/Низкий приоритет)
1. [ ] Рассмотреть [предложение по улучшению]
2. [ ] Проверить [конкретный аспект]

### Следующие шаги
- [Что пользователю делать дальше]
- [Рекомендации по тестированию]
- [Соображения по развертыванию, если применимо]

---

## Общая оценка

[2-3 предложения с итоговой оценкой качества кода, готовности к использованию и важных предостережений или рекомендаций]

**Рекомендация**: [Одобрить к использованию / Сначала исправить критические проблемы / Требуются серьезные доработки]
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
