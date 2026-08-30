@echo off
setlocal

:: ========================================================
:: Jarvis LLM Engine: Qwen2.5-3B-Instruct (GPU Mode)
:: Memory footprint: ~1.9 GB VRAM, 0% CPU compute during gen
:: ========================================================

set LLAMA_SERVER_EXE=llama-server.exe
set MODEL_PATH=models\qwen2.5-3b-instruct-q4_k_m.gguf
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
    echo Download Qwen2.5-3B-Instruct-Q4_K_M.gguf and place in models\
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
    --cont-batching

endlocal
