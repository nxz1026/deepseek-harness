# Start the DeepSeek Harness Web server (local source mode).
#
# Prereqs:
#   - Run once at repo root: corepack pnpm install && corepack pnpm run build
#   - Node 22.19+/24+ with corepack available (repo pins pnpm@11.7.0)
#   - Credentials: put a .env at the repo root (with DEEPSEEK_API_KEY=...),
#     or set $env:DSH_ENV_FILE to point at another .env file.
#
# Usage:
#   .\start-dsh-web.ps1                 # web profile default host/port (http://127.0.0.1:3080)
#   .\start-dsh-web.ps1 --port 8080     # custom port
#   .\start-dsh-web.ps1 --host 0.0.0.0  # bind all interfaces (LAN access)
# Stop with Ctrl+C (prompts to confirm; default Yes, case-insensitive).
#
# Double-click launcher: start-dsh-web.bat

$ErrorActionPreference = 'Stop'

# Force UTF-8 so Chinese server logs render correctly. This script is launched
# with `powershell -NoProfile` (see start-dsh-web.bat), so the profile's UTF-8
# setup does not apply here.
#
# Encoding note: `Start-Process -RedirectStandardOutput` writes the captured
# server output using the system ANSI codepage (GBK on zh-CN Windows), so the
# log files are NOT UTF-8. We read them back with `-Encoding Default` (the same
# system codepage) to recover the correct Chinese; the console is switched to
# UTF-8 below so PowerShell renders that string without mojibake.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp.com 65001 | Out-Null
$PSDefaultParameterValues['Get-Content:Encoding'] = 'Default'

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

# Resolve the bound port so we can detect a conflict before launch.
# Default is 3080 (see @deepseek-ai/dsh-web-app startup); override with --port <n>.
function Get-RequestedPort {
    param([string[]]$RawArgs)
    for ($i = 0; $i -lt $RawArgs.Count; $i++) {
        $a = $RawArgs[$i]
        if ($a -eq '--port' -and ($i + 1) -lt $RawArgs.Count) { return $RawArgs[$i + 1] }
        if ($a -like '--port=*') { return $a.Substring(7) }
    }
    return '3080'
}

$port = Get-RequestedPort -RawArgs $args
if ($port -notmatch '^\d+$') { $port = '3080' }

# Free a conflicting listener before booting, so a stale instance (or another
# app) on the same port does not abort the server with EADDRINUSE. Only an
# actively LISTENing socket counts; TIME_WAIT leftovers are owned by PID 0
# (Idle) and must be ignored.
$conflict = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($conflict) {
    $pids = $conflict.OwningProcess | Where-Object { $_ -ne 0 } | Sort-Object -Unique
    $procs = $pids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_ } | ForEach-Object { "$($_.Id) ($($_.ProcessName))" }
    Write-Host "Port $port is already in use by: $($procs -join ', ')" -ForegroundColor Yellow
    $answer = Read-Host 'Kill the conflicting process(es) and continue? [Y/n]'
    if ($answer -notmatch '^[Nn]') {
        $pids | ForEach-Object {
            Write-Host "Killing PID $_ ..." -ForegroundColor Yellow
            Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
        if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
            Write-Host "Port $port is still occupied; aborting." -ForegroundColor Red
            Write-Host 'Press Enter to close this window...'
            Read-Host | Out-Null
            exit 1
        }
    } else {
        Write-Host "Aborted; choose another port with --port <n>." -ForegroundColor Yellow
        Write-Host 'Press Enter to close this window...'
        Read-Host | Out-Null
        exit 1
    }
}

# Start the web server in the background and tail its log live in this window.
# We invoke node directly with the tsx loader (the same command `pnpm dsh`
# resolves to) instead of `corepack pnpm dsh`: pnpm spawns node with redirected
# stdio, and on Windows a Node process with no attached console crashes with
# "Assertion failed: process_title". Server output is redirected to a log file,
# which this script tails in real time; pass --port / --host through to `dsh web`.
$dshBin = Join-Path $repoRoot 'apps/cli/src/bin.ts'
$nodeArgs = @('--import', 'tsx/esm', $dshBin, 'web') + $args

$logOut = Join-Path $env:TEMP 'dsh-web.out.log'
$logErr = Join-Path $env:TEMP 'dsh-web.err.log'
Remove-Item -LiteralPath $logOut, $logErr -ErrorAction SilentlyContinue

# Start-Process cannot redirect stdout and stderr to the same file, so use two
# and tail both (see windows-build-guide.md 坑 4).
$server = Start-Process -FilePath 'node' -ArgumentList $nodeArgs `
    -NoNewWindow -RedirectStandardOutput $logOut -RedirectStandardError $logErr -PassThru

Write-Host "Server starting (PID $($server.Id)). Live logs:" -ForegroundColor Cyan
Write-Host "  stdout: $logOut" -ForegroundColor Cyan
Write-Host "  stderr: $logErr" -ForegroundColor Cyan
Write-Host 'Boot can take 10-30s on first launch (tsx compiles, Cordis loads);' -ForegroundColor Yellow
Write-Host 'wait for the "dsh web: http://..." line, then Ctrl+C to stop.' -ForegroundColor Yellow

# Poll both log files and print only new lines, so the console shows the server
# stream live while a single foreground loop also detects a crash or Ctrl+C.
$outOff = 0
$errOff = 0
function PrintNew($path, [ref]$off) {
    $lines = @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
    if ($lines.Count -gt $off.Value) {
        $lines[$off.Value..($lines.Count - 1)] | Write-Host
        $off.Value = $lines.Count
    }
}
$stopReason = 'ctrlc'
$scriptError = $null
try {
    while ($true) {
        if ($server.HasExited) {
            $code = $null
            try { $code = $server.ExitCode } catch { }
            if ($null -eq $code -or $code -eq 0) {
                $stopReason = 'clean'
                break
            }
            $stopReason = 'crash'
            throw "Server process exited (exit code: $code)."
        }
        PrintNew $logOut ([ref]$outOff)
        PrintNew $logErr ([ref]$errOff)
        Start-Sleep -Milliseconds 200
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl+C: intentional shutdown, not a failure.
    $stopReason = 'ctrlc'
} catch {
    $stopReason = 'crash'
    $scriptError = $_.Exception.Message
} finally {
    if ($server -ne $null -and -not $server.HasExited) {
        $server.Kill()
        $server.WaitForExit(2000)
    }
    Write-Host ''
    if ($stopReason -eq 'crash') {
        Write-Host 'The DeepSeek Harness web server stopped unexpectedly:' -ForegroundColor Red
        if ($scriptError) { Write-Host $scriptError -ForegroundColor Red }
        Write-Host ''
        Write-Host 'Common causes:' -ForegroundColor Yellow
        Write-Host '  - Frontend not built. Run .\build.ps1 first.' -ForegroundColor Yellow
        Write-Host '  - Node not on PATH, or tsx missing. Use Node 22.19+/24+.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Last stderr:' -ForegroundColor Red
        @(Get-Content -LiteralPath $logErr -ErrorAction SilentlyContinue) | Select-Object -Last 15 | Write-Host
    } else {
        Write-Host 'Server stopped.' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'Last log lines (stdout):' -ForegroundColor Cyan
    @(Get-Content -LiteralPath $logOut -ErrorAction SilentlyContinue) | Select-Object -Last 30 | Write-Host
    Write-Host 'Last log lines (stderr):' -ForegroundColor Cyan
    @(Get-Content -LiteralPath $logErr -ErrorAction SilentlyContinue) | Select-Object -Last 30 | Write-Host
    Write-Host "Full logs: $logOut (stdout) / $logErr (stderr)" -ForegroundColor Cyan
    Write-Host 'Press Enter to close this window...'
    Read-Host | Out-Null
}
