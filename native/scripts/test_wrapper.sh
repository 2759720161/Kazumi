#!/bin/bash
# Test wrapper compilation for OHOS target
# IMPORTANT: Source files MUST be on /mnt/ (Windows fs) because clang.exe is a Windows binary

echo "=== Testing OHOS clang wrapper ==="

BUILD_TMPDIR="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/_build_tmp"
mkdir -p "$BUILD_TMPDIR"

# Test 1: Compile on Windows fs (/mnt/d) - this is the ONLY supported mode
echo "Test 1: Compile on Windows fs (/mnt/d)..."
echo 'int main(){return 0;}' > "$BUILD_TMPDIR/test_ohos.c"
if ~/kazumi_build/wrappers/ohos-clang -fPIC -c "$BUILD_TMPDIR/test_ohos.c" -o "$BUILD_TMPDIR/test_ohos.o" 2>&1; then
    echo "  Compile: OK"
    file "$BUILD_TMPDIR/test_ohos.o"
else
    echo "  Compile: FAILED"
    cat "$BUILD_TMPDIR/test_ohos.o" 2>/dev/null
    rm -f "$BUILD_TMPDIR/test_ohos.c" "$BUILD_TMPDIR/test_ohos.o"
    exit 1
fi

# Test 2: Compile with -I include path on /mnt/d
echo "Test 2: Compile with -I/mnt/d/... include path..."
mkdir -p "$BUILD_TMPDIR/test_inc"
echo 'int foo(){return 42;}' > "$BUILD_TMPDIR/test_inc/foo.h"
echo '#include "foo.h"
int main(){return foo();}' > "$BUILD_TMPDIR/test_inc_main.c"
if ~/kazumi_build/wrappers/ohos-clang -fPIC -I"$BUILD_TMPDIR/test_inc" -c "$BUILD_TMPDIR/test_inc_main.c" -o "$BUILD_TMPDIR/test_inc_main.o" 2>&1; then
    echo "  Compile with -I: OK"
    file "$BUILD_TMPDIR/test_inc_main.o"
else
    echo "  Compile with -I: FAILED"
fi
rm -rf "$BUILD_TMPDIR/test_inc" "$BUILD_TMPDIR/test_inc_main.c" "$BUILD_TMPDIR/test_inc_main.o"

# Test 3: Test llvm-ar.exe
echo "Test 3: Test llvm-ar..."
NDK="$HOME/ohos_ndk"
if "$NDK/llvm/bin/llvm-ar.exe" --version 2>&1 | head -1; then
    echo "  llvm-ar: OK"
else
    echo "  llvm-ar: FAILED"
fi

rm -f "$BUILD_TMPDIR/test_ohos.c" "$BUILD_TMPDIR/test_ohos.o"

echo "=== All wrapper tests complete ==="
