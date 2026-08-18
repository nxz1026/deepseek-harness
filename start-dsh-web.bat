@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

rem Launch the web server in a Windows Terminal tab (pretty, no conhost box).
rem For the system-tray experience (no window at all + tray controls), use
rem dsh-web-launcher.lnk instead, which runs dsh-tray.ps1.
where wt.exe >nul 2>nul
if %ERRORLEVEL%==0 (
    wt.exe -d "%SCRIPT_DIR%" powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start-dsh-web.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start-dsh-web.ps1" %*
)
