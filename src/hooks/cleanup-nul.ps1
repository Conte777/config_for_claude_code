param()

$ErrorActionPreference = 'SilentlyContinue'

try {
    $inputJson = [Console]::In.ReadToEnd()

    if ([string]::IsNullOrWhiteSpace($inputJson)) {
        exit 0
    }

    $data = $inputJson | ConvertFrom-Json
    $cwd = $data.cwd

    if ([string]::IsNullOrWhiteSpace($cwd)) {
        exit 0
    }

    # Windows reserved name workaround: use \\?\ prefix
    $uncPath = "\\?\$(Join-Path -Path $cwd -ChildPath 'nul')"

    if (Test-Path -LiteralPath $uncPath) {
        Remove-Item -LiteralPath $uncPath -Force
    }

    exit 0
}
catch {
    exit 0
}
