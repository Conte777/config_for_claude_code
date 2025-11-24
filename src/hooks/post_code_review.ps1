<#
.SYNOPSIS
    PostToolUse hook for Task tool (code-reviewer).
.DESCRIPTION
    After code-reviewer completes, inject prompt for final summary report.
#>

$ErrorActionPreference = 'SilentlyContinue'

$inputData = $input | Out-String | ConvertFrom-Json

if ($inputData.tool_name -ne 'Task') {
    Write-Output '{}'
    exit 0
}

if ($inputData.tool_input.subagent_type -ne 'code-reviewer') {
    Write-Output '{}'
    exit 0
}

$transcriptPath = $inputData.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
    Write-Output '{}'
    exit 0
}

$workflowActive = $false
foreach ($line in (Get-Content $transcriptPath)) {
    try {
        $entry = $line | ConvertFrom-Json
        if ($entry.type -eq 'tool_use' -and $entry.name -eq 'TodoWrite') {
            $workflowActive = $true
        }
    } catch {}
}

if (-not $workflowActive) {
    Write-Output '{}'
    exit 0
}

$reportPrompt = @"
Code review has been completed!

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

Generate the final summary report now.
"@

$response = @{
    decision = 'block'
    reason = $reportPrompt
} | ConvertTo-Json -Compress -Depth 10

Write-Output $response
exit 0
