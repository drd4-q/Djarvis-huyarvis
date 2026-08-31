@echo off
setlocal
cd /d "%~dp0"

echo =======================================================================
echo              JARVIS AI ASSISTANT - INSTALLER / SETUP
echo =======================================================================
echo.
echo Launching installation wizard...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Installation failed or was cancelled.
    pause
) else (
    echo.
    echo [SUCCESS] Setup complete!
    pause
)
endlocal
