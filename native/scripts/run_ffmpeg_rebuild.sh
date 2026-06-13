#!/bin/bash
set -euo pipefail

cd /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi
mkdir -p native/build_logs

exec bash native/scripts/build_ffmpeg_ohos.sh \
    ~/ohos_ndk \
    /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg
