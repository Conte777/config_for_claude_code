---
name: review-mr
description: >-
  This skill should be used when the user asks to "review-mr",
  "проверить MR", "ревью задачи", "review merge request",
  "проверить задачу на ревью"
version: 0.1.0
hooks:
  UserPromptSubmit:
    - matcher: "review-mr"
      hooks:
        - type: command
          command: "bash $HOME/.claude/skills/review-mr/scripts/fetch-review-context.sh"
          timeout: 60
---

# Review MR Skill

Скил для автоматизации ревью задач: получение контекста из Jira, скачивание диффов из GitLab, анализ соответствия изменений задаче и запуск code review для каждого MR.

## Step 1: Parse Hook Context

В контексте уже есть `additionalContext` от UserPromptSubmit хука с данными из Jira и списком MR с путями к diff-файлам. Хук срабатывает автоматически при вызове скилла.

**Действия:**
- Найди в контексте блок с Jira-данными (title, description, comments)
- Найди список MR с путями к diff-файлам в `/tmp/`
- Если MR не найдены — спроси пользователя через AskUserQuestion, какие MR нужно проверить

## Step 2: Analyze Change Alignment

Прочитай каждый diff файл из `/tmp/` через Read tool и сопоставь изменения с описанием и требованиями Jira-задачи.

**Выведи краткий отчёт:**
- Что соответствует задаче
- Что вызывает вопросы (изменения, не связанные с задачей)
- Чего потенциально не хватает (ожидаемые изменения, отсутствующие в diff)

## Step 3: Run Code Review for Each MR

Для каждого MR **последовательно**:

1. **Setup worktree:**
   ```bash
   bash scripts/setup-worktree.sh <SOURCE_BRANCH> <TARGET_BRANCH>
   ```
   Скрипт выведет путь к worktree.

2. **Run code review:**
   Invoke Skill tool: `start-review` в контексте worktree.

3. **Cleanup worktree:**
   ```bash
   git worktree remove <WORKTREE_PATH> --force 2>/dev/null; git worktree prune
   ```

**Important:** Выполняй MR последовательно, не параллельно — каждый worktree требует отдельного контекста.

## Step 4: Final Report

Собери единый отчёт, объединяющий:
- **Анализ соответствия** (Step 2) — насколько изменения соответствуют задаче
- **Результаты code review** (Step 3) — найденные проблемы по каждому MR

Формат отчёта по каждому MR:

```
## MR !{iid}: {title}
**Branch:** {source} → {target}
**URL:** {mr_url}

### Соответствие задаче
- {alignment_notes}

### Code Review
{review_findings}
```
