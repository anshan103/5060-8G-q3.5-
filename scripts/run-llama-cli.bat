@echo off
REM ============================================================
REM  run-llama-cli.bat
REM  Run one inference with the self-built llama-cli.
REM
REM  Usage:
REM    run-llama-cli.bat [model path] [prompt]
REM
REM  Why a .bat: PowerShell's Start-Process -ArgumentList joins arguments
REM  with spaces without quoting, so a prompt containing spaces gets split
REM  into separate argv entries and llama-cli fails with
REM  "error: invalid argument: is".
REM
REM  NOTE: keep this file ASCII-only (cmd.exe parses .bat in OEM codepage).
REM ============================================================
setlocal

set "MODEL=%~1"
if "%MODEL%"=="" set "MODEL=D:\ninfer\models\Ternary-Bonsai-8B-TQ2_0.gguf"
set "PROMPT=%~2"
if "%PROMPT%"=="" set "PROMPT=17+25=?"

set "BIN=D:\ninfer\src\llama.cpp-prismml\build-cpu\bin\llama-cli.exe"
if not exist "%BIN%" (
  echo [ERR] llama-cli not found: "%BIN%"
  echo       run build-llama-cpp-cpu.bat first
  exit /b 1
)
if not exist "%MODEL%" (
  echo [ERR] model not found: "%MODEL%"
  exit /b 2
)

echo [model]  %MODEL%
echo [prompt] %PROMPT%
echo.

"%BIN%" -m "%MODEL%" -p "%PROMPT%" -n 64 -t 16 --no-warmup -no-cnv

echo.
echo [done] exit=%ERRORLEVEL%
