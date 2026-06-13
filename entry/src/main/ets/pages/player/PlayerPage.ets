import { PlayerSurface } from '../../components/player/PlayerSurface'
import { EpisodePanelItem } from '../../components/player/EpisodePanel'
import { SniffErrorOverlay } from '../../components/player/SniffErrorOverlay'
import { GestureLayer } from '../../components/player/GestureLayer'
import { DanmakuCanvas } from '../../components/player/DanmakuCanvas'
import { IPlayerEngine, PlaybackOptions, PlayerState } from '../../core/player/IPlayerEngine'
import { PlayerEngineFactory } from '../../core/player/PlayerEngineFactory'
import { DanmakuManager } from '../../core/danmaku/DanmakuManager'
import { VideoSourceResolver } from '../../core/sniffer/VideoSourceResolver'
import { VideoSourceRequest } from '../../core/sniffer/VideoSourceRequest'
import { VideoSourceResult } from '../../core/sniffer/VideoSourceResult'
import { HistoryStore } from '../../store/HistoryStore'
import { HistoryRecord } from '../../models/HistoryRecord'
import { Logger } from '../../utils/Logger'
import { router, window } from '@kit.ArkUI'

import { webview } from '@kit.ArkWeb'
import { getEffectiveTopSafeHeight } from '../../utils/HdsPageStyle'

const logger = new Logger('PlayerPage')

class JsBridgeProxy {
  private resolver: VideoSourceResolver

  constructor(resolver: VideoSourceResolver) {
    this.resolver = resolver
  }

  postMessage(message: string): void {
    this.resolver.handleJsBridgeMessage(message)
  }
}

@Entry
@Component
export struct PlayerPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State videoUrl: string = ''
  @State animeName: string = ''
  @State episodeName: string = ''
  private bangumiId: number = 0
  @State isPlaying: boolean = false
  @State positionMs: number = 0
  @State durationMs: number = 0
  @State speed: number = 1.0
  @State volume: number = 1.0
  @State isControlVisible: boolean = true
  @State episodes: EpisodePanelItem[] = []
  @State currentEpisodeIndex: number = -1
  @State selectedPanelTab: number = 0
  @State sniffStatus: string = 'idle'
  @State sniffMessage: string = ''
  @State sniffRetryCount: number = 0
  @State playbackOptions: PlaybackOptions = new PlaybackOptions()
  @State webviewReady: boolean = false
  @State snifferWebVisible: boolean = true
  @State screenBrightness: number = 0.5
  @State isFullScreen: boolean = false
  private playerEngine: IPlayerEngine | null = null
  private hasEngine: boolean = false
  private danmakuManager: DanmakuManager | null = null
  @State isDanmakuEnabled: boolean = true
  private historyStore: HistoryStore = new HistoryStore()
  private sourceResolver: VideoSourceResolver = new VideoSourceResolver()
  private webController: webview.WebviewController = new webview.WebviewController()
  private animeId: string = ''
  private animeCover: string = ''
  private animeUrl: string = ''
  private sourceId: number = -1
  private lastHistoryUpdateMs: number = 0
  private episodeUrl: string = ''
  private ruleSourceId: number = -1
  private pendingSniff: boolean = false
  private lastSeekRequestAtMs: number = 0
  private pendingSeekMs: number = -1
  private pendingSeekTimer: number = -1
  private readonly seekThrottleMs: number = 300
  private playbackRetryCount: number = 0
  private readonly maxPlaybackRetryCount: number = 1

  aboutToAppear(): void {
    this.danmakuManager = new DanmakuManager()

    const params = router.getParams() as Record<string, Object>
    if (params !== null) {
      if (params['videoUrl'] !== undefined) this.videoUrl = params['videoUrl'] as string
      if (params['episodeUrl'] !== undefined) this.episodeUrl = params['episodeUrl'] as string
      if (params['ruleSourceId'] !== undefined) this.ruleSourceId = params['ruleSourceId'] as number
      if (params['animeName'] !== undefined) this.animeName = params['animeName'] as string
      if (params['episodeName'] !== undefined) this.episodeName = params['episodeName'] as string
      if (params['animeId'] !== undefined) this.animeId = params['animeId'] as string
      if (params['animeCover'] !== undefined) this.animeCover = params['animeCover'] as string
      if (params['animeUrl'] !== undefined) this.animeUrl = params['animeUrl'] as string
      if (params['sourceId'] !== undefined) this.sourceId = params['sourceId'] as number
      if (params['episodesJson'] !== undefined) this.episodes = this.parseEpisodePanelItems(params['episodesJson'] as string)
      if (params['currentEpisodeIndex'] !== undefined) this.currentEpisodeIndex = params['currentEpisodeIndex'] as number
      if (params['bangumiId'] !== undefined) this.bangumiId = params['bangumiId'] as number
    }

    if (this.videoUrl.length > 0) {
      const options = new PlaybackOptions()
      options.url = this.videoUrl
      this.playbackOptions = options
    }

    this.sourceResolver.setWebController(this.webController)

    if (this.episodeUrl.length > 0 && this.videoUrl.length === 0) {
      this.pendingSniff = true
    }
  }

  aboutToDisappear(): void {
    this.saveHistory()
    this.sourceResolver.cancel()
    this.clearPendingSeek()
    if (this.danmakuManager !== null) {
      this.danmakuManager.release()
      this.danmakuManager = null
    }
    if (this.isFullScreen) {
      this.setFullScreenMode(false)
    }
  }

  onBackPress(): boolean {
    if (this.isFullScreen) {
      this.toggleFullScreen()
      return true
    }
    return false
  }

  build() {
    Stack() {
      Column() {
        if (!this.isFullScreen) {
          Column()
            .width('100%')
            .height(getEffectiveTopSafeHeight(this.topSafeHeight))
            .backgroundColor($r('app.color.page_background_green'))
        }

        this.VideoSection()

        if (!this.isFullScreen) {
          this.PanelSection()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isFullScreen ? Color.Black : $r('app.color.page_background_green'))

      if (!this.isFullScreen) {
        this.DownloadButton()
      }

      if (this.snifferWebVisible) {
        Web({ src: '', controller: this.webController })
          .width(1)
          .height(1)
          .visibility(Visibility.None)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy({
            object: new JsBridgeProxy(this.sourceResolver),
            name: 'jsBridge',
            methodList: ['postMessage'],
            controller: this.webController
          })
          .javaScriptProxy({
            object: new JsBridgeProxy(this.sourceResolver),
            name: 'JSBridgeDebug',
            methodList: ['postMessage'],
            controller: this.webController
          })
          .javaScriptProxy({
            object: new JsBridgeProxy(this.sourceResolver),
            name: 'VideoBridgeDebug',
            methodList: ['postMessage'],
            controller: this.webController
          })

          .onInterceptRequest((event) => {
            if (event && event.request && event.request.getRequestUrl()) {
              let url = event.request.getRequestUrl()
              this.sourceResolver.handleInterceptedRequest(url)
            }
            return null
          })
          .onPageEnd(() => {
            this.sourceResolver.onWebViewPageEnd()
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (event && event.error && this.shouldLogWebViewError()) {
              logger.warn('WebView error: %{public}s', event.error.getErrorInfo())
            }
          })
          .onControllerAttached(() => {
            this.webviewReady = true
            this.sourceResolver.setWebController(this.webController)
            if (this.pendingSniff) {
              this.pendingSniff = false
              this.startSniffing()
            }
          })
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_green'))
  }

  @Builder
  private VideoSection() {
    Stack() {
      if (this.sniffStatus === 'sniffing') {
        this.SniffingOverlay()
      } else if (this.sniffStatus === 'error' || this.sniffStatus === 'timeout' || this.sniffStatus === 'captcha') {
        SniffErrorOverlay({
          status: this.sniffStatus,
          message: this.sniffMessage,
          retryCount: this.sniffRetryCount,
          onRetry: () => {
            this.startSniffing()
          },
          onBack: () => {
            router.back()
          }
        })
      } else {
        PlayerSurface({
          videoUrl: this.videoUrl,
          playbackOptions: this.playbackOptions,
          onStateChange: (state: PlayerState) => {
            this.handlePlayerState(state)
          },
          onPlayerReady: () => {
            logger.info('Player ready')
          },
          onEngineReady: (engine: IPlayerEngine) => {
            this.playerEngine = engine
            this.hasEngine = true
            if (this.danmakuManager !== null) {
              this.danmakuManager.init().then(() => {
                this.isDanmakuEnabled = this.danmakuManager!.getIsDanmakuEnabled()
                if (this.danmakuManager !== null && this.animeName.length > 0) {
                  this.danmakuManager.loadDanmakuForEpisode(this.animeName, this.currentEpisodeIndex, this.bangumiId, this.episodeName)
                }
              })
            }
          }
        })

        if (this.hasEngine) {
          DanmakuCanvas({
            isDanmakuEnabled: this.isDanmakuEnabled,
            onCanvasReady: (context: CanvasRenderingContext2D, width: number, height: number) => {
              if (this.danmakuManager !== null) {
                this.danmakuManager.onCanvasReady(context, width, height)
              }
            },
            onCanvasSizeChanged: (width: number, height: number) => {
              if (this.danmakuManager !== null) {
                this.danmakuManager.onCanvasSizeChanged(width, height)
              }
            }
          })
        }
      }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.isControlVisible = !this.isControlVisible
        })

      GestureLayer({
        durationMs: this.durationMs,
        positionMs: this.positionMs,
        volume: this.volume,
        screenBrightness: this.screenBrightness,
        isPlaying: this.isPlaying,
        onSeek: (positionMs: number) => {
          this.seekTo(positionMs)
        },
        onVolumeChange: (volume: number) => {
          if (this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.setVolume(volume)
            this.volume = volume
          }
        },
        onBrightnessChange: (brightness: number) => {
          this.screenBrightness = brightness
        },
        onTogglePlayPause: () => {
          this.togglePlayPause()
        }
      })

      if (this.isControlVisible) {
        this.VideoTopBar()
        this.VideoBottomBar()
      }
    }
    .width('100%')
    .aspectRatio(16 / 9)
    .layoutWeight(this.isFullScreen ? 1 : 0)
    .backgroundColor(Color.Black)
  }

  @Builder
  private VideoTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(26)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.overlay_topbar_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .onClick(() => {
        if (this.isFullScreen) {
          this.toggleFullScreen()
        } else {
          router.back()
        }
      })

      Column() {
        Text(this.animeName.length > 0 ? this.animeName : 'Kazumi')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.episodeName.length > 0) {
          Text(this.episodeName)
            .fontSize(12)
            .fontColor($r('app.color.text_overlay_dim'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .margin({ left: 10, right: 10 })

      Text(`${this.speed}x`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .borderRadius(15)
        .backgroundColor($r('app.color.overlay_topbar_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_light') })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.isFullScreen ? this.topSafeHeight + 8 : 8, bottom: 8 })
    .backgroundColor($r('app.color.overlay_topbar_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .align(Alignment.Top)
  }

  @Builder
  private VideoBottomBar() {
    Column() {
      Row() {
        Text(this.formatTime(this.positionMs))
          .fontSize(11)
          .fontColor($r('app.color.text_on_primary'))

        Slider({
          value: this.durationMs > 0 ? this.positionMs : 0,
          min: 0,
          max: this.durationMs > 0 ? this.durationMs : 1,
          step: 1000
        })
          .layoutWeight(1)
          .trackColor($r('app.color.track_slider'))
          .selectedColor($r('app.color.accent_green_light'))
          .onChange((value: number) => {
            this.seekTo(value)
          })

        Text(this.formatTime(this.durationMs))
          .fontSize(11)
          .fontColor($r('app.color.text_on_primary'))
      }
      .width('100%')
      .padding({ left: 12, right: 12 })

      Row() {
        Button(this.isPlaying ? '暂停' : '播放')
          .height(32)
          .padding({ left: 14, right: 14 })
          .fontSize(13)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(16)
          .backgroundColor($r('app.color.border_specular'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .onClick(() => {
            this.togglePlayPause()
          })

        if (this.hasNextEpisode()) {
          Button('下一集')
            .height(32)
            .padding({ left: 14, right: 14 })
            .fontSize(13)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(16)
            .backgroundColor($r('app.color.border_specular'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .margin({ left: 10 })
            .onClick(() => {
              this.playNextEpisode()
            })
        }

        Text(`${this.speed}x`)
          .fontSize(12)
          .fontColor($r('app.color.text_on_primary'))
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .borderRadius(15)
          .backgroundColor($r('app.color.border_specular'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .margin({ left: 10 })
          .onClick(() => {
            this.nextSpeed()
          })

        Blank()

        Button() {
          Text(this.isFullScreen ? '退出全屏' : '全屏')
            .fontSize(13)
            .fontColor($r('app.color.text_on_primary'))
        }
        .height(32)
        .padding({ left: 14, right: 14 })
        .borderRadius(16)
        .backgroundColor($r('app.color.border_specular'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .onClick(() => {
          this.toggleFullScreen()
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 5, bottom: this.isFullScreen ? this.bottomSafeHeight + 8 : 8 })
    }
    .width('100%')
    .backgroundColor($r('app.color.overlay_topbar_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .align(Alignment.Bottom)
  }

  @Builder
  private PanelSection() {
    Column() {
      Row() {
        this.PanelTab('选集', 0)
        this.PanelTab('评论', 1)

        Blank()

        Row() {
          Text(this.isDanmakuEnabled ? '弹幕已开启' : '已关闭弹幕')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_hint_green'))
        }
        .height(42)
        .padding({ left: 18, right: 18 })
        .borderRadius(21)
        .border({ width: 1, color: $r('app.color.border_panel') })
        .onClick(() => {
          if (this.danmakuManager !== null) {
            this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
          }
        })
      }
      .width('100%')
      .height(72)
      .padding({ left: 28, right: 22 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.divider_green'))

      if (this.selectedPanelTab === 0) {
        this.EpisodePanelBody()
      } else {
        this.CommentPanelBody()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.page_background_green'))
  }

  @Builder
  private PanelTab(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selectedPanelTab === index ? $r('app.color.accent_green') : $r('app.color.text_title_green'))

      Row()
        .width(48)
        .height(5)
        .borderRadius(3)
        .backgroundColor(this.selectedPanelTab === index ? $r('app.color.accent_green') : $r('app.color.color_transparent'))
        .margin({ top: 14 })
    }
    .height(64)
    .justifyContent(FlexAlign.End)
    .margin({ right: 82 })
    .onClick(() => {
      this.selectedPanelTab = index
    })
  }

  @Builder
  private EpisodePanelBody() {
    Scroll() {
      Column() {
        Row() {
          Text('合集')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title_green'))

          Text(this.animeName.length > 0 ? this.animeName : '播放列表')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_subtitle_green'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 10, right: 10 })

          Text('播放列表1')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent_green'))
        }
        .width('100%')
        .padding({ left: 28, right: 28, top: 28, bottom: 22 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.episodes, (ep: EpisodePanelItem, index?: number) => {
            Row() {
              Text(index === this.currentEpisodeIndex ? `||| ${this.getEpisodeDisplayName(ep, index)}` : this.getEpisodeDisplayName(ep, index))
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(index === this.currentEpisodeIndex ? $r('app.color.accent_green') : $r('app.color.text_episode_unselected'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .height(80)
            .width('30.5%')
            .padding({ left: 16, right: 10 })
            .borderRadius(8)
            .backgroundColor(index === this.currentEpisodeIndex ? $r('app.color.episode_item_selected_bg') : $r('app.color.episode_item_unselected_bg'))
            .margin({ right: '2.8%', bottom: 14 })
            .onClick(() => {
              if (index !== undefined) {
                this.onEpisodeSelected(index)
              }
            })
          }, (ep: EpisodePanelItem, index?: number) => `player_ep_${ep.url}_${index}`)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        Column()
          .height(this.bottomSafeHeight + 100)
      }
      .width('100%')
    }
    .layoutWeight(1)
  }

  @Builder
  private CommentPanelBody() {
    Column() {
      Text('暂无评论')
        .fontSize(17)
        .fontColor($r('app.color.text_hint_green'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private DownloadButton() {
    Button() {
      Text('↓')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_download_button'))
    }
    .width(72)
    .height(72)
    .borderRadius(20)
    .backgroundColor($r('app.color.accent_green_light'))
    .shadow({ radius: 18, color: $r('app.color.shadow_button_accent'), offsetY: 8 })
    .position({ x: '80%', y: '84%' })
  }

  @Builder
  private SniffingOverlay() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.text_on_primary'))
      Text('正在嗅探视频源...')
        .fontSize(16)
        .fontColor($r('app.color.text_on_primary'))
        .margin({ top: 16 })
      if (this.sniffRetryCount > 0) {
        Text(`重试第 ${this.sniffRetryCount} 次`)
          .fontSize(12)
          .fontColor($r('app.color.text_retry_count'))
          .margin({ top: 8 })
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }

  private nextSpeed(): void {
    const speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    const currentIdx = speeds.indexOf(this.speed)
    const nextIdx = currentIdx >= 0 ? (currentIdx + 1) % speeds.length : 2
    this.changeSpeed(speeds[nextIdx])
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`
  }

  private getEpisodeDisplayName(ep: EpisodePanelItem, index: number | undefined): string {
    if (ep.name.length > 0) {
      return ep.name
    }
    const safeIndex = index !== undefined ? index : 0
    const epNumber = safeIndex + 1
    return `第${epNumber < 10 ? '0' : ''}${epNumber}集`
  }

  private async startSniffing(): Promise<void> {
    if (this.episodeUrl.length === 0) {
      this.sniffStatus = 'error'
      this.sniffMessage = '无效的剧集地址'
      return
    }

    if (!this.snifferWebVisible) {
      this.webviewReady = false
      this.pendingSniff = true
      this.snifferWebVisible = true
      return
    }

    if (!this.webviewReady) {
      this.pendingSniff = true
      return
    }

    this.sniffStatus = 'sniffing'
    this.sniffMessage = ''
    this.sniffRetryCount = 0

    const request = new VideoSourceRequest()
    request.episodeUrl = this.episodeUrl
    request.ruleSourceId = this.ruleSourceId

    try {
      const result = await this.sourceResolver.resolve(request)
      await this.handleSniffResult(result)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Sniff failed: %{public}s', msg)
      this.sniffStatus = 'error'
      this.sniffMessage = '嗅探异常: ' + msg
    }
  }

  private async handleSniffResult(result: VideoSourceResult): Promise<void> {
    if (result.isPlayable()) {
      const request = new VideoSourceRequest()
      request.episodeUrl = this.episodeUrl
      request.ruleSourceId = this.ruleSourceId
      const options = await this.sourceResolver.buildPlaybackOptionsWithRule(result, request)

      // [REQ-TSX-001] PlayerSurface reacts to videoUrl changes, so options must be ready first.
      this.removeSnifferWebView()
      this.playbackOptions = options
      this.videoUrl = result.videoUrl
      this.sniffStatus = 'success'
      logger.info('Sniff success: %{public}s [%{public}s] in %{public}dms',
        result.videoUrl.substring(0, 80), result.videoType, result.sniffDurationMs)
    } else if (result.status === 'captcha') {
      this.sniffStatus = 'captcha'
      this.sniffMessage = result.errorMessage
    } else if (result.status === 'timeout') {
      this.sniffStatus = 'timeout'
      this.sniffMessage = result.errorMessage
    } else {
      this.sniffStatus = 'error'
      this.sniffMessage = result.errorMessage.length > 0 ? result.errorMessage : '未找到视频流'
    }
    this.sniffRetryCount = result.retryCount
  }

  private removeSnifferWebView(): void {
    this.sourceResolver.cancel()
    this.pendingSniff = false
    this.webviewReady = false
    this.snifferWebVisible = false
  }

  private handlePlayerState(state: PlayerState): void {
    this.isPlaying = state.playing
    this.positionMs = state.positionMs
    this.durationMs = state.durationMs
    this.speed = state.speed
    this.volume = state.volume

    if (this.danmakuManager !== null) {
      this.danmakuManager.onPlayerStateUpdate(state)
    }

    if (state.stateName === 'playing') {
      this.playbackRetryCount = 0
    }

    if (state.stateName === 'error' && state.error.length > 0) {
      if (state.error.indexOf('prepare timeout') !== -1 &&
        this.playbackRetryCount < this.maxPlaybackRetryCount) {
        this.playbackRetryCount++
        logger.warn('Playback prepare timeout, retry sniff %{public}d/%{public}d',
          this.playbackRetryCount, this.maxPlaybackRetryCount)
        this.videoUrl = ''
        this.playbackOptions = new PlaybackOptions()
        this.sniffStatus = 'sniffing'
        this.sniffMessage = ''
        this.startSniffing()
        return
      }
      this.sniffStatus = 'error'
      this.sniffMessage = state.error
    }

    if (state.completed && this.hasNextEpisode()) {
      logger.info('Playback completed, auto play next episode')
      this.playNextEpisode()
    }

    const now = Date.now()
    if (now - this.lastHistoryUpdateMs > 5000) {
      this.saveHistory()
      this.lastHistoryUpdateMs = now
    }
  }

  private togglePlayPause(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      if (this.isPlaying) {
        this.playerEngine.pause()
      } else {
        this.playerEngine.play()
      }
    }
  }

  private seekTo(positionMs: number): void {
    if (!this.hasEngine) {
      return
    }

    this.positionMs = positionMs
    const now = Date.now()
    const elapsed = now - this.lastSeekRequestAtMs
    if (elapsed >= this.seekThrottleMs) {
      this.performSeek(positionMs)
      return
    }

    this.pendingSeekMs = positionMs
    if (this.pendingSeekTimer >= 0) {
      return
    }

    this.pendingSeekTimer = setTimeout(() => {
      this.pendingSeekTimer = -1
      if (this.pendingSeekMs >= 0) {
        const target = this.pendingSeekMs
        this.pendingSeekMs = -1
        this.performSeek(target)
      }
    }, this.seekThrottleMs - elapsed)
  }

  private changeSpeed(speed: number): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(speed)
      this.speed = speed
    }
  }

  private toggleFullScreen(): void {
    this.isFullScreen = !this.isFullScreen

    this.setFullScreenMode(this.isFullScreen)
  }

  private async setFullScreenMode(fullScreen: boolean): Promise<void> {
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (fullScreen) {
        mainWindow.setWindowSystemBarEnable([])
        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
      } else {
        mainWindow.setWindowSystemBarEnable(['status', 'navigation'])
        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
      }
    } catch (_err) {
      logger.warn('Failed to toggle system bars for fullscreen')
    }
  }

  private hasNextEpisode(): boolean {
    return this.episodes.length > 0 && this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex < this.episodes.length - 1
  }

  private playNextEpisode(): void {
    if (this.hasNextEpisode()) {
      this.onEpisodeSelected(this.currentEpisodeIndex + 1)
    }
  }

  private onEpisodeSelected(index: number): void {
    if (index >= 0 && index < this.episodes.length) {
      this.saveHistory()
      this.currentEpisodeIndex = index
      this.episodeName = this.episodes[index].name
      this.episodeUrl = this.episodes[index].url
      this.videoUrl = ''
      this.playbackOptions = new PlaybackOptions()
      this.playbackRetryCount = 0
      this.sniffStatus = 'sniffing'
      this.sniffMessage = ''
      this.sniffRetryCount = 0
      this.startSniffing()

      if (this.danmakuManager !== null) {
        this.danmakuManager.loadDanmakuForEpisode(this.animeName, index + 1, this.bangumiId, this.episodeName)
      }
    }
  }

  private parseEpisodePanelItems(json: string): EpisodePanelItem[] {
    if (json.length === 0) {
      return []
    }
    try {
      return JSON.parse(json) as EpisodePanelItem[]
    } catch (err) {
      logger.warn('Parse episode panel items failed: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  private async saveHistory(): Promise<void> {
    if (this.animeId.length === 0) {
      return
    }
    try {
      const record = new HistoryRecord()
      record.animeId = this.animeId
      record.animeName = this.animeName
      record.animeCover = this.animeCover
      record.animeUrl = this.animeUrl
      record.sourceId = this.sourceId >= 0 ? this.sourceId : this.ruleSourceId
      record.episodeName = this.episodeName
      record.episodeUrl = this.episodeUrl.length > 0 ? this.episodeUrl : this.videoUrl
      record.positionMs = this.positionMs
      record.durationMs = this.durationMs
      await this.historyStore.upsert(record)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Save history failed: %{public}s', msg)
    }
  }

  private performSeek(positionMs: number): void {
    if (!this.hasEngine || this.playerEngine === null) {
      return
    }
    this.lastSeekRequestAtMs = Date.now()
    this.playerEngine.seek(positionMs)
  }

  private clearPendingSeek(): void {
    if (this.pendingSeekTimer >= 0) {
      clearTimeout(this.pendingSeekTimer)
      this.pendingSeekTimer = -1
    }
    this.pendingSeekMs = -1
  }

  private shouldLogWebViewError(): boolean {
    if (this.sniffStatus === 'success') {
      return false
    }
    return this.sourceResolver.getIsResolving()
  }
}
