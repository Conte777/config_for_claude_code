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

### Agent Delegation for Code Tasks

**CRITICAL RULE**: ALL code writing tasks MUST ALWAYS be delegated to the `code-writer` sub-agent using the Task tool, regardless of the task source:
- Tasks requested directly by the user
- Tasks identified during plan execution
- Code modifications needed while implementing a feature
- Refactoring or code improvements

**Never write code directly** - always invoke the code-writer agent for any code generation, modification, or refactoring.

### Mandatory Code Review

**CRITICAL RULE**: After ANY code generation, modification, or refactoring task, the `code-reviewer` sub-agent MUST ALWAYS be invoked using the Task tool to validate the changes.

This applies to:
- All code written by the `code-writer` agent
- Any code modifications during plan execution
- Refactoring tasks
- Bug fixes and improvements

**Never skip code review** - always invoke the code-reviewer agent after code changes are complete, regardless of task complexity or size.

**CRITICAL RULE - Code Review Scope**: When invoking the `code-reviewer` agent, you MUST explicitly specify in the prompt:
- What files were created or modified
- What specific functions, classes, or code blocks were changed
- The scope of changes (new feature, refactoring, bug fix, etc.)

The code-reviewer agent should focus ONLY on the modified/created code, not the entire codebase. Provide clear context about what changed to enable focused and efficient review.

### Automatic VSCode Diagnostics Fixing

**CRITICAL RULE**: After `code-reviewer` completes the first review, if VSCode diagnostics contains ERROR level issues (severity 0), automatically invoke `code-writer` to fix them, then re-run `code-reviewer` for validation.

**Trigger Condition:**
- VSCode diagnostics shows ERROR level (severity 0) diagnostics from language servers
- Sources: Go compiler errors, Java compiler errors, Python linter errors (pylint, mypy), etc.

**NOT Triggered by:**
- CRITICAL/HIGH severity issues from manual code review
- Security vulnerabilities identified by reviewer
- Logic bugs or best practices violations
- Only VSCode diagnostics warnings/info/hints (severity 1-3)

**Fixing Process:**

1. **Analyze VSCode Diagnostics from First Review:**
   - Extract only ERROR level (severity 0) diagnostics
   - Group by file and source (Go compiler, javac, pylint, mypy, etc.)
   - Ignore warnings, info, hints (severity 1-3)

2. **Invoke code-writer for Fixing:**

   Prepare fixing prompt with:
   - Original task context (language, framework, implementation)
   - List of files modified in original implementation
   - **Only VSCode diagnostic errors** with:
     - File path and line number
     - Error code and source (e.g., Go: "undefined: variable", Java: "cannot find symbol", Python: "E0602: Undefined variable")
     - Error message
     - Current code snippet
   - Explicit constraints:
     - Fix ONLY VSCode diagnostic errors
     - Do not fix manual review issues (security, logic, etc.)
     - Do not modify unrelated code
     - Make minimal changes to resolve errors

3. **Re-invoke code-reviewer for Validation:**

   After code-writer completes fixes:
   - Specify files modified during fixing
   - Scope: "Validation after VSCode diagnostics fixing"
   - Full review including fresh VSCode diagnostics check

4. **Proceed to Final Summary:**
   - Generate Final Summary Report regardless of second review results
   - If VSCode errors remain: include in report
   - If new errors introduced: highlight in report
   - If all resolved: mark diagnostics as clean

### Final Summary Report

**CRITICAL RULE**: After BOTH `code-writer` and `code-reviewer` agents complete their work, you MUST generate a comprehensive final summary report that consolidates the results from both agents.

This report is the primary deliverable to the user and should provide a clear, actionable overview of the entire code implementation and review process.

**When to Generate**:
- After code-writer completes implementation AND code-reviewer finishes review
- After automatic VSCode diagnostics fixing (if triggered)
- Before presenting final results to the user
- As the concluding step of any code writing workflow

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
