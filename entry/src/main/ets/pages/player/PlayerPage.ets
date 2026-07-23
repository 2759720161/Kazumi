import { PlayerSurface, releaseRetainedPlayerSession } from '../../components/player/PlayerSurface'
import { EpisodePanelItem } from '../../components/player/EpisodePanel'
import { SniffErrorOverlay } from '../../components/player/SniffErrorOverlay'
import { GestureLayer } from '../../components/player/GestureLayer'
import { DanmakuCanvas } from '../../components/player/DanmakuCanvas'
import { BusinessError } from '@kit.BasicServicesKit'
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

import { DanmakuFileParser, LocalDanmakuParseResult } from '../../core/danmaku/DanmakuFileParser'
import { LocalFilePicker, LocalFileResult } from '../../services/LocalFilePicker'
import { CastEventCallbacks, CastMediaInfo, CastSessionManager } from '../../services/CastSessionManager'
import { HistorySyncService } from '../../services/HistorySyncService'
import { PiPCallbacks, PiPManager } from '../../services/PiPManager'
import { TypeNodePiPRoute, TypeNodePiPSession } from '../../services/TypeNodePiPSession'
import { PlaybackSessionActions, PlaybackSessionStore } from '../../services/PlaybackSessionStore'
import { Logger } from '../../utils/Logger'
import { router, window, PiPWindow, promptAction } from '@kit.ArkUI'
import { audio } from '@kit.AudioKit'
import { common } from '@kit.AbilityKit'
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit'

import { webview } from '@kit.ArkWeb'
import { getBottomSpacerHeight, getEffectiveTopSafeHeight } from '../../utils/HdsPageStyle'
import {
  PLAYER_AUTO_FULLSCREEN_DEFAULT,
  PLAYER_AUTO_FULLSCREEN_PHONE_SHORT_EDGE_MAX,
  PREFS_KEY_PLAYER_AUTO_FULLSCREEN
} from '../../utils/PlayerAutoFullscreen'
import {
  PLAYER_AUTO_PIP_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_PIP
} from '../../utils/PlayerAutoPiP'
import { ContinuationPlayerParams, ContinuationState } from '../../utils/ContinuationState'

const logger = new Logger('PlayerPage')
const PLAYER_LIVE_URL_KEY: string = 'playerLivePlaybackUrl'
const PLAYER_LIVE_POSITION_KEY: string = 'playerLivePlaybackPositionMs'
const PLAYER_REBUILD_RESUME_GUARD_MS: number = 3000

class JsBridgeProxy {
  private resolver: VideoSourceResolver
  private workerId: number

  constructor(resolver: VideoSourceResolver, workerId: number = 1) {
    this.resolver = resolver
    this.workerId = workerId
  }

  postMessage(message: string): void {
    this.resolver.handleJsBridgeMessage(message, this.workerId)
  }
}

class PreparedVideoSource {
  key: string = ''
  result: VideoSourceResult = new VideoSourceResult()
  createdAtMs: number = 0
}

@Entry
@Component
export struct PlayerPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('keyboardAvoidHeight') keyboardAvoidHeight: number = 0
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') appInForeground: boolean = true
  @StorageLink('danmakuSettingsVersion') @Watch('onDanmakuSettingsVersionChanged') danmakuSettingsVersion: number = 0
  @State videoUrl: string = ''
  @State animeName: string = ''
  @State episodeName: string = ''
  private bangumiId: number = 0
  @State isPlaying: boolean = false
  @State isPlayerLoading: boolean = false
  @State isPlayerBuffering: boolean = false
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
  @State episodeReverseOrder: boolean = false
  @State selectedPanelTab: number = 0
  @State sniffStatus: string = 'idle'
  @State sniffMessage: string = ''
  @State sniffRetryCount: number = 0
  @State isEpisodeSwitching: boolean = false
  @State playbackOptions: PlaybackOptions = new PlaybackOptions()
  @State liveStartPositionMs: number = 0
  @State webviewReady: boolean = false
  @State backgroundWebviewReady: boolean = false
  @State snifferWebVisible: boolean = true
  @State screenBrightness: number = 0.5
  @State isFullScreen: boolean = false
  @State isPiPActive: boolean = false
  @State private videoWidth: number = 0
  @State private videoHeight: number = 0
  @StorageLink('playerAutoFullscreen') playerAutoFullscreen: boolean = PLAYER_AUTO_FULLSCREEN_DEFAULT
  @StorageLink(PREFS_KEY_PLAYER_AUTO_PIP) playerAutoPiP: boolean = PLAYER_AUTO_PIP_DEFAULT
  private playerEngine: IPlayerEngine | null = null
  private xComponentController: XComponentController | null = null
  @State hasEngine: boolean = false
  private danmakuManager: DanmakuManager | null = null
  @State isDanmakuEnabled: boolean = true
  @State isDanmakuLoading: boolean = false
  @State showMoreMenu: boolean = false
  @State showDanmakuMatchPanel: boolean = false
  @State showEpisodeSidePanel: boolean = false
  @State showSpeedPanel: boolean = false
  @State episodePanelOffsetX: number = 0
  @State @Watch('onDanmakuSettingsVisibilityChanged') showDanmakuSettingsPanel: boolean = false
  @State @Watch('onDanmakuSettingsVisibilityChanged') showDanmakuSettingsSheet: boolean = false
  @State danmakuSettingsOpenVersion: number = 0
  @State showHud: boolean = false
  @State hudText: string = ''
  @State currentCollectType: number = CollectType.none
  @State currentAspectMode: VideoAspectMode = VideoAspectMode.contain
  @State showAspectModePanel: boolean = false
  @State showRoadPickerPopup: boolean = false
  @State showSideRoadPickerPopup: boolean = false
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
  private castSessionManager: CastSessionManager = CastSessionManager.getInstance()
  private pipManager: PiPManager = PiPManager.getInstance()
  private playbackSessionStore: PlaybackSessionStore = PlaybackSessionStore.getInstance()
  private logListener: ((event: ResolveLogEvent) => void) | null = null
  private webController: webview.WebviewController = new webview.WebviewController()
  private backgroundWebController: webview.WebviewController = new webview.WebviewController()
  private animeId: string = ''
  private animeCover: string = ''
  private animeUrl: string = ''
  private sourceId: number = -1
  private lastHistoryUpdateMs: number = 0
  private episodeUrl: string = ''
  private ruleSourceId: number = -1
  private pendingSniff: boolean = false
  private preparedVideoResults: PreparedVideoSource[] = []
  private lastSeekRequestAtMs: number = 0
  private pendingSeekMs: number = -1
  private pendingSeekTimer: number = -1
  private readonly seekThrottleMs: number = 300
  private playbackRetryCount: number = 0
  private readonly maxPlaybackRetryCount: number = 1
  private controlHideTimer: number = -1
  private hudTimer: number = -1
  private brightnessApplyTimer: number = -1
  private volumeApplyTimer: number = -1
  private danmakuSettingsReloadTimer: number = -1
  private danmakuLoadingPollTimer: number = -1
  private lastBrightnessApplyMs: number = 0
  private pendingBrightnessValue: number = -1
  private lastVolumeApplyMs: number = 0
  private pendingVolumeValue: number = -1
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
  private readonly speedOptions: number[] = [0.5, 0.75, 1.0, 1.25, 1.75, 2.0]
  private audioManager: audio.AudioManager | null = null
  private mediaVolumeMinLevel: number = -1
  private mediaVolumeMaxLevel: number = -1
  private fullscreenRestoreOrientation: window.Orientation = window.Orientation.UNSPECIFIED
  private readonly AUTO_FULLSCREEN_SETTLE_MS: number = 900
  private autoFullscreenActive: boolean = false
  private autoFullscreenEnterMs: number = 0
  private autoFullscreenExitCheckPending: boolean = false
  private lastPlayerAreaWidth: number = 0
  private lastPlayerAreaHeight: number = 0
  private isPageAlive: boolean = false
  private keepPlaybackForPiP: boolean = false
  private isRestoringFromPiP: boolean = false
  private isLeavingWithPiP: boolean = false
  private pendingAutoEnterPiP: boolean = false
  private playerStateDiagSeq: number = 0
  private lastPlayerStateDiagName: string = ''
  private lastPlayerStateDiagPlaying: boolean = false
  private lastPlayerStateDiagBucket: number = -1
  private lastPlayerStateDiagMs: number = 0
  private lastPlaybackSessionSyncMs: number = 0
  private lastPlaybackSessionStateName: string = ''
  private lastPlaybackSessionPlaying: boolean = false
  private lastPlaybackSessionPositionMs: number = -1
  private lastPlaybackSessionDurationMs: number = -1
  @State isAnimatingFullscreen: boolean = false
  @State nonVideoOpacity: number = 1

  aboutToAppear(): void {
    this.isPageAlive = true
    AppStorage.setOrCreate('playerPageActive', true)
    this.danmakuManager = new DanmakuManager()
    this.danmakuManager.init().then(() => {
      if (this.isPageAlive && this.danmakuManager !== null) {
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
      if (params['resumeTypeNodePiP'] !== undefined) {
        this.pendingAutoEnterPiP = params['resumeTypeNodePiP'] as boolean
      }
    }

    if (this.roads.length > 0 && this.selectedRoadIndex >= 0 && this.selectedRoadIndex < this.roads.length) {
      this.episodes = this.toEpisodePanelItems(this.roads[this.selectedRoadIndex])
    }
    this.visibleRoadIndex = this.selectedRoadIndex
    this.markContinuationState()

    if (this.videoUrl.length > 0) {
      const options = new PlaybackOptions()
      options.url = this.videoUrl
      if (this.historySeekMs > 0) {
        options.startPositionMs = this.historySeekMs
        this.historySeekMs = -1
      }
      this.playbackOptions = options
      this.isPlayerLoading = true
      this.isPlayerBuffering = false
    }

    this.sourceResolver.setWorkerWebController(1, this.webController)
    this.sourceResolver.setWorkerWebController(2, this.backgroundWebController)

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

    this.initializeCastSession()
    this.registerPlaybackSessionActions()
    this.initializePiP()
    this.loadSystemMediaVolume()
    this.startAutoHideTimer()
    this.setKeepScreenOn(true)
    this.loadAspectModePreference()
    this.loadPlayerAutoFullscreenPreference().then(() => {
      this.applyPlayerAutoFullscreenRuntimeState()
    }).catch((_err: Error) => {
      this.applyPlayerAutoFullscreenRuntimeState()
    })
    this.loadPlayerAutoPiPPreference()
    this.episodeGridColumns = this.getEpisodeGridColumns()
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('playerPageActive', false)
    if (this.shouldKeepPlaybackForPiP()) {
      this.setKeepScreenOn(false)
      this.saveHistory()
      this.pauseAutoHideTimer()
      this.clearHudTimer()
      this.clearBrightnessApplyTimer()
      this.clearVolumeApplyTimer()
      this.clearDanmakuSettingsReloadTimer()
      logger.info('PlayerPage aboutToDisappear skipped release for PiP')
      return
    }
    releaseRetainedPlayerSession()
    this.playbackSessionStore.reset('player')
    this.isPageAlive = false
    this.setKeepScreenOn(false)
    this.saveHistory()
    this.stopPlaybackBeforeLeaving()
    this.sourceResolver.cancel()
    if (this.logListener !== null) {
      this.sourceResolver.removeLogListener(this.logListener)
      this.logListener = null
    }
    this.clearPendingSeek()
    this.pauseAutoHideTimer()
    this.clearHudTimer()
    this.clearBrightnessApplyTimer()
    this.clearVolumeApplyTimer()
    this.clearDanmakuSettingsReloadTimer()
    this.stopDanmakuLoadingPoll()
    if (this.danmakuManager !== null) {
      this.danmakuManager.release()
      this.danmakuManager = null
    }
    if (this.isFullScreen) {
      this.setFullScreenMode(false)
    }
    this.setAutoRotationEnabled(false)
    this.pipManager.destroyPiP()
  }

  private onAppForegroundChanged(): void {
    if (this.appInForeground) {
      return
    }
    this.pauseForApplicationBackground()
  }

  private pauseForApplicationBackground(): void {
    if (!this.isPageAlive || this.shouldKeepPlaybackForPiP()) {
      return
    }
    this.saveHistory()
    if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
      logger.info('PlayerPage pause playback for app background')
      this.playerEngine.pause()
      this.isPlaying = false
      this.pauseAutoHideTimer()
    }
  }

  private shouldKeepPlaybackForPiP(): boolean {
    return this.keepPlaybackForPiP || this.isPiPActive || this.pipManager.isActive() || this.pipManager.isCreating()
  }

  private showPiPBackBlockedToast(): void {
    try {
      promptAction.showToast({ message: '画中画启动失败' })
    } catch (_err) {
    }
  }

  private handleBackFromPlayer(): boolean {
    if (this.isAnimatingFullscreen) {
      return true
    }
    if (this.isFullScreen) {
      this.toggleFullScreen()
      return true
    }
    return false
  }

  private async leavePlayerWithPiP(): Promise<void> {
    if (this.handleBackFromPlayer()) {
      return
    }
    if (!this.canLeaveWithTypeNodePiP()) {
      router.back()
      return
    }
    if (this.isLeavingWithPiP) {
      return
    }
    this.isLeavingWithPiP = true
    if (!TypeNodePiPSession.getInstance().isRunning() && this.hasEngine) {
      const started = await this.startTypeNodePiPForLeaving()
      if (!started) {
        this.showPiPBackBlockedToast()
        this.isLeavingWithPiP = false
        return
      }
    }
    if (!this.handleBackFromPlayer()) {
      router.back()
    }
  }

  onBackPress(): boolean {
    if (this.handleBackFromPlayer()) {
      return true
    }
    if (this.shouldAutoLeaveWithTypeNodePiP()) {
      this.leavePlayerWithPiP()
    } else {
      this.leavePlayerNormally()
    }
    return true
  }

  private leavePlayerNormally(): void {
    if (this.handleBackFromPlayer()) {
      return
    }
    router.back()
  }

  private canLeaveWithTypeNodePiP(): boolean {
    const url = this.videoUrl.length > 0 ? this.videoUrl : this.playbackOptions.url
    if (url.length === 0) {
      return false
    }
    if (this.sniffStatus !== 'success' && this.sniffStatus !== 'idle') {
      return false
    }
    return this.hasEngine
  }

  private shouldAutoLeaveWithTypeNodePiP(): boolean {
    return this.playerAutoPiP && this.canLeaveWithTypeNodePiP()
  }

  private async startTypeNodePiPForLeaving(): Promise<boolean> {
    const route = new TypeNodePiPRoute()
    route.url = 'pages/player/PlayerPage'
    route.params = this.buildContinuationRouteParams()
    route.params['historyPositionMs'] = this.positionMs

    const options = this.cloneCurrentPlaybackOptions()
    options.startPositionMs = this.positionMs
    // Same-session PiP restore should reuse the resolved stream instead of sniffing the episode page again.
    route.params['videoUrl'] = options.url
    const context = getContext(this) as common.UIAbilityContext
    const contentWidth = this.videoWidth > 0 ? this.videoWidth : 1920
    const contentHeight = this.videoHeight > 0 ? this.videoHeight : 1080
    return TypeNodePiPSession.getInstance().start(
      context,
      this.getUIContext(),
      options,
      route,
      contentWidth,
      contentHeight,
      contentWidth > contentHeight ? 2 : 1,
      this.isPlaying
    )
  }

  private buildContinuationRouteParams(): Record<string, Object> {
    const source = this.buildContinuationParams()
    const params: Record<string, Object> = {}
    params['videoUrl'] = source.videoUrl
    params['episodeUrl'] = source.episodeUrl
    params['ruleSourceId'] = source.ruleSourceId
    params['animeName'] = source.animeName
    params['episodeName'] = source.episodeName
    params['animeId'] = source.animeId
    params['animeCover'] = source.animeCover
    params['animeUrl'] = source.animeUrl
    params['sourceId'] = source.sourceId
    params['episodesJson'] = source.episodesJson
    params['currentEpisodeIndex'] = source.currentEpisodeIndex
    params['roadsJson'] = source.roadsJson
    params['selectedRoadIndex'] = source.selectedRoadIndex
    params['bangumiId'] = source.bangumiId
    params['bangumiCover'] = source.bangumiCover
    params['coverFallback'] = source.coverFallback
    params['animeDesc'] = source.animeDesc
    params['sourceName'] = source.sourceName
    params['historyPositionMs'] = source.historyPositionMs
    return params
  }

  private cloneCurrentPlaybackOptions(): PlaybackOptions {
    const cloned = new PlaybackOptions()
    cloned.url = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUrl
    cloned.startPositionMs = this.playbackOptions.startPositionMs
    cloned.referer = this.playbackOptions.referer
    cloned.userAgent = this.playbackOptions.userAgent
    cloned.proxy = this.playbackOptions.proxy
    cloned.streamMetadata = this.playbackOptions.streamMetadata
    cloned.isLocalFile = this.playbackOptions.isLocalFile
    cloned.localFileSize = this.playbackOptions.localFileSize
    const keys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      cloned.headers[key] = this.playbackOptions.headers[key]
    }
    return cloned
  }

  build() {
    Stack() {
      // Web uses a native rendering layer. Keep both sniff workers below the
      // player UI so their internal nodes cannot cover the retry controls.
      if (this.snifferWebVisible) {
        this.ForegroundSnifferWeb()
        this.BackgroundSnifferWeb()
      }

      if (this.shouldUseTabletPlayerLayout()) {
        this.TabletPlayerLayout()
      } else {
        this.StackedPlayerLayout()
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_media'))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.handlePlayerAreaChange(this.normalizeAreaSize(newArea.width as number),
        this.normalizeAreaSize(newArea.height as number))
    })
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
  }

  @Builder
  private StackedPlayerLayout() {
    Column() {
      Column()
        .width('100%')
        .height(this.isFullScreen ? 0 : getEffectiveTopSafeHeight(this.topSafeHeight))
        .opacity(this.nonVideoOpacity)
        .backgroundColor($r('app.color.page_background_media'))

      this.VideoSection()

      Column() {
        this.PanelSection()
      }
      .width('100%')
      .height(this.isFullScreen ? 0 : undefined)
      .layoutWeight(this.isFullScreen ? 0 : 1)
      .opacity(this.nonVideoOpacity)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(1)
    .backgroundColor(this.isFullScreen ? Color.Black : $r('app.color.page_background_media'))
  }

  @Builder
  private TabletPlayerLayout() {
    Column() {
      Column()
        .width('100%')
        .height(this.isFullScreen ? 0 : getEffectiveTopSafeHeight(this.topSafeHeight))
        .opacity(this.nonVideoOpacity)
        .backgroundColor($r('app.color.page_background_media'))

      Row() {
        Column() {
          this.VideoSection()
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Black)

        if (!this.isFullScreen) {
          Column() {
            this.PanelSection()
          }
          .width(this.getTabletPlayerPanelWidth())
          .height('100%')
          .clip(true)
          .backgroundColor($r('app.color.page_background_media'))
          .border({ width: { left: 0.5 }, color: $r('app.color.divider_color') })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .zIndex(1)
    .backgroundColor(this.isFullScreen ? Color.Black : $r('app.color.page_background_media'))
  }

  @Builder
  private ForegroundSnifferWeb() {
    Web({ src: '', controller: this.webController })
      .width(1)
      .height(1)
      .visibility(Visibility.None)
      .hitTestBehavior(HitTestMode.None)
      .focusable(false)
      .focusOnTouch(false)
      .zIndex(0)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .mixedMode(MixedMode.All)
      .javaScriptProxy({
        object: new JsBridgeProxy(this.sourceResolver, 1),
        name: 'jsBridge',
        methodList: ['postMessage'],
        controller: this.webController
      })
      .javaScriptProxy({
        object: new JsBridgeProxy(this.sourceResolver, 1),
        name: 'JSBridgeDebug',
        methodList: ['postMessage'],
        controller: this.webController
      })
      .javaScriptProxy({
        object: new JsBridgeProxy(this.sourceResolver, 1),
        name: 'VideoBridgeDebug',
        methodList: ['postMessage'],
        controller: this.webController
      })
      .onInterceptRequest((event) => {
        if (event && event.request && event.request.getRequestUrl()) {
          let url = event.request.getRequestUrl()
          let headers: Record<string, string> = {}
          const requestHeaders = event.request.getRequestHeader()
          for (let i = 0; i < requestHeaders.length; i++) {
            const header = requestHeaders[i]
            if (header.headerKey.length > 0) {
              headers[header.headerKey] = header.headerValue
            }
          }
          this.sourceResolver.handleInterceptedRequest(url, headers, 1)
        }
        return null
      })
      .onPageBegin(() => {
        this.sourceResolver.onWebViewPageBegin(1)
      })
      .onPageEnd(() => {
        this.sourceResolver.onWebViewPageEnd(1)
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (event && event.error && this.shouldLogWebViewError()) {
          logger.warn('WebView error worker=1: %{public}s', event.error.getErrorInfo())
        }
      })
      .onControllerAttached(() => {
        this.webviewReady = true
        this.sourceResolver.setWorkerWebController(1, this.webController)
        this.ensureResolveLogListener()
        if (this.pendingSniff) {
          this.pendingSniff = false
          this.startSniffing()
        }
      })
  }

  @Builder
  private BackgroundSnifferWeb() {
    Web({ src: '', controller: this.backgroundWebController })
      .width(1)
      .height(1)
      .visibility(Visibility.None)
      .hitTestBehavior(HitTestMode.None)
      .focusable(false)
      .focusOnTouch(false)
      .zIndex(0)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .mixedMode(MixedMode.All)
      .javaScriptProxy({
        object: new JsBridgeProxy(this.sourceResolver, 2),
        name: 'jsBridge',
        methodList: ['postMessage'],
        controller: this.backgroundWebController
      })
      .javaScriptProxy({
        object: new JsBridgeProxy(this.sourceResolver, 2),
        name: 'JSBridgeDebug',
        methodList: ['postMessage'],
        controller: this.backgroundWebController
      })
      .javaScriptProxy({
        object: new JsBridgeProxy(this.sourceResolver, 2),
        name: 'VideoBridgeDebug',
        methodList: ['postMessage'],
        controller: this.backgroundWebController
      })
      .onInterceptRequest((event) => {
        if (event && event.request && event.request.getRequestUrl()) {
          let url = event.request.getRequestUrl()
          let headers: Record<string, string> = {}
          const requestHeaders = event.request.getRequestHeader()
          for (let i = 0; i < requestHeaders.length; i++) {
            const header = requestHeaders[i]
            if (header.headerKey.length > 0) {
              headers[header.headerKey] = header.headerValue
            }
          }
          this.sourceResolver.handleInterceptedRequest(url, headers, 2)
        }
        return null
      })
      .onPageBegin(() => {
        this.sourceResolver.onWebViewPageBegin(2)
      })
      .onPageEnd(() => {
        this.sourceResolver.onWebViewPageEnd(2)
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (event && event.error && this.shouldLogWebViewError()) {
          logger.warn('WebView error worker=2: %{public}s', event.error.getErrorInfo())
        }
      })
      .onControllerAttached(() => {
        this.backgroundWebviewReady = true
        this.sourceResolver.setWorkerWebController(2, this.backgroundWebController)
      })
  }

  private ensureResolveLogListener(): void {
    if (this.logListener !== null) {
      return
    }
    this.logListener = (event: ResolveLogEvent) => {
      if (this.resolveLogs.length >= 50) {
        this.resolveLogs.splice(0, 1)
      }
      this.resolveLogs.push(event)
    }
    this.sourceResolver.addLogListener(this.logListener)
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
      onSetDanmakuEnabled: (enabled: boolean) => {
        this.setDanmakuEnabled(enabled)
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

      if (this.isSniffFailureStatus()) {
        SniffErrorOverlay({
          status: this.sniffStatus,
          message: this.sniffMessage,
          retryCount: this.sniffRetryCount,
          onRetry: () => {
            logger.info('SniffErrorOverlay retry tapped')
            this.startSniffing()
          },
          onBack: () => {
            logger.info('SniffErrorOverlay back tapped')
            this.leavePlayerNormally()
          }
        })
      }
    }
    .width('100%')
    .aspectRatio(this.isFullScreen || this.shouldUseTabletPlayerLayout() ? undefined : 16 / 9)
    .layoutWeight(this.isFullScreen || this.shouldUseTabletPlayerLayout() ? 1 : 0)
    .backgroundColor(Color.Black)
    .clip(true)
    .renderFit(RenderFit.RESIZE_FILL)
  }

  @Builder
  private VideoLayerContent() {
      if (this.videoUrl.length === 0) {
        if (this.sniffStatus === 'sniffing') {
          this.SniffingOverlay()
        }
      } else {
        PlayerSurface({
          videoUrl: this.videoUrl,
          playbackOptions: this.playbackOptions,
          liveStartPositionMs: this.liveStartPositionMs,
          fillParent: this.isFullScreen,
          aspectMode: this.currentAspectMode,
          keepAliveOnDisappear: this.shouldKeepPlaybackForPiP(),
          onStateChange: (state: PlayerState) => {
            this.handlePlayerState(state)
          },
          onPlayerReady: () => {
            if (this.isPageAlive) {
              logger.info('Player ready')
            }
          },
          onEngineReady: (engine: IPlayerEngine) => {
            if (!this.isPageAlive) {
              engine.stop()
              return
            }
            this.playerEngine = engine
            this.hasEngine = true
            if (this.danmakuManager !== null) {
            this.danmakuManager.init().then(() => {
              if (!this.isPageAlive) {
                return
              }
              this.isDanmakuEnabled = this.danmakuManager!.getIsDanmakuEnabled()
              if (this.danmakuManager !== null && this.animeName.length > 0) {
                this.danmakuManager.loadDanmakuForEpisode(this.animeName, this.getCurrentEpisodeNo(), this.bangumiId, this.episodeName, this.sourceId, this.episodeUrl)
                this.startDanmakuLoadingPoll()
              }
              })
            }
          },
          onSurfaceReady: (controller: XComponentController) => {
            this.xComponentController = controller
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

        if (this.shouldShowPlayerLoadingOverlay()) {
          this.PlayerLoadingOverlay()
        }

        if (this.sniffStatus === 'sniffing') {
          this.SniffingOverlay()
        }
      }

      if (this.sniffStatus === 'success' || this.sniffStatus === 'idle') {
        GestureLayer({
          durationMs: this.durationMs,
          positionMs: this.positionMs,
          volume: this.volume,
          screenBrightness: this.screenBrightness,
          isPlaying: this.isPlaying,
          isControlVisible: this.isControlVisible,
          gestureEnabled: this.isPlayerGestureEnabled(),
          onSeek: (positionMs: number) => {
            this.seekTo(positionMs)
            this.showHudText(`跳转到 ${this.formatTime(positionMs)}`)
            this.showControlsWithAutoHide()
          },
          onVolumeChange: (volume: number) => {
            this.requestSystemMediaVolume(volume)
            if (this.hasEngine && this.playerEngine !== null) {
              this.playerEngine.setVolume(volume)
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
          onSetDanmakuEnabled: (enabled: boolean) => {
            this.setDanmakuEnabled(enabled)
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

  private isSniffFailureStatus(): boolean {
    return this.sniffStatus === 'error' ||
      this.sniffStatus === 'timeout' ||
      this.sniffStatus === 'captcha'
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

      if (this.isFullScreen && this.showSpeedPanel) {
        this.SpeedPanelOverlay()
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
        } else if (this.shouldAutoLeaveWithTypeNodePiP()) {
          this.leavePlayerWithPiP()
        } else {
          this.leavePlayerNormally()
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

      if (!this.isFullScreen) {
        this.CastPickerToolButton()
      }

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
          this.MoreMenuItem('加载本地弹幕', () => {
            this.pickAndLoadLocalDanmaku()
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
          this.MoreMenuItem('加载本地弹幕', () => {
            this.pickAndLoadLocalDanmaku()
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
          this.MoreMenuItem('倍速', () => {
            this.openSpeedPanel()
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
  private SpeedPanelOverlay() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeSpeedPanel()
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.FastOutSlowIn }))

      Column() {
        Row() {
          Text('播放速度')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))

          Blank()

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([$r('app.color.text_title')])
          }
          .width(40)
          .height(40)
          .margin({ left: 12 })
          .backgroundColor($r('app.color.episode_item_unselected_bg'))
          .onClick(() => {
            this.closeSpeedPanel()
          })
        }
        .width('100%')
        .height(72)
        .padding({ left: 22, right: 14, top: 10, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.speedOptions, (item: number, index?: number) => {
              this.SpeedOptionRow(item, index)
            }, (item: number) => `player_speed_${item}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width(this.getSpeedSidePanelWidth())
      .height('100%')
      .backgroundColor($r('app.color.player_side_panel_surface'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius({ topLeft: 32, bottomLeft: 32 })
      .border({ width: { left: 0.5 }, color: $r('app.color.divider_blue') })
      .shadow({ radius: 32, color: $r('app.color.shadow_surface'), offsetX: -12 })
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
  private SpeedOptionRow(item: number, index?: number) {
    Row() {
      Text(this.formatSpeedLabel(item))
        .fontSize(17)
        .fontWeight(this.isSpeedSelected(item) ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.isSpeedSelected(item) ? $r('app.color.accent_blue') : $r('app.color.text_title'))
        .maxLines(1)

      Blank()

      if (this.isSpeedSelected(item)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%')
    .height(50)
    .padding({ left: 18, right: 18 })
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isSpeedSelected(item) ? '#1F0A84FF' : $r('app.color.episode_item_unselected_bg'))
    .border({
      width: 0.5,
      color: this.isSpeedSelected(item) ? $r('app.color.divider_blue') : $r('app.color.card_specular_border')
    })
    .onClick(() => {
      this.selectSpeed(item)
    })
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

        this.PiPToolButton()

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

      this.CastPickerToolButton()

      this.PiPToolButton()

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
        if (this.isFullScreen) {
          this.openSpeedPanel()
        } else {
          this.nextSpeed()
          this.showControlsWithAutoHide()
        }
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
      SymbolGlyph(this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off'))
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
        .draggable(false)
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
  private CastPickerToolButton() {
    Row() {
      AVCastPicker({
        normalColor: '#F2FFFFFF',
        activeColor: '#F2FFFFFF',
        onStateChange: (state: AVCastPickerState) => {
          if (state === AVCastPickerState.STATE_APPEARING) {
            this.pauseAutoHideTimer()
            this.syncCastMediaInfo()
          } else if (state === AVCastPickerState.STATE_DISAPPEARING) {
            this.showControlsWithAutoHide()
          }
        }
      })
        .width(24)
        .height(24)
    }
    .width(44)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private PiPToolButton() {
    if (PiPManager.isPiPSupported() && this.hasEngine) {
      this.ImageToolButton($r('app.media.ic_pip'), '画中画', () => {
        this.leavePlayerWithPiP()
      })
    }
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
        .backgroundColor(Color.Transparent)
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
        Column() {
          this.EpisodePanelBody()
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      }
      .padding(0)
      .width('100%')
      .height('100%')
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
        Column() {
          this.DanmakuSettingsTabBody()
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      }
      .padding(0)
      .width('100%')
      .height('100%')
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
    .fadingEdge(true)
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

          this.EpisodeOrderButton()

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
            .bindMenu(this.showRoadPickerPopup, this.RoadPickerPopupContent, {
              placement: Placement.Bottom,
              showInSubWindow: false,
              onDisappear: () => {
                this.showRoadPickerPopup = false
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 0, bottom: 2 })

        if (this.getVisibleEpisodes().length > 0) {
          Grid() {
            ForEach(this.getDisplayedEpisodes(), (ep: EpisodePanelItem, index?: number) => {
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

        Blank()
          .height(this.getEpisodePanelBottomSpacerHeight())
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
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
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          this.EpisodeOrderButton()

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
            this.showSideRoadPickerPopup = !this.showSideRoadPickerPopup
          })
          .bindMenu(this.showSideRoadPickerPopup, this.RoadPickerPopupContent, {
            placement: Placement.BottomLeft,
            showInSubWindow: false,
            onDisappear: () => {
              this.showSideRoadPickerPopup = false
            }
          })
        }

        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            if (this.getVisibleEpisodes().length > 0) {
              ForEach(this.getDisplayedEpisodes(), (ep: EpisodePanelItem, index?: number) => {
                this.SideEpisodeCard(ep, index)
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
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width(this.getPlayerSidePanelWidth())
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
      onSetDanmakuEnabled: (enabled: boolean) => {
        this.setDanmakuEnabled(enabled)
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
        if (this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(12)
            .fontColor([$r('app.color.text_on_primary')])
            .margin({ right: 4 })
        }
        Text(this.getEpisodeDisplayName(ep, this.getActualEpisodeIndex(index)))
          .fontSize(14)
          .fontWeight(this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex ? $r('app.color.text_on_primary') : $r('app.color.text_episode_unselected'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .height(52)
      .padding({ left: 12, right: 8 })
      .borderRadius(12)
      .backgroundColor(this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex ? $r('app.color.accent_blue') : $r('app.color.episode_item_unselected_bg'))

      if (this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex && this.positionMs > 0 && this.durationMs > 0) {
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
      const actualIndex = this.getActualEpisodeIndex(index)
      if (actualIndex >= 0) {
        this.onEpisodeSelected(actualIndex)
      }
    })
    .gesture(LongPressGesture({ duration: 500 })
      .onAction(() => {
        const actualIndex = this.getActualEpisodeIndex(index)
        if (actualIndex >= 0) {
          this.onEpisodeSelected(actualIndex)
          this.showHudText(`从${this.getEpisodeDisplayName(ep, actualIndex)}开始连续播放`)
        }
      })
    )
  }

  @Builder
  private SideEpisodeCard(ep: EpisodePanelItem, index?: number) {
    Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        if (this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(12)
            .fontColor([$r('app.color.text_on_primary')])
            .margin({ right: 4 })
        }
        Text(this.getEpisodeDisplayName(ep, this.getActualEpisodeIndex(index)))
          .fontSize(14)
          .fontWeight(this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex ? $r('app.color.text_on_primary') : $r('app.color.text_episode_unselected'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .height(44)
      .width('100%')
      .padding({ left: 12, right: 8 })
      .borderRadius(10)
      .backgroundColor(this.visibleRoadIndex === this.selectedRoadIndex && this.getActualEpisodeIndex(index) === this.currentEpisodeIndex ? $r('app.color.accent_blue') : $r('app.color.episode_item_unselected_bg'))
    }
    .width('48%')
    .margin({ right: '2%', bottom: 8 })
    .onClick(() => {
      const actualIndex = this.getActualEpisodeIndex(index)
      if (actualIndex >= 0) {
        this.onEpisodeSelected(actualIndex)
      }
    })
  }

  @Builder
  private EpisodeOrderButton() {
    Row() {
      Text(this.episodeReverseOrder ? '倒序' : '正序')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
    }
    .height(32)
    .padding({ left: 12, right: 12 })
    .borderRadius(16)
    .backgroundColor($r('app.color.accent_blue'))
    .margin({ left: 8 })
    .onClick(() => {
      this.episodeReverseOrder = !this.episodeReverseOrder
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private RoadPickerPopupContent() {
    Menu() {
      ForEach(this.roads, (road: PlaybackRoad, index?: number) => {
        MenuItem() {
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
          }
          .width('100%')
          .height(58)
          .padding({ left: 14, right: 14 })
          .borderRadius(14)
          .backgroundColor(index === this.visibleRoadIndex ? $r('app.color.episode_item_selected_bg') : Color.Transparent)
        }
        .onClick(() => {
          if (index !== undefined) {
            this.onRoadSelected(index)
            this.showRoadPickerPopup = false
            this.showSideRoadPickerPopup = false
          }
        })
      }, (road: PlaybackRoad, index?: number) => `road_menu_${index}`)
    }
    .width(240)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
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
        Text(this.isEpisodeSwitching ? '正在切换播放集' : '正在嗅探播放地址')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .margin({ top: 16 })
        Text(this.isEpisodeSwitching ? '当前画面会保持显示，找到新地址后自动切换' : '正在从当前线路提取可播放视频流')
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
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .zIndex(5)
  }

  @Builder
  private PlayerLoadingOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        LoadingProgress()
          .width(40)
          .height(40)
          .color($r('app.color.accent_blue_light'))
        Text(this.getPlayerLoadingTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .margin({ top: 16 })
        Text(this.getPlayerLoadingSubtitle())
          .fontSize(12)
          .fontColor('#BFFFFFFF')
          .margin({ top: 6 })
      }
      .padding({ left: 26, right: 26, top: 24, bottom: 24 })
      .borderRadius(22)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .zIndex(3)
    .hitTestBehavior(HitTestMode.None)
  }

  private getPlayerLoadingTitle(): string {
    return this.isPlayerBuffering ? '正在缓冲视频' : '正在加载视频'
  }

  private getPlayerLoadingSubtitle(): string {
    if (this.isPlayerBuffering) {
      return '网络较慢，请稍候'
    }
    return '已找到播放地址，正在初始化播放器'
  }

  private nextSpeed(): void {
    const speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.75, 2.0]
    const currentIdx = this.findCurrentSpeedIndex(speeds)
    const nextIdx = currentIdx >= 0 ? (currentIdx + 1) % speeds.length : 2
    this.changeSpeed(speeds[nextIdx])
    this.showHudText(this.formatSpeedLabel(speeds[nextIdx]))
    logger.info('Player speed changed by UI: %{public}s', this.formatSpeedLabel(speeds[nextIdx]))
  }

  private openSpeedPanel(): void {
    if (!this.isFullScreen) {
      this.nextSpeed()
      this.showControlsWithAutoHide()
      return
    }

    this.showMoreMenu = false
    this.showAspectModePanel = false
    this.showEpisodeSidePanel = false
    this.showDanmakuSettingsPanel = false
    this.showSpeedPanel = true
    this.pauseAutoHideTimer()
  }

  private closeSpeedPanel(): void {
    this.showSpeedPanel = false
  }

  private selectSpeed(speed: number): void {
    this.changeSpeed(speed)
    this.showHudText(this.formatSpeedLabel(speed))
    this.showSpeedPanel = false
    this.showControlsWithAutoHide()
    logger.info('Player speed selected by UI: %{public}s', this.formatSpeedLabel(speed))
  }

  private isSpeedSelected(speed: number): boolean {
    return Math.abs(this.speed - speed) < 0.01
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

  private setDanmakuEnabled(enabled: boolean): void {
    if (this.isDanmakuEnabled === enabled) {
      return
    }
    if (this.danmakuManager === null) {
      this.isDanmakuEnabled = enabled
      this.showHudText(enabled ? '弹幕已开启' : '弹幕已关闭')
      return
    }

    const managerEnabled = this.danmakuManager.getIsDanmakuEnabled()
    if (managerEnabled !== enabled) {
      this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
    } else {
      this.isDanmakuEnabled = enabled
    }
    this.showHudText(this.isDanmakuEnabled ? '弹幕已开启' : '弹幕已关闭')

    if (this.isDanmakuEnabled && !this.danmakuManager.hasDanmakuData()) {
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
    this.showRoadPickerPopup = false
    this.showSideRoadPickerPopup = false
    if (this.isFullScreen) {
      this.showMoreMenu = false
      this.showSpeedPanel = false
      this.showDanmakuMatchPanel = false
      this.showDanmakuSettingsPanel = false
      this.showDanmakuSettingsSheet = false
      this.pauseAutoHideTimer()
      this.showEpisodeSidePanel = true
    }
  }

  private closeEpisodeSidePanel(): void {
    this.episodePanelOffsetX = 0
    this.showRoadPickerPopup = false
    this.showSideRoadPickerPopup = false
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
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
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
    this.isPlayerLoading = false
    this.isPlayerBuffering = false
    this.sniffMessage = ''
    this.sniffRetryCount = 0

    const request = new VideoSourceRequest()
    request.episodeUrl = this.episodeUrl
    request.ruleSourceId = this.ruleSourceId

    try {
      const preparedResult = this.takePreparedResult(this.episodeUrl, this.ruleSourceId)
      if (preparedResult !== null && preparedResult.isPlayable()) {
        logger.info('Use prepared video source for episodeUrl=%{public}s',
          this.episodeUrl.length > 40 ? this.episodeUrl.substring(0, 40) + '...' : this.episodeUrl)
        logger.warn('CrashDiag sniff using prepared result: episodeHash=%{public}s videoHash=%{public}s type=%{public}s',
          this.shortHash(this.episodeUrl), this.shortHash(preparedResult.videoUrl), preparedResult.videoType)
        await this.handleSniffResult(preparedResult)
        return
      }
      const result = await this.sourceResolver.resolve(request)
      await this.handleSniffResult(result)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Sniff failed: %{public}s', msg)
      this.isEpisodeSwitching = false
      this.sniffStatus = 'error'
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.sniffMessage = '嗅探异常: ' + msg
    }
  }

  private async handleSniffResult(result: VideoSourceResult): Promise<void> {
    if (result.errorCode === ResolveErrorCode.Cancelled) {
      logger.info('Sniff result discarded: session cancelled')
      return
    }

    if (result.isPlayable()) {
      logger.warn('CrashDiag handleSniffResult playable begin: episodeHash=%{public}s videoHash=%{public}s type=%{public}s duration=%{public}dms',
        this.shortHash(this.episodeUrl), this.shortHash(result.videoUrl), result.videoType, result.sniffDurationMs)
      const request = new VideoSourceRequest()
      request.episodeUrl = this.episodeUrl
      request.ruleSourceId = this.ruleSourceId
      const optionsStartMs = Date.now()
      const options = await this.sourceResolver.buildPlaybackOptionsWithRule(result, request)
      logger.warn('CrashDiag handleSniffResult options built: elapsed=%{public}dms refererLen=%{public}d headerCount=%{public}d',
        Date.now() - optionsStartMs, options.referer.length, Object.keys(options.headers).length)

      // [REQ-TSX-001] PlayerSurface reacts to videoUrl changes, so options must be ready first.
      logger.warn('CrashDiag handleSniffResult keep sniffer webview begin')
      this.keepSnifferWebViewForPool()
      logger.warn('CrashDiag handleSniffResult assign playbackOptions begin')
      if (this.historySeekMs > 0) {
        options.startPositionMs = this.historySeekMs
        this.historySeekMs = -1
      }
      this.playbackOptions = options
      logger.warn('CrashDiag handleSniffResult assign videoUrl begin: videoHash=%{public}s',
        this.shortHash(result.videoUrl))
      this.videoUrl = result.videoUrl
      this.isEpisodeSwitching = false
      this.isPlayerLoading = true
      this.isPlayerBuffering = false
      this.sniffStatus = 'success'
      logger.warn('CrashDiag handleSniffResult syncCastMediaInfo begin')
      this.syncCastMediaInfo()
      logger.info('Sniff success: %{public}s [%{public}s] in %{public}dms',
        result.videoUrl.substring(0, 80), result.videoType, result.sniffDurationMs)
      logger.warn('CrashDiag handleSniffResult saveHistory begin')
      await this.saveHistory()
      logger.warn('CrashDiag handleSniffResult prepareNext begin')
      this.prepareNextEpisode()
      logger.warn('CrashDiag handleSniffResult playable end')
    } else if (result.errorCode === ResolveErrorCode.Captcha) {
      this.isEpisodeSwitching = false
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.sniffStatus = 'captcha'
      this.sniffMessage = result.errorMessage
    } else if (result.errorCode === ResolveErrorCode.Timeout) {
      this.isEpisodeSwitching = false
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.sniffStatus = 'timeout'
      this.sniffMessage = result.errorMessage
    } else if (result.errorCode === ResolveErrorCode.Network) {
      this.isEpisodeSwitching = false
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.sniffStatus = 'error'
      this.sniffMessage = result.errorMessage.length > 0 ? result.errorMessage : '网络错误'
    } else {
      this.isEpisodeSwitching = false
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.sniffStatus = 'error'
      this.sniffMessage = result.errorMessage.length > 0 ? result.errorMessage : '未找到视频流'
    }
    this.sniffRetryCount = result.retryCount
  }

  private removeSnifferWebView(): void {
    this.sourceResolver.cancel()
    this.pendingSniff = false
    this.webviewReady = false
    this.backgroundWebviewReady = false
    this.snifferWebVisible = false
  }

  private keepSnifferWebViewForPool(): void {
    this.pendingSniff = false
    if (!this.snifferWebVisible) {
      this.webviewReady = false
      this.backgroundWebviewReady = false
      this.snifferWebVisible = true
    }
  }

  private prepareNextEpisode(): void {
    if (!this.backgroundWebviewReady) {
      logger.info('prepareNext skipped: background WebView not ready')
      return
    }
    const nextEpisode = this.findNextEpisodeForPrepare()
    if (nextEpisode === null) {
      return
    }
    const request = new VideoSourceRequest()
    request.episodeUrl = nextEpisode.url
    request.ruleSourceId = this.ruleSourceId
    this.sourceResolver.prepareNext(request).then((result: VideoSourceResult) => {
      if (result.isPlayable()) {
        this.storePreparedResult(nextEpisode.url, this.ruleSourceId, result)
        logger.info('prepareNext success: %{public}s', result.videoUrl.substring(0, 80))
      } else if (result.errorCode !== ResolveErrorCode.Cancelled) {
        logger.info('prepareNext skipped/failed: %{public}s', result.errorMessage)
      }
    }).catch((err: Error) => {
      logger.warn('prepareNext failed: %{public}s', err.message)
    })
  }

  private findNextEpisodeForPrepare(): EpisodePanelItem | null {
    if (this.selectedRoadIndex < 0 || this.selectedRoadIndex >= this.roads.length) {
      return null
    }
    const road = this.roads[this.selectedRoadIndex]
    if (this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex < road.episodes.length - 1) {
      const item = this.toEpisodePanelItems(road)[this.currentEpisodeIndex + 1]
      return item === undefined ? null : item
    }
    for (let i = this.selectedRoadIndex + 1; i < this.roads.length; i++) {
      if (this.roads[i].episodes.length > 0) {
        const item = this.toEpisodePanelItems(this.roads[i])[0]
        return item === undefined ? null : item
      }
    }
    return null
  }

  private buildPreparedResultKey(episodeUrl: string, ruleSourceId: number): string {
    return String(ruleSourceId) + '|' + episodeUrl
  }

  private readonly preparedResultTtlMs: number = 600000

  private takePreparedResult(episodeUrl: string, ruleSourceId: number): VideoSourceResult | null {
    const key = this.buildPreparedResultKey(episodeUrl, ruleSourceId)
    const now = Date.now()
    for (let i = this.preparedVideoResults.length - 1; i >= 0; i--) {
      if (now - this.preparedVideoResults[i].createdAtMs > this.preparedResultTtlMs) {
        this.preparedVideoResults.splice(i, 1)
      }
    }
    for (let i = 0; i < this.preparedVideoResults.length; i++) {
      if (this.preparedVideoResults[i].key === key) {
        const result = this.preparedVideoResults[i].result
        this.preparedVideoResults.splice(i, 1)
        return result
      }
    }
    return null
  }

  private storePreparedResult(episodeUrl: string, ruleSourceId: number, result: VideoSourceResult): void {
    const key = this.buildPreparedResultKey(episodeUrl, ruleSourceId)
    for (let i = this.preparedVideoResults.length - 1; i >= 0; i--) {
      if (this.preparedVideoResults[i].key === key) {
        this.preparedVideoResults.splice(i, 1)
      }
    }
    const item = new PreparedVideoSource()
    item.key = key
    item.result = result
    item.createdAtMs = Date.now()
    this.preparedVideoResults.push(item)
    while (this.preparedVideoResults.length > 4) {
      this.preparedVideoResults.splice(0, 1)
    }
  }

  private handlePlayerState(state: PlayerState): void {
    if (!this.isPageAlive) {
      return
    }
    // Keep the old frame visible while the next episode is being resolved.
    // Ignore its callbacks so the old engine cannot overwrite the new episode's
    // position, duration, or error state during the handoff.
    if (this.isEpisodeSwitching) {
      return
    }
    const seq = ++this.playerStateDiagSeq
    const stateStartMs = Date.now()
    const bucket = Math.floor(state.positionMs / 1000)
    const stateChanged = state.stateName !== this.lastPlayerStateDiagName ||
      state.playing !== this.lastPlayerStateDiagPlaying ||
      Math.abs(bucket - this.lastPlayerStateDiagBucket) >= 2 ||
      state.error.length > 0
    const diagNow = Date.now()
    const shouldLog = stateChanged || seq % 30 === 0 || diagNow - this.lastPlayerStateDiagMs >= 1000
    if (shouldLog) {
      this.lastPlayerStateDiagName = state.stateName
      this.lastPlayerStateDiagPlaying = state.playing
      this.lastPlayerStateDiagBucket = bucket
      this.lastPlayerStateDiagMs = diagNow
      logger.warn('CrashDiag PlayerPage state begin: seq=%{public}d name=%{public}s playing=%{public}s pos=%{public}d dur=%{public}d errLen=%{public}d',
        seq, state.stateName, String(state.playing), state.positionMs, state.durationMs, state.error.length)
    }
    if (this.shouldIgnoreTransientRebuildZeroState(state)) {
      if (shouldLog) {
        logger.warn('CrashDiag PlayerPage ignore transient rebuild zero: seq=%{public}d state=%{public}s liveStart=%{public}d',
          seq, state.stateName, this.liveStartPositionMs)
      }
      return
    }
    this.isPlaying = state.playing
    this.updatePlayerLoadingState(state)
    this.isPlayerBuffering = this.resolvePlayerBufferingState(state)
    if (!this.isDraggingProgress) {
      this.positionMs = state.positionMs
    }
    this.durationMs = state.durationMs
    this.bufferMs = state.bufferMs
    if (state.playing && state.positionMs > 0) {
      this.liveStartPositionMs = state.positionMs
      this.cacheLivePlaybackPosition(state.positionMs)
    }
    this.markContinuationState()
    if (Math.abs(this.speed - state.speed) > 0.001) {
      this.speed = state.speed
      this.speedLabel = this.formatSpeedLabel(state.speed)
    }
    if (this.shouldSyncPlaybackSessionState(state)) {
      const sessionStartMs = Date.now()
      this.playbackSessionStore.updatePlayerState(state, 'player')
      const playbackStoreElapsed = Date.now() - sessionStartMs
      if (shouldLog || playbackStoreElapsed >= 50) {
        logger.warn('CrashDiag PlayerPage state session sync: seq=%{public}d playbackStoreElapsed=%{public}dms',
          seq, playbackStoreElapsed)
      }
    }
    if (state.durationMs > 0) {
      this.castSessionManager.updateDuration(state.durationMs)
    }
    if (state.videoWidth > 0 && state.videoHeight > 0 &&
      (state.videoWidth !== this.videoWidth || state.videoHeight !== this.videoHeight)) {
      this.videoWidth = state.videoWidth
      this.videoHeight = state.videoHeight
    }
    if (this.pipManager.isActive()) {
      this.pipManager.updatePlaybackState(state.playing)
      if (state.videoWidth > 0 && state.videoHeight > 0) {
        this.pipManager.updateContentSize(state.videoWidth, state.videoHeight)
      }
    }

    if (this.danmakuManager !== null) {
      this.danmakuManager.onPlayerStateUpdate(state)
    }

    if (state.stateName === 'playing') {
      if (state.positionMs > 0 || state.durationMs > 0) {
        this.playbackRetryCount = 0
      }
      if (this.pendingAutoEnterPiP && !this.isLeavingWithPiP) {
        this.pendingAutoEnterPiP = false
        setTimeout(() => {
          if (this.isPageAlive && this.hasEngine && !this.isLeavingWithPiP) {
            this.leavePlayerWithPiP()
          }
        }, 180)
      }
    }

    if (state.stateName === 'error' && state.error.length > 0) {
      this.playerEngine = null
      this.hasEngine = false
      if (state.error.indexOf('prepare timeout') !== -1 &&
        this.playbackRetryCount < this.maxPlaybackRetryCount) {
        this.playbackRetryCount++
        logger.warn('Playback prepare timeout, retry sniff %{public}d/%{public}d',
          this.playbackRetryCount, this.maxPlaybackRetryCount)
        this.videoUrl = ''
        this.playbackOptions = new PlaybackOptions()
        this.isPlayerLoading = false
        this.isPlayerBuffering = false
        this.sniffStatus = 'sniffing'
        this.sniffMessage = ''
        this.startSniffing()
        return
      }
      // Remove the failed native surface before rendering the retry overlay.
      // Keeping XComponentType.SURFACE mounted makes the ArkUI buttons visible
      // but prevents them from receiving touch events on some devices.
      this.videoUrl = ''
      this.playbackOptions = new PlaybackOptions()
      this.sniffStatus = 'error'
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.sniffMessage = state.error
      this.removeSnifferWebView()
      logger.warn('CrashDiag PlayerPage playback error overlay mounted: seq=%{public}d errLen=%{public}d',
        seq, state.error.length)
    }

    if (state.completed && this.hasNextEpisode()) {
      logger.info('Playback completed, auto play next episode')
      this.playNextEpisode()
    }

    if (state.playing && this.durationMs > 0 &&
      this.positionMs / this.durationMs > 0.8 &&
      !this.sourceResolver.getIsPreparingNext()) {
      this.prepareNextEpisode()
    }

    const now = Date.now()
    if (now - this.lastHistoryUpdateMs > 5000) {
      this.saveHistory()
      this.lastHistoryUpdateMs = now
    }
    const elapsed = Date.now() - stateStartMs
    if (shouldLog || elapsed >= 50) {
      logger.warn('CrashDiag PlayerPage state end: seq=%{public}d elapsed=%{public}dms',
        seq, elapsed)
    }
  }

  private shouldIgnoreTransientRebuildZeroState(state: PlayerState): boolean {
    if (this.liveStartPositionMs < PLAYER_REBUILD_RESUME_GUARD_MS || state.positionMs >= 1000 || state.completed || state.error.length > 0) {
      return false
    }
    return state.stateName === 'creating' ||
      state.stateName === 'initialized' ||
      state.stateName === 'prepared' ||
      state.stateName === 'playing'
  }

  private cacheLivePlaybackPosition(positionMs: number): void {
    const targetUrl = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUrl
    if (targetUrl.length === 0 || positionMs <= 0) {
      return
    }
    AppStorage.setOrCreate(PLAYER_LIVE_URL_KEY, targetUrl)
    AppStorage.setOrCreate(PLAYER_LIVE_POSITION_KEY, positionMs)
  }

  private clearLivePlaybackPosition(): void {
    this.liveStartPositionMs = 0
    AppStorage.setOrCreate(PLAYER_LIVE_POSITION_KEY, 0)
  }

  private updatePlayerLoadingState(state: PlayerState): void {
    if (state.stateName === 'error' || state.completed ||
      state.stateName === 'stopped' || state.stateName === 'released') {
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      return
    }

    if (state.playing || state.stateName === 'playing' || state.positionMs > 0) {
      this.isPlayerLoading = false
      return
    }

    if (this.videoUrl.length === 0 || (this.sniffStatus !== 'success' && this.sniffStatus !== 'idle')) {
      this.isPlayerLoading = false
      return
    }

    if (state.stateName === 'creating' || state.stateName === 'preparing' ||
      state.stateName === 'initialized' || state.stateName === 'prepared' || state.buffering) {
      this.isPlayerLoading = true
    }
  }

  private resolvePlayerBufferingState(state: PlayerState): boolean {
    if (!state.buffering || this.isPlayerLoading) {
      return false
    }
    if (this.videoUrl.length === 0 || (this.sniffStatus !== 'success' && this.sniffStatus !== 'idle')) {
      return false
    }
    if (state.stateName === 'error' || state.completed ||
      state.stateName === 'stopped' || state.stateName === 'released') {
      return false
    }
    return state.playing || state.stateName === 'playing' || state.positionMs > 0 || state.durationMs > 0
  }

  private shouldShowPlayerLoadingOverlay(): boolean {
    return (this.isPlayerLoading || this.isPlayerBuffering) &&
      this.videoUrl.length > 0 &&
      (this.sniffStatus === 'success' || this.sniffStatus === 'idle')
  }

  private stopPlaybackBeforeLeaving(): void {
    this.isPlaying = false
    this.isPlayerLoading = false
    this.isPlayerBuffering = false
    this.castSessionManager.updatePlaybackState(this.positionMs, false)
    if (this.playerEngine !== null) {
      try {
        this.playerEngine.stop()
      } catch (err) {
        logger.warn('Stop player before leaving failed')
      }
    }
    this.playerEngine = null
    this.hasEngine = false
  }

  private togglePlayPause(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      const nextPlaying = !this.isPlaying
      this.isPlaying = nextPlaying
      if (!nextPlaying) {
        this.playerEngine.pause()
        this.castSessionManager.sendPause()
      } else {
        this.playerEngine.play()
        this.castSessionManager.sendPlay()
      }
    }
  }

  private toggleControls(): void {
    if (this.isControlVisible) {
      this.isControlVisible = false
      this.showMoreMenu = false
      this.showAspectModePanel = false
      this.showEpisodeSidePanel = false
      this.showSpeedPanel = false
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

  private getEpisodePanelBottomSpacerHeight(): number {
    return getBottomSpacerHeight(this.bottomSafeHeight) + 16
  }

  private getControlAnimationDuration(): number {
    return this.suppressControlAnimation ? 0 : 260
  }

  private showControlsWithAutoHide(): void {
    this.isControlVisible = true
    if (!this.showMoreMenu && !this.isDraggingProgress && !this.showDanmakuSettingsPanel && !this.showDanmakuSettingsSheet && !this.showEpisodeSidePanel && !this.showAspectModePanel && !this.showSpeedPanel && this.selectedPanelTab !== 1) {
      this.startAutoHideTimer()
    }
  }

  private shouldSyncPlaybackSessionState(state: PlayerState): boolean {
    const now = Date.now()
    const stateChanged = state.stateName !== this.lastPlaybackSessionStateName ||
      state.playing !== this.lastPlaybackSessionPlaying ||
      state.completed ||
      state.error.length > 0
    const positionChanged = this.lastPlaybackSessionPositionMs < 0 ||
      Math.abs(state.positionMs - this.lastPlaybackSessionPositionMs) >= 1000
    const durationChanged = state.durationMs > 0 &&
      Math.abs(state.durationMs - this.lastPlaybackSessionDurationMs) >= 1000
    const timedSync = now - this.lastPlaybackSessionSyncMs >= 1000

    if (!stateChanged && !durationChanged && (!positionChanged || !timedSync)) {
      return false
    }

    this.lastPlaybackSessionSyncMs = now
    this.lastPlaybackSessionStateName = state.stateName
    this.lastPlaybackSessionPlaying = state.playing
    this.lastPlaybackSessionPositionMs = state.positionMs
    if (state.durationMs > 0) {
      this.lastPlaybackSessionDurationMs = state.durationMs
    }
    return true
  }

  private startAutoHideTimer(): void {
    this.pauseAutoHideTimer()
    this.controlHideTimer = setTimeout(() => {
      if (!this.isDraggingProgress && !this.showMoreMenu && !this.showDanmakuSettingsPanel && !this.showDanmakuSettingsSheet && !this.showEpisodeSidePanel && !this.showAspectModePanel && !this.showSpeedPanel && this.selectedPanelTab !== 1) {
        this.isControlVisible = false
      }
      this.controlHideTimer = -1
    }, 3000)
  }

  private isPlayerGestureEnabled(): boolean {
    return !this.showMoreMenu &&
      !this.showDanmakuMatchPanel &&
      !this.showDanmakuSettingsPanel &&
      !this.showDanmakuSettingsSheet &&
      !this.showEpisodeSidePanel &&
      !this.showAspectModePanel &&
      !this.showSpeedPanel
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

  private requestSystemMediaVolume(volume: number): void {
    const normalizedVolume = this.clampUnitValue(volume)
    this.volume = normalizedVolume
    this.pendingVolumeValue = normalizedVolume
    const now = Date.now()
    const elapsed = now - this.lastVolumeApplyMs
    if (elapsed >= 80) {
      this.applySystemMediaVolume(normalizedVolume)
      return
    }
    if (this.volumeApplyTimer >= 0) {
      return
    }
    this.volumeApplyTimer = setTimeout(() => {
      this.volumeApplyTimer = -1
      if (this.pendingVolumeValue >= 0) {
        this.applySystemMediaVolume(this.pendingVolumeValue)
      }
    }, 80 - elapsed)
  }

  private async applySystemMediaVolume(volume: number): Promise<void> {
    this.lastVolumeApplyMs = Date.now()
    const normalizedVolume = this.clampUnitValue(volume)
    try {
      const manager = this.getAudioManager()
      const minLevel = await this.getMediaVolumeMinLevel(manager)
      const maxLevel = await this.getMediaVolumeMaxLevel(manager)
      if (maxLevel <= minLevel) {
        logger.warn('Invalid system media volume range: %{public}d-%{public}d', minLevel, maxLevel)
        return
      }
      const targetLevel = Math.round(minLevel + normalizedVolume * (maxLevel - minLevel))
      await manager.setVolume(audio.AudioVolumeType.MEDIA, targetLevel)
      logger.info('Apply system media volume: level=%{public}d range=%{public}d-%{public}d',
        targetLevel, minLevel, maxLevel)
    } catch (err) {
      logger.warn('Failed to apply system media volume: %{public}s', String(err))
    }
  }

  private async loadSystemMediaVolume(): Promise<void> {
    try {
      const manager = this.getAudioManager()
      const minLevel = await this.getMediaVolumeMinLevel(manager)
      const maxLevel = await this.getMediaVolumeMaxLevel(manager)
      if (maxLevel <= minLevel) {
        return
      }
      const currentLevel = await manager.getVolume(audio.AudioVolumeType.MEDIA)
      this.volume = this.clampUnitValue((currentLevel - minLevel) / (maxLevel - minLevel))
      logger.info('Load system media volume: level=%{public}d range=%{public}d-%{public}d',
        currentLevel, minLevel, maxLevel)
    } catch (err) {
      logger.warn('Failed to load system media volume: %{public}s', String(err))
    }
  }

  private getAudioManager(): audio.AudioManager {
    if (this.audioManager === null) {
      this.audioManager = audio.getAudioManager()
    }
    return this.audioManager
  }

  private async getMediaVolumeMinLevel(manager: audio.AudioManager): Promise<number> {
    if (this.mediaVolumeMinLevel < 0) {
      this.mediaVolumeMinLevel = await manager.getMinVolume(audio.AudioVolumeType.MEDIA)
    }
    return this.mediaVolumeMinLevel
  }

  private async getMediaVolumeMaxLevel(manager: audio.AudioManager): Promise<number> {
    if (this.mediaVolumeMaxLevel < 0) {
      this.mediaVolumeMaxLevel = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA)
    }
    return this.mediaVolumeMaxLevel
  }

  private clampUnitValue(value: number): number {
    if (value < 0) {
      return 0
    }
    if (value > 1) {
      return 1
    }
    return value
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

  private clearVolumeApplyTimer(): void {
    if (this.volumeApplyTimer >= 0) {
      clearTimeout(this.volumeApplyTimer)
      this.volumeApplyTimer = -1
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
    this.showRoadPickerPopup = false
    this.showSideRoadPickerPopup = false
    this.showEpisodeSidePanel = false
    this.showSpeedPanel = false
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

  private async pickAndLoadLocalDanmaku(): Promise<void> {
    try {
    const context = getContext(this) as common.UIAbilityContext
      const fileResult: LocalFileResult | null = await LocalFilePicker.pickDanmakuFile(context)
      if (fileResult === null) {
        return
      }
      const parseResult: LocalDanmakuParseResult = DanmakuFileParser.parse(fileResult.fileName, fileResult.content)
      if (parseResult.errorMessage.length > 0) {
        this.showHudText(parseResult.errorMessage)
        return
      }
      if (this.danmakuManager !== null) {
        if (this.danmakuManager.hasDanmakuData()) {
          this.danmakuManager.appendLocalDanmaku(parseResult.items)
          this.showHudText('追加 ' + parseResult.items.length + ' 条本地弹幕')
        } else {
          this.danmakuManager.loadLocalDanmaku(parseResult.items)
          this.showHudText('加载 ' + parseResult.items.length + ' 条本地弹幕')
        }
      }
    } catch (err) {
      logger.error('加载本地弹幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('加载本地弹幕失败')
    }
  }

  private async openDanmakuMatchPanel(): Promise<void> {
    this.showMoreMenu = false
    this.showSpeedPanel = false
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
    this.liveStartPositionMs = positionMs
    if (positionMs > 0) {
      this.cacheLivePlaybackPosition(positionMs)
    } else {
      this.clearLivePlaybackPosition()
    }
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
    if (this.isAnimatingFullscreen) {
      return
    }
    this.isAnimatingFullscreen = true
    this.suppressControlAnimation = true
    this.autoFullscreenActive = false
    this.autoFullscreenEnterMs = 0
    this.autoFullscreenExitCheckPending = false
    this.isControlVisible = true
    this.showMoreMenu = false
    this.showAspectModePanel = false
    this.showSpeedPanel = false
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.showEpisodeSidePanel = false
    this.pauseAutoHideTimer()

    if (!this.isFullScreen) {
      this.getUIContext().animateTo({
        duration: 350,
        curve: Curve.FastOutSlowIn,
        onFinish: () => {
          this.setFullScreenMode(true, true)
          this.isAnimatingFullscreen = false
          this.suppressControlAnimation = false
          this.showControlsWithAutoHide()
        }
      }, () => {
        this.isFullScreen = true
        this.nonVideoOpacity = 0
      })
    } else {
      this.setFullScreenMode(false)
      setTimeout(() => {
        this.getUIContext().animateTo({
          duration: 350,
          curve: Curve.FastOutSlowIn,
          onFinish: () => {
            this.isAnimatingFullscreen = false
            this.suppressControlAnimation = false
            this.showControlsWithAutoHide()
          }
        }, () => {
          this.isFullScreen = false
          this.nonVideoOpacity = 1
        })
      }, 80)
    }
  }

  private async setFullScreenMode(fullScreen: boolean, lockLandscape: boolean = true): Promise<void> {
    AppStorage.setOrCreate('playerFullScreen', fullScreen)
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (fullScreen) {
        this.fullscreenRestoreOrientation = mainWindow.getPreferredOrientation()
        mainWindow.setWindowSystemBarEnable([])
        if (lockLandscape && this.isPhoneDevice()) {
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE)
        }
        mainWindow.enableLandscapeMultiWindow().catch((err: BusinessError) => {
          logger.warn('enableLandscapeMultiWindow failed: %{public}d', err.code)
        })
      } else {
        mainWindow.setWindowSystemBarEnable(['status', 'navigation'])
        if (this.isPhoneDevice()) {
          await mainWindow.setPreferredOrientation(this.fullscreenRestoreOrientation)
        } else {
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION)
        }
        mainWindow.disableLandscapeMultiWindow().catch((err: BusinessError) => {
          logger.warn('disableLandscapeMultiWindow failed: %{public}d', err.code)
        })
        this.fullscreenRestoreOrientation = window.Orientation.UNSPECIFIED
      }
    } catch (_err) {
      logger.warn('Failed to toggle system bars for fullscreen')
    }
  }

  private async loadPlayerAutoFullscreenPreference(): Promise<void> {
    try {
      this.playerAutoFullscreen = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_PLAYER_AUTO_FULLSCREEN,
        PLAYER_AUTO_FULLSCREEN_DEFAULT
      )
      AppStorage.setOrCreate('playerAutoFullscreen', this.playerAutoFullscreen)
    } catch (_err) {
      this.playerAutoFullscreen = PLAYER_AUTO_FULLSCREEN_DEFAULT
      AppStorage.setOrCreate('playerAutoFullscreen', PLAYER_AUTO_FULLSCREEN_DEFAULT)
    }
  }

  private async loadPlayerAutoPiPPreference(): Promise<void> {
    try {
      this.playerAutoPiP = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_PLAYER_AUTO_PIP,
        PLAYER_AUTO_PIP_DEFAULT
      )
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, this.playerAutoPiP)
    } catch (_err) {
      this.playerAutoPiP = PLAYER_AUTO_PIP_DEFAULT
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, PLAYER_AUTO_PIP_DEFAULT)
    }
  }

  private applyPlayerAutoFullscreenRuntimeState(): void {
    this.setAutoRotationEnabled(this.playerAutoFullscreen)
    if (this.playerAutoFullscreen && this.lastPlayerAreaWidth > 0 && this.lastPlayerAreaHeight > 0) {
      this.handlePlayerAreaChange(this.lastPlayerAreaWidth, this.lastPlayerAreaHeight)
    }
  }

  private normalizeAreaSize(value: number): number {
    return value > 0 ? value : 0
  }

  private handlePlayerAreaChange(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return
    }
    this.lastPlayerAreaWidth = width
    this.lastPlayerAreaHeight = height
    if (!this.playerAutoFullscreen) {
      return
    }
    const shortEdge = Math.min(width, height)
    const isPhoneWindow = shortEdge <= PLAYER_AUTO_FULLSCREEN_PHONE_SHORT_EDGE_MAX
    if (!isPhoneWindow) {
      return
    }
    if (width > height && !this.isFullScreen) {
      this.enterAutoFullscreen()
    } else if (height >= width && this.isFullScreen && this.autoFullscreenActive) {
      if (this.isAutoFullscreenSettling()) {
        return
      }
      this.confirmAutoFullscreenExit(width, height)
    }
  }

  private isAutoFullscreenSettling(): boolean {
    return this.autoFullscreenActive && this.autoFullscreenEnterMs > 0 &&
      Date.now() - this.autoFullscreenEnterMs < this.AUTO_FULLSCREEN_SETTLE_MS
  }

  private async confirmAutoFullscreenExit(areaWidth: number, areaHeight: number): Promise<void> {
    if (this.autoFullscreenExitCheckPending) {
      return
    }
    this.autoFullscreenExitCheckPending = true
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      const rect = mainWindow.getWindowProperties().windowRect
      if (rect.width > rect.height) {
        logger.info('Ignore auto fullscreen exit while window is landscape: area=%{public}dx%{public}d window=%{public}dx%{public}d',
          Math.round(areaWidth), Math.round(areaHeight), rect.width, rect.height)
        return
      }
      logger.info('Confirm auto fullscreen exit: area=%{public}dx%{public}d window=%{public}dx%{public}d',
        Math.round(areaWidth), Math.round(areaHeight), rect.width, rect.height)
      this.exitAutoFullscreen()
    } catch (_err) {
      logger.warn('Confirm auto fullscreen exit fallback: %{public}s', _err instanceof Error ? _err.message : String(_err))
      this.exitAutoFullscreen()
    } finally {
      this.autoFullscreenExitCheckPending = false
    }
  }

  private enterAutoFullscreen(): void {
    if (this.isAnimatingFullscreen) {
      return
    }
    this.isAnimatingFullscreen = true
    this.autoFullscreenActive = true
    this.autoFullscreenEnterMs = Date.now()
    this.autoFullscreenExitCheckPending = false
    this.suppressControlAnimation = true
    this.isControlVisible = true
    this.showMoreMenu = false
    this.showAspectModePanel = false
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.showEpisodeSidePanel = false
    this.pauseAutoHideTimer()

    this.getUIContext().animateTo({
      duration: 350,
      curve: Curve.FastOutSlowIn,
      onFinish: () => {
        this.setFullScreenMode(true, false)
        this.isAnimatingFullscreen = false
        this.suppressControlAnimation = false
        this.showControlsWithAutoHide()
      }
    }, () => {
      this.isFullScreen = true
      this.nonVideoOpacity = 0
    })
  }

  private exitAutoFullscreen(): void {
    if (this.isAnimatingFullscreen) {
      return
    }
    this.isAnimatingFullscreen = true
    this.autoFullscreenActive = false
    this.autoFullscreenEnterMs = 0
    this.autoFullscreenExitCheckPending = false
    this.suppressControlAnimation = true
    this.setFullScreenMode(false)
    this.setAutoRotationEnabled(true)
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 350,
        curve: Curve.FastOutSlowIn,
        onFinish: () => {
          this.isAnimatingFullscreen = false
          this.suppressControlAnimation = false
          this.showControlsWithAutoHide()
        }
      }, () => {
        this.isFullScreen = false
        this.nonVideoOpacity = 1
      })
    }, 80)
  }

  private async setAutoRotationEnabled(enabled: boolean): Promise<void> {
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (this.isPhoneDevice()) {
        if (enabled) {
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION)
        } else {
          await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        }
      } else {
        // Tablet: always allow auto rotation
        await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION)
      }
    } catch (_err) {
      logger.warn('Failed to set auto rotation: %{public}s', _err instanceof Error ? _err.message : String(_err))
    }
  }

  private isPhoneDevice(): boolean {
    return this.screenWidthVp < 600
  }

  private shouldUseTabletPlayerLayout(): boolean {
    return this.screenWidthVp >= 840
  }

  private getTabletPlayerPanelWidth(): number {
    if (this.screenWidthVp >= 1200) {
      return 420
    }
    return 360
  }

  private getPlayerSidePanelWidth(): Dimension {
    if (this.screenWidthVp <= 0) {
      return '40%'
    }
    const targetWidth = Math.round(this.screenWidthVp * 0.4)
    if (this.screenWidthVp < 840) {
      return Math.max(320, targetWidth)
    }
    return Math.min(Math.max(360, targetWidth), 560)
  }

  private getSpeedSidePanelWidth(): Dimension {
    if (this.screenWidthVp <= 0) {
      return 300
    }
    if (this.screenWidthVp < 720) {
      return Math.min(300, Math.max(260, Math.round(this.screenWidthVp * 0.42)))
    }
    return Math.min(340, Math.max(300, Math.round(this.screenWidthVp * 0.28)))
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

  private hasPreviousEpisode(): boolean {
    if (this.selectedRoadIndex >= 0 && this.selectedRoadIndex < this.roads.length) {
      if (this.currentEpisodeIndex > 0) {
        return true
      }
      for (let i = this.selectedRoadIndex - 1; i >= 0; i--) {
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

  private playPreviousEpisode(): void {
    if (this.selectedRoadIndex >= 0 && this.selectedRoadIndex < this.roads.length) {
      if (this.currentEpisodeIndex > 0) {
        this.visibleRoadIndex = this.selectedRoadIndex
        this.onEpisodeSelected(this.currentEpisodeIndex - 1)
        return
      }
      for (let i = this.selectedRoadIndex - 1; i >= 0; i--) {
        if (this.roads[i].episodes.length > 0) {
          this.visibleRoadIndex = i
          this.onEpisodeSelected(this.roads[i].episodes.length - 1)
          return
        }
      }
    }
  }

  private onEpisodeSelected(index: number): void {
    const visibleEpisodes = this.getVisibleEpisodes()
    if (index >= 0 && index < visibleEpisodes.length) {
      this.saveHistory()
      const keepCurrentVideo = this.hasEngine && this.videoUrl.length > 0
      this.isEpisodeSwitching = keepCurrentVideo
      this.stopBeforeSniff()
      this.selectedRoadIndex = this.visibleRoadIndex
      this.episodes = this.toEpisodePanelItems(this.roads[this.visibleRoadIndex])
      this.currentEpisodeIndex = index
      this.episodeName = visibleEpisodes[index].name
      this.episodeUrl = visibleEpisodes[index].url
      if (!keepCurrentVideo) {
        this.videoUrl = ''
        this.syncCastMediaInfo()
      }
      this.isPlayerLoading = false
      this.isPlayerBuffering = false
      this.positionMs = 0
      this.durationMs = 0
      this.bufferMs = 0
      this.clearLivePlaybackPosition()
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
    // Keep the current player surface alive during episode resolution. Once
    // playback options for the new episode arrive, PlayerSurface replaces the
    // engine through its normal target-change path.
    this.sourceResolver.cancel()
    this.pendingSniff = false
    this.syncCastMediaInfo()
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

  private getDisplayedEpisodes(): EpisodePanelItem[] {
    const items = this.getVisibleEpisodes()
    if (!this.episodeReverseOrder) {
      return items
    }
    const result: EpisodePanelItem[] = []
    for (let i = items.length - 1; i >= 0; i--) {
      result.push(items[i])
    }
    return result
  }

  private getActualEpisodeIndex(displayIndex: number | undefined): number {
    if (displayIndex === undefined) {
      return -1
    }
    const count = this.getVisibleEpisodes().length
    if (displayIndex < 0 || displayIndex >= count) {
      return -1
    }
    return this.episodeReverseOrder ? count - 1 - displayIndex : displayIndex
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
    const historyAnimeId = this.buildHistoryAnimeId()
    const historyEpisodeUrl = this.episodeUrl.length > 0 ? this.episodeUrl : this.videoUrl
    if (historyAnimeId.length === 0 || historyEpisodeUrl.length === 0) {
      return
    }
    try {
      const record = new HistoryRecord()
      record.animeId = historyAnimeId
      record.animeName = this.animeName
      record.animeCover = this.animeCover
      record.animeUrl = this.animeUrl
      record.bangumiId = this.bangumiId
      record.sourceId = this.sourceId >= 0 ? this.sourceId : this.ruleSourceId
      record.episodeName = this.episodeName
      record.episodeUrl = historyEpisodeUrl
      record.positionMs = this.positionMs
      record.durationMs = this.durationMs
      record.roadIndex = this.selectedRoadIndex
      record.episodeIndex = this.currentEpisodeIndex
      await this.historyStore.upsert(record)
      HistorySyncService.getInstance().scheduleAutoUploadAfterLocalChange()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Save history failed: %{public}s', msg)
    }
  }

  private buildHistoryAnimeId(): string {
    if (this.animeId.length > 0) {
      return this.animeId
    }

    const sourceId = this.sourceId >= 0 ? this.sourceId : this.ruleSourceId
    const identityUrl = this.animeUrl.length > 0 ? this.animeUrl : this.episodeUrl
    if (sourceId >= 0 && identityUrl.length > 0) {
      return String(sourceId) + '_' + identityUrl
    }

    if (identityUrl.length > 0) {
      return identityUrl
    }

    return this.animeName
  }

  private markContinuationState(): void {
    ContinuationState.markPlayer(this.buildContinuationParams(), this.positionMs)
  }

  private buildContinuationParams(): ContinuationPlayerParams {
    const sourceId = this.sourceId >= 0 ? this.sourceId : this.ruleSourceId
    const params = new ContinuationPlayerParams()
    params.videoUrl = this.episodeUrl.length > 0 ? '' : this.videoUrl
    params.episodeUrl = this.episodeUrl
    params.ruleSourceId = this.ruleSourceId
    params.animeName = this.animeName
    params.episodeName = this.episodeName
    params.animeId = this.animeId
    params.animeCover = this.animeCover
    params.animeUrl = this.animeUrl
    params.sourceId = sourceId
    params.episodesJson = JSON.stringify(this.episodes)
    params.currentEpisodeIndex = this.currentEpisodeIndex
    params.roadsJson = JSON.stringify(this.roads)
    params.selectedRoadIndex = this.selectedRoadIndex
    params.bangumiId = this.bangumiId
    params.bangumiCover = this.bangumiCover
    params.coverFallback = this.coverFallback
    params.animeDesc = this.animeDesc
    params.sourceName = this.sourceName
    params.historyPositionMs = this.positionMs
    return params
  }

  private performSeek(positionMs: number): void {
    if (!this.hasEngine || this.playerEngine === null) {
      return
    }
    this.lastSeekRequestAtMs = Date.now()
    this.playerEngine.seek(positionMs)
    this.castSessionManager.sendSeek(positionMs)
  }

  private initializeCastSession(): void {
    const context = getContext(this) as common.UIAbilityContext
    this.castSessionManager.setCallbacks(this.buildCastCallbacks())
    this.castSessionManager.ensureVideoSession(context).then(() => {
      this.syncCastMediaInfo()
    }).catch((_err: Error) => {
      logger.warn('initializeCastSession failed')
    })
  }

  private registerPlaybackSessionActions(): void {
    const actions = new PlaybackSessionActions()
    actions.onPlay = () => {
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
      }
    }
    actions.onPause = () => {
      if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
        this.playerEngine.pause()
        this.isPlaying = false
      }
    }
    actions.onSeek = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    actions.onFastForward = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    actions.onRewind = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    actions.onNext = () => {
      this.playNextEpisode()
    }
    actions.onPrevious = () => {
      this.playPreviousEpisode()
    }
    this.playbackSessionStore.setActions(actions, 'player')
    this.syncPlaybackSessionMedia()
  }

  private buildCastCallbacks(): CastEventCallbacks {
    const callbacks = new CastEventCallbacks()
    callbacks.onPlay = () => {
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
      }
    }
    callbacks.onPause = () => {
      if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
        this.playerEngine.pause()
        this.isPlaying = false
      }
    }
    callbacks.onSeek = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    callbacks.onFastForward = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    callbacks.onRewind = (positionMs: number) => {
      this.seekTo(positionMs)
    }
    callbacks.onPlayNext = () => {
      this.playNextEpisode()
    }
    callbacks.onPlayPrevious = () => {
      this.playPreviousEpisode()
    }
    callbacks.onCastDeviceConnected = () => {
      if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
        this.playerEngine.pause()
        this.isPlaying = false
      }
    }
    callbacks.onCastDeviceDisconnected = () => {
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
      }
    }
    callbacks.onEndOfStream = () => {
      if (this.hasNextEpisode()) {
        this.playNextEpisode()
      } else {
        this.castSessionManager.stopCasting()
      }
    }
    callbacks.onRemotePositionChange = (positionMs: number) => {
      if (!this.isDraggingProgress) {
        this.positionMs = positionMs
      }
    }
    return callbacks
  }

  private syncCastMediaInfo(): void {
    if (this.videoUrl.length === 0 || this.playbackOptions.isLocalFile) {
      this.castSessionManager.setCastSupported(false)
      this.syncPlaybackSessionMedia()
      return
    }

    const info = new CastMediaInfo()
    info.url = this.videoUrl
    info.title = this.animeName.length > 0 ? this.animeName : this.buildPlayerTitle()
    info.subtitle = this.episodeName
    info.cover = this.getCastCover()
    info.durationMs = this.durationMs
    info.positionMs = this.positionMs
    info.hasNext = this.hasNextEpisode()
    info.hasPrevious = this.hasPreviousEpisode()
    this.castSessionManager.updateMedia(info)
    this.castSessionManager.setCastSupported(true)
    this.syncPlaybackSessionMedia()
    if (this.pipManager.isActive()) {
      this.pipManager.setNextPreviousEnabled(this.hasNextEpisode(), this.hasPreviousEpisode())
    }
  }

  private syncPlaybackSessionMedia(): void {
    const url = this.videoUrl.length > 0 ? this.videoUrl : this.playbackOptions.url
    if (url.length === 0) {
      return
    }
    this.playbackSessionStore.updateMedia(url,
      this.animeName.length > 0 ? this.animeName : this.buildPlayerTitle(),
      this.episodeName,
      this.getCastCover(),
      this.durationMs,
      this.positionMs,
      this.hasNextEpisode(),
      this.hasPreviousEpisode(),
      this.playbackOptions.isLocalFile,
      'player')
  }

  private getCastCover(): string {
    if (this.bangumiCover.length > 0) {
      return this.bangumiCover
    }
    if (this.animeCover.length > 0) {
      return this.animeCover
    }
    if (this.coverFallback.length > 0) {
      return this.coverFallback
    }
    return ''
  }

  private initializePiP(): void {
    this.pipManager.setCallbacks(this.buildPiPCallbacks())
  }

  private async startPiP(): Promise<boolean> {
    if (this.pipManager.isActive() || this.pipManager.isCreating()) {
      return true
    }
    if (this.xComponentController === null) {
      logger.warn('PiP: XComponentController not available')
      return false
    }
    if (this.isFullScreen) {
      this.toggleFullScreen()
      await new Promise<void>((resolve) => setTimeout(resolve, 400))
    }
    this.pauseAutoHideTimer()
    const context = getContext(this) as common.UIAbilityContext
    const contentWidth = this.videoWidth > 0 ? this.videoWidth : 1920
    const contentHeight = this.videoHeight > 0 ? this.videoHeight : 1080
    const isWideContent = contentWidth > contentHeight
    const controlGroups: Array<PiPWindow.VideoPlayControlGroup> = [
      PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT
    ]
    const success = await this.pipManager.createAndStart(
      context, this.xComponentController, contentWidth, contentHeight, controlGroups,
      isWideContent ? 2 : 1)
    if (success) {
      this.keepPlaybackForPiP = true
      this.isRestoringFromPiP = false
      this.isPiPActive = true
      this.pipManager.updatePlaybackState(this.isPlaying)
      this.pipManager.setNextPreviousEnabled(this.hasNextEpisode(), this.hasPreviousEpisode())
    }
    return success
  }

  private buildPiPCallbacks(): PiPCallbacks {
    const callbacks = new PiPCallbacks()
    callbacks.onPlay = () => {
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
        this.pipManager.updatePlaybackState(true)
      }
    }
    callbacks.onPause = () => {
      if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
        this.playerEngine.pause()
        this.isPlaying = false
        this.pipManager.updatePlaybackState(false)
      }
    }
    callbacks.onNext = () => {
      this.playNextEpisode()
    }
    callbacks.onPrevious = () => {
      this.playPreviousEpisode()
    }
    callbacks.onFastForward = () => {
      if (this.hasEngine && this.playerEngine !== null) {
        this.seekTo(Math.min(this.positionMs + 15000, this.durationMs))
      }
    }
    callbacks.onFastBackward = () => {
      if (this.hasEngine && this.playerEngine !== null) {
        this.seekTo(Math.max(this.positionMs - 15000, 0))
      }
    }
    callbacks.onRestore = () => {
      this.isPageAlive = true
      this.keepPlaybackForPiP = false
      this.isRestoringFromPiP = true
      if (this.hasEngine && this.playerEngine !== null && !this.isPlaying) {
        this.playerEngine.play()
        this.isPlaying = true
      }
      this.isPiPActive = false
    }
    callbacks.onPiPStopped = () => {
      if (this.isRestoringFromPiP) {
        this.isRestoringFromPiP = false
        this.keepPlaybackForPiP = false
        this.isPiPActive = false
        return
      }
      if (this.keepPlaybackForPiP) {
        this.stopPlaybackBeforeLeaving()
      }
      this.keepPlaybackForPiP = false
      this.isPiPActive = false
    }
    return callbacks
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

  private async toggleCollect(): Promise<void> {
    try {
      const animeItem = this.buildAnimeItemFromPlayer()
      if (CollectType.isFavorite(this.currentCollectType)) {
        await this.collectController.deleteCollect(animeItem)
        this.currentCollectType = CollectType.none
      } else {
        await this.collectController.addCollect(animeItem, CollectType.favorite)
        this.currentCollectType = CollectType.favorite
      }
    } catch (err) {
      logger.error('Toggle collect failed: %{public}s', err instanceof Error ? err.message : String(err))
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

  private shortHash(value: string): string {
    let hash = 0
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
    }
    return String(value.length) + ':' + String(hash)
  }
}
