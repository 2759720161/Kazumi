#!/usr/bin/env python3
import re, os

src = "/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/FFmpeg_ohos"
prefix = "/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg"
pkgd = os.path.join(prefix, "lib", "pkgconfig")
os.makedirs(pkgd, exist_ok=True)

libs = {
    "libavutil": ("avutil", ""),
    "libswresample": ("swresample", "libavutil"),
    "libswscale": ("swscale", "libavutil"),
    "libavcodec": ("avcodec", "libavutil libswresample"),
    "libavformat": ("avformat", "libavcodec libswresample libavutil"),
    "libavfilter": ("avfilter", "libavformat libavcodec libswresample libswscale libavutil"),
}

for lib, (name, req) in libs.items():
    suffix = lib[3:].upper()
    vmh = os.path.join(src, lib, "version_major.h")
    vh = os.path.join(src, lib, "version.h")
    major = minor = micro = "0"
    if os.path.exists(vmh):
        txt = open(vmh).read()
        m = re.search(r"LIB" + suffix + r"_VERSION_MAJOR\s+(\d+)", txt)
        if m:
            major = m.group(1)
    if os.path.exists(vh):
        txt = open(vh).read()
        if major == "0":
            m = re.search(r"LIB" + suffix + r"_VERSION_MAJOR\s+(\d+)", txt)
            if m:
                major = m.group(1)
        m = re.search(r"LIB" + suffix + r"_VERSION_MINOR\s+(\d+)", txt)
        if m:
            minor = m.group(1)
        m = re.search(r"LIB" + suffix + r"_VERSION_MICRO\s+(\d+)", txt)
        if m:
            micro = m.group(1)
    ver = f"{major}.{minor}.{micro}"
    pc = f"""prefix={prefix}
exec_prefix=${{prefix}}
libdir=${{prefix}}/lib
includedir=${{prefix}}/include

Name: {lib}
Description: FFmpeg {name} library
Version: {ver}
Requires: {req}
Libs: -L${{libdir}} -l{name}
Cflags: -I${{includedir}}
"""
    with open(os.path.join(pkgd, f"{lib}.pc"), "w") as f:
        f.write(pc)
    print(f"{lib}: {ver}")