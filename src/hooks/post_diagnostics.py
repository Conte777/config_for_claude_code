#!/usr/bin/env python3
"""
PostToolUse hook for diagnostics tools (get_diagnostics, Bash)

Detects when project-wide diagnostics are clean and injects a prompt to
trigger the code-reviewer workflow stage.

This hook is the second stage of the automated workflow pipeline:
- Stage 1→2: Handled by post_todowrite.py (when todos complete)
- Stage 2→3: Detects clean diagnostics → injects code-reviewer prompt
- Stage 3→4: Handled by post_code_review.py (when review completes)

Triggers on:
- mcp__vscode-mcp__get_diagnostics: VSCode MCP diagnostics check
- Bash: Language-specific diagnostic tools (tsc, eslint, mypy, go vet, etc.)

Validates that:
1. Diagnostics are clean (0 critical issues)
2. Workflow is active (post_todowrite injection in transcript)
3. Code-reviewer hasn't been called yet (prevents duplicate triggers)
"""

import json
import sys
import os
import re
from typing import Dict, Optional, Tuple


def parse_transcript_recent(transcript_path: str, lookback: int = 100) -> list[Dict]:
    """
    Parse JSONL transcript and return recent tool uses.

    Args:
        transcript_path: Absolute path to the session transcript file
        lookback: Number of recent entries to return

    Returns:
        List of recent tool use entries
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
                    if entry.get("type") == "tool_use":
                        recent_entries.append(entry)
                except (json.JSONDecodeError, KeyError):
                    continue

    except (IOError, OSError) as e:
        print(f"Warning: Failed to read transcript: {e}", file=sys.stderr)
        return []

    return recent_entries[-lookback:]


def is_diagnostics_clean_mcp(tool_response: Dict) -> bool:
    """
    Check if VSCode MCP diagnostics show no critical issues.

    Args:
        tool_response: Tool response from mcp__vscode-mcp__get_diagnostics

    Returns:
        True if no ERROR or WARNING level issues, False otherwise
    """
    diagnostics = tool_response.get("diagnostics", [])
    return not any(d.get("severity", 999) <= 1 for d in diagnostics)


def is_diagnostics_clean_bash(tool_response: Dict) -> bool:
    """
    Check if bash diagnostic command succeeded.

    Args:
        tool_response: Tool response from Bash tool

    Returns:
        True if exit code 0 and no error patterns, False otherwise
    """
    exit_code = tool_response.get("exit_code", 1)
    output = tool_response.get("output", "")

    if exit_code != 0:
        return False

    error_patterns = [
        r'\d+\s+error(s)?',
        r'ERROR:',
        r'FAILED',
        r'✖',
        r'found .* error',
        r'compilation failed',
        r'type error',
        r'mypy:.*error',
    ]

    for pattern in error_patterns:
        if re.search(pattern, output, re.IGNORECASE):
            return False

    return True


def is_workflow_active_and_code_reviewer_not_called(
    recent_entries: list[Dict]
) -> bool:
    """
    Check if workflow was initiated by post_todowrite and code-reviewer
    hasn't been called yet.

    Validates that TodoWrite appears AFTER any previous code-reviewer calls
    (indicating a new workflow cycle) to prevent cross-workflow contamination.

    Args:
        recent_entries: List of recent tool use entries from transcript

    Returns:
        True if workflow is active and code-reviewer not yet called in this cycle
    """
    last_todowrite_idx = -1
    last_code_reviewer_idx = -1

    for idx, entry in enumerate(recent_entries):
        tool_name = entry.get("name", "")
        tool_input = entry.get("input", {})

        if tool_name == "TodoWrite":
            last_todowrite_idx = idx

        if tool_name == "Task" and tool_input.get("subagent_type") == "code-reviewer":
            last_code_reviewer_idx = idx

    return last_todowrite_idx > last_code_reviewer_idx and last_todowrite_idx >= 0


def create_code_review_prompt() -> str:
    """
    Create the prompt to inject for code-reviewer invocation.

    Returns:
        Formatted prompt string
    """
    return """Project-wide diagnostics are clean! All issues have been resolved.

According to the CLAUDE.md workflow, you must now invoke the code-reviewer sub-agent:

**Pre-Review Preparation**:

Before invoking code-reviewer, consolidate information from all completed tasks:

1. **Aggregate Modified Files**: Collect all files created/modified across ALL tasks
2. **Aggregate Modified Components**: List all functions, classes, methods changed
3. **Summarize Scope**: Overall description of what was implemented
4. **Context Collection**: Important decisions or trade-offs made

**Invoking code-reviewer**:

Call the Task tool with subagent_type="code-reviewer" and provide:
- Complete file list: All files created/modified during task execution
- Complete component list: All functions, classes, code blocks changed
- Consolidated scope: Overall description of implementation
- Cross-task context: How different tasks relate to each other, dependencies
- **Skip diagnostics**: Instruct code-reviewer to NOT run diagnostic tools (already performed)

Proceed with code review now. The final report will be generated automatically after review completes."""


def main():
    """
    Main hook execution logic.

    Hook Input (via stdin):
        {
            "tool_name": "mcp__vscode-mcp__get_diagnostics" | "Bash",
            "tool_input": {...},
            "tool_response": {...},
            "transcript_path": "/path/to/transcript.jsonl",
            "session_id": "...",
            "cwd": "...",
            "permission_mode": "..."
        }

    Hook Output (stdout if triggering):
        {
            "decision": "block",
            "reason": "Detailed prompt for next workflow stage",
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "stage": "diagnostics_clean_to_code_review",
                "diagnosticsTool": "mcp__vscode-mcp__get_diagnostics" | "Bash"
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

    if tool_name not in ["mcp__vscode-mcp__get_diagnostics", "Bash"]:
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    transcript_path = input_data.get("transcript_path", "")
    if not transcript_path:
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    tool_response = input_data.get("tool_response", {})

    is_clean = False

    if tool_name == "mcp__vscode-mcp__get_diagnostics":
        is_clean = is_diagnostics_clean_mcp(tool_response)
    elif tool_name == "Bash":
        is_clean = is_diagnostics_clean_bash(tool_response)

    if not is_clean:
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    recent_entries = parse_transcript_recent(transcript_path)

    if not is_workflow_active_and_code_reviewer_not_called(recent_entries):
        response = {}
        print(json.dumps(response, ensure_ascii=False))
        sys.exit(0)

    response = {
        "decision": "block",
        "reason": create_code_review_prompt(),
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "stage": "diagnostics_clean_to_code_review",
            "diagnosticsTool": tool_name,
        }
    }

    print(json.dumps(response, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
