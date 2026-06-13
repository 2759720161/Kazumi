#!/bin/bash
FFMPEG_PREFIX="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg"
FFMPEG_SRC="/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg_ohos"
PKGD="${FFMPEG_PREFIX}/lib/pkgconfig"
mkdir -p "${PKGD}"

get_version() {
    local lib=$1
    local major=$(grep 'VERSION_MAJOR' "${FFMPEG_SRC}/${lib}/version_major.h" 2>/dev/null | grep -oP '\d+' || grep 'VERSION_MAJOR' "${FFMPEG_SRC}/${lib}/version.h" | head -1 | grep -oP '\d+')
    local minor=$(grep 'VERSION_MINOR' "${FFMPEG_SRC}/${lib}/version.h" | head -1 | grep -oP '\d+')
    local micro=$(grep 'VERSION_MICRO' "${FFMPEG_SRC}/${lib}/version.h" | head -1 | grep -oP '\d+')
    echo "${major}.${minor}.${micro}"
}

for lib in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    case $lib in
        libavutil)   name=avutil;   desc="FFmpeg utility library";   req="" ;;
        libswresample) name=swresample; desc="FFmpeg audio resampling library"; req="libavutil" ;;
        libswscale)  name=swscale;  desc="FFmpeg image scaling library";  req="libavutil" ;;
        libavcodec)  name=avcodec;  desc="FFmpeg codec library";  req="libavutil libswresample" ;;
        libavformat) name=avformat; desc="FFmpeg container format library"; req="libavcodec libswresample libavutil" ;;
        libavfilter) name=avfilter; desc="FFmpeg audio/video filtering library"; req="libavformat libavcodec libswresample libswscale libavutil" ;;
    esac

    ver=$(get_version $lib)
    
    cat > "${PKGD}/${lib}.pc" << EOF
prefix=${FFMPEG_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ${lib}
Description: ${desc}
Version: ${ver}
Requires: ${req}
Libs: -L\${libdir} -l${name}
Cflags: -I\${includedir}
EOF
    echo "${lib}: version ${ver}"
done

echo "Generated pkg-config files in ${PKGD}"
