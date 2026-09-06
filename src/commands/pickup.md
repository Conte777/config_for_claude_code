---
description: Resume the interrupted work from where it stopped
disable-model-invocation: true
---

Pick the work back up. Ask nothing — the answer to "what next" is in this session already.

1. Check for work running in the background: `ListAgents`, and `TaskOutput` for any Workflow or sub-agent this session started.
   - Still running → wait for it, then continue from its result.
   - Finished → read the result and continue from it.
   - A Workflow that failed part-way → re-run it with `resumeFromRunId` set to that run's id rather than from scratch.
2. No background work → resume the last unfinished step of the main task, at the point it stopped.

Report what was still outstanding and what you did about it.
