#!/bin/bash
set -euo pipefail

FFMPEG_SRC="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg_ohos"
CC_WRAPPER="/home/ljb/kazumi_build/wrappers/ohos-clang"
AR="/home/ljb/ohos_ndk/llvm/bin/llvm-ar.exe"
INSTALL_LIB="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg/lib"

cd "${FFMPEG_SRC}"

echo "Recompiling ohcodec.o and ohdec.o without LTO..."
"${CC_WRAPPER}" -fPIC -O2 -c -I. -Ilibavcodec -Ilibavutil -o libavcodec/ohcodec.o libavcodec/ohcodec.c
"${CC_WRAPPER}" -fPIC -O2 -c -I. -Ilibavcodec -Ilibavutil -o libavcodec/ohdec.o libavcodec/ohdec.c

echo "Updating libavcodec.a..."
cp libavcodec/libavcodec.a libavcodec/libavcodec.a.bak
"${AR}" rcs libavcodec/libavcodec.a libavcodec/ohcodec.o libavcodec/ohdec.o

echo "Copying to install dir..."
cp libavcodec/libavcodec.a "${INSTALL_LIB}/"

echo "Verifying symbols..."
nm libavcodec/ohdec.o | grep -E "discard_buffer|ff_h264_oh|ff_hevc_oh" | head -10
nm libavcodec/ohcodec.o | grep -E "ff_h264_oh|ff_hevc_oh" | head -10

echo "Done!"