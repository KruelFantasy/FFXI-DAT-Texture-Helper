@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Start.ps1"
if errorlevel 1 echo Please copy the error above if you need help.
pause
