#!/bin/bash
SRC="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native"
DST="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/entry/src/main/cpp/includes"

cp -rv ${SRC}/mpv_output/include/mpv/* ${DST}/mpv/
cp -rv ${SRC}/ffmpeg/include/libavutil/* ${DST}/libavutil/
cp -rv ${SRC}/ffmpeg/include/libavcodec/* ${DST}/libavcodec/
cp -rv ${SRC}/ffmpeg/include/libavformat/* ${DST}/libavformat/
cp -rv ${SRC}/ffmpeg/include/libswresample/* ${DST}/libswresample/
cp -rv ${SRC}/ffmpeg/include/libswscale/* ${DST}/libswscale/
cp -rv ${SRC}/ffmpeg/include/libavfilter/* ${DST}/libavfilter/
cp -rv ${SRC}/deps/include/libplacebo/* ${DST}/libplacebo/
cp -rv ${SRC}/deps/include/ass/* ${DST}/ass/
cp -rv ${SRC}/deps/include/freetype2/* ${DST}/freetype2/
cp -rv ${SRC}/deps/include/harfbuzz/* ${DST}/harfbuzz/
cp -rv ${SRC}/deps/include/fribidi/* ${DST}/fribidi/

echo "=== Headers copied ==="
for d in mpv libavutil libavcodec libavformat libswresample libswscale libavfilter libplacebo ass freetype2 harfbuzz fribidi; do
    echo "$d: $(ls ${DST}/$d/ | wc -l) files"
done