@echo off
REM ============================================================
REM  build-llama-cpp-cpu.bat
REM  Build llama.cpp on Windows with MSVC + Ninja (CPU only, no CUDA Toolkit).
REM
REM  Usage:
REM    build-llama-cpp-cpu.bat [source dir] [build subdir] [jobs]
REM
REM  Defaults:
REM    source  D:\ninfer\src\llama.cpp-prismml
REM    build   build-cpu
REM    jobs    16
REM
REM  Requires:
REM    VS BuildTools with VCTools + VC.CMake.Project
REM    (CMake and Ninja ship inside VS, no separate install needed)
REM
REM  NOTE: keep this file ASCII-only. cmd.exe parses .bat in the OEM codepage,
REM        and non-ASCII bytes in comments can break command parsing.
REM ============================================================
setlocal

set "SRC=%~1"
if "%SRC%"=="" set "SRC=D:\ninfer\src\llama.cpp-prismml"
set "BUILD=%~2"
if "%BUILD%"=="" set "BUILD=build-cpu"
set "JOBS=%~3"
if "%JOBS%"=="" set "JOBS=16"

if not exist "%SRC%\CMakeLists.txt" (
  echo [ERR] source dir not found: "%SRC%"
  echo       clone the repo first, or pass the path as the 1st argument
  exit /b 1
)

set "VSWHERE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo [ERR] vswhere not found - VS BuildTools is not installed
  exit /b 2
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if "%VSPATH%"=="" (
  echo [ERR] VS found but the C++ toolchain is missing - add the VCTools workload
  exit /b 2
)
echo [info] VS at "%VSPATH%"

call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 (
  echo [ERR] vcvars64.bat failed
  exit /b 3
)

set "CMAKE=%VSPATH%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set "NINJA=%VSPATH%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
if not exist "%CMAKE%" (
  echo [ERR] cmake not found in VS - add the VC.CMake.Project component
  exit /b 4
)
set "PATH=%NINJA%;%PATH%"

echo [1/2] configure
"%CMAKE%" -S "%SRC%" -B "%SRC%\%BUILD%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DGGML_CUDA=OFF ^
  -DGGML_NATIVE=ON ^
  -DLLAMA_BUILD_TESTS=OFF ^
  -DLLAMA_BUILD_EXAMPLES=ON ^
  -DLLAMA_BUILD_SERVER=ON ^
  -DLLAMA_CURL=OFF
if errorlevel 1 (
  echo [ERR] configure failed
  exit /b 5
)

echo [2/2] build with %JOBS% jobs
"%CMAKE%" --build "%SRC%\%BUILD%" -j %JOBS%
if errorlevel 1 (
  echo [ERR] build failed
  exit /b 6
)

echo.
echo [OK] binaries in "%SRC%\%BUILD%\bin\"
if exist "%SRC%\%BUILD%\bin\llama-cli.exe" echo      llama-cli.exe    OK
if exist "%SRC%\%BUILD%\bin\llama-server.exe" echo      llama-server.exe OK
exit /b 0
