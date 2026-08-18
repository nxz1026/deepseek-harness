# DSH Web system-tray launcher (1+6 combo):
#   - keeps the server running HEADLESS (no console window at all), and
#   - the tray icon is the control surface (start / stop / restart / open UI /
#     show logs), while "Show Logs" opens a Windows Terminal tab that tails logs.
#
# Entry point: dsh-web-launcher.lnk (created alongside this file), which runs
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File dsh-tray.ps1
# so double-clicking shows only the tray icon - no ugly cmd box.
#
# NOTE: this file must stay ASCII-only (PowerShell 5.1 reads .ps1 as the system
# codepage; non-ASCII breaks string parsing). See windows-build-guide.md 坑 3.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$launcher = Join-Path $repoRoot 'start-dsh-web.ps1'
$tailScript = Join-Path $repoRoot 'tail-dsh-web-logs.ps1'
$port = 3080

$wt = Get-Command wt.exe -ErrorAction SilentlyContinue

function Get-DshRunning {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    ($c.OwningProcess | Where-Object { $_ -ne 0 } | Measure-Object).Count -gt 0
}

function Start-Dsh {
    Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $launcher, '-Headless', '-OpenBrowser'
    )
}

function Stop-Dsh {
    Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $launcher, '-Stop'
    )
}

function ShowLogs {
    if ($wt) {
        Start-Process -FilePath $wt.Path -ArgumentList @(
            'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tailScript
        )
    } else {
        Start-Process -FilePath 'powershell' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tailScript
        )
    }
}

function Restart-Dsh {
    Stop-Dsh
    Start-Sleep -Seconds 2
    Start-Dsh
}

# --- Tray icon + context menu ---
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = 'DSH Web'
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$openUI = $menu.Items.Add('Open Web UI')
$openUI.Add_Click({ Start-Process "http://127.0.0.1:$port" })

$showLogs = $menu.Items.Add('Show Logs (Windows Terminal)')
$showLogs.Add_Click({ ShowLogs })

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$start = $menu.Items.Add('Start Server')
$start.Add_Click({
        Start-Dsh
        $notify.ShowBalloonTip(3000, 'DSH Web', "Starting... browser opens at http://127.0.0.1:$port", 'Info')
    })

$stop = $menu.Items.Add('Stop Server')
$stop.Add_Click({
        Stop-Dsh
        $notify.ShowBalloonTip(3000, 'DSH Web', 'Stopping server...', 'Info')
    })

$restart = $menu.Items.Add('Restart Server')
$restart.Add_Click({
        Restart-Dsh
        $notify.ShowBalloonTip(3000, 'DSH Web', 'Restarting server...', 'Info')
    })

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$exit = $menu.Items.Add('Exit (stop server)')
$exit.Add_Click({
        Stop-Dsh
        $notify.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })

# Start / Stop / Restart are mutually exclusive with the server's running state:
# only the valid action(s) for the current state are enabled.
function Update-MenuState {
    $running = Get-DshRunning
    $start.Enabled = -not $running
    $stop.Enabled = $running
    $restart.Enabled = $running
    $notify.Text = if ($running) { "DSH Web - running (:${port})" } else { "DSH Web - stopped (:${port})" }
}
$menu.Add_Opening({ Update-MenuState })

$notify.ContextMenuStrip = $menu
$notify.Add_DoubleClick({ Start-Process "http://127.0.0.1:$port" })

# Auto-start the server on launch so double-clicking the shortcut just works.
Start-Dsh
$notify.ShowBalloonTip(3000, 'DSH Web', "Launching at http://127.0.0.1:$port`nRight-click the icon to control it.", 'Info')

# Keep the tray alive with a hidden form message loop.
$hiddenForm = New-Object System.Windows.Forms.Form
$hiddenForm.WindowState = 'Minimized'
$hiddenForm.ShowInTaskbar = $false
$hiddenForm.Visible = $false
[System.Windows.Forms.Application]::Run($hiddenForm)
