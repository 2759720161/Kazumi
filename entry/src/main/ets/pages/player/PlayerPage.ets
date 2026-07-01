import { PlayerSurface } from '../../components/player/PlayerSurface'
import { EpisodePanelItem } from '../../components/player/EpisodePanel'
import { SniffErrorOverlay } from '../../components/player/SniffErrorOverlay'
import { GestureLayer } from '../../components/player/GestureLayer'
import { DanmakuCanvas } from '../../components/player/DanmakuCanvas'
import { PlaybackRoad } from '../../models/PlaybackRoad'
import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode, VideoAspectModeHelper } from '../../core/player/IPlayerEngine'
import { PlayerEngineFactory } from '../../core/player/PlayerEngineFactory'
import { DanmakuManager } from '../../core/danmaku/DanmakuManager'
import { DanmakuMappingRecord } from '../../core/danmaku/DanmakuMappingStore'
import { DanmakuMatchPanel } from '../../components/player/DanmakuMatchPanel'
import { DanmakuSettingsPanelContent } from '../../components/player/DanmakuSettingsPanel'
import { DanmakuSettingsSidePanel } from '../../components/player/DanmakuSettingsSidePanel'
import { AspectModePanel } from '../../components/player/AspectModePanel'
import { VideoSourceResolver } from '../../core/sniffer/VideoSourceResolver'
import { VideoSourceRequest } from '../../core/sniffer/VideoSourceRequest'
import { VideoSourceResult } from '../../core/sniffer/VideoSourceResult'
import { ResolveErrorCode } from '../../core/sniffer/ResolveErrorCode'
import { ResolveLogEvent } from '../../core/sniffer/ResolveLogEvent'
import { HistoryStore } from '../../store/HistoryStore'
import { PreferencesStore } from '../../store/PreferencesStore'
import { HistoryRecord } from '../../models/HistoryRecord'
import { CollectController } from '../../controller/CollectController'
import { CollectType } from '../../models/CollectType'
import { AnimeItem } from '../../models/AnimeItem'
import { CollectStatusMenu } from '../../components/collect/CollectStatusMenu'

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
  @StorageLink('keyboardAvoidHeight') keyboardAvoidHeight: number = 0
  @StorageLink('danmakuSettingsVersion') @Watch('onDanmakuSettingsVersionChanged') danmakuSettingsVersion: number = 0
  @State videoUrl: string = ''
  @State animeName: string = ''
  @State episodeName: string = ''
  private bangumiId: number = 0
  @State isPlaying: boolean = false
  @State positionMs: number = 0
  @State durationMs: number = 0
  @State bufferMs: number = 0
  @State speed: number = 1.0
  @State speedLabel: string = '1x'
  @State volume: number = 1.0
  @State isControlVisible: boolean = true
  @State isDraggingProgress: boolean = false
  @State episodes: EpisodePanelItem[] = []
  @State roads: PlaybackRoad[] = []
  @State selectedRoadIndex: number = 0
  @State visibleRoadIndex: number = 0
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
  @State hasEngine: boolean = false
  private danmakuManager: DanmakuManager | null = null
  @State isDanmakuEnabled: boolean = true
  @State isDanmakuLoading: boolean = false
  @State showMoreMenu: boolean = false
  @State showDanmakuMatchPanel: boolean = false
  @State showEpisodeSidePanel: boolean = false
  @State episodePanelOffsetX: number = 0
  @State @Watch('onDanmakuSettingsVisibilityChanged') showDanmakuSettingsPanel: boolean = false
  @State @Watch('onDanmakuSettingsVisibilityChanged') showDanmakuSettingsSheet: boolean = false
  @State danmakuSettingsOpenVersion: number = 0
  @State showHud: boolean = false
  @State hudText: string = ''
  @State currentCollectType: number = CollectType.none
  @State showCollectMenu: boolean = false
  @State currentAspectMode: VideoAspectMode = VideoAspectMode.contain
  @State showAspectModePanel: boolean = false
  @State showRoadPickerPopup: boolean = false
  @State sequentialPlayEpisodeIndex: number = -1
  @State resolveLogs: ResolveLogEvent[] = []

  @State hasCurrentManualMapping: boolean = false
  @State currentManualMappingText: string = ''
  @State suppressControlAnimation: boolean = false
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State episodeGridColumns: string = '1fr 1fr 1fr'
  private panelTabsController: TabsController = new TabsController()
  private historyStore: HistoryStore = new HistoryStore()
  private collectController: CollectController = new CollectController()
  private sourceResolver: VideoSourceResolver = new VideoSourceResolver()
  private logListener: ((event: ResolveLogEvent) => void) | null = null
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
  private controlHideTimer: number = -1
  private hudTimer: number = -1
  private brightnessApplyTimer: number = -1
  private danmakuSettingsReloadTimer: number = -1
  private danmakuLoadingPollTimer: number = -1
  private lastBrightnessApplyMs: number = 0
  private pendingBrightnessValue: number = -1
  private keepScreenOnRequestToken: number = 0
  private keepScreenOnEnabled: boolean = false
  private wasPlayingBeforeDrag: boolean = false
  private episodePanelPanStartOffsetX: number = 0
  private bangumiCover: string = ''
  private coverFallback: string = ''
  private animeDesc: string = ''
  private sourceName: string = ''
  private historySeekMs: number = -1
  private temporarySpeedBeforeLongPress: number = -1

  aboutToAppear(): void {
    this.danmakuManager = new DanmakuManager()
    this.danmakuManager.init().then(() => {
      if (this.danmakuManager !== null) {
        this.isDanmakuEnabled = this.danmakuManager.getIsDanmakuEnabled()
        this.startDanmakuLoadingPoll()
      }
    })

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
      if (params['roadsJson'] !== undefined) this.roads = this.parseRoads(params['roadsJson'] as string)
      if (params['selectedRoadIndex'] !== undefined) this.selectedRoadIndex = params['selectedRoadIndex'] as number
      if (params['historyPositionMs'] !== undefined) this.historySeekMs = params['historyPositionMs'] as number
      if (params['bangumiId'] !== undefined) this.bangumiId = params['bangumiId'] as number
      if (params['bangumiCover'] !== undefined) this.bangumiCover = params['bangumiCover'] as string
      if (params['coverFallback'] !== undefined) this.coverFallback = params['coverFallback'] as string
      if (params['animeDesc'] !== undefined) this.animeDesc = params['animeDesc'] as string
      if (params['sourceName'] !== undefined) this.sourceName = params['sourceName'] as string
    }

    if (this.roads.length > 0 && this.selectedRoadIndex >= 0 && this.selectedRoadIndex < this.roads.length) {
      this.episodes = this.toEpisodePanelItems(this.roads[this.selectedRoadIndex])
    }
    this.visibleRoadIndex = this.selectedRoadIndex

    if (this.videoUrl.length > 0) {
      const options = new PlaybackOptions()
      options.url = this.videoUrl
      if (this.historySeekMs > 0) {
        options.startPositionMs = this.historySeekMs
        this.historySeekMs = -1
      }
      this.playbackOptions = options
    }

    this.sourceResolver.setWebController(this.webController)

    if (this.animeId.length > 0) {
      this.collectController.getCollectType(this.animeId).then((type: number) => {
        this.currentCollectType = type
      }).catch((err: Error) => {
        logger.warn('Load collect type failed: %{public}s', err.message)
      })
    }

    if (this.episodeUrl.length > 0 && this.videoUrl.length === 0) {
      this.pendingSniff = true
    }
    logger.info('PlayerPage aboutToAppear episodeUrl=%{public}s videoUrl=%{public}s ruleSourceId=%{public}d pendingSniff=%{public}s',
      this.episodeUrl.length > 0 ? 'ok' : 'empty', this.videoUrl.length > 0 ? 'ok' : 'empty',
      this.ruleSourceId, String(this.pendingSniff))

    this.startAutoHideTimer()
    this.setKeepScreenOn(true)
    this.loadAspectModePreference()
    this.episodeGridColumns = this.getEpisodeGridColumns()
  }

  aboutToDisappear(): void {
    this.setKeepScreenOn(false)
    this.saveHistory()
    this.sourceResolver.cancel()
    if (this.logListener !== null) {
      this.sourceResolver.removeLogListener(this.logListener)
      this.logListener = null
    }
    this.clearPendingSeek()
    this.pauseAutoHideTimer()
    this.clearHudTimer()
    this.clearBrightnessApplyTimer()
    this.clearDanmakuSettingsReloadTimer()
    this.stopDanmakuLoadingPoll()
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
            .backgroundColor($r('app.color.page_background_media'))
        }

        this.VideoSection()

        if (!this.isFullScreen) {
          this.PanelSection()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isFullScreen ? Color.Black : $r('app.color.page_background_media'))

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
          .onPageBegin(() => {
            this.sourceResolver.onWebViewPageBegin()
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

    this.logListener = (event: ResolveLogEvent) => {
      if (this.resolveLogs.length >= 50) {
        this.resolveLogs.splice(0, 1)
      }
      this.resolveLogs.push(event)
    }
    this.sourceResolver.addLogListener(this.logListener)
            if (this.pendingSniff) {
              this.pendingSniff = false
              this.startSniffing()
            }
          })
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_media'))
    .bindSheet($$this.showDanmakuSettingsSheet, this.buildDanmakuSettingsSheet, {
      height: '50%',
      showClose: false,
      dragBar: true,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showDanmakuSettingsSheet = false
        this.startAutoHideTimer()
      }
    })
    .bindSheet($$this.showCollectMenu, this.buildCollectStatusSheet, {
      height: 'auto',
      showClose: false,
      dragBar: true,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showCollectMenu = false
        this.startAutoHideTimer()
      }
    })
  }

  @Builder
  buildDanmakuMatchSheet() {
    DanmakuMatchPanel({
      animeName: this.animeName,
      bangumiId: this.bangumiId,
      episodeNo: this.getCurrentEpisodeNo(),
      currentMappingText: this.currentManualMappingText,
      hasCurrentMapping: this.hasCurrentManualMapping,
      onEpisodeSelected: (episodeId: number, animeId: number, animeTitle: string, episodeTitle: string) => {
        return this.onDanmakuEpisodeSelected(episodeId, animeId, animeTitle, episodeTitle)
      },
      onClearCurrentMapping: () => {
        return this.clearCurrentManualMapping()
      }
    })
  }

  @Builder
  buildDanmakuSettingsSheet() {
    DanmakuSettingsPanelContent({
      isDanmakuEnabled: this.isDanmakuEnabled,
      isFullScreen: this.isFullScreen,
      settingsVersion: this.danmakuSettingsOpenVersion,
      onToggleDanmaku: () => {
        this.toggleDanmaku()
      },
      onPanelClose: () => {
        this.showDanmakuSettingsSheet = false
      },
      onPauseAutoHide: () => {
        this.pauseAutoHideTimer()
      },
      onResumeAutoHide: () => {
        this.startAutoHideTimer()
      }
    })
  }

  @Builder
  private VideoSection() {
    Stack({ alignContent: Alignment.Center }) {
      this.VideoLayerContent()
    }
    .width('100%')
    .height(this.isFullScreen ? '100%' : undefined)
    .aspectRatio(this.isFullScreen ? undefined : 16 / 9)
    .layoutWeight(this.isFullScreen ? 1 : 0)
    .backgroundColor(Color.Black)
    .clip(true)
  }

  @Builder
  private VideoLayerContent() {
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
          fillParent: this.isFullScreen,
          aspectMode: this.currentAspectMode,
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
                this.danmakuManager.loadDanmakuForEpisode(this.animeName, this.getCurrentEpisodeNo(), this.bangumiId, this.episodeName, this.sourceId, this.episodeUrl)
                this.startDanmakuLoadingPoll()
              }
              })
            }
          }
        })

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
          .width('100%')
          .height('100%')
          .zIndex(2)

      }

      if (this.sniffStatus === 'success' || this.sniffStatus === 'idle') {
        GestureLayer({
          durationMs: this.durationMs,
          positionMs: this.positionMs,
          volume: this.volume,
          screenBrightness: this.screenBrightness,
          isPlaying: this.isPlaying,
          isControlVisible: this.isControlVisible,
          onSeek: (positionMs: number) => {
            this.seekTo(positionMs)
            this.showHudText(`跳转到 ${this.formatTime(positionMs)}`)
            this.showControlsWithAutoHide()
          },
          onVolumeChange: (volume: number) => {
            if (this.hasEngine && this.playerEngine !== null) {
              this.playerEngine.setVolume(volume)
              this.volume = volume
            }
          },
          onBrightnessChange: (brightness: number) => {
            this.requestWindowBrightness(brightness)
          },
          onTogglePlayPause: () => {
            this.togglePlayPause()
            this.showHudText(this.isPlaying ? '播放' : '暂停')
          },
          onToggleControls: () => {
            this.toggleControls()
          },
          onTemporarySpeedStart: () => {
            this.startTemporarySpeed()
          },
          onTemporarySpeedEnd: () => {
            this.endTemporarySpeed()
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(4)

        this.PlayerControlOverlay()
      }

      if (this.showHud) {
        this.HudView()
      }

      if (this.showDanmakuMatchPanel) {
        this.DanmakuMatchOverlay()
      }

      if (this.isFullScreen && this.showEpisodeSidePanel) {
        this.EpisodeSidePanel()
      }

      if (this.isFullScreen && this.showDanmakuSettingsPanel) {
        DanmakuSettingsSidePanel({
          showPanel: this.showDanmakuSettingsPanel,
          isDanmakuEnabled: this.isDanmakuEnabled,
          isFullScreen: this.isFullScreen,
          settingsVersion: this.danmakuSettingsOpenVersion,
          onPanelClose: () => {
            this.closeDanmakuSettings()
          },
          onToggleDanmaku: () => {
            this.toggleDanmaku()
          },
          onPauseAutoHide: () => {
            this.pauseAutoHideTimer()
          },
          onResumeAutoHide: () => {
            this.startAutoHideTimer()
          }
        })
          .zIndex(10)
      }
  }

  @Builder
  private DanmakuMatchOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.closeDanmakuMatchPanel()
        })

      Column() {
        this.buildDanmakuMatchSheet()
      }
      .width(this.isFullScreen ? 560 : '86%')
      .height(this.isFullScreen ? '68%' : '72%')
      .borderRadius(18)
      .clip(true)
      .backgroundColor($r('app.color.page_background_media'))
      .shadow({ radius: 24, color: $r('app.color.shadow_surface'), offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#33000000')
    .zIndex(11)
    .onAppear(() => {
      this.pauseAutoHideTimer()
    })
    .onDisAppear(() => {
      this.startAutoHideTimer()
    })
  }

  @Builder
  private PlayerControlOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.VideoTopBar()

        Blank()
          .layoutWeight(1)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)

        this.VideoBottomBar()
      }
      .width('100%')
      .height('100%')
      .zIndex(6)
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.showMoreMenu) {
        this.PlayerMoreMenu()
      }

      if (this.showAspectModePanel) {
        this.AspectModePanelOverlay()
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(6)
      .hitTestBehavior(this.isControlVisible ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private VideoTopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.isFullScreen) {
          this.toggleFullScreen()
        } else {
          router.back()
        }
      })

      if (this.isFullScreen) {
        Text(this.buildPlayerTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 10, right: 10 })
      } else {
        Blank()
          .layoutWeight(1)
      }

      this.TopSymbolButton($r('sys.symbol.forward_end_fill'), '快进', () => {
        this.seekForward(10000)
      })

      if (!this.isFullScreen) {
        if (this.isDanmakuLoading) {
          this.DanmakuLoadingButton()
        } else {
          this.DanmakuToggleButton(true)
        }
      }

      this.TopSymbolButton(
        this.currentCollectType > CollectType.none ? CollectType.getIcon(this.currentCollectType) : $r('sys.symbol.heart_badge_plus'),
        this.currentCollectType > CollectType.none ? CollectType.getLabel(this.currentCollectType) : '收藏',
        () => {
          this.showCollectMenu = true
        },
        this.currentCollectType > CollectType.none
      )

      this.TopSymbolButton(this.showMoreMenu ? $r('sys.symbol.xmark') : $r('sys.symbol.dot_grid_1x2'),
        this.showMoreMenu ? '收起' : '更多', () => {
        this.showMoreMenu = !this.showMoreMenu
        if (this.showMoreMenu) {
          this.pauseAutoHideTimer()
        } else {
          this.startAutoHideTimer()
        }
      })
    }
    .width('100%')
    .height(this.isFullScreen ? this.topSafeHeight + 68 : 64)
    .padding({ left: 10, right: 14, top: this.isFullScreen ? this.topSafeHeight + 8 : 8, bottom: 8 })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#AA000000', 0.0], ['#5C000000', 0.55], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : -12 })
    .opacity(this.isControlVisible ? 1 : 0)
    .animation({ duration: this.getControlAnimationDuration(), curve: Curve.EaseInOut })
  }



  @Builder
  private PlayerMoreMenu() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.showMoreMenu = false
        })

      Column() {
        if (this.isFullScreen) {
          this.MoreMenuItem(this.isDanmakuEnabled ? '关闭弹幕' : '开启弹幕', () => {
            this.toggleDanmaku()
            this.showMoreMenu = false
          })
          this.MoreMenuItem('弹幕匹配', () => {
            this.openDanmakuMatchPanel()
            this.showMoreMenu = false
          })
          this.MoreMenuItem('弹幕设置', () => {
            this.openDanmakuSettings()
            this.showMoreMenu = false
          })
          this.MoreMenuItem('视频比例', () => {
            this.showAspectModePanel = true
          })

        } else {
          this.MoreMenuItem('弹幕匹配', () => {
            this.openDanmakuMatchPanel()
            this.showMoreMenu = false
          })
          this.MoreMenuItem('弹幕设置', () => {
            this.openDanmakuSettings()
            this.showMoreMenu = false
          })
          this.MoreMenuItem('视频比例', () => {
            this.showAspectModePanel = true
          })
          this.MoreMenuItem('倍速', () => {
            this.nextSpeed()
            this.showMoreMenu = false
          })

        }
      }
      .width(156)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.category_menu_surface'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
      .margin({ top: this.isFullScreen ? this.topSafeHeight + 46 : 46, right: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(8)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private AspectModePanelOverlay() {
    if (this.showAspectModePanel) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.color_transparent'))
          .onClick(() => {
            this.showAspectModePanel = false
          })

        AspectModePanel({
          currentMode: this.currentAspectMode,
          onSelectMode: (mode: VideoAspectMode) => {
            this.applyAspectMode(mode)
            this.showAspectModePanel = false
            this.showMoreMenu = false
          }
        })
          .margin({ top: this.isFullScreen ? this.topSafeHeight + 46 : 46, right: 12 })
      }
      .width('100%')
      .height('100%')
      .zIndex(9)
      .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    }
  }

  @Builder
  private MoreMenuItem(label: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      action()
    })
  }

  @Builder
  private VideoBottomBar() {
    Column() {
      if (this.isFullScreen) {
        this.LandscapeProgressRow()
        this.LandscapeControlRow()
      } else {
        this.PortraitControlRow()
      }
    }
    .width('100%')
    .padding({ top: this.isFullScreen ? 18 : 12 })
    .linearGradient({
      direction: GradientDirection.Top,
      colors: [['#B8000000', 0.0], ['#70000000', 0.58], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : 12 })
    .opacity(this.isControlVisible ? 1 : 0)
    .animation({ duration: this.getControlAnimationDuration(), curve: Curve.EaseInOut })
  }

  @Builder
  private LandscapeProgressRow() {
    Row() {
      Text(this.formatTime(this.positionMs))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))

      this.ProgressSlider()

      Text(this.formatTime(this.durationMs))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
    }
    .width('100%')
    .height(28)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  private ProgressSlider() {
    Slider({
      value: this.durationMs > 0 ? this.positionMs : 0,
      min: 0,
      max: this.durationMs > 0 ? this.durationMs : 1,
      step: 1000
    })
      .layoutWeight(1)
      .trackColor('#55FFFFFF')
      .selectedColor($r('app.color.accent_blue'))
      .blockColor($r('app.color.text_on_primary'))
      .onChange((value: number, mode: SliderChangeMode) => {
        if (mode === SliderChangeMode.Begin) {
          this.isDraggingProgress = true
          this.wasPlayingBeforeDrag = this.isPlaying
          if (this.wasPlayingBeforeDrag && this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.pause()
          }
          this.pauseAutoHideTimer()
        } else if (mode === SliderChangeMode.Moving) {
          this.positionMs = value
        } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
          this.isDraggingProgress = false
          this.seekTo(value)
          if (this.wasPlayingBeforeDrag && this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.play()
          }
          this.showControlsWithAutoHide()
        } else {
          this.positionMs = value
        }
      })
  }

  @Builder
  private PortraitControlRow() {
    Column() {
      Row() {
        Text(this.formatTime(this.positionMs))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')

        this.ProgressSlider()

        Text(this.formatTime(this.durationMs))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')
      }
      .width('100%')
      .height(24)
      .padding({ left: 14, right: 14 })

      Row() {
        this.PlaybackToolButton()

        if (this.hasNextEpisode()) {
          this.SymbolToolButton($r('sys.symbol.forward_end_fill'), '下一集', () => {
            this.playNextEpisode()
          })
        }

        Blank()
          .layoutWeight(1)

        if (this.isDanmakuLoading) {
          this.DanmakuLoadingButton()
        } else {
          this.DanmakuToggleButton(false)
        }

        this.SpeedToolButton()

        this.ImageToolButton($r('app.media.ic_public_view_list'), '选集', () => {
          this.openEpisodePanel()
        })

        this.SymbolToolButton($r('sys.symbol.arrow_up_left_and_arrow_down_right'), '全屏', () => {
          this.toggleFullScreen()
        })
      }
      .width('100%')
      .height(50)
      .padding({ left: 10, right: 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ bottom: this.bottomSafeHeight > 0 ? this.bottomSafeHeight : 0 })
  }

  @Builder
  private LandscapeControlRow() {
    Row({ space: 8 }) {
      this.PlaybackToolButton()

      if (this.hasNextEpisode()) {
        this.SymbolToolButton($r('sys.symbol.forward_end_fill'), '下一集', () => {
          this.playNextEpisode()
        })
      }

      if (this.isDanmakuLoading) {
        this.DanmakuLoadingButton()
      } else {
        this.DanmakuToggleButton(false)
      }

      this.SymbolToolButton($r('sys.symbol.barrage_setting'), '弹幕设置', () => {
        this.openDanmakuSettings()
      })

      Blank()
        .layoutWeight(1)

      this.SpeedToolButton()

      this.ImageToolButton($r('app.media.ic_public_view_list'), '选集', () => {
        this.openEpisodePanel()
      })

      this.SymbolToolButton(this.isFullScreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
        $r('sys.symbol.arrow_up_left_and_arrow_down_right'), this.isFullScreen ? '退出全屏' : '全屏', () => {
        this.toggleFullScreen()
      })
    }
    .height(this.bottomSafeHeight + 62)
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: this.bottomSafeHeight + 12 })
    .alignItems(VerticalAlign.Center)
  }
  @Builder
  private PlaybackToolButton() {
    if (this.isPlaying) {
      this.SymbolToolButton($r('sys.symbol.pause_fill'), '暂停', () => {
        this.togglePlayPause()
      })
    } else {
      this.SymbolToolButton($r('sys.symbol.play_fill'), '播放', () => {
        this.togglePlayPause()
      })
    }
  }

  @Builder
  private SpeedToolButton() {
    Row() {
      Text(this.speedLabel)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width(44)
      .height(40)
      .backgroundColor('#00000000')
      .border({ width: 0, color: '#00000000' })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.nextSpeed()
        this.showControlsWithAutoHide()
      })
  }

  @Builder
  private TopSymbolButton(symbol: Resource, accessibilityLabel: string, action: () => void, active: boolean = false) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([active ? $r('app.color.accent_blue_light') : $r('app.color.text_on_primary')])
    }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor('#00000000')
      .border({ width: 0, color: '#00000000' })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        action()
        this.showControlsWithAutoHide()
      })
  }

  @Builder
  private SymbolToolButton(symbol: Resource, accessibilityLabel: string, action: () => void, active: boolean = false) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(23)
        .fontColor([active ? $r('app.color.accent_blue_light') : $r('app.color.text_on_primary')])
    }
      .width(44)
      .height(40)
      .borderRadius(20)
      .backgroundColor('#00000000')
      .border({ width: 0, color: '#00000000' })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        action()
        this.showControlsWithAutoHide()
      })
  }

  @Builder
  private DanmakuToggleButton(isTopBar: boolean) {
    Row() {
      SymbolGlyph(this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off  '))
        .fontSize(isTopBar ? 22 : 23)
        .renderingStrategy(this.isDanmakuEnabled ? SymbolRenderingStrategy.MULTIPLE_COLOR : SymbolRenderingStrategy.SINGLE)
        .fontColor(this.isDanmakuEnabled ?
          ['#F2FFFFFF', $r('app.color.accent_blue'), $r('app.color.accent_blue')] :
          ['#F2FFFFFF'])
    }
      .width(44)
      .height(isTopBar ? 44 : 40)
      .borderRadius(isTopBar ? 22 : 20)
      .backgroundColor('#00000000')
      .border({ width: 0, color: '#00000000' })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggleDanmaku()
        this.showControlsWithAutoHide()
      })
  }

  @Builder
  private ImageToolButton(icon: Resource, accessibilityLabel: string, action: () => void, active: boolean = false) {
    Row() {
      Image(icon)
        .width(23)
        .height(23)
        .objectFit(ImageFit.Contain)
        .opacity(active ? 1 : 0.95)
    }
      .width(44)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        action()
        this.showControlsWithAutoHide()
      })
  }
  @Builder
  private DanmakuLoadingButton() {
    Row() {
      LoadingProgress()
        .width(22)
        .height(22)
        .color($r('app.color.text_on_primary'))
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .enabled(false)
  }

  @Builder
  private HudView() {
    Column() {
      Text(this.hudText)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .padding({ left: 24, right: 24, top: 14, bottom: 14 })
        .borderRadius(18)
        .backgroundColor('#8A000000')
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: '#33FFFFFF' })
        .shadow({ radius: 18, color: '#66000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .zIndex(9)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private PanelSection() {
    Tabs({ index: this.selectedPanelTab, controller: this.panelTabsController }) {
      TabContent() {
        this.EpisodePanelBody()
      }
      .padding(0)
      .tabBar(SubTabBarStyle.of('选集')
        .indicator({
          color: $r('app.color.accent_blue'),
          height: 3,
          width: 32,
          borderRadius: 2,
          marginTop: 0
        })
        .selectedMode(SelectedMode.INDICATOR)
        .labelStyle({
          font: { size: 18, weight: 500 },
          selectedColor: $r('app.color.accent_blue'),
          unselectedColor: $r('app.color.text_subtitle')
        })
        .board({ borderRadius: 0 })
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      )

      TabContent() {
        this.DanmakuSettingsTabBody()
      }
      .padding(0)
      .tabBar(SubTabBarStyle.of('弹幕')
        .indicator({
          color: $r('app.color.accent_blue'),
          height: 3,
          width: 32,
          borderRadius: 2,
          marginTop: 0
        })
        .selectedMode(SelectedMode.INDICATOR)
        .labelStyle({
          font: { size: 18, weight: 500 },
          selectedColor: $r('app.color.accent_blue'),
          unselectedColor: $r('app.color.text_subtitle')
        })
        .board({ borderRadius: 0 })
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      )
    }
    .barMode(BarMode.Fixed)
    .barPosition(BarPosition.Start)
    .barWidth('100%')
    .barHeight(56)
    .barBackgroundColor($r('app.color.page_background_media'))
    .onChange((index: number) => {
      this.selectedPanelTab = index
    })
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.page_background_media'))
  }

  @Builder
  private EpisodePanelBody() {
    Scroll() {
      Column() {
        Row() {
          Text(this.animeName.length > 0 ? this.animeName : '播放列表')
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_title'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.roads.length > 1) {
            Row() {
              Text(this.getSelectedRoadName())
                .fontSize(13)
                .fontColor($r('app.color.text_hint'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(11)
                .fontColor([$r('app.color.text_hint')])
            }
            .margin({ left: 8 })
            .onClick(() => {
              this.showRoadPickerPopup = !this.showRoadPickerPopup
            })
            .bindPopup(this.showRoadPickerPopup, {
              builder: this.RoadPickerPopupContent,
              placement: Placement.Bottom,
              showInSubWindow: false,
              onStateChange: (e: PopupStateChangeParam) => {
                if (!e.isVisible) {
                  this.showRoadPickerPopup = false
                }
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 0, bottom: 2 })

        if (this.getVisibleEpisodes().length > 0) {
          Grid() {
            ForEach(this.getVisibleEpisodes(), (ep: EpisodePanelItem, index?: number) => {
              GridItem() {
                this.EpisodeCard(ep, index)
              }
            }, (ep: EpisodePanelItem, index?: number) => `player_ep_${ep.url}_${index}`)
          }
          .columnsTemplate(this.episodeGridColumns)
          .columnsGap(8)
          .rowsGap(10)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: 16, right: 16 })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const width = Number(newArea.width)
            if (width >= 840) {
              this.episodeGridColumns = '1fr 1fr 1fr 1fr 1fr'
            } else if (width >= 600) {
              this.episodeGridColumns = '1fr 1fr 1fr 1fr'
            } else {
              this.episodeGridColumns = '1fr 1fr 1fr'
            }
          })
        } else {
          Row() {
            Text('该线路暂无剧集')
              .fontSize(14)
              .fontColor($r('app.color.text_hint'))
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
        }

        Column()
          .height(this.bottomSafeHeight + 80)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .padding(0)
    .margin(0)
  }

  @Builder
  private EpisodeSidePanel() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeEpisodeSidePanel()
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.FastOutSlowIn }))

      Column() {
        Row() {
          Column() {
            Text('选集')
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))

            Text(this.getSelectedRoadName())
              .fontSize(13)
              .fontColor($r('app.color.text_hint'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('app.color.text_title')])
          }
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.episode_item_unselected_bg'))
          .onClick(() => {
            this.closeEpisodeSidePanel()
          })
        }
        .width('100%')
        .height(72)
        .padding({ left: 18, right: 14, top: 10, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        if (this.roads.length > 1) {
          Row() {
            Text(this.getSelectedRoadName())
              .fontSize(13)
              .fontColor($r('app.color.text_hint'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(11)
              .fontColor([$r('app.color.text_hint')])
          }
          .width('100%')
          .padding({ left: 18, right: 14, top: 0, bottom: 8 })
          .onClick(() => {
            this.showRoadPickerPopup = !this.showRoadPickerPopup
          })
          .bindPopup(this.showRoadPickerPopup, {
            builder: this.RoadPickerPopupContent,
            placement: Placement.BottomLeft,
            showInSubWindow: false,
            onStateChange: (e: PopupStateChangeParam) => {
              if (!e.isVisible) {
                this.showRoadPickerPopup = false
              }
            }
          })
        }

        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            if (this.getVisibleEpisodes().length > 0) {
              ForEach(this.getVisibleEpisodes(), (ep: EpisodePanelItem, index?: number) => {
                Stack({ alignContent: Alignment.Bottom }) {
                  Row() {
                    if (this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex) {
                      SymbolGlyph($r('sys.symbol.play_fill'))
                        .fontSize(12)
                        .fontColor([$r('app.color.text_on_primary')])
                        .margin({ right: 4 })
                    }
                    Text(this.getEpisodeDisplayName(ep, index))
                      .fontSize(14)
                      .fontWeight(this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex ? $r('app.color.text_on_primary') : $r('app.color.text_episode_unselected'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .height(44)
                  .width('100%')
                  .padding({ left: 12, right: 8 })
                  .borderRadius(10)
                  .backgroundColor(this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex ? $r('app.color.accent_blue') : $r('app.color.episode_item_unselected_bg'))
                }
                .width('48%')
                .margin({ right: '2%', bottom: 8 })
                .onClick(() => {
                  if (index !== undefined) {
                    this.onEpisodeSelected(index)
                  }
                })
              }, (ep: EpisodePanelItem, index?: number) => `player_side_ep_${ep.url}_${index}`)
            } else {
              Row() {
                Text('该线路暂无剧集')
                  .fontSize(15)
                  .fontColor($r('app.color.text_hint'))
              }
              .width('100%')
              .height(120)
              .justifyContent(FlexAlign.Center)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 8, top: 8, bottom: this.bottomSafeHeight + 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('42%')
      .height('100%')
      .backgroundColor($r('app.color.player_side_panel_surface'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius({ topLeft: 32, bottomLeft: 32 })
      .border({ width: { left: 0.5 }, color: $r('app.color.divider_blue') })
      .shadow({ radius: 32, color: $r('app.color.shadow_surface'), offsetX: -12 })
      .translate({ x: this.episodePanelOffsetX })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 10 })
          .onActionStart(() => {
            this.episodePanelPanStartOffsetX = this.episodePanelOffsetX
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event.offsetX > 0) {
              this.episodePanelOffsetX = this.episodePanelPanStartOffsetX + event.offsetX
            }
          })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX > 50) {
              this.closeEpisodeSidePanel()
            }
            this.episodePanelOffsetX = 0
          })
      )
      .transition(
        TransitionEffect.move(TransitionEdge.END)
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: 300, curve: Curve.FastOutSlowIn })
      )
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
    .onAppear(() => {
      this.pauseAutoHideTimer()
    })
    .onDisAppear(() => {
      this.startAutoHideTimer()
    })
  }

  @Builder
  private DanmakuSettingsTabBody() {
    DanmakuSettingsPanelContent({
      isDanmakuEnabled: this.isDanmakuEnabled,
      isFullScreen: this.isFullScreen,
      settingsVersion: this.danmakuSettingsOpenVersion,
      onToggleDanmaku: () => {
        this.toggleDanmaku()
      },
      onPanelClose: () => {
        this.selectedPanelTab = 0
      },
      onPauseAutoHide: () => {
        this.pauseAutoHideTimer()
      },
      onResumeAutoHide: () => {
        this.startAutoHideTimer()
      }
    })
  }

  @Builder
  private EpisodeCard(ep: EpisodePanelItem, index?: number) {
    Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        if (this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(12)
            .fontColor([$r('app.color.text_on_primary')])
            .margin({ right: 4 })
        }
        Text(this.getEpisodeDisplayName(ep, index))
          .fontSize(14)
          .fontWeight(this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex ? $r('app.color.text_on_primary') : $r('app.color.text_episode_unselected'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .height(52)
      .padding({ left: 12, right: 8 })
      .borderRadius(12)
      .backgroundColor(this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex ? $r('app.color.accent_blue') : $r('app.color.episode_item_unselected_bg'))

      if (this.visibleRoadIndex === this.selectedRoadIndex && index === this.currentEpisodeIndex && this.positionMs > 0 && this.durationMs > 0) {
        Row()
          .width(`${Math.min(this.positionMs / this.durationMs * 100, 100)}%`)
          .height(2)
          .backgroundColor($r('app.color.text_on_primary'))
          .borderRadius({ bottomLeft: 12, bottomRight: 12 })
          .opacity(0.4)
      }
    }
    .width('100%')
    .borderRadius(12)
    .clip(true)
    .onClick(() => {
      if (index !== undefined) {
        this.onEpisodeSelected(index)
      }
    })
    .gesture(LongPressGesture({ duration: 500 })
      .onAction(() => {
        if (index !== undefined) {
          this.onEpisodeSelected(index)
          this.showHudText(`从${this.getEpisodeDisplayName(ep, index)}开始连续播放`)
        }
      })
    )
  }

  @Builder
  private RoadPickerPopupContent() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.play_circle'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
        
        Text('选择播放源')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      
      Column() {
        ForEach(this.roads, (road: PlaybackRoad, index?: number) => {
          Row() {
            Column() {
              Text(this.getRoadDisplayName(road, index))
                .fontSize(15)
                .fontWeight(index === this.visibleRoadIndex ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(index === this.visibleRoadIndex ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              
              Text(`${road.episodes.length}集`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            
            if (index === this.visibleRoadIndex) {
              Column() {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(20)
                  .fontColor([$r('app.color.accent_blue')])
              }
              .width(24)
              .height('100%')
              .justifyContent(FlexAlign.Center)
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .borderRadius(12)
          .backgroundColor(index === this.visibleRoadIndex ? $r('app.color.episode_item_selected_bg') : $r('app.color.card_background'))
          .margin({ bottom: 4 })
          .onClick(() => {
            if (index !== undefined) {
              this.onRoadSelected(index)
              this.showRoadPickerPopup = false
            }
          })
        }, (road: PlaybackRoad, index?: number) => `road_popup_${index}`)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 8 })
    }
    .width(240)
    .borderRadius(16)
    .backgroundColor($r('app.color.page_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
  }

  @Builder
  private SniffingOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#FF050505', 0.0], ['#FF101318', 0.58], ['#FF050505', 1.0]]
        })

      Column() {
        LoadingProgress()
          .width(42)
          .height(42)
          .color($r('app.color.accent_blue_light'))
        Text('正在嗅探播放地址')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .margin({ top: 16 })
        Text('正在从当前线路提取可播放视频流')
          .fontSize(12)
          .fontColor('#BFFFFFFF')
          .margin({ top: 6 })
        if (this.sniffRetryCount > 0) {
          Text(`第 ${this.sniffRetryCount} 次重试`)
            .fontSize(12)
            .fontColor('#99FFFFFF')
            .margin({ top: 8 })
        }
      }
      .padding({ left: 26, right: 26, top: 24, bottom: 24 })
      .borderRadius(22)
      .backgroundColor('#66000000')
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: '#33FFFFFF' })
      .shadow({ radius: 28, color: '#99000000', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .zIndex(1)
  }

  private nextSpeed(): void {
    const speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.75, 2.0]
    const currentIdx = this.findCurrentSpeedIndex(speeds)
    const nextIdx = currentIdx >= 0 ? (currentIdx + 1) % speeds.length : 2
    this.changeSpeed(speeds[nextIdx])
    this.showHudText(this.formatSpeedLabel(speeds[nextIdx]))
    logger.info('Player speed changed by UI: %{public}s', this.formatSpeedLabel(speeds[nextIdx]))
  }

  private findCurrentSpeedIndex(speeds: number[]): number {
    let closestIndex = -1
    let closestDelta = Number.MAX_VALUE
    for (let i = 0; i < speeds.length; i++) {
      const delta = Math.abs(speeds[i] - this.speed)
      if (delta < closestDelta) {
        closestDelta = delta
        closestIndex = i
      }
    }
    return closestDelta <= 0.02 ? closestIndex : -1
  }

  private formatSpeedLabel(speed: number): string {
    if (Math.abs(speed - 1.0) < 0.01) {
      return '1x'
    }
    if (Math.abs(speed - Math.round(speed)) < 0.01) {
      return `${Math.round(speed)}x`
    }
    return `${speed.toFixed(2).replace(/0$/, '')}x`
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

  private buildPlayerTitle(): string {
    const title = this.animeName.length > 0 ? this.animeName : 'Kazumi'
    if (this.episodeName.length === 0) {
      return title
    }
    return `${title} [${this.episodeName}]`
  }

  private seekForward(deltaMs: number): void {
    const target = this.positionMs + deltaMs
    if (this.durationMs > 0 && target > this.durationMs) {
      this.seekTo(this.durationMs)
      this.showHudText(`快进到 ${this.formatTime(this.durationMs)}`)
      return
    }
    this.seekTo(target)
    this.showHudText(`快进 ${Math.floor(deltaMs / 1000)} 秒`)
  }

  private toggleDanmaku(): void {
    if (this.danmakuManager === null) {
      this.isDanmakuEnabled = !this.isDanmakuEnabled
      this.showHudText(this.isDanmakuEnabled ? '弹幕已开启' : '弹幕已关闭')
      return
    }

    const nextEnabled = this.danmakuManager.toggleDanmaku()
    this.isDanmakuEnabled = nextEnabled
    this.showHudText(nextEnabled ? '弹幕已开启' : '弹幕已关闭')

    if (nextEnabled && !this.danmakuManager.hasDanmakuData()) {
      this.requestCurrentDanmakuLoad()
    }
  }

  private requestCurrentDanmakuLoad(): void {
    if (this.danmakuManager === null || this.animeName.length === 0) {
      return
    }
    this.danmakuManager.loadDanmakuForEpisode(this.animeName, this.getCurrentEpisodeNo(), this.bangumiId,
      this.episodeName, this.sourceId, this.episodeUrl)
    this.startDanmakuLoadingPoll()
  }

  private async onDanmakuEpisodeSelected(episodeId: number, animeId: number,
    animeTitle: string, episodeTitle: string): Promise<boolean> {
    if (this.danmakuManager === null) {
      return false
    }
    const success: boolean = await this.danmakuManager.loadDanmakuByEpisodeId(
      episodeId, animeId, animeTitle, episodeTitle)
    if (success) {
      await this.danmakuManager.saveManualMapping(
        this.bangumiId, this.getCurrentEpisodeNo(), this.animeName,
        animeId, episodeId, animeTitle, episodeTitle, this.sourceId, this.episodeUrl)
      if (!this.isDanmakuEnabled) {
        this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
      }
      this.hasCurrentManualMapping = true
      this.currentManualMappingText = `${animeTitle} / ${episodeTitle.length > 0 ? episodeTitle : `episodeId ${episodeId}`}`
      this.showDanmakuMatchPanel = false
      this.showHudText('弹幕已切换')
      return true
    }
    this.showHudText('弹幕加载失败')
    return false
  }

  private openEpisodePanel(): void {
    this.selectedPanelTab = 0
    if (this.isFullScreen) {
      this.showMoreMenu = false
      this.showDanmakuMatchPanel = false
      this.showDanmakuSettingsPanel = false
      this.showDanmakuSettingsSheet = false
      this.pauseAutoHideTimer()
      this.showEpisodeSidePanel = true
    }
  }

  private closeEpisodeSidePanel(): void {
    this.episodePanelOffsetX = 0
    this.showEpisodeSidePanel = false
    this.startAutoHideTimer()
  }

  private applyAspectMode(mode: VideoAspectMode): void {
    this.currentAspectMode = mode

    this.showHudText(VideoAspectModeHelper.getLabel(mode))
    this.persistAspectMode(mode)
  }

  private async persistAspectMode(mode: VideoAspectMode): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setNumber('videoAspectMode', mode)
    } catch (err) {
      logger.warn('Persist videoAspectMode failed: %{public}s', String(err))
    }
  }

  private async loadAspectModePreference(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      const savedMode = await prefs.getNumber('videoAspectMode', VideoAspectMode.contain)
      this.currentAspectMode = VideoAspectModeHelper.fromValue(savedMode)
    } catch (err) {
      logger.warn('Load videoAspectMode preference failed')
    }
  }

  private async startSniffing(): Promise<void> {
    if (this.episodeUrl.length === 0) {
      this.sniffStatus = 'error'
      this.sniffMessage = '无效的剧集地址'
      return
    }
    logger.info('startSniffing episodeUrl=%{public}s ruleSourceId=%{public}d snifferWebVisible=%{public}s webviewReady=%{public}s',
      this.episodeUrl.length > 40 ? this.episodeUrl.substring(0, 40) + '...' : this.episodeUrl,
      this.ruleSourceId, String(this.snifferWebVisible), String(this.webviewReady))

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
    if (result.errorCode === ResolveErrorCode.Cancelled) {
      logger.info('Sniff result discarded: session cancelled')
      return
    }

    if (result.isPlayable()) {
      const request = new VideoSourceRequest()
      request.episodeUrl = this.episodeUrl
      request.ruleSourceId = this.ruleSourceId
      const options = await this.sourceResolver.buildPlaybackOptionsWithRule(result, request)

      // [REQ-TSX-001] PlayerSurface reacts to videoUrl changes, so options must be ready first.
      this.removeSnifferWebView()
      if (this.historySeekMs > 0) {
        options.startPositionMs = this.historySeekMs
        this.historySeekMs = -1
      }
      this.playbackOptions = options
      this.videoUrl = result.videoUrl
      this.sniffStatus = 'success'
      logger.info('Sniff success: %{public}s [%{public}s] in %{public}dms',
        result.videoUrl.substring(0, 80), result.videoType, result.sniffDurationMs)
    } else if (result.errorCode === ResolveErrorCode.Captcha) {
      this.sniffStatus = 'captcha'
      this.sniffMessage = result.errorMessage
    } else if (result.errorCode === ResolveErrorCode.Timeout) {
      this.sniffStatus = 'timeout'
      this.sniffMessage = result.errorMessage
    } else if (result.errorCode === ResolveErrorCode.Network) {
      this.sniffStatus = 'error'
      this.sniffMessage = result.errorMessage.length > 0 ? result.errorMessage : '网络错误'
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
    if (!this.isDraggingProgress) {
      this.positionMs = state.positionMs
    }
    this.durationMs = state.durationMs
    this.bufferMs = state.bufferMs
    if (Math.abs(this.speed - state.speed) > 0.001) {
      this.speed = state.speed
      this.speedLabel = this.formatSpeedLabel(state.speed)
    }
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
      const nextPlaying = !this.isPlaying
      this.isPlaying = nextPlaying
      if (!nextPlaying) {
        this.playerEngine.pause()
      } else {
        this.playerEngine.play()
      }
    }
  }

  private toggleControls(): void {
    if (this.isControlVisible) {
      this.isControlVisible = false
      this.showMoreMenu = false
      this.showAspectModePanel = false
      this.showEpisodeSidePanel = false
      this.pauseAutoHideTimer()
      return
    }
    this.showControlsWithAutoHide()
  }

  private getTopControlOffset(): number {
    return this.isFullScreen ? this.topSafeHeight + 64 : 64
  }

  private getBottomControlOffset(): number {
    return this.isFullScreen ? this.bottomSafeHeight + 112 : 64
  }

  private getControlAnimationDuration(): number {
    return this.suppressControlAnimation ? 0 : 260
  }

  private showControlsWithAutoHide(): void {
    this.isControlVisible = true
    if (!this.showMoreMenu && !this.isDraggingProgress && !this.showDanmakuSettingsPanel && !this.showDanmakuSettingsSheet && !this.showEpisodeSidePanel && !this.showAspectModePanel && this.selectedPanelTab !== 1) {
      this.startAutoHideTimer()
    }
  }

  private startAutoHideTimer(): void {
    this.pauseAutoHideTimer()
    this.controlHideTimer = setTimeout(() => {
      if (!this.isDraggingProgress && !this.showMoreMenu && !this.showDanmakuSettingsPanel && !this.showDanmakuSettingsSheet && !this.showEpisodeSidePanel && !this.showAspectModePanel && this.selectedPanelTab !== 1) {
        this.isControlVisible = false
      }
      this.controlHideTimer = -1
    }, 3000)
  }

  private pauseAutoHideTimer(): void {
    if (this.controlHideTimer >= 0) {
      clearTimeout(this.controlHideTimer)
      this.controlHideTimer = -1
    }
  }

  private showHudText(text: string): void {
    this.clearHudTimer()
    this.hudText = text
    this.showHud = true
    this.hudTimer = setTimeout(() => {
      this.showHud = false
      this.hudTimer = -1
    }, 900)
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer)
      this.hudTimer = -1
    }
  }

  private requestWindowBrightness(brightness: number): void {
    this.screenBrightness = brightness
    this.pendingBrightnessValue = brightness
    const now = Date.now()
    const elapsed = now - this.lastBrightnessApplyMs
    if (elapsed >= 80) {
      this.applyWindowBrightness(brightness)
      return
    }
    if (this.brightnessApplyTimer >= 0) {
      return
    }
    this.brightnessApplyTimer = setTimeout(() => {
      this.brightnessApplyTimer = -1
      if (this.pendingBrightnessValue >= 0) {
        this.applyWindowBrightness(this.pendingBrightnessValue)
      }
    }, 80 - elapsed)
  }

  private async applyWindowBrightness(brightness: number): Promise<void> {
    this.lastBrightnessApplyMs = Date.now()
    this.pendingBrightnessValue = brightness
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      await mainWindow.setWindowBrightness(brightness)
    } catch (_err) {
      logger.warn('Failed to apply window brightness')
    }
  }

  private async setKeepScreenOn(keepScreenOn: boolean): Promise<void> {
    const requestToken = ++this.keepScreenOnRequestToken
    if (this.keepScreenOnEnabled === keepScreenOn) {
      return
    }

    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (requestToken !== this.keepScreenOnRequestToken) {
        return
      }
      await mainWindow.setWindowKeepScreenOn(keepScreenOn)
      if (requestToken === this.keepScreenOnRequestToken) {
        this.keepScreenOnEnabled = keepScreenOn
      }
    } catch (_err) {
      logger.warn('Failed to set screen keep-on: %{public}s', String(keepScreenOn))
    }
  }

  private clearBrightnessApplyTimer(): void {
    if (this.brightnessApplyTimer >= 0) {
      clearTimeout(this.brightnessApplyTimer)
      this.brightnessApplyTimer = -1
    }
  }

  private onDanmakuSettingsVersionChanged(): void {
    this.scheduleDanmakuSettingsReload()
  }

  private onDanmakuSettingsVisibilityChanged(): void {
    if (this.showDanmakuSettingsPanel || this.showDanmakuSettingsSheet) {
      this.pauseAutoHideTimer()
    }
  }

  private openDanmakuSettings(): void {
    this.showEpisodeSidePanel = false
    this.pauseAutoHideTimer()
    this.danmakuSettingsOpenVersion++
    if (this.isFullScreen) {
      this.showDanmakuSettingsSheet = false
      this.showDanmakuSettingsPanel = true
      return
    }
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.selectedPanelTab = 1
  }

  private async openDanmakuMatchPanel(): Promise<void> {
    this.showMoreMenu = false
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.showEpisodeSidePanel = false
    this.pauseAutoHideTimer()
    await this.refreshCurrentManualMapping()
    this.showDanmakuMatchPanel = true
  }

  private closeDanmakuMatchPanel(): void {
    this.showDanmakuMatchPanel = false
    this.startAutoHideTimer()
  }

  private async refreshCurrentManualMapping(): Promise<void> {
    if (this.danmakuManager === null) {
      this.hasCurrentManualMapping = false
      this.currentManualMappingText = ''
      return
    }
    const record: DanmakuMappingRecord | null = await this.danmakuManager.getCurrentManualMapping(
      this.bangumiId, this.getCurrentEpisodeNo(), this.animeName)
    if (record !== null && record.episodeId > 0) {
      this.hasCurrentManualMapping = true
      const animeTitle = record.animeTitle.length > 0 ? record.animeTitle : `animeId ${record.animeId}`
      const episodeTitle = record.episodeTitle.length > 0 ? record.episodeTitle : `episodeId ${record.episodeId}`
      this.currentManualMappingText = `${animeTitle} / ${episodeTitle}`
    } else {
      this.hasCurrentManualMapping = false
      this.currentManualMappingText = ''
    }
  }

  private async clearCurrentManualMapping(): Promise<boolean> {
    if (this.danmakuManager === null) {
      return false
    }
    const success = await this.danmakuManager.clearManualMapping(
      this.bangumiId, this.getCurrentEpisodeNo(), this.animeName)
    if (success) {
      this.hasCurrentManualMapping = false
      this.currentManualMappingText = ''
      this.showHudText('当前匹配已清除')
    }
    return success
  }

  private closeDanmakuSettings(): void {
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.startAutoHideTimer()
  }

  private scheduleDanmakuSettingsReload(): void {
    this.clearDanmakuSettingsReloadTimer()
    this.danmakuSettingsReloadTimer = setTimeout(() => {
      this.danmakuSettingsReloadTimer = -1
      this.reloadDanmakuSettings()
    }, 150)
  }

  private clearDanmakuSettingsReloadTimer(): void {
    if (this.danmakuSettingsReloadTimer >= 0) {
      clearTimeout(this.danmakuSettingsReloadTimer)
      this.danmakuSettingsReloadTimer = -1
    }
  }

  private startDanmakuLoadingPoll(): void {
    if (this.danmakuLoadingPollTimer >= 0) {
      return
    }
    this.danmakuLoadingPollTimer = setInterval(() => {
      if (this.danmakuManager !== null) {
        this.isDanmakuLoading = this.danmakuManager.getIsLoading()
        if (!this.isDanmakuLoading) {
          this.stopDanmakuLoadingPoll()
        }
      }
    }, 200)
  }

  private stopDanmakuLoadingPoll(): void {
    if (this.danmakuLoadingPollTimer >= 0) {
      clearInterval(this.danmakuLoadingPollTimer)
      this.danmakuLoadingPollTimer = -1
    }
  }

  private async reloadDanmakuSettings(): Promise<void> {
    if (this.danmakuManager === null) {
      return
    }
    await this.danmakuManager.reloadSettings()
    this.isDanmakuEnabled = this.danmakuManager.getIsDanmakuEnabled()
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
      this.speedLabel = this.formatSpeedLabel(speed)
    }
  }

  private startTemporarySpeed(): void {
    if (!this.hasEngine || this.playerEngine === null) {
      return
    }
    if (this.temporarySpeedBeforeLongPress < 0) {
      this.temporarySpeedBeforeLongPress = this.speed
    }
    this.changeSpeed(2.0)
    this.showHudText('2x 快进播放')
  }

  private endTemporarySpeed(): void {
    if (this.temporarySpeedBeforeLongPress < 0) {
      return
    }
    const restoreSpeed = this.temporarySpeedBeforeLongPress
    this.temporarySpeedBeforeLongPress = -1
    this.changeSpeed(restoreSpeed)
    this.showHudText(this.formatSpeedLabel(restoreSpeed))
  }

  private toggleFullScreen(): void {
    this.suppressControlAnimation = true
    this.isControlVisible = true
    this.showMoreMenu = false
    this.showAspectModePanel = false
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.showEpisodeSidePanel = false
    this.pauseAutoHideTimer()
    this.isFullScreen = !this.isFullScreen

    this.setFullScreenMode(this.isFullScreen)
    setTimeout(() => {
      this.suppressControlAnimation = false
      this.showControlsWithAutoHide()
    }, 360)
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
    if (this.selectedRoadIndex >= 0 && this.selectedRoadIndex < this.roads.length) {
      if (this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex < this.roads[this.selectedRoadIndex].episodes.length - 1) {
        return true
      }
      for (let i = this.selectedRoadIndex + 1; i < this.roads.length; i++) {
        if (this.roads[i].episodes.length > 0) {
          return true
        }
      }
    }
    return false
  }

  private playNextEpisode(): void {
    if (this.selectedRoadIndex >= 0 && this.selectedRoadIndex < this.roads.length) {
      if (this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex < this.roads[this.selectedRoadIndex].episodes.length - 1) {
        this.visibleRoadIndex = this.selectedRoadIndex
        this.onEpisodeSelected(this.currentEpisodeIndex + 1)
        return
      }
      for (let i = this.selectedRoadIndex + 1; i < this.roads.length; i++) {
        if (this.roads[i].episodes.length > 0) {
          this.visibleRoadIndex = i
          this.onEpisodeSelected(0)
          return
        }
      }
    }
  }

  private onEpisodeSelected(index: number): void {
    const visibleEpisodes = this.getVisibleEpisodes()
    if (index >= 0 && index < visibleEpisodes.length) {
      this.saveHistory()
      this.stopBeforeSniff()
      this.selectedRoadIndex = this.visibleRoadIndex
      this.episodes = this.toEpisodePanelItems(this.roads[this.visibleRoadIndex])
      this.currentEpisodeIndex = index
      this.episodeName = visibleEpisodes[index].name
      this.episodeUrl = visibleEpisodes[index].url
      this.videoUrl = ''
      this.positionMs = 0
      this.durationMs = 0
      this.bufferMs = 0
      this.historySeekMs = -1
      this.playbackOptions = new PlaybackOptions()
      this.playbackRetryCount = 0
      this.sniffStatus = 'sniffing'
      this.sniffMessage = ''
      this.sniffRetryCount = 0
      this.startSniffing()

      if (this.danmakuManager !== null) {
        this.danmakuManager.loadDanmakuForEpisode(this.animeName, this.getCurrentEpisodeNo(), this.bangumiId, this.episodeName, this.sourceId, this.episodeUrl)
        this.startDanmakuLoadingPoll()
      }
      this.showEpisodeSidePanel = false
      this.showControlsWithAutoHide()
    }
  }

  private stopBeforeSniff(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.stop()
      this.hasEngine = false
      this.isPlaying = false
    }
    this.sourceResolver.cancel()
    this.pendingSniff = false
  }

  private getCurrentEpisodeNo(): number {
    if (this.currentEpisodeIndex >= 0) {
      return this.currentEpisodeIndex + 1
    }
    return 1
  }

  private onRoadSelected(index: number): void {
    if (index < 0 || index >= this.roads.length || index === this.visibleRoadIndex) {
      return
    }
    this.visibleRoadIndex = index
    this.episodes = this.toEpisodePanelItems(this.roads[index])
  }

  private getSelectedRoadName(): string {
    if (this.roads.length > 0 && this.visibleRoadIndex >= 0 && this.visibleRoadIndex < this.roads.length) {
      return this.getRoadDisplayName(this.roads[this.visibleRoadIndex], this.visibleRoadIndex)
    }
    return '播放列表1'
  }

  private getRoadDisplayName(road: PlaybackRoad, index: number | undefined): string {
    if (road.name.length > 0) {
      return road.name
    }
    const safeIndex = index !== undefined ? index : 0
    return `播放列表${safeIndex + 1}`
  }

  private getEpisodeGridColumns(): string {
    if (this.screenWidthVp >= 840) {
      return '1fr 1fr 1fr 1fr 1fr'
    } else if (this.screenWidthVp >= 600) {
      return '1fr 1fr 1fr 1fr'
    }
    return '1fr 1fr 1fr'
  }

  private parseRoads(json: string): PlaybackRoad[] {
    if (json.length === 0) {
      return []
    }
    try {
      return JSON.parse(json) as PlaybackRoad[]
    } catch (err) {
      logger.warn('Parse player roads failed: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  private toEpisodePanelItems(road: PlaybackRoad): EpisodePanelItem[] {
    const items: EpisodePanelItem[] = []
    for (let i = 0; i < road.episodes.length; i++) {
      const item = new EpisodePanelItem()
      item.name = road.episodes[i].name
      item.url = road.episodes[i].url
      items.push(item)
    }
    if (items.length === 0 && road.data.length > 0) {
      for (let i = 0; i < road.data.length; i++) {
        const item = new EpisodePanelItem()
        item.name = i < road.identifier.length ? road.identifier[i] : `第${i + 1}集`
        item.url = road.data[i]
        items.push(item)
      }
    }
    return items
  }

  private getVisibleEpisodes(): EpisodePanelItem[] {
    if (this.visibleRoadIndex >= 0 && this.visibleRoadIndex < this.roads.length) {
      return this.toEpisodePanelItems(this.roads[this.visibleRoadIndex])
    }
    return []
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
      record.roadIndex = this.selectedRoadIndex
      record.episodeIndex = this.currentEpisodeIndex
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

  @Builder
  buildCollectStatusSheet(): void {
    CollectStatusMenu({
      currentType: this.currentCollectType,
      isVisible: $showCollectMenu,
      onSelect: (type: number) => {
        this.onCollectTypeSelected(type)
      }
    })
  }

  private async onCollectTypeSelected(type: number): Promise<void> {
    if (type === CollectType.none) {
      this.showCollectMenu = false
      try {
        const animeItem = this.buildAnimeItemFromPlayer()
        await this.collectController.deleteCollect(animeItem)
        this.currentCollectType = CollectType.none
      } catch (err) {
        logger.error('Delete collect failed: %{public}s', err instanceof Error ? err.message : String(err))
      }
      return
    }
    try {
      const animeItem = this.buildAnimeItemFromPlayer()
      await this.collectController.addCollect(animeItem, type)
      this.currentCollectType = type
      this.showCollectMenu = false
    } catch (err) {
      logger.error('Add collect failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private buildAnimeItemFromPlayer(): AnimeItem {
    const item = new AnimeItem()
    item.name = this.animeName
    item.cover = this.animeCover
    item.url = this.animeUrl
    item.sourceId = this.sourceId >= 0 ? this.sourceId : this.ruleSourceId
    item.bangumiId = this.bangumiId
    item.bangumiCover = this.bangumiCover
    item.coverFallback = this.coverFallback
    item.desc = this.animeDesc
    item.sourceName = this.sourceName
    return item
  }
}
