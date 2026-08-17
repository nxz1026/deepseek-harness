@echo off
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dsh-web.ps1" %*
