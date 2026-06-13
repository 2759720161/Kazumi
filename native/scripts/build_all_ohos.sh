#!/bin/bash
# build_all_ohos.sh - One-click build FFmpeg + libmpv for HarmonyOS NEXT
# Run in WSL environment
#
# IMPORTANT: Source code is cloned and built in ~/kazumi_build/ (Linux filesystem)
# to avoid NTFS permission issues. Only final .so/.h are copied to project dir.
#
# Prerequisites:
#   - WSL2 Ubuntu
#   - Build tools: git, make, nasm/yasm, pkg-config, meson, ninja
#   - OHOS NDK at ~/ohos_ndk (symlink to DevEco Studio SDK)
#
# Usage:
#   ./build_all_ohos.sh [OHOS_NDK_PATH]
#
# Output:
#   native/ffmpeg/ - FFmpeg libraries and headers
#   native/mpv/    - libmpv library and headers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OHOS_NDK="${1:-$HOME/ohos_ndk}"
PROJECT_NATIVE="${SCRIPT_DIR}/.."

FFMPEG_PREFIX="${PROJECT_NATIVE}/ffmpeg"
MPV_PREFIX="${PROJECT_NATIVE}/mpv_output"

echo "=========================================="
echo " Build FFmpeg + libmpv for HarmonyOS NEXT"
echo " (WSL + Windows NDK Toolchain)"
echo ""
echo " Source code: ~/kazumi_build/ (Linux fs)"
echo " Output:      native/ffmpeg/ + native/mpv/"
echo "=========================================="
echo "OHOS NDK: ${OHOS_NDK}"
echo "FFmpeg output: ${FFMPEG_PREFIX}"
echo "mpv output: ${MPV_PREFIX}"
echo ""

echo "[1/3] Building FFmpeg..."
bash "${SCRIPT_DIR}/build_ffmpeg_ohos.sh" "${OHOS_NDK}" "${FFMPEG_PREFIX}"

echo ""
echo "[2/3] Building libmpv..."
bash "${SCRIPT_DIR}/build_libmpv_ohos.sh" "${OHOS_NDK}" "${FFMPEG_PREFIX}" "${MPV_PREFIX}"

echo ""
echo "[3/3] Organizing output for project..."

mkdir -p "${PROJECT_NATIVE}/ffmpeg/lib/aarch64-linux-ohos"
mkdir -p "${PROJECT_NATIVE}/ffmpeg/include"
mkdir -p "${PROJECT_NATIVE}/mpv/lib/aarch64-linux-ohos"
mkdir -p "${PROJECT_NATIVE}/mpv/include"

if [ -d "${FFMPEG_PREFIX}/lib" ]; then
    cp -v ${FFMPEG_PREFIX}/lib/*.so* "${PROJECT_NATIVE}/ffmpeg/lib/aarch64-linux-ohos/" 2>/dev/null || true
    cp -rv ${FFMPEG_PREFIX}/include/* "${PROJECT_NATIVE}/ffmpeg/include/" 2>/dev/null || true
fi

if [ -d "${MPV_PREFIX}/lib" ]; then
    cp -v ${MPV_PREFIX}/lib/*.so* "${PROJECT_NATIVE}/mpv/lib/aarch64-linux-ohos/" 2>/dev/null || true
    cp -rv ${MPV_PREFIX}/include/* "${PROJECT_NATIVE}/mpv/include/" 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo " Build Complete!"
echo "=========================================="
echo ""
echo "FFmpeg libraries:"
ls -1 "${PROJECT_NATIVE}/ffmpeg/lib/aarch64-linux-ohos/" 2>/dev/null || echo "  (none)"
echo ""
echo "mpv libraries:"
ls -1 "${PROJECT_NATIVE}/mpv/lib/aarch64-linux-ohos/" 2>/dev/null || echo "  (none)"
echo ""
echo "Next steps:"
echo "  1. Edit entry/build-profile.json5 to add externalNativeOptions"
echo "  2. Build the HarmonyOS project with DevEco Studio"
echo "  3. The CMakeLists.txt in entry/src/main/cpp/ will link these libraries"
