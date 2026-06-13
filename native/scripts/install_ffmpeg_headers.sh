#!/bin/bash
FFMPEG_SRC="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg"
INSTALL_PREFIX="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg"

# Remove flat headers
rm -rf "${INSTALL_PREFIX}/include"

# Install with proper subdirectory structure
for dir in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    if [ -d "${FFMPEG_SRC}/${dir}/" ]; then
        mkdir -p "${INSTALL_PREFIX}/include/${dir}"
        # Only copy public headers (not _internal or _priv)
        for h in "${FFMPEG_SRC}/${dir}/"*.h; do
            base=$(basename "$h")
            case "$base" in
                *_internal.h|*_priv.h|*internal.h|cpu_internal.h|*tablegen*) continue ;;
            esac
            cp -v "$h" "${INSTALL_PREFIX}/include/${dir}/"
        done
    fi
done

# Also copy compat stdatomic.h
mkdir -p "${INSTALL_PREFIX}/include/compat/atomics/gcc"
cp -v "${FFMPEG_SRC}/compat/atomics/gcc/stdatomic.h" "${INSTALL_PREFIX}/include/compat/atomics/gcc/" 2>/dev/null || true

echo "Header structure:"
for dir in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    echo "${dir}: $(ls ${INSTALL_PREFIX}/include/${dir}/ | wc -l) files"
done