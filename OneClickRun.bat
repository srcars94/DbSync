@echo off
set SCRIPT=sync.ps1

echo Running %SCRIPT%...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0%SCRIPT%"

pause
