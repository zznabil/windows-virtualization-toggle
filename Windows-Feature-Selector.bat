@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows-Feature-Selector.ps1" %*
set "result=%errorlevel%"
exit /b %result%
