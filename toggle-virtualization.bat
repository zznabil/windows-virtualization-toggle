@echo off
setlocal

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process -FilePath '%~0' -Verb RunAs"
    exit /b
)

:: Run the sibling PowerShell script
:: %~dp0 provides the directory path of the batch file
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0toggle-virtualization.ps1"

:: Exit with the same exit code as PowerShell
exit /b %errorLevel%
