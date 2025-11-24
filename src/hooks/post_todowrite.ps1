<#
.SYNOPSIS
    PostToolUse hook for TodoWrite tool.
.DESCRIPTION
    Detects when all tasks completed, runs static analyzers,
    and injects appropriate prompt based on results.
#>

$ErrorActionPreference = 'SilentlyContinue'

function Get-ProjectTypes {
    param([string]$Cwd)

    $types = @()
    $indicators = @{
        'python' = @('pyproject.toml', 'setup.py', 'requirements.txt')
        'typescript' = @('tsconfig.json')
        'javascript' = @('package.json')
        'go' = @('go.mod')
        'rust' = @('Cargo.toml')
    }

    foreach ($lang in $indicators.Keys) {
        foreach ($file in $indicators[$lang]) {
            if (Test-Path (Join-Path $Cwd $file)) {
                $types += $lang
                break
            }
        }
    }
    return $types
}

function Get-Analyzers {
    param([string[]]$ProjectTypes)

    $analyzerMap = @{
        'python' = @(
            @{ name = 'ruff'; cmd = @('ruff', 'check', '.') }
            @{ name = 'mypy'; cmd = @('mypy', '.') }
        )
        'typescript' = @(
            @{ name = 'tsc'; cmd = @('npx', 'tsc', '--noEmit') }
            @{ name = 'eslint'; cmd = @('npx', 'eslint', '.') }
        )
        'javascript' = @(
            @{ name = 'eslint'; cmd = @('npx', 'eslint', '.') }
        )
        'go' = @(
            @{ name = 'go vet'; cmd = @('go', 'vet', './...') }
        )
        'rust' = @(
            @{ name = 'clippy'; cmd = @('cargo', 'clippy') }
        )
    }

    $analyzers = @()
    foreach ($ptype in $ProjectTypes) {
        if ($analyzerMap.ContainsKey($ptype)) {
            foreach ($analyzer in $analyzerMap[$ptype]) {
                if (Get-Command $analyzer.cmd[0] -ErrorAction SilentlyContinue) {
                    $analyzers += $analyzer
                }
            }
        }
    }
    return $analyzers
}

function Get-ModifiedCodeFiles {
    param([string]$TranscriptPath)

    $nonCodeExtensions = @(
        '.md', '.txt', '.rst',
        '.json', '.yml', '.yaml', '.toml', '.xml',
        '.css', '.scss', '.sass', '.less',
        '.html', '.htm', '.ejs', '.pug'
    )

    $fileModifyingTools = @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')
    $successfulToolIds = [System.Collections.Generic.HashSet[string]]::new()
    $modifiedFiles = [System.Collections.Generic.HashSet[string]]::new()

    if (-not (Test-Path $TranscriptPath)) {
        return @()
    }

    foreach ($line in (Get-Content $TranscriptPath)) {
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.type -eq 'tool_result' -and -not $entry.PSObject.Properties['error']) {
                [void]$successfulToolIds.Add($entry.tool_use_id)
            }
        } catch {}
    }

    foreach ($line in (Get-Content $TranscriptPath)) {
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.type -ne 'tool_use' -or $fileModifyingTools -notcontains $entry.name) {
                continue
            }

            if (-not $successfulToolIds.Contains($entry.id)) {
                continue
            }

            $entryInput = $entry.input
            switch ($entry.name) {
                { $_ -in @('Write', 'Edit', 'NotebookEdit') } {
                    if ($entryInput.file_path) {
                        $ext = [System.IO.Path]::GetExtension($entryInput.file_path).ToLower()
                        if ($ext -and $nonCodeExtensions -notcontains $ext) {
                            [void]$modifiedFiles.Add($entryInput.file_path)
                        }
                    }
                }
                'MultiEdit' {
                    if ($entryInput.edits) {
                        foreach ($edit in $entryInput.edits) {
                            if ($edit.file_path) {
                                $ext = [System.IO.Path]::GetExtension($edit.file_path).ToLower()
                                if ($ext -and $nonCodeExtensions -notcontains $ext) {
                                    [void]$modifiedFiles.Add($edit.file_path)
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    return @($modifiedFiles)
}

function Invoke-StaticAnalysis {
    param([string]$Cwd)

    $projectTypes = Get-ProjectTypes -Cwd $Cwd
    if ($projectTypes.Count -eq 0) {
        return @{ passed = $true; errors = '' }
    }

    $analyzers = Get-Analyzers -ProjectTypes $projectTypes
    if ($analyzers.Count -eq 0) {
        return @{ passed = $true; errors = '' }
    }

    $errorMessages = @()
    foreach ($analyzer in $analyzers) {
        try {
            $proc = Start-Process -FilePath $analyzer.cmd[0] `
                -ArgumentList ($analyzer.cmd | Select-Object -Skip 1) `
                -WorkingDirectory $Cwd `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput "$env:TEMP\hook_stdout.txt" `
                -RedirectStandardError "$env:TEMP\hook_stderr.txt"

            if ($proc.ExitCode -ne 0) {
                $stdout = Get-Content "$env:TEMP\hook_stdout.txt" -Raw -ErrorAction SilentlyContinue
                $stderr = Get-Content "$env:TEMP\hook_stderr.txt" -Raw -ErrorAction SilentlyContinue
                $output = "$stdout$stderr".Trim()
                if ($output) {
                    $errorMessages += "[$($analyzer.name)]`n$output"
                }
            }
        } catch {
            continue
        }
    }

    if ($errorMessages.Count -gt 0) {
        return @{ passed = $false; errors = ($errorMessages -join "`n`n") }
    }
    return @{ passed = $true; errors = '' }
}

$inputData = $input | Out-String | ConvertFrom-Json

if ($inputData.tool_name -ne 'TodoWrite') {
    Write-Output '{}'
    exit 0
}

$transcriptPath = $inputData.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
    Write-Output '{}'
    exit 0
}

$lastTodos = $null
foreach ($line in (Get-Content $transcriptPath)) {
    try {
        $entry = $line | ConvertFrom-Json
        if ($entry.type -eq 'tool_use' -and $entry.name -eq 'TodoWrite') {
            $lastTodos = $entry.input.todos
        }
    } catch {}
}

if (-not $lastTodos -or $lastTodos.Count -eq 0) {
    Write-Output '{}'
    exit 0
}

$allCompleted = ($lastTodos | Where-Object { $_.status -ne 'completed' }).Count -eq 0

if (-not $allCompleted) {
    Write-Output '{}'
    exit 0
}

$cwd = if ($inputData.cwd) { $inputData.cwd } else { Get-Location }

$modifiedCodeFiles = Get-ModifiedCodeFiles -TranscriptPath $transcriptPath
if ($modifiedCodeFiles.Count -eq 0) {
    Write-Output '{}'
    exit 0
}

$analysis = Invoke-StaticAnalysis -Cwd $cwd

if ($analysis.passed) {
    $reason = 'All tasks completed and static analysis passed! Invoke the code-reviewer agent now.'
} else {
    $reason = "Static analysis found issues. Fix them:`n`n$($analysis.errors)"
}

$response = @{
    decision = 'block'
    reason = $reason
    hookSpecificOutput = @{
        hookEventName = 'PostToolUse'
        completedTasks = $lastTodos.Count
        staticAnalysisPassed = $analysis.passed
    }
} | ConvertTo-Json -Compress -Depth 10

Write-Output $response
exit 0
