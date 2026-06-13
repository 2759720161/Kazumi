#!/usr/bin/env python3
"""Patch mpv meson.build to make libplacebo optional for OHOS build."""
import re

MESON_PATH = "/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/mpv/meson.build"

with open(MESON_PATH, 'r') as f:
    content = f.read()

# 1. Make libplacebo optional
content = content.replace(
    "libplacebo = dependency('libplacebo', version: '>=6.338.2',\n"
    "                default_options: ['default_library=static', 'demos=false'])",
    "libplacebo = dependency('libplacebo', version: '>=6.338.2',\n"
    "                default_options: ['default_library=static', 'demos=false'],\n"
    "                required: get_option('libplacebo'))"
)

# 2. Make libass optional
content = content.replace(
    "libass = dependency('libass', version: '>= 0.12.2')",
    "libass = dependency('libass', version: '>= 0.12.2', required: get_option('libass'))"
)

# 3. Conditional dependencies list
content = content.replace(
    "dependencies = [libass,\n"
    "                libavcodec,\n"
    "                libavfilter,\n"
    "                libavformat,\n"
    "                libavutil,\n"
    "                libplacebo,\n"
    "                libswresample,\n"
    "                libswscale]",
    "dependencies = [libavcodec,\n"
    "                libavfilter,\n"
    "                libavformat,\n"
    "                libavutil,\n"
    "                libswresample,\n"
    "                libswscale]\n"
    "if libass.found()\n"
    "    dependencies += libass\n"
    "endif\n"
    "if libplacebo.found()\n"
    "    dependencies += libplacebo\n"
    "endif"
)

# 4. Conditional features
content = content.replace(
    "    'libass': true,\n"
    "    'libplacebo': true,",
    "    'libass': libass.found(),\n"
    "    'libplacebo': libplacebo.found(),"
)

# 5. Conditional libplacebo sources
content = content.replace(
    "    ## libplacebo\n"
    "    'video/out/placebo/ra_pl.c',\n"
    "    'video/out/placebo/utils.c',\n"
    "    'video/out/vo_gpu_next.c',\n"
    "    'video/out/gpu_next/context.c',",
    "    ## libplacebo (conditional - skipped if not found)"
)

# 6. Fix vulkan check to handle missing libplacebo
content = content.replace(
    "vulkan_opt = get_option('vulkan').require(\n"
    "    libplacebo.get_variable('pl_has_vulkan', default_value: '0') == '1',\n"
    "    error_message: 'libplacebo compiled without vulkan support!',\n"
    ")",
    "vulkan_opt = get_option('vulkan').require(\n"
    "    libplacebo.found() and libplacebo.get_variable('pl_has_vulkan', default_value: '0') == '1',\n"
    "    error_message: 'libplacebo not found or compiled without vulkan support!',\n"
    ")"
)

with open(MESON_PATH, 'w') as f:
    f.write(content)

print("Patched meson.build: libplacebo and libass are now optional")