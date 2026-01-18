# Commit Helper Script
# Validates git state and extracts commit metadata
# Returns JSON output for Claude to process

$ErrorActionPreference = "Stop"

# Initialize result object
$result = @{
    stagedFiles = @()
    stagedCount = 0
    branchName = ""
    ticketId = $null
    isProtectedBranch = $false
    warnings = @()
}

# Check if git repository
try {
    $null = git rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not a git repository"
        exit 1
    }
} catch {
    Write-Error "Git is not available"
    exit 1
}

# Get staged files
$stagedFiles = git diff --cached --name-only 2>$null
if ($stagedFiles) {
    $result.stagedFiles = @($stagedFiles -split "`n" | Where-Object { $_ })
    $result.stagedCount = $result.stagedFiles.Count
} else {
    $result.warnings += "EMPTY_STAGING"
}

# Get current branch name
$branchName = git branch --show-current 2>$null
if ($branchName) {
    $result.branchName = $branchName.Trim()
} else {
    # Detached HEAD state
    $result.branchName = git rev-parse --short HEAD 2>$null
    $result.warnings += "DETACHED_HEAD"
}

# Check for protected branches
$protectedBranches = @("main", "master", "develop", "stage", "staging")
if ($protectedBranches -contains $result.branchName.ToLower()) {
    $result.isProtectedBranch = $true
    $result.warnings += "PROTECTED_BRANCH"
}

# Extract ticket ID (CUS-XXXX pattern, case insensitive)
if ($result.branchName -match "(?i)(CUS-\d+)") {
    $result.ticketId = $matches[1].ToUpper()
} else {
    $result.warnings += "NO_TICKET_ID"
}

# Output as JSON
$result | ConvertTo-Json -Compress
