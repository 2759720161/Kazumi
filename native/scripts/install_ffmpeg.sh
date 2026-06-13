#!/bin/bash
FFMPEG_SRC="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg"
INSTALL_PREFIX="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg"

mkdir -p "${INSTALL_PREFIX}/lib" "${INSTALL_PREFIX}/include"

for lib in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    if [ -f "${FFMPEG_SRC}/${lib}/${lib}.a" ]; then
        cp -v "${FFMPEG_SRC}/${lib}/${lib}.a" "${INSTALL_PREFIX}/lib/"
    fi
done

for dir in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    if [ -d "${FFMPEG_SRC}/${dir}/" ]; then
        for h in "${FFMPEG_SRC}/${dir}/"*.h; do
            [ -f "$h" ] && cp -v "$h" "${INSTALL_PREFIX}/include/"
        done
    fi
done

if [ -d "${FFMPEG_SRC}/compat/atomics/gcc/" ]; then
    cp -v "${FFMPEG_SRC}/compat/atomics/gcc/stdatomic.h" "${INSTALL_PREFIX}/include/" 2>/dev/null || true
fi

echo "Verifying installed libraries..."
ls -la "${INSTALL_PREFIX}/lib/"
echo "Verifying headers..."
ls "${INSTALL_PREFIX}/include/" | head -20
echo "=== FFmpeg install complete ==="