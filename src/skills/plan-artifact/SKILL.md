---
name: plan-artifact
description: Keep an implementation plan as one Artifact page that grows through the planning session. Use when grilling runs toward a plan to implement (`/grill-me давай составим план для …`, `/grill-with-docs`), or the user asks to plan before coding — «давай составим план», «спланируем», "let's plan", "make a plan for".
---

# Plan as an Artifact page

The page is the plan: one URL for the whole session, a reader's first screen shows what changes and why in plain words, everything under «Подробно» is for checking and executing the work. A cold session handed the link must be able to execute it.

Grilling that stress-tests an idea with nothing to implement gets no page.

## 1. Create the page at once

Copy [`template.html`](template.html) to the scratchpad as `plan-<slug>.html`, keep its CSS and section order, and fill what is already known: title, summary, meta chips, «Что изменится», the «Было» diagram, and every question you are about to ask as a line in «Ещё не решено». Publish it with `icon: "plan"` before the first round of questions. That file path stays the page's source for the session, so every republish lands on the same URL.

## 2. Grow it after every round

After each round of answers, before asking the next round:

- Each answered question leaves «Ещё не решено» and becomes a row in «Решения». When the user explained their choice, their reason goes into «Почему», in their terms; otherwise write the reason the decision rests on.
- Rework the top half, the diagrams and the steps to match the decisions.
- Republish the same file.

A fork discovered while drafting (a library behaves differently, a step turns out to need a choice) goes to the user as a grilling question and onto «Ещё не решено». The page carries only decisions the user made.

Comments on the page arrive as corrections: read them with `ArtifactComments`, apply them, republish, answer in the terminal.

## 3. Hand it over

The plan is final when «Ещё не решено» is empty and removed. Post the link in the terminal and ask for approval there; implementation starts on the user's go-ahead phrase. If plan mode is on, call `ExitPlanMode` with the link and two lines of substance.

During implementation, republish only when a decision or a step changes, so the page stays true for a session that picks it up later.

From another session, update by `url`: read the page with `Artifact` `action: "read"`, edit the saved file, publish it with that `url`.

## Page rules

Top half — readable without the code. Service and product names are fine; file paths, types and function names belong under «Подробно».

- **Header**: a two-to-four-word name as `<title>` and `h1`, a 2–3 sentence summary of what works differently afterwards and why, meta chips for repo(s), branch and ticket.
- **«Что изменится»**: 3–7 lines, one change each, tagged `add` / `edit` / `del`.
- **Diagram**: «Было» and «Станет» of the mechanism the change touches, required whenever data flow, links between components, states or structure change. Load `artifact-diagramming` first, draw inline SVG with the template's `.dia` classes (`add` / `del` on nodes, edges, arrowheads and labels), label the edges, give each SVG its own marker ids. Flows wider than two columns go in `.dias.stack` with the SVG inside `.scroll` and class `wide`.
- **«Нужно от тебя»**, only when the user must act by hand (a deposit to test a withdrawal flow, a login): each action and the step it blocks; the step itself carries the `ждёт тебя` tag.
- **«Ещё не решено»**, only while questions are open.

Under «Подробно»:

- **Шаги**: one per commit or MR, in order. Each has a title, a one-line why, files tagged `add` / `edit` / `del` / `keep`, and a checkable «Готово, когда». Evidence (`file:line`, library source) goes in the step's `details.ev`.
- **Решения**: grouped by topic with `tr.grp` rows, final state only — no question numbers, no history of reversals.
- **Что может сломаться**: each risk paired with the existing signal that shows it.
- **Проверка на стенде** and **Не трогаем**.

The page states the plan and nothing about its own status. A section with nothing to say is removed. A list past ten items is split under subheadings with the count in each. The page is written in the conversation's language.
