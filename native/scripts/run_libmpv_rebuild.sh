#!/bin/bash
set -euo pipefail

cd /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi
mkdir -p native/build_logs

exec bash native/scripts/build_libmpv_ohos.sh \
    ~/ohos_ndk \
    /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg \
    /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/deps \
    /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/mpv_output
