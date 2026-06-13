#!/bin/bash
set -euo pipefail

cd /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi
mkdir -p native/build_logs
rm -f native/build_logs/libmpv_rebuild_wsl.log native/build_logs/libmpv_rebuild_wsl.pid

nohup bash native/scripts/run_libmpv_rebuild.sh \
    > native/build_logs/libmpv_rebuild_wsl.log \
    2>&1 \
    < /dev/null &

echo $! > native/build_logs/libmpv_rebuild_wsl.pid
cat native/build_logs/libmpv_rebuild_wsl.pid
