@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-harness.ps1" -Mode Web
if errorlevel 1 pause
