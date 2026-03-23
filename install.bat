@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%main.ps1"

if not exist "%PS_SCRIPT%" (
    echo.
    echo  [x] main.ps1 not found next to install.bat
    echo      Expected: %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorLevel% == 0 goto :RunInstall

echo  [!] Requesting administrator privileges...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs -WorkingDirectory '%SCRIPT_DIR%'"
exit /b 0

:RunInstall
powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File "%PS_SCRIPT%"

if %errorLevel% neq 0 (
    echo.
    echo  [x] Installer exited with error code %errorLevel%
    echo.
    pause
)

endlocal
exit /b 0
