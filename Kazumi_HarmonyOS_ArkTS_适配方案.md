# Kazumi 纯鸿蒙原生 ArkTS 重构适配方案（修正版）

## 1. 项目背景

Kazumi 当前已有 HarmonyOS NEXT 适配分支，但该分支本质上仍是基于 Flutter-ohos 生态运行，并通过 `media_kit` / `media_kit_video` / `media_kit_libs_ohos` 间接获得 mpv 播放能力。

本方案的目标不是在现有 Flutter-ohos 项目上继续修补，而是规划一个新的纯鸿蒙原生版本：

```text
ArkTS + ArkUI
  + 原生 Web 嗅探
  + 原生数据存储
  + 原生 AVPlayer 基础播放器
  + 可选 NDK/NAPI/libmpv 高级播放器
```

需要明确的是：

1. ErBWs/Kazumi 可参考其 HarmonyOS 适配经验、播放器参数配置、WebView 嗅探逻辑、窗口/全屏/音量桥接思路。
2. ErBWs/Kazumi 不能被视为现成的 ArkTS + NAPI + libmpv 原生播放器底座。
3. 纯 ArkTS 版应作为新工程或新分支并行开发，不建议直接替换当前 Flutter-ohos 版本。

---

## 2. 重构目标

### 2.1 核心目标

| 目标 | 说明 |
|---|---|
| 原生化 | 使用 ArkTS / ArkUI 重写 UI、状态、路由和业务层 |
| 业务闭环 | 实现搜索、详情、剧集列表、视频嗅探、基础播放、收藏、历史 |
| 平台融合 | 适配 HarmonyOS NEXT、折叠屏、平板、鸿蒙 PC、多窗 |
| 播放器可扩展 | 先用 AVPlayer 跑通基础播放，再独立攻坚 mpv |
| 长期可维护 | 将解析引擎、播放器引擎、UI 层解耦 |

### 2.2 非目标

第一阶段不追求一次性完整复刻 Flutter-ohos 版全部能力。

以下功能后置：

- mpv 完整移植；
- Anime4K；
- ASS/SSA 外挂字幕；
- 复杂播放器截图；
- DLNA；
- WebDAV；
- 同步播放；
- 实况窗；
- 服务卡片；
- 鸿蒙 PC 深度优化；
- 完整下载器。

---

## 3. 当前 Kazumi 实现认知修正

### 3.1 当前 HarmonyOS 分支并非纯 ArkTS 原生

当前 HarmonyOS 分支入口仍然是 FlutterAbility：

```text
EntryAbility extends FlutterAbility
```

它通过 Flutter 插件体系注册平台能力，并没有直接提供一个可复用的 ArkTS 原生播放器框架。

### 3.2 当前 mpv 能力来源

当前 Kazumi 的 mpv 能力主要来自：

```text
Dart / Flutter
  ↓
media_kit Player
  ↓
media_kit_video VideoController
  ↓
media_kit_libs_ohos
  ↓
底层 native player / mpv
```

项目自身在 Dart 层负责：

- 构造播放参数；
- 传入视频 URL；
- 设置 headers；
- 设置代理；
- 设置缓存；
- 设置硬解参数；
- 下发 mpv property；
- 下发 mpv command；
- 切换 Anime4K shader；
- 获取播放状态；
- 截图。

项目没有自己实现：

- libmpv 交叉编译脚本；
- NAPI 播放器桥；
- XComponent 渲染；
- EGLContext 管理；
- mpv render thread；
- mpv event thread。

因此，纯 ArkTS 版若要保留 mpv，需要重新做播放器内核工程。

---

## 4. 总体技术路线

采用“双播放器引擎”路线。

```text
ArkTS UI
  ↓
IPlayerEngine 抽象接口
  ├── AvPlayerEngine：基础播放，优先落地
  └── MpvPlayerEngine：高级播放，独立攻坚
```

### 4.1 第一阶段：AVPlayer MVP

先使用 HarmonyOS 原生 AVPlayer 实现基础播放链路。

目标：

- m3u8 播放；
- mp4 播放；
- 播放 / 暂停；
- seek；
- 倍速；
- 基础音量；
- 播放进度；
- 播放错误提示；
- WebView 嗅探到视频地址后直接播放。

### 4.2 第二阶段：mpv 高级播放器

在业务链路稳定后，单独开发 mpv native 模块。

目标：

- libmpv 交叉编译；
- NAPI 封装；
- XComponent surface 渲染；
- OpenGL/EGL 上下文；
- 自定义 headers；
- 代理；
- 大缓存；
- 外挂字幕；
- Anime4K；
- 截图；
- 播放器日志；
- 复杂 m3u8 兼容。

---

## 5. 架构设计

### 5.1 应用总体架构

```text
Kazumi-HarmonyOS/
├── AppScope/
│   └── app.json5
├── entry/
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/
│   │   │   ├── pages/
│   │   │   ├── components/
│   │   │   ├── core/
│   │   │   │   ├── engine/
│   │   │   │   ├── player/
│   │   │   │   ├── sniffer/
│   │   │   │   └── danmaku/
│   │   │   ├── models/
│   │   │   ├── network/
│   │   │   ├── store/
│   │   │   └── utils/
│   │   ├── cpp/
│   │   │   └── mpv/
│   │   ├── resources/
│   │   └── module.json5
│   ├── oh-package.json5
│   └── build-profile.json5
└── build-profile.json5
```

### 5.2 分层说明

| 层级 | 目录 | 职责 |
|---|---|---|
| UI 层 | `pages/`, `components/` | 首页、详情页、播放页、设置页、规则管理页 |
| 业务层 | `core/` | 解析、嗅探、播放器控制、弹幕调度 |
| 数据层 | `models/`, `store/` | 数据模型、本地数据库、设置项 |
| 网络层 | `network/` | HTTP 请求、headers、cookie、代理 |
| Native 层 | `cpp/mpv/` | libmpv、EGL、XComponent、NAPI |

---

## 6. 核心模块设计

## 6.1 解析引擎

### 6.1.1 目标

将 Kazumi 现有插件规则系统迁移到 ArkTS。

核心能力：

- 规则源管理；
- 搜索 URL 构造；
- GET / POST 请求；
- 自定义 headers；
- User-Agent；
- Referer；
- Cookie；
- HTML 解析；
- XPath 提取；
- 正则辅助；
- 反爬检测；
- 剧集列表解析。

### 6.1.2 建议接口

```ts
export interface RuleModel {
  api: string
  type: string
  name: string
  version: string
  baseUrl: string
  searchUrl: string
  searchList: string
  searchName: string
  searchResult: string
  chapterRoads: string
  chapterResult: string
  userAgent: string
  referer: string
  usePost: boolean
  useWebview: boolean
  useLegacyParser: boolean
  adBlocker: boolean
}

export interface SearchItem {
  name: string
  src: string
}

export interface Road {
  name: string
  data: string[]
  identifier: string[]
}
```

### 6.1.3 解析流程

```text
用户输入关键词
  ↓
RuleParser 构造搜索 URL
  ↓
HttpClient 请求 HTML
  ↓
HTML Parser 生成 DOM
  ↓
XPath 提取搜索结果
  ↓
用户选择番剧
  ↓
请求详情页 HTML
  ↓
XPath 提取剧集线路和剧集 URL
```

### 6.1.4 风险点

| 风险 | 说明 | 处理 |
|---|---|---|
| ArkTS HTML/XPath 库不稳定 | ohpm 生态成熟度不如 Dart/npm | 阶段 0 必须做 POC |
| 站点反爬 | 搜索页可能返回验证码 | 加入反爬检测和 WebView 验证入口 |
| 编码问题 | 部分站点非 UTF-8 | HTTP 层需支持 charset 处理 |
| Cookie 问题 | 部分站点依赖 Cookie | 建立 RuleCookieManager |

---

## 6.2 WebView 视频嗅探

### 6.2.1 修正原则

不能只依赖 `onInterceptRequest`。

Kazumi 当前 Flutter-ohos 实现并不是单纯请求拦截，而是通过 JS 注入监听：

- iframe；
- video 标签；
- source 标签；
- fetch；
- XHR；
- Response.text；
- M3U8 内容。

ArkTS 版本应采用组合方案：

```text
Web 组件请求拦截
  + JS 注入
  + JSBridge 回传
  + URL 过滤
  + 超时控制
  + 取消机制
```

### 6.2.2 嗅探架构

```text
VideoSniffer
  ├── HiddenWebHost
  ├── RequestInterceptor
  ├── JSInjector
  ├── CandidateUrlFilter
  ├── TimeoutController
  └── SnifferResult
```

### 6.2.3 嗅探流程

```text
加载剧集播放页
  ↓
注入 JS
  ↓
监听 iframe/video/source/fetch/XHR
  ↓
发现 m3u8/mp4/blob 相关请求
  ↓
过滤广告和无效 URL
  ↓
回传真实视频 URL
  ↓
交给播放器引擎
```

### 6.2.4 JS 注入方向

```js
// 伪代码：监听 video 标签
const observer = new MutationObserver(() => {
  document.querySelectorAll('video').forEach(video => {
    const src = video.getAttribute('src')
    if (src && !src.startsWith('blob:')) {
      bridge.postMessage(src)
    }

    video.querySelectorAll('source').forEach(source => {
      const sourceSrc = source.getAttribute('src')
      if (sourceSrc) {
        bridge.postMessage(sourceSrc)
      }
    })
  })
})

// 伪代码：监听 XHR
const rawOpen = XMLHttpRequest.prototype.open
XMLHttpRequest.prototype.open = function (...args) {
  this.addEventListener('load', () => {
    try {
      if (this.responseText && this.responseText.trim().startsWith('#EXTM3U')) {
        bridge.postMessage(args[1])
      }
    } catch (_) {}
  })
  return rawOpen.apply(this, args)
}
```

---

## 6.3 播放器抽象层

### 6.3.1 播放器接口

```ts
export interface PlaybackOptions {
  headers?: Record<string, string>
  startPositionMs?: number
  referer?: string
  userAgent?: string
  proxy?: string
  adBlocker?: boolean
  isLocalFile?: boolean
}

export interface PlayerState {
  playing: boolean
  buffering: boolean
  positionMs: number
  durationMs: number
  bufferMs: number
  completed: boolean
}

export interface IPlayerEngine {
  prepare(url: string, options?: PlaybackOptions): Promise<void>
  play(): Promise<void>
  pause(): Promise<void>
  stop(): Promise<void>
  seek(positionMs: number): Promise<void>
  setSpeed(speed: number): Promise<void>
  setVolume(volume: number): Promise<void>
  getState(): PlayerState
  release(): Promise<void>
}
```

### 6.3.2 AVPlayerEngine

用于 MVP。

职责：

- 快速验证播放链路；
- 支持基础 m3u8/mp4；
- 支持基础播放控制；
- 支持基础错误回调；
- 支持播放进度同步。

限制：

- Anime4K 不支持；
- ASS/SSA 字幕能力有限；
- 复杂 m3u8 兼容性需验证；
- headers / referer / proxy 支持要逐项实测；
- 截图能力需另行设计。

### 6.3.3 MpvPlayerEngine

用于高级播放器。

职责：

- 使用 NAPI 调用 C++ mpv core；
- 使用 XComponent 承载画面；
- 使用 mpv render API 渲染；
- 支持高级播放参数；
- 支持 Anime4K；
- 支持外挂字幕；
- 支持复杂 m3u8；
- 支持截图；
- 支持日志。

---

## 7. mpv 原生底座方案

## 7.1 mpv 架构

```text
Player.ets
  ↓
MpvPlayer.ts
  ↓
NAPI Bridge
  ↓
MpvCore.cpp
  ├── mpv_handle
  ├── mpv_render_context
  ├── EGLDisplay
  ├── EGLContext
  ├── EGLSurface
  ├── Render Thread
  ├── Event Thread
  └── Thread-safe Callback
  ↓
XComponent Surface
```

## 7.2 C++ 模块结构

```text
entry/src/main/cpp/mpv/
├── include/
│   ├── mpv_core.h
│   ├── mpv_render.h
│   ├── mpv_event_loop.h
│   └── napi_mpv_bridge.h
├── src/
│   ├── mpv_core.cpp
│   ├── mpv_render.cpp
│   ├── mpv_event_loop.cpp
│   └── napi_mpv_bridge.cpp
├── third_party/
│   ├── include/
│   └── libs/
└── CMakeLists.txt
```

## 7.3 NAPI 暴露接口

ArkTS 侧建议只调用稳定 API，不直接暴露 mpv 细节。

```ts
export class MpvPlayer {
  create(surfaceId: string): Promise<void>
  load(url: string, options?: PlaybackOptions): Promise<void>
  play(): Promise<void>
  pause(): Promise<void>
  stop(): Promise<void>
  seek(positionMs: number): Promise<void>
  setSpeed(speed: number): Promise<void>
  setVolume(volume: number): Promise<void>
  setProperty(name: string, value: string): Promise<void>
  command(args: string[]): Promise<void>
  setShader(paths: string[]): Promise<void>
  clearShader(): Promise<void>
  addSubtitle(path: string): Promise<void>
  screenshot(): Promise<ArrayBuffer>
  destroy(): Promise<void>
}
```

## 7.4 线程模型

### 7.4.1 UI Thread

负责：

- ArkUI 页面；
- 控制栏；
- 手势；
- 状态展示；
- XComponent 生命周期。

禁止：

- 阻塞等待 mpv；
- 执行长耗时 native 调用；
- 直接处理视频帧。

### 7.4.2 NAPI Thread

负责：

- 参数校验；
- Promise 封装；
- 调用 C++ player core；
- 创建线程安全回调。

禁止：

- 跑 `mpv_wait_event`；
- 跑渲染循环。

### 7.4.3 Event Thread

负责：

```cpp
while (running) {
  mpv_event* event = mpv_wait_event(mpv, timeout);
  dispatchEvent(event);
}
```

监听：

- duration；
- time-pos；
- pause；
- eof-reached；
- cache-buffering-state；
- video-params；
- error。

### 7.4.4 Render Thread

负责：

- EGL 初始化；
- EGLSurface 创建；
- `eglMakeCurrent`；
- `mpv_render_context_render`；
- `eglSwapBuffers`；
- surface resize；
- surface destroy；
- context recovery。

## 7.5 XComponent 生命周期

必须处理：

| 生命周期 | 处理 |
|---|---|
| onLoad | 获取 surfaceId，创建 native player |
| onSurfaceCreated | 创建 NativeWindow / EGLSurface |
| onSurfaceChanged | 更新 mpv render size |
| onSurfaceDestroyed | 暂停渲染，释放 EGLSurface |
| 页面退出 | destroy mpv，释放线程 |
| 横竖屏切换 | resize + render context 更新 |
| 后台进入前台 | 恢复 surface / EGL |
| 多窗变化 | resize + UI 重排 |

常见问题：

- 黑屏；
- 有声音无画面；
- 旋转后画面卡死；
- 返回页面崩溃；
- 多次进入播放器内存泄漏；
- 后台恢复 EGL context 丢失。

## 7.6 mpv 初始化伪代码

```cpp
mpv_handle* mpv = mpv_create();

mpv_set_option_string(mpv, "terminal", "no");
mpv_set_option_string(mpv, "msg-level", "all=v");
mpv_set_option_string(mpv, "vo", "libmpv");
mpv_set_option_string(mpv, "hwdec", "auto-safe");

int ret = mpv_initialize(mpv);
if (ret < 0) {
  // 初始化失败
}
```

## 7.7 OpenGL render context 伪代码

```cpp
mpv_opengl_init_params glInitParams = {
  .get_proc_address = [](void*, const char* name) {
    return reinterpret_cast<void*>(eglGetProcAddress(name));
  }
};

mpv_render_param params[] = {
  { MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL) },
  { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInitParams },
  { MPV_RENDER_PARAM_INVALID, nullptr }
};

mpv_render_context_create(&renderContext, mpv, params);
```

## 7.8 渲染伪代码

```cpp
void renderFrame() {
  eglMakeCurrent(display, surface, surface, context);

  int width = surfaceWidth;
  int height = surfaceHeight;
  int fbo = 0;

  mpv_opengl_fbo mpfbo {
    .fbo = fbo,
    .w = width,
    .h = height,
    .internal_format = 0
  };

  int flipY = 1;

  mpv_render_param params[] = {
    { MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo },
    { MPV_RENDER_PARAM_FLIP_Y, &flipY },
    { MPV_RENDER_PARAM_INVALID, nullptr }
  };

  mpv_render_context_render(renderContext, params);
  eglSwapBuffers(display, surface);
}
```

## 7.9 Anime4K 实现

### 7.9.1 shader 文件管理

shader 文件不能只放在 rawfile 中直接传路径，需要确保 mpv 可以读取真实文件路径。

建议启动时复制到应用沙箱目录：

```text
/data/storage/el2/base/files/anime_shaders/
```

### 7.9.2 加载 shader

```cpp
std::vector<const char*> args = {
  "change-list",
  "glsl-shaders",
  "set",
  shaderPathList.c_str(),
  nullptr
};

mpv_command(mpv, args.data());
```

### 7.9.3 关闭 shader

```cpp
const char* args[] = {
  "change-list",
  "glsl-shaders",
  "clr",
  "",
  nullptr
};

mpv_command(mpv, args);
```

### 7.9.4 风险

| 风险 | 说明 |
|---|---|
| OpenGL ES 兼容性 | 某些 Anime4K shader 可能不兼容移动端 GPU |
| 性能 | 1080p 以上可能发热、掉帧 |
| 驱动差异 | 不同鸿蒙设备 GPU 行为不一致 |
| 路径权限 | mpv 必须能读取 shader 文件 |
| 渲染链路 | shader 依赖 mpv render pipeline 稳定 |

Anime4K 应放在 mpv 出画面、m3u8 播放、基础字幕稳定之后再做。

## 7.10 外挂字幕

建议交给 mpv/libass 处理，不建议 ArkUI 自己绘制 ASS 字幕。

```cpp
const char* args[] = {
  "sub-add",
  subtitlePath,
  nullptr
};

mpv_command(mpv, args);
```

优点：

- 字幕同步由 mpv 负责；
- ASS/SSA 特效由 libass 处理；
- 字体、描边、定位、缩放更可靠；
- 截图时可包含字幕。

ArkUI 只负责弹幕，不负责 ASS 字幕。

---

## 8. UI 重构方案

## 8.1 首页 Index

### 功能

- 番剧推荐；
- 最近更新；
- 规则源切换；
- 搜索入口；
- 收藏入口。

### 组件建议

- `Navigation`
- `Tabs`
- `Grid`
- `LazyForEach`
- `Refresh`
- `Search`

### 长列表原则

禁止在大数据列表中使用普通 `ForEach` 一次性渲染所有卡片。

建议：

```text
Grid
  + LazyForEach
  + IDataSource
  + cachedCount
```

### 自适应布局

| 宽度 | 布局 |
|---|---|
| < 600vp | 3 列 |
| 600vp - 840vp | 4 列 |
| > 840vp | 6 列或更多 |

---

## 8.2 详情页 Detail

### 功能

- 封面；
- 标题；
- 简介；
- 标签；
- 剧集线路；
- 剧集按钮；
- 收藏按钮；
- 继续播放。

### 布局建议

手机：

```text
封面
标题
简介
剧集列表
```

平板 / PC：

```text
左侧：封面 + 信息
右侧：简介 + 剧集列表
```

### 剧集按钮

使用 `Flex` + `FlexWrap.Wrap`，不要写死每行数量。

---

## 8.3 播放页 Player

### 图层结构

```text
Stack
  ├── Layer 0: XComponent / AVPlayer Surface
  ├── Layer 1: Canvas 弹幕层
  └── Layer 2: 播放控制 UI + 手势层
```

### 控制层

包含：

- 返回；
- 标题；
- 播放/暂停；
- 进度条；
- 当前时间；
- 总时长；
- 倍速；
- 选集；
- 弹幕开关；
- 全屏；
- 设置；
- 超分入口，mpv 版本启用。

### 手势

| 区域 | 手势 | 行为 |
|---|---|---|
| 左半屏 | 上下滑 | 亮度 |
| 右半屏 | 上下滑 | 音量 |
| 全屏 | 左右滑 | seek |
| 单击 | 点击 | 显示/隐藏控制栏 |
| 双击 | 点击 | 播放/暂停 |

### 注意

播放页的高频状态不要全部放在父组件 `@State`，否则会导致大面积重绘。

建议拆分：

- `PlayerSurface`
- `DanmakuCanvas`
- `ControlOverlay`
- `GestureLayer`
- `EpisodePanel`

---

## 8.4 规则管理页 Rules

### 功能

- 规则列表；
- 导入规则；
- 编辑规则；
- 删除规则；
- 测试搜索；
- 测试剧集解析；
- 测试视频嗅探。

### 建议

规则页应内置调试功能，方便迁移期间验证规则兼容性。

---

## 9. 数据存储设计

## 9.1 Preferences

用于：

- 主题；
- 默认规则；
- 默认播放器；
- 弹幕开关；
- 播放速度；
- 是否自动播放；
- 是否启用代理；
- 代理地址；
- 播放器设置。

## 9.2 RDB

用于：

- 收藏；
- 历史；
- 搜索历史；
- 下载记录；
- 规则源；
- 弹幕缓存索引。

## 9.3 文件存储

用于：

- 图片缓存；
- 视频缓存；
- 下载文件；
- shader 文件；
- 字幕文件；
- 日志文件。

---

## 10. 弹幕方案

## 10.1 弹幕不依赖 mpv

弹幕建议使用 ArkUI Canvas 绘制，覆盖在播放器 Surface 之上。

```text
播放器画面
  ↓
Canvas 弹幕层
  ↓
控制栏
```

## 10.2 弹幕核心

```ts
interface DanmakuItem {
  timeMs: number
  text: string
  color: string
  mode: 'scroll' | 'top' | 'bottom'
}
```

## 10.3 渲染原则

- 弹幕计算和轨道分配尽量独立；
- UI 层只负责绘制；
- 高频刷新不要触发整个页面重建；
- 长弹幕列表需要预处理；
- 播放 seek 后要重置弹幕轨道。

---

## 11. 下载功能后置方案

下载器不放入 MVP。

后续实现：

- m3u8 解析；
- ts 分片下载；
- 并发控制；
- 暂停；
- 恢复；
- 删除；
- 空间检测；
- 下载进度；
- 本地播放；
- 断点续传。

下载器建议独立成 `DownloadManager`，不要和播放器强耦合。

---

## 12. 阶段路线图

## 12.1 Phase 0：POC 验证

这是必须阶段，不建议跳过。

| POC | 目标 | 通过标准 |
|---|---|---|
| POC-1 | ArkTS HTML/XPath 解析 | 能解析 3 个现有规则源 |
| POC-2 | WebView 嗅探 | 能抓到真实 m3u8/mp4 |
| POC-3 | AVPlayer 播放 | 能播放主要 m3u8/mp4 |
| POC-4 | libmpv + XComponent | 本地 mp4 出画面，支持 play/pause/seek |

只有 POC-4 通过后，才进入 Anime4K、外挂字幕、硬解等高级功能。

## 12.2 Phase 1：ArkTS MVP

目标：

- 首页；
- 搜索；
- 详情；
- 规则管理；
- WebView 嗅探；
- AVPlayer 播放；
- 收藏；
- 历史；
- 基础设置。

里程碑：

```text
输入关键词
  ↓
搜索出番剧
  ↓
进入详情
  ↓
选择剧集
  ↓
嗅探视频地址
  ↓
AVPlayer 播放
  ↓
记录历史
```

## 12.3 Phase 2：数据和体验补齐

目标：

- 规则导入/导出；
- 搜索历史；
- 收藏分类；
- 播放历史；
- 弹幕；
- 深色模式；
- 多端布局；
- 基础缓存；
- 日志系统。

## 12.4 Phase 3：mpv 播放器 SDK

目标：

- libmpv 编译；
- NAPI 桥；
- XComponent 渲染；
- EGL 生命周期；
- 播放控制；
- 播放状态回调；
- 错误回调；
- m3u8；
- headers；
- referer；
- proxy。

## 12.5 Phase 4：mpv 高级能力

目标：

- 外挂字幕；
- ASS/SSA；
- 截图；
- Anime4K；
- 大缓存；
- 硬解；
- 播放器日志；
- 复杂源兼容；
- 性能优化。

## 12.6 Phase 5：鸿蒙生态能力

目标：

- 智慧多窗；
- 折叠屏；
- 鸿蒙 PC；
- 服务卡片；
- 实况窗；
- 跨端流转。

---

## 13. Go / No-Go 标准

## 13.1 AVPlayer 是否足够

如果 AVPlayer 能覆盖 80% 以上常用视频源，则 MVP 继续使用 AVPlayer。

如果出现大量：

- m3u8 播放失败；
- headers 无法传递；
- Referer 无法生效；
- 代理不可用；
- 异常流无法播放；

则提高 mpv 优先级。

## 13.2 mpv 是否继续投入

mpv POC 必须满足：

| 条件 | 标准 |
|---|---|
| 编译 | libmpv + FFmpeg + libass 能稳定生成 arm64 so |
| 渲染 | XComponent 可稳定出画面 |
| 生命周期 | 进入/退出/旋转/后台恢复不崩 |
| 控制 | play/pause/seek 可用 |
| 网络 | m3u8 可播放 |
| 回调 | 播放状态可回到 ArkTS |
| 稳定性 | 连续播放和切集无明显泄漏 |

不满足这些条件时，不进入 Anime4K 阶段。

---

## 14. 风险清单

| 风险 | 等级 | 说明 | 处理 |
|---|---|---|---|
| HTML/XPath 库不可用 | 高 | ArkTS 生态库可能不稳定 | Phase 0 验证 |
| Web 嗅探不稳定 | 高 | 站点反爬和动态加载复杂 | 请求拦截 + JS 注入 |
| AVPlayer headers 支持不足 | 中高 | 部分站点依赖 Referer/UA | 实测，不足则 mpv |
| libmpv 编译困难 | 高 | 依赖多，交叉编译复杂 | 单独 native SDK 化 |
| XComponent 黑屏 | 高 | surface 生命周期复杂 | 独立渲染线程 |
| EGL context 丢失 | 高 | 后台/旋转/多窗常见 | 生命周期状态机 |
| Anime4K 性能差 | 中高 | GPU 压力大 | 后置，做开关和降级 |
| 包体过大 | 中高 | mpv + FFmpeg 体积大 | 裁剪 codec/protocol |
| 功耗上升 | 中 | shader/软解可能耗电 | 性能测试 |
| 数据迁移复杂 | 中 | Hive 数据不能直接用 | 做导入工具 |

---

## 15. 性能策略

## 15.1 UI 性能

- 长列表使用 LazyForEach；
- 播放页拆分组件；
- 高频播放状态不要驱动整页刷新；
- Canvas 弹幕独立绘制；
- 图片缓存分级；
- 封面图懒加载。

## 15.2 播放器性能

AVPlayer 版：

- 优先系统硬解；
- 尽量减少 UI overlay 重绘；
- seek 节流；
- 进度回调节流。

mpv 版：

- render thread 独立；
- event thread 独立；
- shader 可关闭；
- 低端设备默认关闭 Anime4K；
- 控制日志等级；
- 检测掉帧；
- 监控内存。

## 15.3 包体控制

基础版：

```text
ArkTS + AVPlayer
```

包体相对可控。

完整版：

```text
ArkTS + libmpv + FFmpeg + libass + shader
```

包体可能显著增加，需要单独裁剪：

- 删除不需要的 FFmpeg decoder；
- 删除不需要的 protocol；
- 精简字体；
- 精简 shader；
- 按架构打包；
- 避免同时打入无用 ABI。

---

## 16. 推荐开发顺序

```text
1. 建 ArkTS 空工程
2. 实现 HTTP Client
3. 实现规则模型
4. 实现 HTML/XPath POC
5. 实现搜索解析
6. 实现剧集解析
7. 实现 WebView 嗅探 POC
8. 实现 AVPlayer 播放 POC
9. 做首页/搜索/详情最小 UI
10. 串联完整播放链路
11. 加收藏和历史
12. 加基础设置
13. 加弹幕 Canvas
14. 独立启动 mpv native POC
15. mpv 接入主播放器抽象
16. 补字幕、截图、Anime4K
17. 做多端优化和鸿蒙生态能力
```

---

## 17. 最终结论

Kazumi 纯鸿蒙原生 ArkTS 重构可行，但不应被描述为简单迁移。

正确定位是：

```text
业务层重写
  + UI 原生重构
  + 解析引擎迁移
  + Web 嗅探重建
  + 播放器双引擎设计
  + mpv native SDK 独立攻坚
```

最推荐路线：

1. 先完成 ArkTS + AVPlayer MVP；
2. 验证规则解析和 Web 嗅探能跑通；
3. 再独立开发 libmpv + NAPI + XComponent 播放器；
4. 最后补 Anime4K、外挂字幕、截图、硬解等高级能力。

不要把 mpv、Anime4K、ASS 字幕、下载器、实况窗、服务卡片、鸿蒙 PC 完整适配全部放进第一阶段。

本方案的核心原则是：

> 先跑通业务闭环，再攻坚播放器内核；先基础播放，再高级 mpv；先可用，再完整。
