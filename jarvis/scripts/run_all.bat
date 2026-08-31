@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

cd /d "%~dp0.."

echo =======================================================================
echo  JARVIS AI ASSISTANT (Unified Monolithic Engine)
echo  [GPU]: Qwen2.5-3B-Instruct (~1.9 GB VRAM)
echo  [Audio]: Miniaudio (16kHz Capture, 24kHz Playback)
echo  [System]: Native In-Memory Win32 Control
echo =======================================================================
echo.

:: 1. Build binary if missing
if not exist "zig-out\bin\jarvis.exe" (
    if not exist "zig-out\bin\jarvis" (
        echo [Setup] jarvis executable not found. Compiling with Zig...
        zig build -Doptimize=ReleaseFast
        if not exist "zig-out\bin\jarvis.exe" if not exist "zig-out\bin\jarvis" (
            echo [ERROR] Failed to compile jarvis executable.
            echo Please make sure Zig is installed or run install.bat.
            pause
            exit /b 1
        )
    )
)

:: 2. Launch llama-server in background if not already responding
curl.exe -s http://127.0.0.1:8080/health >nul 2>&1
if %errorlevel% equ 0 goto llm_ready

echo [1/3] Starting Local Brain (llama-server on GPU)...
start "Jarvis - LLM Server" /min cmd /c call "%~dp0run_llama_server.bat"
echo [1/3] Waiting for LLM server to initialize...

set /a attempts=0
:wait_llm
ping -n 2 127.0.0.1 >nul
curl.exe -s http://127.0.0.1:8080/health >nul 2>&1
if %errorlevel% equ 0 goto llm_ready
set /a attempts+=1
if !attempts! lss 20 goto wait_llm
echo [Warning] LLM server taking longer than usual to start. Launching Jarvis...
goto check_vlm

:llm_ready
echo [1/2] LLM Brain is ready!
echo [2/2] Launching Jarvis Assistant (Native Windows Engine)...
echo.
goto start_jarvis

:start_jarvis
:: 3. Launch Unified Jarvis Assistant
echo [3/3] Launching Jarvis Assistant...
echo.

if exist "zig-out\bin\jarvis.exe" (
    "zig-out\bin\jarvis.exe" %*
) else if exist "zig-out\bin\jarvis" (
    "zig-out\bin\jarvis" %*
) else (
    echo [ERROR] jarvis executable not found in zig-out\bin\
    echo Please run 'zig build' first or use install.bat
    pause
    exit /b 1
)

if %errorlevel% neq 0 (
    echo.
    echo [Jarvis exited with code %errorlevel%]
    pause
)

endlocal
