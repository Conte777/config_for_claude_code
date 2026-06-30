---
description: Create branch PREFIX/slug (ticket optional, model picks feat/fix)
argument-hint: [CUS-N] [description]
disable-model-invocation: true
---

Эта команда обрабатывается детерминированным хуком `git-hook.sh` на
`UserPromptSubmit` (он блокирует промпт). Если ты видишь этот текст — хук не
сработал; ничего не делай и сообщи об этом.
