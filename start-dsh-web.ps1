# Start the DeepSeek Harness Web server (local source mode).
#
# Prereqs:
#   - Run once at repo root: corepack pnpm install && corepack pnpm run build
#   - Node 22.19+/24+ with corepack available (repo pins pnpm@11.7.0)
#   - Credentials: put a .env at the repo root (with DEEPSEEK_API_KEY=...),
#     or set $env:DSH_ENV_FILE to point at another .env file.
#
# Usage:
#   .\start-dsh-web.ps1                 # web profile default host/port
#   .\start-dsh-web.ps1 --port 8080     # custom port
#   .\start-dsh-web.ps1 --host 0.0.0.0  # bind all interfaces (LAN access)
# Stop with Ctrl+C (prompts to confirm; default Yes, case-insensitive).
#
# Double-click launcher: start-dsh-web.bat

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location -LiteralPath $repoRoot

# Load .env (repo root by default; override via DSH_ENV_FILE) for DEEPSEEK_API_KEY etc.
$envFile = if ($env:DSH_ENV_FILE) { $env:DSH_ENV_FILE } else { Join-Path $repoRoot '.env' }
if (Test-Path -LiteralPath $envFile) {
    Get-Content -LiteralPath $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -le 0) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrEmpty($key)) { Set-Item -Path "env:$key" -Value $val }
    }
    Write-Host ('Loaded credentials from ' + $envFile)
} else {
    Write-Host ('No .env found at ' + $envFile + '; using current process environment.')
}

# The harness reads DEEPSEEK_API_KEY. If only DEEPSEEK_KEY is present
# (e.g. from a shared .env), map it so the server works out of the box.
if (-not $env:DEEPSEEK_API_KEY -and $env:DEEPSEEK_KEY) {
    $env:DEEPSEEK_API_KEY = $env:DEEPSEEK_KEY
    Write-Host 'Mapped DEEPSEEK_KEY -> DEEPSEEK_API_KEY for the harness.'
}

# Start the web server in the foreground; forward remaining args to `dsh web`.
# Run from a PowerShell window (or via start-dsh-web.bat, which opens its own
# window) so Ctrl+C terminates the server directly without a cmd confirm prompt.
corepack pnpm dsh web @args
