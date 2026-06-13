#!/usr/bin/env python3
"""Generate FFmpeg pkg-config files with correct library version numbers."""
import os
import re

FFMPEG_PREFIX = "/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg"
FFMPEG_SRC = "/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg"
PKGD = os.path.join(FFMPEG_PREFIX, "lib", "pkgconfig")

os.makedirs(PKGD, exist_ok=True)

def get_version(lib):
    major = None
    minor = None
    micro = None
    
    vmaj_path = os.path.join(FFMPEG_SRC, lib, "version_major.h")
    v_path = os.path.join(FFMPEG_SRC, lib, "version.h")
    
    for path in [vmaj_path, v_path]:
        if not os.path.exists(path):
            continue
        with open(path, 'r') as f:
            for line in f:
                m = re.search(r'LIB[A-Z]+_VERSION_MAJOR\s+(\d+)', line)
                if m and major is None:
                    major = m.group(1)
                m = re.search(r'LIB[A-Z]+_VERSION_MINOR\s+(\d+)', line)
                if m and minor is None:
                    minor = m.group(1)
                m = re.search(r'LIB[A-Z]+_VERSION_MICRO\s+(\d+)', line)
                if m and micro is None:
                    micro = m.group(1)
    
    return f"{major or 0}.{minor or 0}.{micro or 0}"

libs = [
    ("libavutil", "avutil", "FFmpeg utility library", ""),
    ("libswresample", "swresample", "FFmpeg audio resampling library", "libavutil"),
    ("libswscale", "swscale", "FFmpeg image scaling library", "libavutil"),
    ("libavcodec", "avcodec", "FFmpeg codec library", "libavutil libswresample"),
    ("libavformat", "avformat", "FFmpeg container format library", "libavcodec libswresample libavutil"),
    ("libavfilter", "avfilter", "FFmpeg audio/video filtering library", "libavformat libavcodec libswresample libswscale libavutil"),
]

for lib, name, desc, req in libs:
    ver = get_version(lib)
    pc = f"""prefix={FFMPEG_PREFIX}
exec_prefix=${{prefix}}
libdir=${{prefix}}/lib
includedir=${{prefix}}/include

Name: {lib}
Description: {desc}
Version: {ver}
Requires: {req}
Libs: -L${{libdir}} -l{name}
Cflags: -I${{includedir}}
"""
    pc_path = os.path.join(PKGD, f"{lib}.pc")
    with open(pc_path, 'w') as f:
        f.write(pc)
    print(f"{lib}: version {ver}")

print(f"Generated pkg-config files in {PKGD}")