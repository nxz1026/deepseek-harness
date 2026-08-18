# Tail the DSH Web server logs in a Windows Terminal tab (used by the tray
# launcher "Show Logs" action). start-dsh-web.ps1 writes the server's stdout /
# stderr to two temp files; this prints only new lines so it is a live view.
# Close the tab (Ctrl+C) to stop tailing - the server keeps running.
$ErrorActionPreference = 'Stop'

$logOut = Join-Path $env:TEMP 'dsh-web.out.log'
$logErr = Join-Path $env:TEMP 'dsh-web.err.log'

Write-Host 'DSH Web live logs (Ctrl+C to close this tab; the server keeps running).' -ForegroundColor Cyan
Write-Host "  stdout: $logOut" -ForegroundColor Cyan
Write-Host "  stderr: $logErr" -ForegroundColor Cyan

# Encode with Default (system ANSI / GBK on zh-CN) to match how Start-Process
# -RedirectStandardOutput wrote the file, so Chinese logs decode correctly.
# The offset must be a plain scalar [ref] (a hashtable member [ref] does NOT
# persist back), otherwise the whole file is reprinted on every loop.
$outOff = 0
$errOff = 0
function PrintNew($path, [ref]$off) {
    $lines = @(Get-Content -LiteralPath $path -Encoding Default -ErrorAction SilentlyContinue)
    # Server restart truncates the log; if it shrank, reset so we don't go silent.
    if ($lines.Count -lt $off.Value) { $off.Value = 0 }
    if ($lines.Count -gt $off.Value) {
        $lines[$off.Value..($lines.Count - 1)] | Write-Host
        $off.Value = $lines.Count
    }
}

while ($true) {
    PrintNew $logOut ([ref]$outOff)
    PrintNew $logErr ([ref]$errOff)
    Start-Sleep -Milliseconds 200
}
