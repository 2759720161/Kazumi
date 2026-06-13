#!/bin/bash
# Fix pkg-config version numbers for FFmpeg
FFMPEG_PREFIX="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg"
FFMPEG_SRC="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg_ohos"
PKGD="${FFMPEG_PREFIX}/lib/pkgconfig"

get_version() {
    local lib=$1
    local major=$(grep "LIB${lib^^}_VERSION_MAJOR" "${FFMPEG_SRC}/${lib}/version.h" 2>/dev/null | head -1 | grep -oP '\d+')
    local minor=$(grep "LIB${lib^^}_VERSION_MINOR" "${FFMPEG_SRC}/${lib}/version.h" 2>/dev/null | head -1 | grep -oP '\d+')
    local micro=$(grep "LIB${lib^^}_VERSION_MICRO" "${FFMPEG_SRC}/${lib}/version.h" 2>/dev/null | head -1 | grep -oP '\d+')
    echo "${major}.${minor}.${micro}"
}

for lib in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    case $lib in
        libavutil) name=avutil; req="" ;;
        libswresample) name=swresample; req="libavutil" ;;
        libswscale) name=swscale; req="libavutil" ;;
        libavcodec) name=avcodec; req="libavutil libswresample" ;;
        libavformat) name=avformat; req="libavcodec libswresample libavutil" ;;
        libavfilter) name=avfilter; req="libavformat libavcodec libswresample libswscale libavutil" ;;
    esac
    ver=$(get_version $lib)
    cat > "${PKGD}/${lib}.pc" << EOF
prefix=${FFMPEG_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ${lib}
Description: FFmpeg ${name} library
Version: ${ver}
Requires: ${req}
Libs: -L\${libdir} -l${name}
Cflags: -I\${includedir}
EOF
    echo "${lib}: version ${ver}"
done