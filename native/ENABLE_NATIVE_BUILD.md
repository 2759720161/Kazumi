# 启用Native构建指南

当FFmpeg和libmpv交叉编译完成后，需要修改 `entry/build-profile.json5` 启用CMake构建。

## 步骤

### 1. 编译Native库（在WSL中）

```bash
cd /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts
chmod +x build_all_ohos.sh
./build_all_ohos.sh
```

### 2. 启用CMake构建

编辑 `entry/build-profile.json5`，在 `buildOption` 中添加 `externalNativeOptions`：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
    "resOptions": {
      "copyCodeResource": {
        "enable": false
      }
    },
    "externalNativeOptions": {
      "path": "./src/main/cpp/CMakeLists.txt",
      "arguments": "",
      "cppFlags": "",
      "targets": [
        "arm64-v8a"
      ]
    }
  },
  ...
}
```

### 3. 重新构建项目

在DevEco Studio中重新构建项目，CMake将自动编译 `mpv_napi.cpp` 并链接libmpv/FFmpeg。

### 4. 验证

- 检查 `entry/build/default/intermediates/cmake/default/arm64-v8a/` 下是否有 `libmpv_napi.so`
- 在SettingsPage中选择"mpv"引擎
- 播放视频时检查日志中是否有 "mpv_napi native module loaded successfully"