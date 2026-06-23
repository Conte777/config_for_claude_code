---
description: Ревью всех MR Jira-задачи фоновым Workflow (6 линз + summarizer)
argument-hint: <JIRA-KEY>
---

`/review-task <KEY>`: данные (MR → diff → клон) уже собрал детерминированный
fetch-хук `review-task-fetch.sh` на `UserPromptSubmit`. Твоя задача — только запустить ревью.

1. Найди в текущем контексте строку от хука: `review-task: ... WORK=<path> ...`.
   - Если строка `review-task:` есть, но **без** `WORK=` (ошибка/нет MR/нет учёток) —
     покажи её пользователю дословно и **остановись**.
   - Если строки нет вовсе — прочитай путь из `~/.claude/.review-task-last` (Read tool).
     Файл пуст/отсутствует → сообщи, что fetch не отработал, и остановись.
2. Запусти ревью одним действием (больше ничего не делай):
   `Workflow({ scriptPath: "<$HOME>/.claude/workflows/review-task.js", args: "<WORK>" })`
   подставив реальный `$HOME` (например `/Users/conte`) и путь `WORK` из шага 1.
3. Workflow вернёт готовый отчёт — выведи его **дословно**, без пересказа и сокращений.
