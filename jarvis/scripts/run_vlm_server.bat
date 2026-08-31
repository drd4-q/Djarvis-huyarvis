@echo off
chcp 65001 >nul
setlocal

:: ========================================================
:: Jarvis Vision Engine: SmolVLM-256M-Instruct (GPU Mode)
:: Memory footprint: ~300 MB VRAM, Multimodal Screen Vision
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
    echo [ERROR] llama-server.exe not found!
    exit /b 1
)

set MODEL_PATH=%PROJECT_DIR%\models\SmolVLM-256M-Instruct-Q8_0.gguf
set MMPROJ_PATH=%PROJECT_DIR%\models\mmproj-SmolVLM-256M-Instruct-Q8_0.gguf
set HOST=127.0.0.1
set PORT=8081

if not exist "%MODEL_PATH%" (
    echo [Vision Engine] SmolVLM-256M model not found at "%MODEL_PATH%".
    exit /b 1
)

if not exist "%MMPROJ_PATH%" (
    echo [Vision Engine] Vision projector not found at "%MMPROJ_PATH%".
    exit /b 1
)

echo [Vision Engine] Launching SmolVLM-256M Vision Server on port %PORT%...

"%LLAMA_SERVER_EXE%" ^
    -m "%MODEL_PATH%" ^
    --mmproj "%MMPROJ_PATH%" ^
    --host %HOST% ^
    --port %PORT% ^
    -ngl 99 ^
    -c 2048 ^
    -t 4 ^
    --jinja

if %errorlevel% neq 0 (
    echo [ERROR] SmolVLM vision server exited with code %errorlevel%.
)

endlocal
