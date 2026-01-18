---
description: Create a commit with ticket ID from branch name
allowed-tools: AskUserQuestion, Read, Skill, Bash(git commit:*)
---

# Commit Command

Create a git commit.

Invoke the commit message skill using Skill tool. Use the generated commit message from this skill.

```bash
git commit -m "MESSAGE"
```

Report success with the commit message used.
