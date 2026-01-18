param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

try {
    $inputJson = $input | Out-String

    if ([string]::IsNullOrWhiteSpace($inputJson)) {
        Write-Output "No input"
        exit 0
    }

    $data = $inputJson | ConvertFrom-Json

    $TealBright = "`e[38;2;69;241;194m"
    $CyanLight = "`e[38;2;12;160;216m"
    $TealDark = "`e[38;2;20;165;174m"
    $Green = "`e[38;2;76;200;116m"
    $Yellow = "`e[38;2;255;200;76m"
    $Red = "`e[38;2;204;100;100m"
    $Reset = "`e[0m"

    $modelId = $data.model.id
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        $modelId = "Unknown"
    }

    if ($modelId -match "sonnet") {
        $modelName = "Sonnet"
    }
    elseif ($modelId -match "opus") {
        $modelName = "Opus"
    }
    elseif ($modelId -match "haiku") {
        $modelName = "Haiku"
    }
    else {
        $modelName = $modelId -replace "-.*", ""
    }

    $currentDir = $data.workspace.current_dir
    if ([string]::IsNullOrWhiteSpace($currentDir)) {
        $currentDir = Get-Location
    }

    $homePath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    $displayPath = $currentDir -replace "^$([regex]::Escape($homePath))", "~"
    $displayPath = $displayPath -replace "\\", "/"

    Push-Location $currentDir

    $gitBranch = ""

    if (Test-Path ".git") {
        $branch = git symbolic-ref --short HEAD 2>$null
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = git rev-parse --short HEAD 2>$null
            if (-not [string]::IsNullOrWhiteSpace($branch)) {
                $branch = "detached:$branch"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($branch)) {
            $gitBranch = $branch
        }
    }

    Pop-Location

    # Get token data directly from Claude Code
    $usedPercentage = 0
    $maxContextTokens = 200000

    if ($null -ne $data.context_window) {
        $usedPercentage = [double]($data.context_window.used_percentage ?? 0)
        $maxContextTokens = [int]($data.context_window.max_tokens ?? 200000)
    }

    $currentContextTokens = [math]::Round($maxContextTokens * $usedPercentage / 100, 0)
    $contextPercent = [math]::Round($usedPercentage, 0)
    $tokensFormatted = if ($currentContextTokens -ge 1000) { "$([math]::Round($currentContextTokens / 1000, 1))K" } else { "$currentContextTokens" }

    $contextColor = if ($contextPercent -lt 50) { $Green } elseif ($contextPercent -lt 80) { $Yellow } else { $Red }

    $userIcon = [char]0xEB99
    $folderIcon = [char]0xF07B
    $gitBranchIcon = [char]0xE725
    $contextIcon = [char]0xF037

    $segments = @()
    $segments += "${TealBright}${userIcon} ${modelName}${Reset}"
    $segments += "on"
    $segments += "${CyanLight}${folderIcon} ${displayPath}${Reset}"

    if (-not [string]::IsNullOrWhiteSpace($gitBranch)) {
        $segments += "${TealDark}${gitBranchIcon} ${gitBranch}${Reset}"
    }

    if ($currentContextTokens -gt 0) {
        $contextWithIcon = "${contextColor}${contextIcon} ${tokensFormatted} ($contextPercent%)${Reset}"
        $segments += $contextWithIcon
    }

    $output = $segments -join " "

    Write-Output $output

}
catch {
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}
