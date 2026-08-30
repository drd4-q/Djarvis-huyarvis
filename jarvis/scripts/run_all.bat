@echo off
setlocal enabledelayedexpansion

echo =======================================================================
echo  JARVIS AI ASSISTANT - HYBRID LOW-RESOURCE PROFILE
echo  [GPU]: Qwen2.5-3B-Instruct (~1.9 GB VRAM)
echo  [CPU]: Whisper STT + Piper TTS + Silero VAD (~140 MB RAM)
echo  [Native]: Zig Core + Go Hub (~30 MB RAM)
echo =======================================================================
echo.

:: 1. Launch LLM on GPU in separate window
echo [1/3] Launching Local Brain (llama-server on GPU)...
start "Jarvis - LLM Brain (GPU)" cmd /k call "%~dp0run_llama_server.bat"

:: 2. Launch Native Zig Core
echo [2/3] Launching Native Execution Core (Zig 0.16.0)...
start "Jarvis - Native Core (Zig)" cmd /k "%~dp0..\core\zig-out\bin\jarvis_core.exe"

:: 3. Launch Go Hub
echo [3/3] Launching Orchestration Hub (Go)...
timeout /t 2 /nobreak >nul
"%~dp0..\hub\hub.exe"

endlocal
