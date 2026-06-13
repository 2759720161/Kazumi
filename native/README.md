# Native Libraries for HarmonyOS NEXT

This directory contains pre-built native libraries (FFmpeg + libmpv) for the Kazumi player engine.

## Directory Structure

```
native/
├── ffmpeg/
│   ├── include/          # FFmpeg headers
│   └── lib/
│       └── aarch64-linux-ohos/   # FFmpeg shared libraries (.so)
├── mpv/
│   ├── include/
│   │   └── mpv/          # mpv client API headers
│   └── lib/
│       └── aarch64-linux-ohos/   # libmpv.so
└── scripts/
    ├── build_ffmpeg_ohos.sh    # FFmpeg cross-compile script
    ├── build_libmpv_ohos.sh    # libmpv cross-compile script
    ├── build_all_ohos.sh       # One-click build (Linux/WSL)
    └── build_native_wsl.bat    # Windows wrapper via WSL
```

## Build Instructions

### Prerequisites

1. **WSL2** (Windows) or Linux environment
2. **OHOS NDK** at `D:\APP\Huawei\OpenHarmony\Sdk\23\native` (Windows) or `/mnt/d/APP/Huawei/OpenHarmony/Sdk/23/native` (WSL)
3. Build tools: `git`, `make`, `nasm`/`yasm`, `pkg-config`, `meson`, `ninja-build`, `python3`

### Option A: Build from Windows (via WSL)

```cmd
cd D:\HarmonyOS\DevEcoStudioProjects\Kazumi\native\scripts
build_native_wsl.bat
```

### Option B: Build from WSL/Linux directly

```bash
cd /mnt/d/HarmonyOS/DevEcoStudioProjects/Kazumi/native/scripts
chmod +x build_all_ohos.sh
./build_all_ohos.sh
```

### Option C: Build individually

```bash
# Step 1: Build FFmpeg
./build_ffmpeg_ohos.sh /path/to/ohos/ndk /path/to/output/ffmpeg

# Step 2: Build libmpv (requires FFmpeg output)
./build_libmpv_ohos.sh /path/to/ohos/ndk /path/to/output/ffmpeg /path/to/output/mpv
```

## FFmpeg Configuration

The build enables only the codecs and protocols needed for anime streaming:
- **Decoders**: H.264, HEVC, AAC, Opus, FLAC, VP8, VP9, AV1, ASS/SRT subtitles
- **Demuxers**: Matroska (MKV), MOV (MP4), FLV, HLS
- **Protocols**: file, http, https, HLS
- **Filters**: aresample, scale
- **Disabled**: avdevice, postproc, debug, ffplay/ffprobe

## libmpv Configuration

- Built as shared library (`libmpv.so`) only
- No player binary (cplayer=false)
- No UI backends (GL, Vulkan, Wayland, X11 all disabled)
- No scripting (Lua, JavaScript disabled)
- No audio backends (PulseAudio, ALSA, JACK, WASAPI disabled)
- Render API enabled for XComponent surface rendering

## Integration

The NAPI bridge (`entry/src/main/cpp/mpv_napi.cpp`) links against these libraries.
`CMakeLists.txt` references them from this directory.

After building, the libraries are automatically picked up by the HarmonyOS build system
through the `externalNativeOptions` in `entry/build-profile.json5`.