---
description: Review the MRs of a Jira task OR a set of GitLab MR URLs in a background Workflow (6 lenses + summarizer)
argument-hint: <JIRA-KEY | task URL | GitLab MR URL(s)>
---

The `review-task-fetch.sh` hook has already fetched the MRs (diff + clone) on `UserPromptSubmit`. The input is either a Jira key/URL (MRs pulled from Jira) or one or more direct GitLab MR URLs (Jira skipped entirely). Just launch the review:

1. Find the hook's `WORK=<path>` in the latest `review-task:` line.
   - A `review-task:` line WITHOUT `WORK=` means it failed (no MRs / no credentials) — show it verbatim and STOP.
   - No `review-task:` line at all → read the path from `~/.claude/.review-task-last`. Empty/missing → report that fetch didn't run and STOP.
2. Copy the workflow script into this session's scratchpad, then run it from there — `Workflow` accepts a `scriptPath` only inside the cwd or the scratchpad, and `~/.claude/workflow-scripts` is outside both in most repos:
   - `Bash cp "$HOME/.claude/workflow-scripts/review-task.js" "<scratchpad>/review-task.js"`, where `<scratchpad>` is the scratchpad directory named in this session's environment.
   - `Workflow({ scriptPath: "<scratchpad>/review-task.js", args: "<WORK>" })` with the `WORK` from step 1. Nothing else.
3. Output the Workflow's report verbatim — no summary, no edits. Do NOT act on the findings (no fixes, no edits, no follow-up) — just show the report to the user and stop.
