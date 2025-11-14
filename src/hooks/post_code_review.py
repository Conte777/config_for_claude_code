#!/usr/bin/env python3
"""
PostToolUse hook for Task tool (code-reviewer invocation)

Detects when code-reviewer sub-agent has been invoked and injects a prompt
to trigger the final summary report workflow stage.

This hook is the third stage of the automated workflow pipeline:
- Stage 1→2: Handled by post_todowrite.py (when todos complete)
- Stage 2→3: Handled by post_diagnostics.py (when diagnostics clean)
- Stage 3→4: Detects code-reviewer invocation → injects final report prompt

Triggers on:
- Task: When Task tool is used with subagent_type="code-reviewer"

Validates that:
1. The Task is specifically for code-reviewer sub-agent
2. Workflow is active (post_todowrite injection in transcript history)
"""

import json
import sys
import os
from typing import Dict


def parse_transcript_recent(transcript_path: str, lookback: int = 200) -> list[Dict]:
    """
    Parse JSONL transcript and return recent entries.

    Args:
        transcript_path: Absolute path to the session transcript file
        lookback: Number of recent entries to return

    Returns:
        List of recent entries
    """
    if not os.path.exists(transcript_path):
        return []

    recent_entries = []

    try:
        with open(transcript_path, 'r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue

                try:
                    entry = json.loads(line.strip())
                    recent_entries.append(entry)
                except (json.JSONDecodeError, KeyError):
                    continue

    except (IOError, OSError) as e:
        print(f"Warning: Failed to read transcript: {e}", file=sys.stderr)
        return []

    return recent_entries[-lookback:]


def is_code_reviewer_task(tool_input: Dict) -> bool:
    """
    Check if this Task tool invocation is for code-reviewer.

    Args:
        tool_input: Tool input from Task tool

    Returns:
        True if subagent_type is "code-reviewer"
    """
    return tool_input.get("subagent_type") == "code-reviewer"


def is_workflow_active(recent_entries: list[Dict]) -> bool:
    """
    Check if workflow was initiated by post_todowrite.

    Scans recent entries for TodoWrite tool usage, which indicates
    that post_todowrite hook injected a prompt.

    Args:
        recent_entries: List of recent entries from transcript

    Returns:
        True if TodoWrite found in recent history
    """
    for entry in recent_entries:
        if entry.get("type") == "tool_use" and entry.get("name") == "TodoWrite":
            return True

    return False


def create_final_report_prompt() -> str:
    """
    Create the prompt to inject for final summary report generation.

    Returns:
        Formatted prompt string
    """
    return """Code review has been completed!

According to the CLAUDE.md workflow, you must now generate the Final Summary Report.

**Report Requirements** (800-1200 tokens):

Generate a comprehensive report that aggregates:
- Summary of all completed tasks from todo list
- Aggregated list of all files created/modified
- Consolidated implementation details
- Comprehensive review results from code-reviewer (what was found, recommendations)
- Overall status and recommendations

**Report Structure**:

Follow the template from CLAUDE.md (lines 137-224):

```markdown
# Отчёт о результатах реализации

## Детали реализации

### Изменённые/созданные файлы
- [file.ext](path) - Description

### Применённые паттерны проектирования
- **Pattern Name**: Where and why used

### Ключевые решения при реализации
- Decision 1
- Decision 2

---

## Результаты проверки кода

### Итого
- **Критических**: X (must fix before merge)
- **Высокий приоритет**: Y (fix before deployment)
- **Рекомендации**: Z improvements

### Критические проблемы
1. [Issue name]
   Detailed explanation...
   Затронутые файлы:
   - file.ext:line

### Высокий приоритет
1. [Issue name]
   Explanation...

### Рекомендации
1. [Improvement suggestion]
   Why and how...

### Положительные наблюдения
- ✅ Good practice 1
- ✅ Good practice 2

---

## Следующие шаги
- What to do next
- Deployment considerations

---

## Общая оценка

2-3 sentence summary of code quality, readiness for use, and important warnings.
```

**Report Format**:
- Use Russian language for the report
- Include file references as markdown links with line numbers
- Provide clear status indicator:
  - ✅ **Ready for Use**: No critical/high issues, implementation complete
  - ⚠️ **Requires Fixes**: High-priority issues found, fix before deployment
  - ❌ **Critical Issues Found**: Security/critical errors, must fix urgently
- Focus on actionable information and clear priorities
- Include function signatures for implemented code

Generate the final summary report now."""


def main():
    """
    Main hook execution logic.

    Hook Input (via stdin):
        {
            "tool_name": "Task",
            "tool_input": {
                "subagent_type": "code-reviewer",
                ...
            },
            "tool_response": {...},
            "transcript_path": "/path/to/transcript.jsonl",
            "session_id": "...",
            "cwd": "...",
            "permission_mode": "..."
        }

    Hook Output (stdout if triggering):
        {
            "decision": "block",
            "reason": "Detailed prompt for final report generation",
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "stage": "code_review_to_final_report",
                "subagentType": "code-reviewer"
            }
        }

    Hook Output (implicit if not triggering):
        Exits with code 0, no stdout output
    """
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    if tool_name != "Task":
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})
    if not is_code_reviewer_task(tool_input):
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    transcript_path = input_data.get("transcript_path", "")
    if not transcript_path:
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    recent_entries = parse_transcript_recent(transcript_path)

    if not is_workflow_active(recent_entries):
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    response = {
        "decision": "block",
        "reason": create_final_report_prompt(),
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "stage": "code_review_to_final_report",
            "subagentType": "code-reviewer",
        }
    }

    print(json.dumps(response, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
