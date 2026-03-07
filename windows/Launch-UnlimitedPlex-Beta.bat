@echo off
title UnlimitedPlex Beta Installer
color 0A

echo.
echo  ============================================================
echo   UnlimitedPlex BETA Installer
echo   Modular Service Selector - Plex + Real-Debrid for Windows
echo  ============================================================
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
    pause
    exit /b 1
)

:: Unblock the PS1 file
echo  Unblocking script...
powershell -Command "Unblock-File -Path '%~dp0UnlimitedPlex-Beta.ps1'" >nul 2>&1

:: Launch Beta GUI (STA required for WPF)
echo  Launching UnlimitedPlex Beta GUI...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -STA -File "%~dp0UnlimitedPlex-Beta.ps1"

if %errorLevel% neq 0 (
    echo.
    echo  [ERROR] The installer encountered an error. Code: %errorLevel%
    echo.
    echo  --- Error Log ---
    if exist "%TEMP%\UnlimitedPlex_Beta_error.log" (
        type "%TEMP%\UnlimitedPlex_Beta_error.log"
    )
    echo.
    echo  --- Manual Launch ---
    echo  powershell -ExecutionPolicy Bypass -STA -File "%~dp0UnlimitedPlex-Beta.ps1"
    echo.
    pause
)