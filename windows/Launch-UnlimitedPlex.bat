@echo off
title UnlimitedPlex Installer
color 0A

echo.
echo  ============================================
echo   UnlimitedPlex Installer
echo   Plex + Real-Debrid + Arr Stack for Windows
echo  ============================================
echo.

:: Check if running as Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo  [!] Not running as Administrator.
    echo  [!] Restarting with elevated privileges...
    echo.
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Check PowerShell version
powershell -Command "if ($PSVersionTable.PSVersion.Major -lt 5) { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo  [ERROR] PowerShell 5.1 or higher is required.
    echo  Please update Windows PowerShell.
    pause
    exit /b 1
)

:: Set execution policy for this session and launch GUI
echo  Launching UnlimitedPlex Installer GUI...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0UnlimitedPlex.ps1"

if %errorLevel% neq 0 (
    echo.
    echo  [ERROR] The installer encountered an error.
    echo  Error code: %errorLevel%
    echo.
    pause
)