#!/bin/bash
# build_harfbuzz_ohos.sh - Cross-compile harfbuzz for HarmonyOS NEXT
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

echo "=== Building harfbuzz ==="
HB_SRC="${PROJECT_NATIVE}/harfbuzz"
if [ ! -d "${HB_SRC}" ]; then
    cd "${PROJECT_NATIVE}"
    git clone --branch 10.2.0 --depth 1 https://gh-proxy.com/https://github.com/harfbuzz/harfbuzz.git || \
    git clone --branch 10.2.0 --depth 1 https://github.com/harfbuzz/harfbuzz.git
fi

cd "${HB_SRC}"
rm -rf build

export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${INSTALL_PREFIX}/lib/pkgconfig"

cat > ohos_cross.txt << CROSSFILE
[binaries]
c = '${CC_WRAPPER}'
cpp = '${CXX_WRAPPER}'
ar = '${AR}'
nm = '${NM}'
ranlib = '${RANLIB}'
strip = '${STRIP}'
pkgconfig = '/usr/bin/pkg-config'

[built-in options]
c_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${INSTALL_PREFIX}/include']
c_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${INSTALL_PREFIX}/lib', '-L${SYSROOT_LIB_WIN}', '-lm', '-lc']
cpp_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${INSTALL_PREFIX}/include', '-std=c++17']
cpp_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${INSTALL_PREFIX}/lib', '-L${SYSROOT_LIB_WIN}', '-lm', '-lc']

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
    -Dtests=disabled \
    -Dcairo=disabled \
    -Dgobject=disabled \
    -Dglib=disabled \
    -Dfreetype=disabled \
    -Dicu=disabled \
    -Ddocs=disabled \
    -Dbenchmark=disabled

ninja -C build/ -j${JOBS}
ninja -C build/ install
echo "=== harfbuzz done ==="
ls -la "${INSTALL_PREFIX}/lib/libharfbuzz.a"