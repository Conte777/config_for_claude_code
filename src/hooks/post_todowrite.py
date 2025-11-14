#!/usr/bin/env python3
"""
PostToolUse hook for TodoWrite tool

Detects when all tasks in the todo list are marked as completed and injects
a prompt to trigger the diagnostics workflow stage.

This hook is the first stage of the automated workflow pipeline:
- Stage 1→2: Detects todo list completion → injects diagnostics prompt
- Stage 2→3: Handled by post_diagnostics.py (when diagnostics are clean)
- Stage 3→4: Handled by post_code_review.py (when code review completes)
- Stage 4: Final report generation (manual or automated)

This hook is triggered after every TodoWrite tool execution and analyzes
the session transcript to determine the current state of all tasks.
"""

import json
import sys
import os
from typing import List, Dict, Optional


def parse_transcript(transcript_path: str) -> Optional[List[Dict]]:
    """
    Parse JSONL transcript to find the latest TodoWrite tool invocation.

    Args:
        transcript_path: Absolute path to the session transcript file

    Returns:
        List of todos from the most recent TodoWrite call, or None if not found
    """
    if not os.path.exists(transcript_path):
        return None

    last_todos = None

    try:
        with open(transcript_path, 'r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue

                try:
                    entry = json.loads(line.strip())

                    # Look for TodoWrite tool usage entries
                    if entry.get("type") == "tool_use":
                        if entry.get("name") == "TodoWrite":
                            tool_input = entry.get("input", {})
                            todos = tool_input.get("todos", [])
                            if todos:
                                last_todos = todos

                except (json.JSONDecodeError, KeyError):
                    continue

    except (IOError, OSError) as e:
        print(f"Warning: Failed to read transcript: {e}", file=sys.stderr)
        return None

    return last_todos


def all_tasks_completed(todos: List[Dict]) -> bool:
    """
    Check if all tasks in the todo list are marked as completed.

    Args:
        todos: List of todo items with status field

    Returns:
        True if all tasks have status="completed", False otherwise
    """
    if not todos:
        return False

    return all(todo.get("status") == "completed" for todo in todos)


def create_injection_prompt() -> str:
    """
    Create the prompt text to inject into Claude Code dialog.

    Returns:
        Formatted prompt string with workflow instructions
    """
    return """All tasks from the todo list have been completed!

According to the CLAUDE.md workflow, you must now perform project-wide diagnostics:

**Diagnostics Check Strategy**:

1. **Primary Method**: Use `mcp__vscode-mcp__get_diagnostics` with workspace path
2. **Fallback Methods** (if MCP unavailable):
   - TypeScript: `npx tsc --noEmit && npx eslint .`
   - Python: `python -m mypy . && python -m pylint .`
   - Go: `go build ./... && go vet ./...`
   - Java: `mvn compile && mvn checkstyle:check`

**Fixing Process**:
1. Check diagnostics for entire project
2. Fix ERROR (severity 0), WARNING (severity 1), INFO/HINT (severity 2-3)
3. Re-check diagnostics after fixes
4. Repeat until all diagnostics are clean

Proceed with diagnostics check now. The next workflow steps will be triggered automatically after diagnostics are clean."""


def main():
    """Main hook execution logic."""
    try:
        # Read hook input from stdin
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input from stdin: {e}", file=sys.stderr)
        sys.exit(1)

    # Verify this is a TodoWrite event
    tool_name = input_data.get("tool_name", "")
    if tool_name != "TodoWrite":
        # Not our concern, exit silently
        sys.exit(0)

    # Get transcript path from hook context
    transcript_path = input_data.get("transcript_path", "")
    if not transcript_path:
        # No transcript available, cannot analyze
        sys.exit(0)

    # Parse transcript to get latest todo state
    todos = parse_transcript(transcript_path)

    # Check if all tasks are completed
    if todos and all_tasks_completed(todos):
        # All tasks completed - inject prompt into dialog
        response = {
            "decision": "block",
            "reason": create_injection_prompt(),
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": f"Todo list completion detected: {len(todos)} tasks all marked as completed.",
                "completedTasks": len(todos)
            }
        }
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    # Not all tasks completed yet, or no todos found - allow normal flow
    response = {}
    print(json.dumps(response, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
