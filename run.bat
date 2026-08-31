@echo off
chcp 65001 >nul
cd /d "%~dp0jarvis\scripts"
call run_all.bat %*

