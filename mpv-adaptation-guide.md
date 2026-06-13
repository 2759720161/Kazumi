# mpv 播放器 SDK HarmonyOS NEXT 适配技术文档

> 项目：Kazumi - 动漫资源搜索播放应用（HarmonyOS NEXT 原生重写版）
> 文档版本：v2.0
> 最后更新：2026-06-12
> 目标平台：HarmonyOS NEXT (API 12+), aarch64, ArkTS + ArkUI

---

## 目录

1. [适配背景与目标平台环境说明](#1-适配背景与目标平台环境说明)
2. [依赖编译链与版本信息](#2-依赖编译链与版本信息)
3. [适配操作步骤与关键配置项解析](#3-适配操作步骤与关键配置项解析)
4. [适配过程中遇到的问题与解决方案](#4-适配过程中遇到的问题与解决方案)
5. [核心注意事项与后续维护建议](#5-核心注意事项与后续维护建议)
6. [当前适配状态总结](#6-当前适配状态总结)

---

## 1. 适配背景与目标平台环境说明

### 1.1 项目背景

上游 Kazumi 是一个基于 Flutter 的跨平台动漫资源搜索与播放应用，其 HarmonyOS 版本采用 Flutter 主体 + OHOS 壳的架构，并非原生 ArkTS 实现。当前项目将其完全重写为 HarmonyOS NEXT 纯血原生应用，使用 ArkTS + ArkUI 作为主体框架，视频播放核心则通过 NAPI 桥接 C/C++ 原生层的 mpv 播放引擎。

### 1.2 为什么选择 mpv

mpv 是一个轻量级、高可定制的开源媒体播放器，以 libmpv 库形式提供 C API，非常适合嵌入式和移动端场景。选择 mpv 的核心原因：

- **格式覆盖全面**：基于 FFmpeg 后端，支持几乎所有主流音视频编解码器
- **字幕渲染完整**：通过 libass 支持 ASS/SRT 等主流字幕格式，含复杂样式和特效
- **渲染管线灵活**：libmpv 提供 OpenGL/Vulkan 渲染回调，可对接任意图形后端
- **C API 稳定**：mpv/client.h 提供的客户端 API 向后兼容，适合长期维护
- **无 GUI 依赖**：纯库模式，不依赖任何窗口系统
- **OHOS 原生适配**：dex2oat/mpv 提供了 OHAudio 音频输出 + OHCodec 硬件解码的原生支持

### 1.3 目标平台环境

| 项目 | 值 |
|------|-----|
| 目标系统 | HarmonyOS NEXT (API 12+) |
| 目标架构 | aarch64 (arm64-v8a) |
| 应用框架 | ArkTS + ArkUI (声明式 UI) |
| 原生层语言 | C/C++ (NAPI 桥接) |
| NDK 路径 | C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native |
| 编译器 | clang/clang++ 15.0.4 (OHOS) |
| 编译器类型 | Windows 可执行文件（.exe），运行于 Windows 文件系统 |
| sysroot | C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\sysroot |
| C 标准库 | musl libc（需 -D__MUSL__ 宏定义） |
| 交叉编译宿主 | WSL2 (Ubuntu 26.04) + Windows NDK 工具链 |

### 1.4 交叉编译环境架构

OHOS NDK 的编译器是 Windows .exe 文件，但构建系统（make/meson/ninja）运行在 WSL2 中。所有源码和中间文件必须位于 Windows 文件系统（/mnt/d/...）上，因为 clang.exe 无法访问 WSL2 的 Linux 文件系统。

关键目录：
- NDK: ~/ohos_ndk (符号链接 → /mnt/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native)
- 项目: D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\ (含 FFmpeg_ohos/, mpv_ohos/, deps/, mpv_output/)
- WSL2: /mnt/d/... 映射到 Windows D: 盘，~/kazumi_build/wrappers/ 存放 wrapper 脚本

---

## 2. 依赖编译链与版本信息

### 2.1 完整依赖树

libmpv.so.2 (mpv v0.39.0 + dex2oat OHOS 适配) 依赖：
- FFmpeg 静态库（已链接进 libmpv.so.2）：libavcodec.a, libavformat.a, libavutil.a, libswresample.a, libswscale.a, libavfilter.a
- mbedTLS 静态库（已链接进 libmpv.so.2）：libmbedtls.a, libmbedx509.a, libmbedcrypto.a
- libass.a → libfreetype.a, libfribidi.a, libharfbuzz.a
- libplacebo.a → fast_float
- OHOS 系统库（动态链接）：libohaudio.so, libnative_media_*.so, libnative_window.so

### 2.2 版本与产物清单

| 依赖 | 版本 | 产物 | 大小（约） | 编译系统 |
|------|------|------|-----------|---------|
| FFmpeg | dex2oat/FFmpeg (dd2976b9) | 6 个静态库 | 各 1-10 MB | configure + make |
| mbedTLS | 3.6.4 | 3 个静态库 | 各 0.5-2 MB | cmake |
| freetype2 | v2.13.3 | libfreetype.a | ~800 KB | meson |
| fribidi | (latest) | libfribidi.a | ~200 KB | meson |
| harfbuzz | v10.2.0 | libharfbuzz.a | ~2 MB | meson |
| libass | v0.17.4 | libass.a | ~300 KB | meson |
| libplacebo | v7.349.0 | libplacebo.a | ~1.5 MB | meson |
| mpv | dex2oat/mpv (d974ee3) | **libmpv.so.2** | **33.8 MB** | meson + ninja |

### 2.3 自建 libmpv.so.2 产物详情

| 属性 | 值 |
|------|-----|
| 文件名 | libmpv.so.2.5.0 |
| 大小 | 33.8 MB |
| 格式 | ELF 64-bit LSB shared object, ARM aarch64 |
| SONAME | libmpv.so（已通过 set_soname.py 修改） |
| NEEDED 依赖 | libc.so, libohaudio.so, libnative_media_codecbase.so, libnative_media_core.so, libnative_media_vdec.so, libnative_window.so, libz.so |
| mpv C API 符号 | 54 个（含 23 个核心 API） |
| HTTPS/TLS | 已启用（ff_https_protocol, ff_tls_protocol 符号存在） |
| mbedTLS | 已静态链接（psa_crypto_init 等符号已解析） |

---

## 3. 适配操作步骤与关键配置项解析

### 3.1 交叉编译环境搭建

#### 3.1.1 WSL2 配置

在 WSL2 中启用 NTFS metadata 支持，否则 git clone 会因 chmod 失败而报错。在 /etc/wsl.conf 中添加：

```ini
[automount]
options = "metadata,umask=22,fmask=11"
```

修改后需重启 WSL：`wsl --shutdown`

#### 3.1.2 WSL2 工具安装

```bash
sudo apt install -y build-essential nasm yasm pkg-config meson ninja-build python3 python3-pip cmake
```

#### 3.1.3 NDK 符号链接

Windows NDK 路径含空格，需创建符号链接：
```bash
ln -s "/mnt/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native" ~/ohos_ndk
```

#### 3.1.4 目录结构准备

```bash
PROJECT_NATIVE=/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native
mkdir -p $PROJECT_NATIVE/{FFmpeg_ohos,mpv_ohos,deps,mpv_output,scripts,mbedtls}
mkdir -p ~/kazumi_build/wrappers
```

### 3.2 Clang Wrapper 脚本原理与实现

#### 3.2.1 为什么需要 Wrapper

OHOS NDK 的 clang.exe 是 Windows 可执行文件，但构建系统在 WSL2 中运行。存在两个核心问题：

1. **路径格式不兼容**：构建系统传递 /mnt/d/... 路径，但 clang.exe 只能理解 D:/... 路径
2. **目标三元组缺失**：每次调用 clang.exe 都必须附加 -target aarch64-linux-ohos --sysroot=... -D__MUSL__ 等参数

Wrapper 脚本自动完成路径转换和参数注入。

#### 3.2.2 Wrapper 生成器实现

文件路径：`native/scripts/gen_wrappers.py`

该 Python 脚本生成两个 bash wrapper 脚本（ohos-clang 和 ohos-clang++），核心逻辑：
- 遍历命令行参数，对 -I/mnt/*、-L/mnt/*、/mnt/* 路径通过 wslpath -w 转换为 Windows 格式
- 自动附加 -target aarch64-linux-ohos --sysroot=... -D__MUSL__ -L CRT路径
- **已添加 aarch64-linux-ohos/bits/ include 路径**（解决 alltypes.h 找不到问题）
- 通过 exec 替换当前进程，直接调用 clang.exe/clang++.exe

### 3.3 mbedTLS 交叉编译

文件路径：`native/scripts/build_mbedtls_ohos.sh`

mbedTLS 3.6.4 使用 CMake 构建，关键配置：
- `-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`：避免链接测试失败
- `git submodule update --init --recursive`：获取 framework 子模块
- OHOS sysroot 的 `bits/alltypes.h` 在 `aarch64-linux-ohos/bits/` 子目录下，需在 wrapper 中添加 include 路径
- Windows 路径中的空格导致 CMake toolchain 和 -L 参数解析失败，需用 wrapper 脚本方式

**FFmpeg 依赖 mbedTLS**：需在 FFmpeg configure 中添加 `--enable-mbedtls --enable-version3`

### 3.4 FFmpeg 交叉编译

文件路径：`native/scripts/build_ffmpeg_ohos.sh`

核心流程：设置 TMPDIR → 生成 wrapper → 克隆 dex2oat/FFmpeg → configure → make → 手动安装

关键 configure 选项：
- `--enable-cross-compile --target-os=linux --arch=aarch64`
- `--cc=wrapper --ar/nm/ranlib/strip=NDK工具`
- `--enable-static --disable-shared`
- `--enable-mbedtls --enable-version3`（HTTPS/TLS 支持）
- `--disable-vulkan`（OHOS sysroot 缺少 vulkan_beta.h）
- `--enable-ohcodec`（需手动修改 config.mak 去掉 `!` 前缀）

**OHCodec 支持的特殊处理**：
1. `CONFIG_OHCODEC` 在 config.mak 中默认为 `!CONFIG_OHCODEC=1`（禁用），需改为 `CONFIG_OHCODEC=1`
2. `hwcontext_oh.o` 需要手动编译并添加到 libavutil.a
3. `CONFIG_H264_OH_DECODER` 和 `CONFIG_HEVC_OH_DECODER` 需去掉 `!` 前缀
4. `codec_list.c` 需手动添加 OH 解码器注册
5. `config_components.h` 需修改 OH 解码器为 1
6. `ohcodec.o` 和 `ohdec.o` 不能用 LTO 编译（LTO 会导致符号被优化掉）

**HLS patch 集成**：
- 从 ErBWs 仓库获取 `ffmpeg-hls-kazumi-combined.patch`
- 手动应用到 `libavformat/hls.c`（10 个修改点，115 行新增）
- 包含 `seg_allow_img` 和 `hls_ad_filter` 两个功能

### 3.5 libmpv 交叉编译

文件路径：`native/scripts/build_libmpv_ohos.sh`

核心流程：生成 wrapper → 设置 PKG_CONFIG_PATH → 克隆 dex2oat/mpv → 生成 meson cross file → meson setup → ninja → 安装

**meson cross file 特殊配置**：
- c_args 额外包含各依赖的 include 路径
- c_link_args 使用 Windows 路径格式的 -L 参数
- **mbedTLS 静态库必须显式链接**：`-lmbedtls -lmbedx509 -lmbedcrypto`
- **正确的库链接顺序**：`-lavformat -lavcodec -lavfilter -lswresample -lswscale -lavutil -lmbedtls -lmbedx509 -lmbedcrypto`（依赖者在前，被依赖者在后）
- **不能使用 `--start-group/--end-group`**：meson 自己也会用这些标志，导致 nested group 错误

**mpv meson 关键选项**：
- `--default-library=shared`（产出 libmpv.so 而非 libmpv.a）
- `-Dohos=enabled -Degl-ohos=disabled`（P0 不启用 EGL，仅 OHCodec Surface 模式）
- 禁用所有平台相关输出：gl/egl/vulkan/wayland/x11/d3d11/cocoa/drm/gbm/...
- 禁用所有音频输出：pulse/alsa/jack/opensles/audiounit/wasapi/...（mpv 内置 ao_ohaudio）

**mpv 源码修改**：
- `vo_ohcodec.c` 文件不存在，需手动创建（OHCodec surface 模式 VO 驱动）
- `ohos_common.c` 中 `ohos_surface_size` 字段在 `#if HAVE_EGL_OHOS` 条件编译内，P0 禁用 egl-ohos 时需添加条件编译保护
- `ff_ohcodec_discard_buffer` 函数不存在，已改为 no-op

### 3.6 NAPI 桥接层与 ArkTS 引擎层

#### 3.6.1 项目文件布局

```
entry/src/main/cpp/
├── CMakeLists.txt
├── mpv_client_napi.cpp           # NAPI 注册
├── mpv_client_wrapper.cpp/h      # mpv client API wrapper
├── mpv_event_handler.cpp/h       # napi_threadsafe_function 事件驱动
├── ohos_surface_helper.cpp/h     # vo=ohcodec+surfaceId 设置
├── set_soname.py                 # Python 脚本：修改 ELF soname
├── fix_needed.py                 # Python 脚本：修改 NEEDED 引用
├── libs/arm64-v8a/
│   ├── libmpv.so                 # 自建 libmpv（33.8MB，soname=libmpv.so）
│   └── libc++_shared.so          # C++ 运行时
├── includes/mpv/                 # mpv 头文件
└── types/libmpv_napi.d.ts        # 类型声明
```

#### 3.6.2 CMakeLists.txt 关键配置

- 链接 libmpv.so（共享库，非静态库）
- ace_napi.z：HarmonyOS NAPI 运行时库
- libc++_shared.so：OHOS C++ 标准库
- `--disable-new-dtags` 和 RPATH 属性：清除 Windows RUNPATH

#### 3.6.3 NAPI 桥接层

暴露的 NAPI 接口：
| 函数名 | 功能 |
|--------|------|
| nativeCreate | 创建 mpv 实例 |
| nativeInitialize | 初始化 mpv 实例 |
| nativeCommand | 发送 mpv 命令 |
| nativeSetProperty | 设置属性 |
| nativeGetProperty | 获取属性 |
| nativeObserveProperty | 观察属性变化 |
| nativeDestroy | 销毁实例 |
| NativeOnEvent | 事件回调注册 |

**关键发现**：OHOS NAPI 的 `napi_create_threadsafe_function` 需要 11 个参数；`napi_tsfn_destroy` 不存在，应使用 `napi_tsfn_abort`。

#### 3.6.4 ArkTS 引擎层

- **MpvPlayerEngine.ets**：事件驱动 + 通用 API 模式
- **PlayerEngineFactory.ets**：mpv 优先，回退 AVPlayer
- **PlayerSurface.ets**：XComponent(SURFACE) 渲染视频
- **PlayerPage.ets**：播放页面 UI（含全屏切换、下一集功能）

---

## 4. 适配过程中遇到的问题与解决方案

### 问题 1：WSL2 + Windows NDK 交叉编译路径不兼容

**问题现象**：clang.exe 无法识别 /mnt/d/... 路径。

**解决方案**：创建 bash wrapper 脚本，自动将 /mnt/* 路径通过 wslpath -w 转换为 Windows 格式，并注入 -target aarch64-linux-ohos 等必要参数。

### 问题 2：Windows clang.exe 无法访问 Linux 文件系统

**问题现象**：clang.exe 无法访问 WSL2 原生文件系统（~/...、/tmp/...）。

**解决方案**：所有源码、构建输出、临时文件必须位于 Windows 文件系统上（即 /mnt/d/... 路径下）。TMPDIR 必须设置。

### 问题 3：HAP 打包 libmpv.so.2 对齐问题

**问题现象**：libmpv_napi.so 的 NEEDED 是 libmpv.so.2，但 HAP 只打包 .so 文件。

**解决方案**：用 Python 脚本 `set_soname.py` 将 libmpv.so 的 ELF soname 从 `libmpv.so.2` 改为 `libmpv.so`。

### 问题 4：PlayerSurface 异步时序错误

**问题现象**：loadEngineType() 是 async 但未 await，导致 initPlayer() 在引擎未就绪时被调用。

**解决方案**：onLoad 改为 async，await loadEngineType() 后再 initPlayer()。

### 问题 5：mpv 事件桥接未闭环

**问题现象**：handleMpvEvent() 没人调用，mpv 事件无法传递到 ArkTS 层。

**解决方案**：添加 mpv_wakeup_callback 注册，NativeOnEvent 导出。

### 问题 6：HLS patch 未集成

**问题现象**：FFmpeg 构建不包含 HLS 广告跳过和伪装图片分片处理。

**解决方案**：从 ErBWs 仓库获取 patch 手动应用到 hls.c（10 个修改点，115 行新增）。

### 问题 7：HTTPS 协议缺失

**问题现象**：FFmpeg 构建没有 TLS 后端，无法播放 HTTPS 视频。

**解决方案**：交叉编译 mbedTLS 3.6.4，FFmpeg 添加 `--enable-mbedtls --enable-version3`。

### 问题 8：psa_crypto_init 运行时未解析

**问题现象**：libmpv 链接时未包含 mbedTLS 静态库，导致运行时找不到 psa_crypto_init。

**解决方案**：meson cross file 中显式添加 `-lmbedtls -lmbedx509 -lmbedcrypto`。

### 问题 9：MPV_EVENT_PROPERTY_CHANGE 事件编号错误

**问题现象**：MpvPlayerEngine.ets 中 `MPV_EVENT_PROPERTY_CHANGE = 23`，但 mpv/client.h 定义为 22，导致 duration/time-pos 属性事件被丢弃，进度条无法工作。

**解决方案**：将 `MPV_EVENT_PROPERTY_CHANGE` 从 23 改为 22，并添加属性变更验证日志。

### 问题 10：OHCodec 解码器需要手动启用

**问题现象**：dex2oat/FFmpeg 的 configure 中没有 OHCODEC 选项，CONFIG_OHCODEC 通过 Makefile 条件编译控制，默认禁用。

**解决方案**：手动修改 config.mak（去掉 `!` 前缀）、codec_list.c（添加 OH 解码器注册）、config_components.h（修改为 1）。ohcodec.o 和 ohdec.o 不能用 LTO 编译。

### 问题 11：vo_ohcodec.c 文件不存在

**问题现象**：dex2oat/mpv 的 meson.build 引用了 vo_ohcodec.c，但文件不在仓库中。

**解决方案**：手动创建 vo_ohcodec.c（OHCodec surface 模式 VO 驱动）。

### 问题 12：libmpv_napi.so 的 Windows RUNPATH

**问题现象**：CMake 在 Windows 上构建时会给 .so 文件添加 Windows 路径的 RUNPATH，导致设备上加载失败。

**解决方案**：CMakeLists.txt 添加 `--disable-new-dtags` 和 RPATH 属性。

### 问题 13：OHOS NAPI API 差异

**问题现象**：多个 OHOS NAPI API 与标准 Node.js NAPI 不同。

**解决方案**：
- `napi_create_threadsafe_function` 需要 11 个参数
- `napi_tsfn_destroy` 不存在，使用 `napi_tsfn_abort`
- `DECLARE_NAPI_FUNCTION` 宏不存在，自定义
- `napi_module` 中 `nm_preferred_filename` 字段不存在
- `napi_define_properties` 只需 4 个参数

### 问题 14：ArkTS 严格模式限制

**问题现象**：ArkTS 严格模式有诸多限制。

**解决方案**：
- `globalThis` 不支持但仅 WARN 不 ERROR
- catch(err) 中 err 是 any 类型，需用 catch(_err) 避免
- 禁止解构声明
- `require` 不存在，需用 `globalThis.requireNapi`
- ForEach 回调内不允许条件渲染
- build() 内不能用 const/let

---

## 5. 核心注意事项与后续维护建议

### 5.1 核心注意事项

1. **所有文件必须在 NTFS 上**：源码、构建输出、临时文件都必须在 /mnt/d/... 路径下
2. **TMPDIR 必须设置**：在运行任何构建脚本前，确保 TMPDIR 指向 NTFS 上的目录
3. **mpv 事件编号必须与头文件一致**：MPV_EVENT_PROPERTY_CHANGE = 22（不是 23）
4. **mbedTLS 必须显式链接进 libmpv.so**：在 meson cross file 的 c_link_args 中添加
5. **OHCodec 解码器需要手动启用**：修改 config.mak/codec_list.c/config_components.h
6. **ohcodec.o/ohdec.o 不能用 LTO 编译**：LTO 会导致符号被优化掉
7. **FFmpeg 以静态库链接进 libmpv.so.2**：HAP 中不包含独立的 libav*.so 文件
8. **libmpv.so 的 SONAME 必须修改**：用 set_soname.py 将 soname 从 libmpv.so.2 改为 libmpv.so
9. **-D__MUSL__ 宏定义**：OHOS 使用 musl libc，此宏必须在所有编译步骤中保持一致
10. **ArkTS 严格模式**：catch(_err)、禁止解构声明、ForEach 内无条件渲染等

### 5.2 后续维护建议

1. **版本升级策略**：FFmpeg 跟随 dex2oat/FFmpeg 上游；mpv 跟随 dex2oat/mpv 上游
2. **CI/CD 自动化**：将交叉编译脚本集成到 CI 流水线
3. **播放页 UI 完善**：全屏横屏模式、弹幕支持、外挂字幕
4. **性能优化**：OHCodec 硬件解码已启用，后续可探索 AV1 硬解
5. **稳定性**：长时间播放测试、内存泄漏检测

---

## 6. 当前适配状态总结

| 阶段 | 状态 | 说明 |
|------|------|------|
| Phase A：预编译库验证 | ✅ 已完成 | ErBWs release 下载、校验、验证通过，M1 决策：Go |
| Phase B：自建构建流水线 | ✅ 已完成 | FFmpeg+mbedTLS+libmpv 构建成功，libmpv.so.2.5.0 (33.8MB) |
| Phase C：NAPI 桥接层重构 | ✅ 已完成 | 事件驱动 + ctxId + 加锁 context map |
| Phase D：ArkTS 引擎层适配 | ✅ 已完成 | MpvPlayerEngine + PlayerEngineFactory + PlayerSurface |
| P0 运行时修复 | ✅ 已完成 | HAP 打包/异步时序/事件桥接/HLS patch/HTTPS/mbedTLS 链接 |
| P1 修复 | ✅ 已完成 | hwdec=ohcodec/事件属性填充/RUNPATH 清除 |
| MPV_EVENT_PROPERTY_CHANGE 修复 | ✅ 已完成 | 事件编号从 23 改为 22 |
| 播放页 UI 功能增强 | 🔄 进行中 | 全屏横屏切换、下一集按钮、自动下一集 |
| Phase E：集成验证 | ⬜ 待开始 | 端到端稳定性测试 |

---

## 附录 A：关键文件路径索引

| 文件 | 绝对路径 |
|------|---------|
| FFmpeg 编译脚本 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\scripts\build_ffmpeg_ohos.sh |
| libmpv 编译脚本 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\scripts\build_libmpv_ohos.sh |
| mbedTLS 编译脚本 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\scripts\build_mbedtls_ohos.sh |
| 一键构建脚本 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\scripts\build_all_ohos.sh |
| Wrapper 生成器 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\scripts\gen_wrappers.py |
| CMakeLists.txt | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\CMakeLists.txt |
| NAPI 桥接代码 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\mpv_client_napi.cpp |
| mpv client wrapper | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\mpv_client_wrapper.cpp |
| mpv event handler | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\mpv_event_handler.cpp |
| ohos surface helper | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\ohos_surface_helper.cpp |
| set_soname.py | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\set_soname.py |
| fix_needed.py | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\fix_needed.py |
| MpvPlayerEngine | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\ets\core\player\MpvPlayerEngine.ets |
| PlayerPage | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\ets\pages\player\PlayerPage.ets |
| libmpv.so | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\entry\src\main\cpp\libs\arm64-v8a\libmpv.so |
| FFmpeg 安装输出 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\ffmpeg\ |
| 依赖安装输出 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\deps\ |
| libmpv 安装输出 | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\mpv_output\ |
| HLS patch | D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\patches\ffmpeg-hls-kazumi-combined.patch |

## 附录 B：环境变量速查

```bash
export TMPDIR=/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/_build_tmp
export PKG_CONFIG_PATH=/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg/lib/pkgconfig:/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/deps/lib/pkgconfig
export PKG_CONFIG_LIBDIR=/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/ffmpeg/lib/pkgconfig:/mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/deps/lib/pkgconfig
```

## 附录 C：快速构建命令序列

1. `python3 /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts/gen_wrappers.py`
2. `bash /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts/build_mbedtls_ohos.sh`
3. `bash /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts/build_ffmpeg_ohos.sh`
4. 编译字幕依赖链（freetype2 → fribidi → harfbuzz → libass）
5. 编译 libplacebo
6. `bash /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts/build_libmpv_ohos.sh`
7. 复制产物到 DevEco Studio 项目
8. 运行 set_soname.py 修改 ELF soname
9. DevEco Studio 构建 HAP
