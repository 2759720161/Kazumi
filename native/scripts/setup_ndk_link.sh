#!/bin/bash
# Setup NDK symlink for WSL build
# The actual NDK is at: C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native

NDK_SRC="/mnt/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native"
NDK_LINK="$HOME/ohos_ndk"

echo "Creating NDK symlink..."
echo "  Source: $NDK_SRC"
echo "  Link:   $NDK_LINK"

if [ -d "$NDK_SRC" ]; then
    ln -snf "$NDK_SRC" "$NDK_LINK"
    echo "Symlink created successfully"
    echo "Verifying..."
    ls "$NDK_LINK/"
    echo "Clang version:"
    "$NDK_LINK/llvm/bin/clang.exe" --version 2>&1 | head -2
else
    echo "ERROR: NDK not found at $NDK_SRC"
    exit 1
fi