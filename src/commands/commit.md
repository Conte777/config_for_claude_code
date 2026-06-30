---
description: Deterministic git commit (staged → haiku msg → validate → commit)
argument-hint: [all] [force]
disable-model-invocation: true
---

Эта команда обрабатывается детерминированным хуком `git-hook.sh` на
`UserPromptSubmit` (он блокирует промпт). Если ты видишь этот текст — хук не
сработал; ничего не делай и сообщи об этом.
