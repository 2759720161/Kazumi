#!/bin/bash
# build_freetype_ohos.sh - Cross-compile freetype2 for HarmonyOS NEXT
set -euo pipefail

OHOS_NDK="${1:-/mnt/d/APP/Huawei/OpenHarmony/Sdk/23/native}"
INSTALL_PREFIX="${2:-/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/deps}"
JOBS=$(nproc)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NATIVE="${SCRIPT_DIR}/.."

WRAPPER_DIR="$HOME/kazumi_build/wrappers"
CC_WRAPPER="${WRAPPER_DIR}/ohos-clang"
CXX_WRAPPER="${WRAPPER_DIR}/ohos-clang++"

wsl_to_win() { wslpath -w "$1" 2>/dev/null || echo "$1"; }
OHOS_NDK_WIN=$(wsl_to_win "${OHOS_NDK}")
SYSROOT_WIN=$(wsl_to_win "${OHOS_NDK}/sysroot")
SYSROOT_LIB_WIN=$(wsl_to_win "${OHOS_NDK}/sysroot/usr/lib/aarch64-linux-ohos")

AR="${OHOS_NDK}/llvm/bin/llvm-ar.exe"
NM="${OHOS_NDK}/llvm/bin/llvm-nm.exe"
RANLIB="${OHOS_NDK}/llvm/bin/llvm-ranlib.exe"
STRIP="${OHOS_NDK}/llvm/bin/llvm-strip.exe"

echo "=== Building freetype2 ==="
FT_SRC="${PROJECT_NATIVE}/freetype2"
if [ ! -d "${FT_SRC}" ]; then
    cd "${PROJECT_NATIVE}"
    git clone --branch VER-2-13-3 --depth 1 https://gh-proxy.com/https://github.com/freetype/freetype.git freetype2 || \
    git clone --branch VER-2-13-3 --depth 1 https://github.com/freetype/freetype.git freetype2
fi

cd "${FT_SRC}"
rm -rf build

cat > ohos_cross.txt << CROSSFILE
[binaries]
c = '${CC_WRAPPER}'
ar = '${AR}'
nm = '${NM}'
ranlib = '${RANLIB}'
strip = '${STRIP}'

[built-in options]
c_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${INSTALL_PREFIX}/include']
c_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${INSTALL_PREFIX}/lib', '-L${SYSROOT_LIB_WIN}', '-lm', '-lc']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
CROSSFILE

meson setup build/ \
    --cross-file ohos_cross.txt \
    --prefix="${INSTALL_PREFIX}" \
    --default-library=static \
    -Dzlib=disabled \
    -Dbzip2=disabled \
    -Dpng=disabled \
    -Dharfbuzz=disabled \
    -Dbrotli=disabled

ninja -C build/ -j${JOBS}
ninja -C build/ install
echo "=== freetype2 done ==="
ls -la "${INSTALL_PREFIX}/lib/libfreetype.a"