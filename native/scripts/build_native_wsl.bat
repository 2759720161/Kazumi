@echo off
REM build_native_wsl.bat - Build FFmpeg + libmpv via WSL
REM Run this from Windows command line
REM
REM Prerequisites:
REM   - WSL2 installed and configured
REM   - Build tools in WSL: git, make, nasm, pkg-config, meson, ninja
REM   - OHOS NDK accessible from WSL via ~/ohos_ndk symlink

setlocal

set SCRIPT_DIR=%~dp0
set WSL_SCRIPT_DIR=/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts
set OHOS_NDK=~/ohos_ndk

echo ==========================================
echo  Building FFmpeg + libmpv via WSL
echo ==========================================
echo.
echo WSL script dir: %WSL_SCRIPT_DIR%
echo OHOS NDK: %OHOS_NDK%
echo.

REM Check WSL is available
wsl --list --quiet >nul 2>&1
if errorlevel 1 (
    echo ERROR: WSL is not installed or not available
    echo Please install WSL2 first: https://learn.microsoft.com/en-us/windows/wsl/install
    exit /b 1
)

REM Install build dependencies if needed
echo Checking WSL build dependencies...
wsl -e bash -c "sudo apt-get update && sudo apt-get install -y build-essential git nasm yasm pkg-config meson ninja-build python3"

echo.
echo Starting build...
wsl -e bash -c "cd '%WSL_SCRIPT_DIR%' && chmod +x build_all_ohos.sh && bash build_all_ohos.sh '%OHOS_NDK%'"

if errorlevel 1 (
    echo.
    echo ERROR: Build failed!
    exit /b 1
)

echo.
echo ==========================================
echo  Build completed successfully!
echo ==========================================
echo.
echo Output is in: %SCRIPT_DIR%..\ffmpeg\ and %SCRIPT_DIR%..\mpv\
echo.
echo Next: Rebuild the HarmonyOS project in DevEco Studio
echo.

endlocal