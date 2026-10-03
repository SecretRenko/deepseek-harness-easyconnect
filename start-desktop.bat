@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-harness.ps1" -Mode Desktop
if errorlevel 1 pause
