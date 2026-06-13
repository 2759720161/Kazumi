#!/bin/bash
# build_libmpv_ohos.sh - Cross-compile libmpv for HarmonyOS NEXT (aarch64)
# Run in WSL with NTFS metadata enabled
#
# Prerequisites: FFmpeg already built, meson, ninja, pkg-config
#
# Usage:
#   ./build_libmpv_ohos.sh [OHOS_NDK_PATH] [FFMPEG_PREFIX] [INSTALL_PREFIX]

set -euo pipefail

OHOS_NDK="${1:-$HOME/ohos_ndk}"
FFMPEG_PREFIX="${2:-/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg}"
DEPS_PREFIX="${3:-/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/deps}"
INSTALL_PREFIX="${4:-/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/mpv_output}"
JOBS=$(nproc)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NATIVE="${SCRIPT_DIR}/.."
MPV_SRC="${PROJECT_NATIVE}/mpv_ohos"

WRAPPER_DIR="$HOME/kazumi_build/wrappers"
mkdir -p "${WRAPPER_DIR}"

wsl_to_win() { wslpath -w "$1" 2>/dev/null || echo "$1"; }

OHOS_NDK_WIN=$(wsl_to_win "${OHOS_NDK}")
SYSROOT_WIN=$(wsl_to_win "${OHOS_NDK}/sysroot")
SYSROOT_LIB_WIN=$(wsl_to_win "${OHOS_NDK}/sysroot/usr/lib/aarch64-linux-ohos")
FFMPEG_WIN=$(wsl_to_win "${FFMPEG_PREFIX}")
DEPS_WIN=$(wsl_to_win "${DEPS_PREFIX}")

echo "=== libmpv Cross-Compile for HarmonyOS NEXT ==="
echo "NDK (Win):     ${OHOS_NDK_WIN}"
echo "Sysroot (Win): ${SYSROOT_WIN}"
echo "FFmpeg:        ${FFMPEG_PREFIX}"
echo "mpv src:       ${MPV_SRC}"
echo "Install:       ${INSTALL_PREFIX}"
echo "Jobs:          ${JOBS}"

[ ! -d "${OHOS_NDK}" ] && { echo "ERROR: NDK not found"; exit 1; }
[ ! -d "${FFMPEG_PREFIX}/lib" ] && { echo "ERROR: FFmpeg not found at ${FFMPEG_PREFIX} - run build_ffmpeg_ohos.sh first"; exit 1; }

# Generate wrapper scripts (same as FFmpeg build)
python3 "${SCRIPT_DIR}/gen_wrappers.py"

CC_WRAPPER="${WRAPPER_DIR}/ohos-clang"
CXX_WRAPPER="${WRAPPER_DIR}/ohos-clang++"

export PKG_CONFIG_PATH="${FFMPEG_PREFIX}/lib/pkgconfig:${DEPS_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${FFMPEG_PREFIX}/lib/pkgconfig:${DEPS_PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_SYSROOT_DIR

if [ ! -d "${MPV_SRC}" ]; then
    echo "Cloning mpv..."
    cd "${PROJECT_NATIVE}"
    git clone --branch v0.39.0 --depth 1 https://gh-proxy.com/https://github.com/mpv-player/mpv.git || \
    git clone --branch v0.39.0 --depth 1 https://kkgithub.com/mpv-player/mpv.git || \
    git clone --branch v0.39.0 --depth 1 https://github.com/mpv-player/mpv.git
fi

cd "${MPV_SRC}"

AR_PATH="${WRAPPER_DIR}/ohos-ar"
NM_PATH="${WRAPPER_DIR}/ohos-nm"
RANLIB_PATH="${WRAPPER_DIR}/ohos-ranlib"
STRIP_PATH="${WRAPPER_DIR}/ohos-strip"
PKG_CONFIG_BIN=$(which pkg-config)

echo "Creating meson cross file..."

cat > ohos_cross.txt << CROSSFILE
[binaries]
c = '${CC_WRAPPER}'
cpp = '${CXX_WRAPPER}'
ar = '${AR_PATH}'
nm = '${NM_PATH}'
ranlib = '${RANLIB_PATH}'
strip = '${STRIP_PATH}'
pkg-config = '${PKG_CONFIG_BIN}'

[built-in options]
c_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${FFMPEG_PREFIX}/include', '-I${DEPS_PREFIX}/include', '-I${DEPS_PREFIX}/include/freetype2']
c_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${FFMPEG_WIN}\\lib', '-L${DEPS_WIN}\\lib', '-L${SYSROOT_LIB_WIN}', '-lavformat', '-lavcodec', '-lavfilter', '-lswresample', '-lswscale', '-lavutil', '-lmbedtls', '-lmbedx509', '-lmbedcrypto', '-lm', '-lc', '-lpthread']
cpp_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${FFMPEG_PREFIX}/include', '-I${DEPS_PREFIX}/include', '-I${DEPS_PREFIX}/include/freetype2']
cpp_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${FFMPEG_WIN}\\lib', '-L${DEPS_WIN}\\lib', '-L${SYSROOT_LIB_WIN}', '-lavformat', '-lavcodec', '-lavfilter', '-lswresample', '-lswscale', '-lavutil', '-lmbedtls', '-lmbedx509', '-lmbedcrypto', '-lm', '-lc', '-lpthread']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
CROSSFILE

echo "Cross file contents:"
cat ohos_cross.txt

echo "Configuring mpv with meson..."

rm -rf build/
meson setup build/ \
    --cross-file ohos_cross.txt \
    --prefix="${INSTALL_PREFIX}" \
    --default-library=shared \
    -Dlibmpv=true \
    -Dcplayer=false \
    -Dbuild-date=false \
    -Dohos=enabled \
    -Degl-ohos=disabled \
    -Dgl=disabled \
    -Degl=disabled \
    -Degl-android=disabled \
    -Degl-angle=disabled \
    -Dvulkan=disabled \
    -Dwayland=disabled \
    -Ddmabuf-wayland=disabled \
    -Dx11=disabled \
    -Dd3d11=disabled \
    -Dd3d-hwaccel=disabled \
    -Ddirect3d=disabled \
    -Dcocoa=disabled \
    -Ddrm=disabled \
    -Dgbm=disabled \
    -Dcaca=disabled \
    -Dsixel=disabled \
    -Dvapoursynth=disabled \
    -Dlua=disabled \
    -Djavascript=disabled \
    -Dsdl2-audio=disabled \
    -Dsdl2-video=disabled \
    -Dsdl2-gamepad=disabled \
    -Dsndio=disabled \
    -Dpulse=disabled \
    -Dalsa=disabled \
    -Djack=disabled \
    -Dopensles=disabled \
    -Daudiounit=disabled \
    -Dcoreaudio=disabled \
    -Dwasapi=disabled \
    -Ddvdnav=disabled \
    -Dcdda=disabled \
    -Duchardet=disabled \
    -Drubberband=disabled \
    -Dlcms2=disabled \
    -Dzimg=disabled \
    -Dvdpau=disabled \
    -Dvaapi=disabled \
    -Dlibavdevice=disabled \
    -Diconv=disabled \
    -Djpeg=disabled \
    -Dlibarchive=disabled \
    -Dlibbluray=disabled

echo "Building mpv..."
ninja -C build/ -j${JOBS}

echo "Installing mpv..."
ninja -C build/ install

echo "Copying headers..."
mkdir -p "${INSTALL_PREFIX}/include/mpv"
cp libmpv/mpv/client.h "${INSTALL_PREFIX}/include/mpv/client.h" 2>/dev/null || true
cp libmpv/mpv/render.h "${INSTALL_PREFIX}/include/mpv/render.h" 2>/dev/null || true
cp libmpv/mpv/render_gl.h "${INSTALL_PREFIX}/include/mpv/render_gl.h" 2>/dev/null || true
cp libmpv/mpv/stream_cb.h "${INSTALL_PREFIX}/include/mpv/stream_cb.h" 2>/dev/null || true

echo "=== libmpv build complete ==="
ls -la "${INSTALL_PREFIX}/lib/"
ls -la "${INSTALL_PREFIX}/include/mpv/"
