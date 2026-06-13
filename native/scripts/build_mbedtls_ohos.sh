#!/bin/bash
# build_mbedtls_ohos.sh - Cross-compile mbedTLS for HarmonyOS NEXT (aarch64)
# Run in WSL
set -euo pipefail

OHOS_NDK="${1:-$HOME/ohos_ndk}"
OHOS_NDK_REAL=$(readlink -f "${OHOS_NDK}" 2>/dev/null || echo "${OHOS_NDK}")
INSTALL_PREFIX="${2:-/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/deps}"
MBEDTLS_VERSION="3.6.4"
JOBS=$(nproc)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NATIVE="${SCRIPT_DIR}/.."
MBEDTLS_SRC="${PROJECT_NATIVE}/mbedtls"

echo "=== mbedTLS Cross-Compile for HarmonyOS NEXT ==="
echo "NDK:           ${OHOS_NDK}"
echo "Install:       ${INSTALL_PREFIX}"
echo "mbedTLS src:   ${MBEDTLS_SRC}"
echo "Version:       ${MBEDTLS_VERSION}"

if [ ! -d "${OHOS_NDK}" ]; then
    echo "ERROR: NDK not found at ${OHOS_NDK}"
    exit 1
fi

if [ ! -d "${MBEDTLS_SRC}" ]; then
    echo "Cloning mbedTLS ${MBEDTLS_VERSION}..."
    cd "${PROJECT_NATIVE}"
    git clone --depth 1 --branch "v${MBEDTLS_VERSION}" https://github.com/Mbed-TLS/mbedtls.git mbedtls || \
    git clone --depth 1 --branch "v${MBEDTLS_VERSION}" https://gh-proxy.com/https://github.com/Mbed-TLS/mbedtls.git mbedtls
fi

cd "${MBEDTLS_SRC}"

BUILD_DIR="${MBEDTLS_SRC}/_build_ohos"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

TOOLCHAIN_FILE="${BUILD_DIR}/ohos-toolchain.cmake"

WRAPPER_DIR="$HOME/kazumi_build/wrappers"
mkdir -p "${WRAPPER_DIR}"
python3 "${SCRIPT_DIR}/gen_wrappers.py"

CC_WRAPPER="${WRAPPER_DIR}/ohos-clang"
CXX_WRAPPER="${WRAPPER_DIR}/ohos-clang++"

echo "Testing wrapper..."
echo 'int main(){return 0;}' > "${BUILD_DIR}/_test.c"
if "${CC_WRAPPER}" -fPIC -c "${BUILD_DIR}/_test.c" -o "${BUILD_DIR}/_test.o" 2>&1; then
    file "${BUILD_DIR}/_test.o"
    rm -f "${BUILD_DIR}/_test.c" "${BUILD_DIR}/_test.o"
    echo "Wrapper test PASSED"
else
    rm -f "${BUILD_DIR}/_test.c" "${BUILD_DIR}/_test.o"
    echo "Wrapper test FAILED"
    exit 1
fi

cat > "${TOOLCHAIN_FILE}" << 'TOOLCHAIN_EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
TOOLCHAIN_EOF

echo "Configuring mbedTLS..."
SYSROOT="${OHOS_NDK}/sysroot"
EXTRA_CFLAGS="--target=aarch64-linux-ohos --sysroot=${SYSROOT} -fPIC -D__MUSL__=1"

cmake -S "${MBEDTLS_SRC}" -B "${BUILD_DIR}" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${CC_WRAPPER}" \
    -DCMAKE_CXX_COMPILER="${CXX_WRAPPER}" \
    -DCMAKE_AR="${WRAPPER_DIR}/ohos-ar" \
    -DCMAKE_RANLIB="${WRAPPER_DIR}/ohos-ranlib" \
    -DCMAKE_C_FLAGS="${EXTRA_CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${EXTRA_CFLAGS}" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DENABLE_PROGRAMS=OFF \
    -DENABLE_TESTING=OFF \
    -DMBEDTLS_FATAL_WARNINGS=OFF \
    -DLINK_WITH_PTHREAD=OFF \
    -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    -DUSE_STATIC_MBEDTLS_LIBRARY=ON

echo "Building mbedTLS..."
cmake --build "${BUILD_DIR}" -j${JOBS}

echo "Installing mbedTLS..."
cmake --install "${BUILD_DIR}"

echo "Verifying..."
ls -la "${INSTALL_PREFIX}/lib/libmbed"* 2>/dev/null || echo "WARNING: No mbedtls libs found"
ls -la "${INSTALL_PREFIX}/include/mbedtls/" 2>/dev/null | head -5

echo "=== mbedTLS build complete ==="