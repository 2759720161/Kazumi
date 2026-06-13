#!/bin/bash
# build_libass_ohos.sh - Cross-compile libass + fribidi for HarmonyOS NEXT
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

COMMON_FLAGS="-target aarch64-linux-ohos --sysroot=${SYSROOT_WIN} -D__MUSL__ -fPIC -O2 -I${INSTALL_PREFIX}/include -L${INSTALL_PREFIX}/lib -L${SYSROOT_LIB_WIN}"

echo "=== Building fribidi ==="
FRIBIDI_SRC="${PROJECT_NATIVE}/fribidi"
if [ ! -d "${FRIBIDI_SRC}" ]; then
    cd "${PROJECT_NATIVE}"
    git clone --depth 1 https://gh-proxy.com/https://github.com/fribidi/fribidi.git || \
    git clone --depth 1 https://github.com/fribidi/fribidi.git
fi

cd "${FRIBIDI_SRC}"
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
    -Ddocs=false \
    -Dtests=false

ninja -C build/ -j${JOBS}
ninja -C build/ install
echo "=== fribidi done ==="

echo "=== Building libass ==="
LIBASS_SRC="${PROJECT_NATIVE}/libass"
if [ ! -d "${LIBASS_SRC}" ]; then
    cd "${PROJECT_NATIVE}"
    git clone --depth 1 https://gh-proxy.com/https://github.com/libass/libass.git || \
    git clone --depth 1 https://github.com/libass/libass.git
fi

cd "${LIBASS_SRC}"
rm -rf build

export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${INSTALL_PREFIX}/lib/pkgconfig"

cat > ohos_cross.txt << CROSSFILE
[binaries]
c = '${CC_WRAPPER}'
ar = '${AR}'
nm = '${NM}'
ranlib = '${RANLIB}'
strip = '${STRIP}'
pkgconfig = '/usr/bin/pkg-config'

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
    -Dfontconfig=disabled \
    -Dasm=disabled \
    -Drequire-system-font-provider=false \
    -Dtest=disabled \
    -Dcompare=disabled \
    -Dprofile=disabled \
    -Dfuzz=disabled \
    -Dcheckasm=disabled \
    -Dlibunibreak=disabled

ninja -C build/ -j${JOBS}
ninja -C build/ install
echo "=== libass done ==="

echo "=== All deps built ==="
ls -la "${INSTALL_PREFIX}/lib/"