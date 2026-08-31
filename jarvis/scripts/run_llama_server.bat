@echo off
chcp 65001 >nul
setlocal

:: ========================================================
:: Jarvis LLM Engine: Qwen2.5-3B-Instruct (GPU Mode)
:: Memory footprint: ~1.9 GB VRAM, 0% CPU compute during gen
:: ========================================================

set SCRIPT_DIR=%~dp0
set PROJECT_DIR=%SCRIPT_DIR%..
cd /d "%PROJECT_DIR%"

set LLAMA_SERVER_EXE=
if exist "%PROJECT_DIR%\bin\llama-server.exe" (
    set "LLAMA_SERVER_EXE=%PROJECT_DIR%\bin\llama-server.exe"
) else (
    where llama-server.exe >nul 2>&1
    if %errorlevel% equ 0 (
        set LLAMA_SERVER_EXE=llama-server.exe
    )
)

if "%LLAMA_SERVER_EXE%"=="" (
    echo [ERROR] llama-server.exe not found in '%PROJECT_DIR%\bin\' or PATH!
    echo Please run install.bat to download models and binaries automatically.
    pause
    exit /b 1
)

set MODEL_PATH=%PROJECT_DIR%\models\qwen2.5-3b-instruct-q4_k_m.gguf
set HOST=127.0.0.1
set PORT=8080

:: GPU Offloading Configuration
set N_GPU_LAYERS=99
set CTX_SIZE=2048
set N_THREADS=4

echo [LLM Engine] Initializing GPU-Accelerated Qwen2.5-3B-Instruct...
echo [LLM Engine] VRAM Target: ~1.9 GB ^| Context: %CTX_SIZE% tokens

if not exist "%MODEL_PATH%" (
    echo [ERROR] Model file "%MODEL_PATH%" not found!
    echo Please run install.bat to download models automatically.
    pause
    exit /b 1
)

"%LLAMA_SERVER_EXE%" ^
    -m "%MODEL_PATH%" ^
    --host %HOST% ^
    --port %PORT% ^
    -ngl %N_GPU_LAYERS% ^
    -c %CTX_SIZE% ^
    -t %N_THREADS% ^
    -ctk q8_0 ^
    -ctv q8_0 ^
    --flash-attn ^
    --jinja ^
    --cont-batching

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] llama-server exited with code %errorlevel%.
    pause
)

endlocal
