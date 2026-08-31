@echo off
setlocal enabledelayedexpansion

echo =======================================================================
echo  JARVIS AI ASSISTANT (Unified Monolithic Engine)
echo  [GPU]: Qwen2.5-3B-Instruct (~1.9 GB VRAM)
echo  [Audio]: Miniaudio (16kHz Capture, 24kHz Playback)
echo  [System]: Native In-Memory Win32 Control
echo =======================================================================
echo.

:: 1. Launch llama-server in background if not already responding
curl -s http://127.0.0.1:8080/health >nul 2>&1
if %errorlevel% neq 0 (
    echo [1/2] Starting Local Brain (llama-server on GPU)...
    start "Jarvis - LLM Server" /min cmd /c call "%~dp0run_llama_server.bat"
    echo [1/2] Waiting for LLM server to initialize...
    timeout /t 3 /nobreak >nul
) else (
    echo [1/2] LLM server is already running.
)

:: 2. Launch Unified Jarvis Assistant
echo [2/2] Launching Jarvis Assistant...
if exist "%~dp0..\zig-out\bin\jarvis.exe" (
    "%~dp0..\zig-out\bin\jarvis.exe"
) else if exist "%~dp0..\zig-out\bin\jarvis" (
    "%~dp0..\zig-out\bin\jarvis"
) else (
    echo [ERROR] jarvis executable not found in zig-out\bin\
    echo Please run 'zig build' first or use install.bat
    pause
)

endlocal
