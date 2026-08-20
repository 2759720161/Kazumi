import { PlayerSurface, releaseRetainedPlayerSession } from '../../components/player/PlayerSurface'
import { GestureLayer } from '../../components/player/GestureLayer'
import { DanmakuCanvas } from '../../components/player/DanmakuCanvas'
import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode, VideoAspectModeHelper } from '../../core/player/IPlayerEngine'
import { DanmakuManager } from '../../core/danmaku/DanmakuManager'
import { BusinessError } from '@kit.BasicServicesKit'
import { DanmakuFileParser, LocalDanmakuParseResult } from '../../core/danmaku/DanmakuFileParser'
import { LocalFilePicker, LocalFileResult } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { DanmakuSettingsPanelContent } from '../../components/player/DanmakuSettingsPanel'
import { DanmakuSettingsSidePanel } from '../../components/player/DanmakuSettingsSidePanel'
import { AspectModePanel } from '../../components/player/AspectModePanel'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { DanmakuItem } from '../../models/DanmakuItem'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { PiPCallbacks, PiPManager } from '../../services/PiPManager'
import { TypeNodePiPRoute, TypeNodePiPSession } from '../../services/TypeNodePiPSession'
import { PlaybackSessionActions, PlaybackSessionStore } from '../../services/PlaybackSessionStore'
import { router, window, PiPWindow, promptAction } from '@kit.ArkUI'
import { KeyCode } from '@ohos.multimodalInput.keyCode'
import { common } from '@kit.AbilityKit'
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit'
import { CastEventCallbacks, CastMediaInfo, CastSessionManager } from '../../services/CastSessionManager'
import { fileIo } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import {
  createConfiguredImmersiveMaterial,
} from '../../utils/ImmersiveMaterial'
import {
  PLAYER_AUTO_FULLSCREEN_DEFAULT,
  PLAYER_AUTO_FULLSCREEN_PHONE_SHORT_EDGE_MAX,
  PREFS_KEY_PLAYER_AUTO_FULLSCREEN
} from '../../utils/PlayerAutoFullscreen'
import {
  PLAYER_AUTO_PIP_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_PIP
} from '../../utils/PlayerAutoPiP'

const logger = new Logger('LocalPlayerPage')

const HISTORY_SAVE_INTERVAL_MS: number = 5000
const PLAYER_LIVE_URL_KEY: string = 'playerLivePlaybackUrl'
const PLAYER_LIVE_POSITION_KEY: string = 'playerLivePlaybackPositionMs'
const PLAYER_REBUILD_RESUME_GUARD_MS: number = 3000

@Entry
@Component
export struct LocalPlayerPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('appInForeground') @Watch('onAppForegroundChanged') appInForeground: boolean = true
  @StorageLink('danmakuSettingsVersion') @Watch('onDanmakuSettingsVersionChanged') danmakuSettingsVersion: number = 0
  @State videoUri: string = ''
  @State videoFileName: string = ''
  @State isPlaying: boolean = false
  @State positionMs: number = 0
  @State liveStartPositionMs: number = 0
  @State durationMs: number = 0
  @State speed: number = 1.0
  @State speedLabel: string = '1x'
  @State isControlVisible: boolean = true
  @State isDraggingProgress: boolean = false
  @State isFullScreen: boolean = false
  @State isPiPActive: boolean = false
  @State private videoWidth: number = 0
  @State private videoHeight: number = 0
  @State private danmakuCanvasWidth: number = 0
  @State private danmakuCanvasHeight: number = 0
  @State private danmakuCanvasOffsetX: number = 0
  @State private danmakuCanvasOffsetY: number = 0
  @StorageLink('playerAutoFullscreen') playerAutoFullscreen: boolean = PLAYER_AUTO_FULLSCREEN_DEFAULT
  @StorageLink(PREFS_KEY_PLAYER_AUTO_PIP) playerAutoPiP: boolean = PLAYER_AUTO_PIP_DEFAULT
  @State playbackOptions: PlaybackOptions = new PlaybackOptions()
  @State playbackQueue: LocalVideoRecord[] = []
  @State currentQueueIndex: number = -1
  @State screenBrightness: number = 0.5
  @State volume: number = 1.0
  private playerEngine: IPlayerEngine | null = null
  private xComponentController: XComponentController | null = null
  private pendingQueueTargetUri: string = ''
  private pendingQueueStartPositionMs: number = 0
  private queueSwitchSawPreparing: boolean = false
  @State hasEngine: boolean = false
  private danmakuManager: DanmakuManager | null = null
  @State isDanmakuEnabled: boolean = true
  @State showHud: boolean = false
  @State hudText: string = ''
  @State playbackErrorText: string = ''
  @State danmakuFileName: string = ''
  @State currentAspectMode: VideoAspectMode = VideoAspectMode.contain
  @State showAspectModePanel: boolean = false
  @State showSpeedMenu: boolean = false
  @State showDanmakuSettingsPanel: boolean = false
  @State showDanmakuSettingsSheet: boolean = false
  @State showDanmakuManageSheet: boolean = false
  @State danmakuSettingsOpenVersion: number = 0
  @State showDanmakuLoadDialog: boolean = false
  @State showDanmakuOffsetPanel: boolean = false
  @State danmakuOffsetMs: number = 0
  @State danmakuLoadedFormat: string = ''
  @State danmakuLoadedCount: number = 0
  @State danmakuUri: string = ''
  @State pendingDanmakuItems: DanmakuItem[] = []
  @State pendingDanmakuFileName: string = ''
  @State pendingDanmakuFormat: string = ''
  @State pendingDanmakuUri: string = ''
  private controlHideTimer: number = -1
  private hudTimer: number = -1
  private keepScreenOnRequestToken: number = 0
  private keepScreenOnEnabled: boolean = false
  private keepScreenOnRequested: boolean = false
  private wasPlayingBeforeDrag: boolean = false
  private lastHistorySaveMs: number = 0
  private historySeekMs: number = -1
  private lastKnownPositionMs: number = 0
  private videoFileSize: number = 0
  private drmScheme: string = ''
  private drmPluginName: string = ''
  private drmOfflineKeyId: string = ''
  private localVideoHistoryStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private fullscreenRestoreOrientation: window.Orientation = window.Orientation.UNSPECIFIED
  private playerLayoutSyncTimer: number = -1
  private fullscreenTransitionTimer: number = -1
  private readonly FULLSCREEN_ROTATION_SETTLE_MS: number = 180
  private readonly AUTO_FULLSCREEN_SETTLE_MS: number = 900
  private autoFullscreenActive: boolean = false
  private autoFullscreenEnterMs: number = 0
  private autoFullscreenExitCheckPending: boolean = false
  private lastPlayerAreaWidth: number = 0
  private lastPlayerAreaHeight: number = 0
  private isPageAlive: boolean = false
  private pipManager: PiPManager = PiPManager.getInstance()
  private playbackSessionStore: PlaybackSessionStore = PlaybackSessionStore.getInstance()
  private castSessionManager: CastSessionManager = CastSessionManager.getInstance()
  private localCastSourceFile: fileIo.File | null = null
  private localCastSourceFileSize: number = 0
  private keepPlaybackForPiP: boolean = false
  private isRestoringFromPiP: boolean = false
  private isLeavingWithPiP: boolean = false
  private lastPlaybackSessionSyncMs: number = 0
  private lastPlaybackSessionStateName: string = ''
  private lastPlaybackSessionPlaying: boolean = false
  private lastPlaybackSessionPositionMs: number = -1
  private lastPlaybackSessionDurationMs: number = -1
  private completionHandledForUrl: string = ''
  @State isAnimatingFullscreen: boolean = false
  @State suppressControlAnimation: boolean = false
  @State hideBottomControlsForFullscreenTransition: boolean = false

  aboutToAppear(): void {
    this.isPageAlive = true
    this.syncKeepScreenOnWithPlayback()
    AppStorage.setOrCreate('playerPageActive', true)
    this.pipManager.setCallbacks(this.buildPiPCallbacks())
    this.registerPlaybackSessionActions()
    this.danmakuManager = new DanmakuManager()
    this.danmakuManager.init().then(() => {
      if (this.isPageAlive && this.danmakuManager !== null) {
        this.isDanmakuEnabled = this.danmakuManager.getIsDanmakuEnabled()
        this.restoreDanmakuFromHistory()
      }
    })

    const rawParams = router.getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      const videoUri = params['videoUri']
      const videoFileName = params['videoFileName']
      const videoFileSize = params['videoFileSize']
      const historyPositionMs = params['historyPositionMs']
      const danmakuUri = params['danmakuUri']
      const danmakuFileName = params['danmakuFileName']
      const danmakuOffsetMs = params['danmakuOffsetMs']
      const danmakuFormat = params['danmakuFormat']
      const danmakuCount = params['danmakuCount']
      const drmScheme = params['drmScheme']
      const drmPluginName = params['drmPluginName']
      const drmOfflineKeyId = params['drmOfflineKeyId']
      const playlistJson = params['playlistJson']
      const queueIndex = params['queueIndex']

      if (typeof videoUri === 'string') this.videoUri = videoUri
      if (typeof videoFileName === 'string') this.videoFileName = videoFileName
      if (typeof videoFileSize === 'number') this.videoFileSize = videoFileSize
      if (typeof historyPositionMs === 'number') {
        this.historySeekMs = historyPositionMs
        if (historyPositionMs > 0) {
          this.lastKnownPositionMs = historyPositionMs
        }
      }
      if (typeof danmakuUri === 'string') this.danmakuUri = danmakuUri
      if (typeof danmakuFileName === 'string') this.danmakuFileName = danmakuFileName
      if (typeof danmakuOffsetMs === 'number') this.danmakuOffsetMs = danmakuOffsetMs
      if (typeof danmakuFormat === 'string') this.danmakuLoadedFormat = danmakuFormat
      if (typeof danmakuCount === 'number') this.danmakuLoadedCount = danmakuCount
      if (typeof drmScheme === 'string') this.drmScheme = drmScheme
      if (typeof drmPluginName === 'string') this.drmPluginName = drmPluginName
      if (typeof drmOfflineKeyId === 'string') this.drmOfflineKeyId = drmOfflineKeyId
      if (typeof playlistJson === 'string') {
        this.playbackQueue = this.decodePlaybackQueue(playlistJson)
      }
      if (typeof queueIndex === 'number' && queueIndex >= 0 && queueIndex < this.playbackQueue.length) {
        this.currentQueueIndex = queueIndex
      }
    }

    if (this.videoUri.length > 0) {
      this.ensurePlaybackQueueForCurrentVideo()
      const options = new PlaybackOptions()
      options.url = this.videoUri
      options.isLocalFile = true
      options.localFileSize = this.videoFileSize
      options.drmScheme = this.drmScheme
      options.drmPluginName = this.drmPluginName
      options.drmOfflineKeyId = this.drmOfflineKeyId
      if (this.historySeekMs > 0) {
        options.startPositionMs = this.historySeekMs
        this.historySeekMs = -1
        this.showHudText('继续播放 ' + this.formatTime(options.startPositionMs))
      }
      this.playbackOptions = options
      this.syncPlaybackSessionMedia()
      this.initializeLocalCastSession()
      this.enterFullscreenOnOpen()
    }

    this.startAutoHideTimer()
    this.loadAspectModePreference()
    this.loadPlayerAutoPiPPreference()
    this.loadPlayerAutoFullscreenPreference().then(() => {
      this.applyPlayerAutoFullscreenRuntimeState()
    }).catch((_err: Error) => {
      this.applyPlayerAutoFullscreenRuntimeState()
    })
    setTimeout(() => {
      if (this.isPageAlive) {
        try {
          this.getUIContext().getFocusController().requestFocus('localPlayerKeyboardTarget')
        } catch (_err) {
          // The target can temporarily have an unfocusable ancestor during page transitions.
          logger.warn('Local player keyboard target is not focusable yet')
        }
      }
    }, 0)
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('playerPageActive', false)
    this.setKeepScreenOn(false)
    this.clearPlayerAspectSyncTimer()
    this.clearFullscreenTransitionTimer()
    if (this.shouldKeepPlaybackForPiP()) {
      this.pauseAutoHideTimer()
      this.clearHudTimer()
      if (this.videoUri.length > 0) {
        this.saveLocalHistory(false)
      }
      logger.info('LocalPlayerPage aboutToDisappear skipped release for PiP')
      return
    }
    void this.stopLocalCastSession()
    releaseRetainedPlayerSession()
    this.playbackSessionStore.reset('local-player')
    this.isPageAlive = false
    this.pauseAutoHideTimer()
    this.clearHudTimer()
    if (this.videoUri.length > 0) {
      this.saveLocalHistory(true)
    }
    this.stopPlaybackBeforeLeaving()
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

  private shouldKeepPlaybackForPiP(): boolean {
    return this.keepPlaybackForPiP || this.isPiPActive || this.pipManager.isActive() || this.pipManager.isCreating()
  }

  private onAppForegroundChanged(): void {
    if (this.appInForeground) {
      this.syncKeepScreenOnWithPlayback()
      return
    }
    this.setKeepScreenOn(false)
    this.pauseForApplicationBackground()
  }

  private pauseForApplicationBackground(): void {
    if (!this.isPageAlive || this.shouldKeepPlaybackForPiP()) {
      return
    }
    if (this.videoUri.length > 0) {
      this.saveLocalHistory(true)
    }
    if (this.hasEngine && this.playerEngine !== null && this.isPlaying) {
      logger.info('LocalPlayerPage pause playback for app background')
      this.playerEngine.pause()
      this.isPlaying = false
      this.pauseAutoHideTimer()
    }
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

  private shouldAutoLeaveWithTypeNodePiP(): boolean {
    return this.playerAutoPiP && this.canLeaveWithTypeNodePiP()
  }

  private canLeaveWithTypeNodePiP(): boolean {
    return this.videoUri.length > 0 && this.hasEngine
  }

  private async startTypeNodePiPForLeaving(): Promise<boolean> {
    const route = new TypeNodePiPRoute()
    route.url = 'pages/player/LocalPlayerPage'
    route.params = this.buildLocalPlayerRouteParams()

    const options = this.cloneCurrentPlaybackOptions()
    options.startPositionMs = this.positionMs
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

  private buildLocalPlayerRouteParams(): Record<string, Object> {
    const params: Record<string, Object> = {}
    params['videoUri'] = this.videoUri
    params['videoFileName'] = this.videoFileName
    params['videoFileSize'] = this.videoFileSize
    params['historyPositionMs'] = this.positionMs
    params['danmakuUri'] = this.danmakuUri
    params['danmakuFileName'] = this.danmakuFileName
    params['danmakuOffsetMs'] = this.danmakuOffsetMs
    params['danmakuFormat'] = this.danmakuLoadedFormat
    params['danmakuCount'] = this.danmakuLoadedCount
    params['drmScheme'] = this.drmScheme
    params['drmPluginName'] = this.drmPluginName
    params['drmOfflineKeyId'] = this.drmOfflineKeyId
    params['playlistJson'] = JSON.stringify(this.playbackQueue)
    params['queueIndex'] = this.currentQueueIndex
    return params
  }

  private cloneCurrentPlaybackOptions(): PlaybackOptions {
    const cloned = new PlaybackOptions()
    cloned.url = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUri
    cloned.startPositionMs = this.playbackOptions.startPositionMs
    cloned.referer = this.playbackOptions.referer
    cloned.userAgent = this.playbackOptions.userAgent
    cloned.proxy = this.playbackOptions.proxy
    cloned.streamMetadata = this.playbackOptions.streamMetadata
    cloned.isLocalFile = true
    cloned.localFileSize = this.playbackOptions.localFileSize
    cloned.drmScheme = this.playbackOptions.drmScheme
    cloned.drmPluginName = this.playbackOptions.drmPluginName
    cloned.drmOfflineKeyId = this.playbackOptions.drmOfflineKeyId
    cloned.drmMimeType = this.playbackOptions.drmMimeType
    const keys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      cloned.headers[key] = this.playbackOptions.headers[key]
    }
    return cloned
  }

  private decodePlaybackQueue(raw: string): LocalVideoRecord[] {
    const result: LocalVideoRecord[] = []
    try {
      const parsed = JSON.parse(raw) as Object[]
      for (let i = 0; i < parsed.length; i++) {
        const data = parsed[i] as Record<string, Object>
        const item = new LocalVideoRecord()
        const fileUri = data['fileUri']
        if (typeof fileUri !== 'string' || fileUri.length === 0) {
          continue
        }
        item.fileUri = fileUri
        if (typeof data['fileName'] === 'string') item.fileName = data['fileName'] as string
        if (typeof data['fileSize'] === 'number') item.fileSize = data['fileSize'] as number
        if (typeof data['coverUri'] === 'string') item.coverUri = data['coverUri'] as string
        if (typeof data['durationMs'] === 'number') item.durationMs = data['durationMs'] as number
        if (typeof data['positionMs'] === 'number') item.positionMs = data['positionMs'] as number
        if (typeof data['lastPlayedAt'] === 'number') item.lastPlayedAt = data['lastPlayedAt'] as number
        if (typeof data['danmakuFileName'] === 'string') item.danmakuFileName = data['danmakuFileName'] as string
        if (typeof data['danmakuUri'] === 'string') item.danmakuUri = data['danmakuUri'] as string
        if (typeof data['danmakuOffsetMs'] === 'number') item.danmakuOffsetMs = data['danmakuOffsetMs'] as number
        if (typeof data['danmakuFormat'] === 'string') item.danmakuFormat = data['danmakuFormat'] as string
        if (typeof data['danmakuCount'] === 'number') item.danmakuCount = data['danmakuCount'] as number
        if (typeof data['drmScheme'] === 'string') item.drmScheme = data['drmScheme'] as string
        if (typeof data['drmPluginName'] === 'string') item.drmPluginName = data['drmPluginName'] as string
        if (typeof data['drmOfflineKeyId'] === 'string') item.drmOfflineKeyId = data['drmOfflineKeyId'] as string
        result.push(item)
      }
    } catch (err) {
      logger.warn('解析播放队列失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return result
  }

  private ensurePlaybackQueueForCurrentVideo(): void {
    if (this.playbackQueue.length === 0) {
      const item = new LocalVideoRecord()
      item.fileUri = this.videoUri
      item.fileName = this.videoFileName
      item.fileSize = this.videoFileSize
      item.positionMs = this.historySeekMs > 0 ? this.historySeekMs : 0
      this.playbackQueue = [item]
      this.currentQueueIndex = 0
      return
    }
    if (this.currentQueueIndex >= 0 && this.currentQueueIndex < this.playbackQueue.length &&
      this.playbackQueue[this.currentQueueIndex].fileUri === this.videoUri) {
      return
    }
    for (let i = 0; i < this.playbackQueue.length; i++) {
      if (this.playbackQueue[i].fileUri === this.videoUri) {
        this.currentQueueIndex = i
        return
      }
    }
    const item = new LocalVideoRecord()
    item.fileUri = this.videoUri
    item.fileName = this.videoFileName
    item.fileSize = this.videoFileSize
    item.positionMs = this.historySeekMs > 0 ? this.historySeekMs : 0
    this.playbackQueue.push(item)
    this.currentQueueIndex = this.playbackQueue.length - 1
  }

  private playPreviousQueueItem(): void {
    if (this.currentQueueIndex <= 0) {
      promptAction.showToast({ message: '已经是第一集了' })
      return
    }
    this.playQueueItem(this.currentQueueIndex - 1, false)
  }

  private playNextQueueItem(autoPlay: boolean): void {
    const nextIndex = this.currentQueueIndex + 1
    if (nextIndex >= this.playbackQueue.length) {
      if (!autoPlay) {
        promptAction.showToast({ message: '已经是最后一集了' })
      }
      return
    }
    this.playQueueItem(nextIndex, autoPlay)
  }

  private async playQueueItem(index: number, autoPlay: boolean): Promise<void> {
    if (index < 0 || index >= this.playbackQueue.length) {
      return
    }
    const item = this.playbackQueue[index]
    if (!await LocalFilePicker.ensureReadableUri(item.fileUri)) {
      this.showHudText('视频暂时不可访问')
      return
    }

    this.captureCurrentQueueProgress()
    const startPositionMs = this.normalizeQueuePosition(item.positionMs, item.durationMs)
    this.pendingQueueTargetUri = item.fileUri
    this.pendingQueueStartPositionMs = startPositionMs
    this.queueSwitchSawPreparing = false
    this.currentQueueIndex = index
    this.videoUri = item.fileUri
    this.videoFileName = item.fileName
    this.videoFileSize = item.fileSize
    this.positionMs = 0
    this.durationMs = 0
    this.lastKnownPositionMs = startPositionMs
    this.clearLivePlaybackPosition()
    this.liveStartPositionMs = startPositionMs
    this.playbackErrorText = ''
    this.completionHandledForUrl = ''
    this.drmScheme = item.drmScheme
    this.drmPluginName = item.drmPluginName
    this.drmOfflineKeyId = item.drmOfflineKeyId
    this.clearDanmakuState()
    this.danmakuFileName = item.danmakuFileName
    this.danmakuUri = item.danmakuUri
    this.danmakuOffsetMs = item.danmakuOffsetMs
    this.danmakuLoadedFormat = item.danmakuFormat
    this.danmakuLoadedCount = item.danmakuCount
    if (this.danmakuFileName.length > 0 && this.danmakuUri.length > 0) {
      this.restoreDanmakuFromHistory()
    }

    const options = new PlaybackOptions()
    options.url = item.fileUri
    options.isLocalFile = true
    options.localFileSize = item.fileSize
    options.startPositionMs = startPositionMs
    options.drmScheme = item.drmScheme
    options.drmPluginName = item.drmPluginName
    options.drmOfflineKeyId = item.drmOfflineKeyId
    this.playerEngine = null
    this.hasEngine = false
    this.playbackOptions = options
    this.syncPlaybackSessionMedia()
    void this.initializeLocalCastSession()
    this.showHudText(autoPlay ? '正在播放下一项' : '已切换视频')
  }

  private normalizeQueuePosition(positionMs: number, durationMs: number): number {
    if (positionMs <= 0 || durationMs <= 0) {
      return Math.max(0, positionMs)
    }
    return positionMs >= durationMs * 0.995 || durationMs - positionMs <= 3000 ? 0 : positionMs
  }

  private captureCurrentQueueProgress(): void {
    if (this.currentQueueIndex < 0 || this.currentQueueIndex >= this.playbackQueue.length ||
      this.playbackQueue[this.currentQueueIndex].fileUri !== this.videoUri) {
      return
    }
    const currentItem = this.playbackQueue[this.currentQueueIndex]
    let currentPositionMs = this.positionMs
    let currentDurationMs = this.durationMs
    if (this.playerEngine !== null) {
      const state = this.playerEngine.getState()
      if (state.positionMs >= 0) currentPositionMs = state.positionMs
      if (state.durationMs > 0) currentDurationMs = state.durationMs
    }
    currentItem.positionMs = Math.max(0, currentPositionMs)
    currentItem.durationMs = Math.max(0, currentDurationMs)
    this.saveLocalHistory()
  }

  build() {
    Stack() {
      this.PlayerState()
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.handlePlayerAreaChange(this.normalizeAreaSize(newArea.width as number),
        this.normalizeAreaSize(newArea.height as number))
    })
  }

  @Builder
  PlayerState(): void {
    Stack() {
      Column() {
        this.VideoSection()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)

      if (this.showDanmakuManageSheet) {
        this.DanmakuManageOverlay()
      }

      if (this.showDanmakuSettingsSheet && !this.isFullScreen) {
        this.DanmakuSettingsOverlay()
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_media'))
    .bindSheet($$this.showDanmakuLoadDialog, this.buildDanmakuLoadDialog, {
      height: 280,
      showClose: false,
      dragBar: false,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showDanmakuLoadDialog = false
        this.startAutoHideTimer()
      }
    })
    .bindSheet($$this.showDanmakuOffsetPanel, this.buildDanmakuOffsetPanel, {
      height: 240,
      showClose: false,
      dragBar: true,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showDanmakuOffsetPanel = false
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
    .layoutWeight(1)
    .backgroundColor(Color.Black)
    .clip(true)
    .renderFit(RenderFit.RESIZE_FILL)
    .id('localPlayerKeyboardTarget')
    .focusable(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handlePlayerKeyEvent(event)
    })
  }

  @Builder
  private VideoLayerContent() {
    if (this.videoUri.length > 0) {
      PlayerSurface({
        videoUrl: this.videoUri,
        playbackOptions: this.playbackOptions,
        liveStartPositionMs: this.liveStartPositionMs,
        fillParent: this.isFullScreen,
        aspectMode: this.currentAspectMode,
        keepAliveOnDisappear: this.shouldKeepPlaybackForPiP(),
        onStateChange: (state: PlayerState) => {
          this.handlePlayerState(state)
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
              })
            }
          },
          onSurfaceReady: (controller: XComponentController) => {
            this.xComponentController = controller
          },
          onVideoLayoutChange: (width: number, height: number, offsetX: number, offsetY: number) => {
            this.danmakuCanvasWidth = width
            this.danmakuCanvasHeight = height
            this.danmakuCanvasOffsetX = offsetX
            this.danmakuCanvasOffsetY = offsetY
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
        .width(this.danmakuCanvasWidth > 0 ? this.danmakuCanvasWidth : '100%')
        .height(this.danmakuCanvasHeight > 0 ? this.danmakuCanvasHeight : '100%')
        .position({ x: this.danmakuCanvasOffsetX, y: this.danmakuCanvasOffsetY })
        .zIndex(2)
    } else {
      Column() {
        Text('未选择视频文件')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }

    GestureLayer({
      durationMs: this.durationMs,
      positionMs: this.positionMs,
      volume: this.volume,
      screenBrightness: this.screenBrightness,
      isPlaying: this.isPlaying,
      isControlVisible: this.isControlVisible,
      gestureEnabled: !this.shouldDisablePlayerGestures(),
      onSeek: (positionMs: number) => {
        this.seekTo(positionMs)
        this.showHudText('跳转到 ' + this.formatTime(positionMs))
        this.showControlsWithAutoHide()
      },
      onVolumeChange: (volume: number) => {
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
      onMouseSingleClick: () => {
        this.togglePlayPause()
        this.showHudText(this.isPlaying ? '播放' : '暂停')
      },
      onMouseDoubleClick: () => {
        this.toggleFullScreen()
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

    if (this.showHud) {
      this.HudView()
    }

    if (this.playbackErrorText.length > 0 && !this.isFullScreen) {
      this.PlaybackErrorOverlay()
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

      if (this.showAspectModePanel) {
        this.AspectModePanelOverlay()
      }
      if (this.showSpeedMenu) {
        this.SpeedMenuOverlay()
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
          this.leavePlayerWithPiP()
        }
      })

      Text(this.videoFileName.length > 0 ? this.videoFileName : '本地播放')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })

      this.ProjectionToolButton()
      this.PiPToolButton()

      this.TopSymbolButton($r('sys.symbol.rectangle_4_group_1'), '视频比例', () => {
        this.showAspectModePanel = true
        this.pauseAutoHideTimer()
      })
    }
    .width('100%')
    .height(this.topSafeHeight + 68)
    .padding({ left: 10, right: 14, top: this.topSafeHeight + 8, bottom: 8 })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#AA000000', 0.0], ['#5C000000', 0.55], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : -12 })
    .opacity(this.isControlVisible ? 1 : 0)
    .hitTestBehavior(this.isControlVisible ? HitTestMode.Default : HitTestMode.None)
    .animation({ duration: this.getControlAnimationDuration(), curve: Curve.EaseInOut })
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
    .opacity(this.shouldShowBottomControlLayer() ? 1 : 0)
    .hitTestBehavior(this.shouldShowBottomControlLayer() ? HitTestMode.Default : HitTestMode.None)
    .animation({ duration: this.getControlAnimationDuration(), curve: Curve.EaseInOut })
  }

  @Builder
  private LandscapeProgressRow() {
    Column({ space: 2 }) {
      this.ProgressUtilityRow()
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
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 2 })
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
      .hitTestBehavior(this.shouldShowBottomControlLayer() ? HitTestMode.Default : HitTestMode.None)
      .onChange((value: number, mode: SliderChangeMode) => {
        if (!this.shouldShowBottomControlLayer()) {
          return
        }
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
      this.ProgressUtilityRow()

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

      this.PrimaryPlaybackControls()
    }
    .width('100%')
    .padding({ bottom: (this.bottomSafeHeight > 0 ? this.bottomSafeHeight : 0) + 16 })
  }

  @Builder
  private ProgressUtilityRow(): void {
    Row() {
      Blank()
        .layoutWeight(1)
      Row({ space: 2 }) {
        this.UtilityDanmakuToggleButton()
        this.UtilitySymbolButton($r('sys.symbol.barrage_setting'), '弹幕设置', () => {
          this.openDanmakuSettings()
        })
      }
    }
    .width('100%')
    .height(32)
    .padding({ left: 2, right: 2 })
  }

  @Builder
  private LandscapeControlRow() {
    Column() {
      this.PrimaryPlaybackControls()
    }
    .height(this.bottomSafeHeight + 62)
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: this.bottomSafeHeight + 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PrimaryPlaybackControls(): void {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 6 }) {
        this.SeekControlButton(false)
        this.TopSymbolButton($r('sys.symbol.backward_end_fill'), '上一集', () => {
          this.playPreviousQueueItem()
        })

        if (this.isPlaying) {
          this.TopSymbolButton($r('sys.symbol.pause_fill'), '暂停', () => {
            this.togglePlayPause()
          })
        } else {
          this.TopSymbolButton($r('sys.symbol.play_fill'), '播放', () => {
            this.togglePlayPause()
          })
        }

        this.TopSymbolButton($r('sys.symbol.forward_end_fill'), '下一集', () => {
          this.playNextQueueItem(false)
        })
        this.SeekControlButton(true)
      }
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        if (!this.isFullScreen) {
          this.SpeedToolButton()
        }
        Blank()
          .layoutWeight(1)
        if (this.isFullScreen) {
          this.SpeedToolButton()
        }
        this.SymbolToolButton(this.isFullScreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
          $r('sys.symbol.arrow_up_left_and_arrow_down_right'), this.isFullScreen ? '退出全屏' : '全屏', () => {
          this.toggleFullScreen()
        })
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height(50)
    .padding({ left: 10, right: 10, bottom: 8 })
  }

  @Builder
  private SeekControlButton(forward: boolean): void {
    this.TopSymbolButton(forward ? $r('sys.symbol.goforward_15') : $r('sys.symbol.gobackward_15'),
      forward ? '前进 15 秒' : '后退 15 秒', () => {
      this.seekByFifteenSeconds(forward)
    })
  }

  @Builder
  private SpeedToolButton() {
    Row() {
      this.CurrentSpeedSymbol()
    }
    .width(44)
    .height(40)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      if (this.showSpeedMenu) {
        this.closeSpeedMenu()
      } else {
        this.openSpeedMenu()
      }
    })
  }

  @Builder
  private CurrentSpeedSymbol(): void {
    if (this.speed === 0.5) {
      SymbolGlyph($r('sys.symbol.speed_50percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 0.75) {
      SymbolGlyph($r('sys.symbol.speed_75percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 1.25) {
      SymbolGlyph($r('sys.symbol.speed_125percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 1.5) {
      SymbolGlyph($r('sys.symbol.speed_150percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 2.0) {
      SymbolGlyph($r('sys.symbol.speed_200percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    } else if (this.speed === 3.0) {
      Text('3×')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
    } else {
      SymbolGlyph($r('sys.symbol.speed_100percent'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
  }

  @Builder
  private UtilitySymbolButton(symbol: Resource, accessibilityLabel: string, action: () => void): void {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(36)
    .height(30)
    .borderRadius(15)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      action()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private UtilityDanmakuToggleButton(): void {
    Row() {
      SymbolGlyph(this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off'))
        .fontSize(22)
        .renderingStrategy(this.isDanmakuEnabled ? SymbolRenderingStrategy.MULTIPLE_COLOR : SymbolRenderingStrategy.SINGLE)
        .fontColor(this.isDanmakuEnabled ?
          ['#F2FFFFFF', $r('app.color.accent_blue'), $r('app.color.accent_blue')] :
          ['#F2FFFFFF'])
    }
    .width(36)
    .height(30)
    .borderRadius(15)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!this.isPlayerControlActionAllowed()) {
        return
      }
      this.toggleDanmaku()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private TopSymbolButton(symbol: Resource, accessibilityLabel: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
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
  private ProjectionToolButton() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.wireless_projection'))
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
      // AVCastPicker owns the system device picker. Keep the requested
      // wireless projection symbol as the visible button surface.
      AVCastPicker({
        normalColor: '#00FFFFFF',
        activeColor: '#00FFFFFF',
        sessionType: 'video',
        onStateChange: (state: AVCastPickerState) => {
          if (state === AVCastPickerState.STATE_APPEARING) {
            this.pauseAutoHideTimer()
            this.syncCastMediaInfo()
          } else if (state === AVCastPickerState.STATE_DISAPPEARING) {
            this.showControlsWithAutoHide()
          }
        }
      })
        .width(44)
        .height(44)
        .opacity(0.01)
    }
    .width(44)
    .height(44)
    .borderRadius(22)
  }

  @Builder
  private PiPToolButton() {
    if (PiPManager.isPiPSupported() && this.hasEngine) {
      Row() {
        SymbolGlyph($r('sys.symbol.smal_window_playback'))
          .fontSize(22)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor('#00000000')
      .border({ width: 0, color: '#00000000' })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (!this.isPlayerControlActionAllowed()) {
          return
        }
        this.startPiPFromControl()
        this.showControlsWithAutoHide()
      })
    }
  }

  @Builder
  private SymbolToolButton(symbol: Resource, accessibilityLabel: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(23)
        .fontColor([$r('app.color.text_on_primary')])
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
  private DanmakuToggleButton() {
    Row() {
      SymbolGlyph(this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off'))
        .fontSize(23)
        .renderingStrategy(this.isDanmakuEnabled ? SymbolRenderingStrategy.MULTIPLE_COLOR : SymbolRenderingStrategy.SINGLE)
        .fontColor(this.isDanmakuEnabled ?
          ['#F2FFFFFF', $r('app.color.accent_blue'), $r('app.color.accent_blue')] :
          ['#F2FFFFFF'])
    }
    .width(44)
    .height(40)
    .borderRadius(20)
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
  private PlaybackErrorOverlay() {
    Column() {
      Text(this.playbackErrorText)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 12 })
      Row({ space: 10 }) {
        if (this.canAuthorizeCurrentVideo()) {
          Button('重新授权')
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(12)
            .onClick(() => {
              this.authorizeCurrentVideo()
            })
        }
        Button('重新选择')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .borderRadius(12)
          .onClick(() => {
            this.pickVideoFile()
          })
      }
      .width('76%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .zIndex(12)
  }

  @Builder
  private AspectModePanelOverlay() {
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
        }
      })
        .margin({ top: this.isFullScreen ? this.topSafeHeight + 46 : 46, right: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(9)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private SpeedMenuOverlay() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .hitTestBehavior(HitTestMode.Default)
        .onClick(() => {
          this.closeSpeedMenu()
        })

      Column() {
        Scroll() {
          Column() {
            this.SpeedMenuItem(3.0)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(2.0)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.75)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.5)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.25)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(1.0)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(0.75)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(0.5)
            this.SpeedMenuDivider()
            this.SpeedMenuItem(0.25)
          }
          .width('100%')
        }
        .width('100%')
        .height(364)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .hitTestBehavior(HitTestMode.Default)
      }
      .width(104)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.speed_menu_surface'))
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
      .margin({ right: 12, bottom: this.isFullScreen ? this.bottomSafeHeight + 74 : this.bottomSafeHeight + 66 })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
  }

  @Builder
  private SpeedMenuItem(value: number) {
    Row() {
      Text(this.formatPlaybackSpeed(value))
        .fontSize(15)
        .fontWeight(Math.abs(this.speed - value) < 0.01 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      if (Math.abs(this.speed - value) < 0.01) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.brand')])
      }
    }
      .width('100%')
      .height(40)
      .padding({ left: 14, right: 14 })
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.setPlaybackSpeed(value)
        this.closeSpeedMenu()
      })
  }

  @Builder
  private SpeedMenuDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.category_menu_divider'))
      .margin({ left: 14, right: 14 })
  }

  private openSpeedMenu(): void {
    this.showSpeedMenu = true
    this.pauseAutoHideTimer()
  }

  private closeSpeedMenu(): void {
    this.showSpeedMenu = false
    this.showControlsWithAutoHide()
  }

  private shouldDisablePlayerGestures(): boolean {
    return this.showSpeedMenu || this.showAspectModePanel || this.showDanmakuSettingsPanel ||
      this.showDanmakuSettingsSheet || this.showDanmakuManageSheet || this.showDanmakuLoadDialog ||
      this.showDanmakuOffsetPanel
  }

  @Builder
  private DanmakuManageOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showDanmakuManageSheet = false
          this.startAutoHideTimer()
        })

      Column() {
        Row() {
          Text('弹幕')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('sys.color.icon_secondary')])
            .width(40)
            .height(40)
            .onClick(() => {
              this.showDanmakuManageSheet = false
              this.startAutoHideTimer()
            })
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)

        Text(this.buildCurrentDanmakuText())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 16 })

        Column({ space: 10 }) {
          this.DanmakuManageAction(this.danmakuFileName.length > 0 ? '更换弹幕' : '加载弹幕',
            '选择 XML / JSON / ASS 文件', $r('sys.symbol.doc_text'), true, () => {
            this.runAfterDanmakuManageClosed(() => {
              this.pickAndLoadLocalDanmaku()
            })
          })
          this.DanmakuManageAction('弹幕设置', '显示密度、透明度、字号等', $r('sys.symbol.barrage_setting'), false, () => {
            this.runAfterDanmakuManageClosed(() => {
              this.openDanmakuSettings()
            })
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: this.bottomSafeHeight + 18 })
      .borderRadius({ topLeft: 18, topRight: 18 })
      .backgroundColor($r('app.color.card_background'))
      .systemMaterial(createConfiguredImmersiveMaterial())
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: -6 })
    }
    .width('100%')
    .height('100%')
    .zIndex(30)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
  }

  @Builder
  private DanmakuManageAction(title: string, subtitle: string, symbol: Resource, primary: boolean, action: () => void) {
    Row({ space: 12 }) {
      Stack() {
        Circle()
          .width(34)
          .height(34)
          .fill(primary ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
          .opacity(primary ? 0.18 : 1)
        SymbolGlyph(symbol)
          .fontSize(19)
          .fontColor([primary ? $r('app.color.accent_blue') : $r('sys.color.icon_secondary')])
      }
      .width(36)
      .height(36)

      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private DanmakuSettingsOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeDanmakuSettings()
        })

      Column() {
        Row() {
          Blank()
            .layoutWeight(1)
          Rect()
            .width(36)
            .height(4)
            .borderRadius(2)
            .fill($r('app.color.divider_color'))
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height(18)
        .alignItems(VerticalAlign.Center)

        this.buildDanmakuSettingsSheet()
      }
      .width('100%')
      .height('70%')
      .borderRadius({ topLeft: 18, topRight: 18 })
      .clip(true)
      .backgroundColor($r('app.color.page_background'))
      .systemMaterial(createConfiguredImmersiveMaterial())
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: -6 })
    }
    .width('100%')
    .height('100%')
    .zIndex(40)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
  }

  @Builder
  buildDanmakuSettingsSheet() {
    DanmakuSettingsPanelContent({
      isDanmakuEnabled: this.isDanmakuEnabled,
      isFullScreen: this.isFullScreen,
      settingsVersion: this.danmakuSettingsOpenVersion,
      showSourceFilter: false,
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
  buildDanmakuLoadDialog() {
    Column() {
      Text('弹幕已存在')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 24, bottom: 4 })
      Text('当前已有 ' + this.danmakuLoadedCount + ' 条弹幕，如何处理新加载的 ' + this.pendingDanmakuItems.length + ' 条弹幕？')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 20 })
        .padding({ left: 24, right: 24 })

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(12)
          .onClick(() => {
            this.showDanmakuLoadDialog = false
            this.pendingDanmakuItems = []
            this.pendingDanmakuFileName = ''
            this.pendingDanmakuFormat = ''
            this.pendingDanmakuUri = ''
          })

        Button('追加')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            this.applyPendingDanmaku(true)
            this.showDanmakuLoadDialog = false
          })

        Button('替换')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.status_error'))
          .fontColor(Color.White)
          .borderRadius(12)
          .onClick(() => {
            this.applyPendingDanmaku(false)
            this.showDanmakuLoadDialog = false
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20 })
    }
    .width('100%')
  }

  @Builder
  buildDanmakuOffsetPanel() {
    Column() {
      Text('弹幕时间校准')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 20, bottom: 8 })

      Text('当前偏移: ' + this.formatOffset(this.danmakuOffsetMs))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 16 })

      Row({ space: 8 }) {
        Button('-5s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(-5000))
        Button('-1s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(-1000))
        Button('重置')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(10)
          .onClick(() => this.resetDanmakuOffset())
        Button('+1s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(1000))
        Button('+5s')
          .layoutWeight(1)
          .height(44)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onClick(() => this.adjustDanmakuOffset(5000))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 20 })
    }
    .width('100%')
  }

  private handlePlayerState(state: PlayerState): void {
    if (!this.isPageAlive) {
      return
    }
    if (this.shouldIgnoreTransientRebuildZeroState(state)) {
      logger.info('LocalPlayerPage ignore transient rebuild zero: state=%{public}s liveStart=%{public}d',
        state.stateName, this.liveStartPositionMs)
      return
    }
    if (this.shouldIgnorePendingQueueSwitchState(state)) {
      return
    }
    this.isPlaying = state.playing
    this.syncKeepScreenOnWithPlayback()
    this.positionMs = state.positionMs
    if (state.positionMs > 0) {
      this.lastKnownPositionMs = state.positionMs
    }
    if (state.playing && state.positionMs > 0) {
      this.liveStartPositionMs = state.positionMs
      this.cacheLivePlaybackPosition(state.positionMs)
    }
    this.durationMs = state.durationMs
    this.volume = state.volume
    this.speed = state.speed
    this.speedLabel = this.formatPlaybackSpeed(this.speed)
    if (this.shouldSyncPlaybackSessionState(state)) {
      this.playbackSessionStore.updatePlayerState(state, 'local-player')
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

    if (state.error.length > 0) {
      logger.warn('Local playback error: %{public}s', state.error)
      this.playbackErrorText = '本地文件访问失败，请重新授权或重新选择'
      this.showHudText('本地文件访问失败')
    } else if (this.playbackErrorText.length > 0 && state.playing) {
      this.playbackErrorText = ''
    }

    if (this.videoUri.length > 0 && this.durationMs > 0 && this.lastKnownPositionMs > 0) {
      const now = Date.now()
      if (now - this.lastHistorySaveMs >= HISTORY_SAVE_INTERVAL_MS) {
        this.lastHistorySaveMs = now
        this.saveLocalHistory()
      }
    }
  }

  private togglePlayPause(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      const nextPlaying = !this.isPlaying
      this.isPlaying = nextPlaying
      this.syncKeepScreenOnWithPlayback()
      if (!nextPlaying) {
        this.playerEngine.pause()
        void this.castSessionManager.sendPause()
      } else {
        this.playerEngine.play()
        void this.castSessionManager.sendPlay()
      }
    }
  }

  private async setKeepScreenOn(keepScreenOn: boolean): Promise<void> {
    if (this.keepScreenOnRequested === keepScreenOn && this.keepScreenOnEnabled === keepScreenOn) {
      return
    }
    this.keepScreenOnRequested = keepScreenOn
    const requestToken = ++this.keepScreenOnRequestToken
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const mainWindow = await window.getLastWindow(context)
      if (requestToken !== this.keepScreenOnRequestToken) {
        return
      }
      await mainWindow.setWindowKeepScreenOn(keepScreenOn)
      this.keepScreenOnEnabled = keepScreenOn
      if (requestToken !== this.keepScreenOnRequestToken) {
        this.setKeepScreenOn(this.keepScreenOnRequested)
        return
      }
      logger.info('Local screen keep-on changed: %{public}s', String(keepScreenOn))
    } catch (_err) {
      logger.warn('Failed to set local screen keep-on: %{public}s', String(keepScreenOn))
    }
  }

  private syncKeepScreenOnWithPlayback(): void {
    const shouldKeepScreenOn = this.isPageAlive && this.appInForeground && this.isPlaying &&
      !this.shouldKeepPlaybackForPiP()
    this.setKeepScreenOn(shouldKeepScreenOn)
  }

  private handlePlayerKeyEvent(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return
    }

    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (this.isFullScreen) {
        this.toggleFullScreen()
      }
      return
    }

    if (this.showDanmakuSettingsPanel || this.showDanmakuSettingsSheet) {
      return
    }

    switch (event.keyCode) {
      case KeyCode.KEYCODE_SPACE:
        this.togglePlayPause()
        this.showHudText(this.isPlaying ? '播放' : '暂停')
        break
      case KeyCode.KEYCODE_DPAD_LEFT:
        this.seekTo(Math.max(this.positionMs - 5000, 0))
        this.showHudText('后退 5 秒')
        break
      case KeyCode.KEYCODE_DPAD_RIGHT:
        this.seekTo(Math.min(this.positionMs + 5000, this.durationMs))
        this.showHudText('前进 5 秒')
        break
      case KeyCode.KEYCODE_DPAD_UP:
        this.changePlayerVolume(0.05)
        break
      case KeyCode.KEYCODE_DPAD_DOWN:
        this.changePlayerVolume(-0.05)
        break
      default:
        break
    }
  }

  private changePlayerVolume(delta: number): void {
    const nextVolume = Math.max(0, Math.min(1, this.volume + delta))
    this.volume = nextVolume
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setVolume(nextVolume)
    }
    this.showHudText(`音量 ${Math.round(nextVolume * 100)}%`)
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

  private shouldIgnorePendingQueueSwitchState(state: PlayerState): boolean {
    if (this.pendingQueueTargetUri.length === 0) {
      return false
    }
    if (this.pendingQueueTargetUri !== this.videoUri) {
      this.pendingQueueTargetUri = ''
      this.pendingQueueStartPositionMs = 0
      this.queueSwitchSawPreparing = false
      return false
    }
    if (state.stateName === 'creating' || state.stateName === 'initialized' ||
      state.stateName === 'preparing' || state.stateName === 'prepared') {
      this.queueSwitchSawPreparing = true
      this.positionMs = this.pendingQueueStartPositionMs
      this.durationMs = 0
      return true
    }
    if (!this.queueSwitchSawPreparing) {
      return true
    }
    if (state.stateName === 'playing' || state.stateName === 'paused' ||
      state.stateName === 'completed' || state.stateName === 'error') {
      this.pendingQueueTargetUri = ''
      this.pendingQueueStartPositionMs = 0
      this.queueSwitchSawPreparing = false
      return false
    }
    return true
  }

  private cacheLivePlaybackPosition(positionMs: number): void {
    const targetUrl = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUri
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

  private stopPlaybackBeforeLeaving(): void {
    this.isPlaying = false
    if (this.playerEngine !== null) {
      try {
        this.playerEngine.stop()
      } catch (err) {
        logger.warn('Stop local player before leaving failed')
      }
    }
    this.playerEngine = null
    this.hasEngine = false
  }

  private seekTo(positionMs: number): void {
    this.positionMs = positionMs
    this.liveStartPositionMs = positionMs
    if (positionMs > 0) {
      this.lastKnownPositionMs = positionMs
      this.lastHistorySaveMs = Date.now()
      this.cacheLivePlaybackPosition(positionMs)
      this.saveLocalHistory()
    } else {
      this.clearLivePlaybackPosition()
    }
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.seek(positionMs)
    }
    void this.castSessionManager.sendSeek(positionMs)
  }

  private toggleDanmaku(): void {
    if (this.danmakuManager !== null) {
      this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
    }
  }

  private setDanmakuEnabled(enabled: boolean): void {
    if (this.isDanmakuEnabled === enabled) {
      return
    }
    if (this.danmakuManager === null) {
      this.isDanmakuEnabled = enabled
      return
    }

    const managerEnabled = this.danmakuManager.getIsDanmakuEnabled()
    if (managerEnabled !== enabled) {
      this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
    } else {
      this.isDanmakuEnabled = enabled
    }
  }

  private toggleControls(): void {
    this.isControlVisible = !this.isControlVisible
    if (this.isControlVisible) {
      this.startAutoHideTimer()
    } else {
      this.pauseAutoHideTimer()
    }
  }

  private showControlsWithAutoHide(): void {
    this.isControlVisible = true
    this.startAutoHideTimer()
  }

  private shouldShowBottomControlLayer(): boolean {
    return this.isControlVisible && !this.hideBottomControlsForFullscreenTransition
  }

  private isPlayerControlActionAllowed(): boolean {
    return this.isControlVisible && !this.hideBottomControlsForFullscreenTransition
  }

  private prepareFullscreenControlTransition(): void {
    this.suppressControlAnimation = true
    this.hideBottomControlsForFullscreenTransition = true
    this.isControlVisible = true
    this.showAspectModePanel = false
    this.showSpeedMenu = false
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.pauseAutoHideTimer()
  }

  private finishFullscreenControlTransition(): void {
    this.isAnimatingFullscreen = false
    this.hideBottomControlsForFullscreenTransition = false
    this.showControlsWithAutoHide()
    this.schedulePlayerAspectSync()
    setTimeout(() => {
      this.suppressControlAnimation = false
    }, 80)
  }

  /**
   * 全屏切换只交给系统窗口旋转完成几何变化，ArkUI 仅负责一次收尾，避免出现两段动画。
   */
  private runFullscreenOneShotTransition(fullScreen: boolean, lockLandscape: boolean): void {
    this.clearFullscreenTransitionTimer()
    this.isFullScreen = fullScreen
    this.setFullScreenMode(fullScreen, lockLandscape)
    logger.info('Fullscreen one-shot rotation started: target=%{public}s', String(fullScreen))
    this.fullscreenTransitionTimer = setTimeout(() => {
      this.fullscreenTransitionTimer = -1
      if (!this.isPageAlive) {
        return
      }
      this.finishFullscreenControlTransition()
      logger.info('Fullscreen one-shot rotation settled: target=%{public}s', String(fullScreen))
    }, this.FULLSCREEN_ROTATION_SETTLE_MS)
  }

  private clearFullscreenTransitionTimer(): void {
    if (this.fullscreenTransitionTimer >= 0) {
      clearTimeout(this.fullscreenTransitionTimer)
      this.fullscreenTransitionTimer = -1
    }
  }

  private schedulePlayerAspectSync(): void {
    if (this.playerLayoutSyncTimer >= 0) {
      clearTimeout(this.playerLayoutSyncTimer)
      this.playerLayoutSyncTimer = -1
    }
    this.playerLayoutSyncTimer = setTimeout(() => {
      this.playerLayoutSyncTimer = -1
      if (!this.isPageAlive || !this.hasEngine || this.playerEngine === null) {
        return
      }
      this.playerEngine.setAspectMode(this.currentAspectMode)
      logger.info('布局稳定后已同步播放器画面比例: %{public}s', String(this.currentAspectMode))
    }, 180)
  }

  private clearPlayerAspectSyncTimer(): void {
    if (this.playerLayoutSyncTimer >= 0) {
      clearTimeout(this.playerLayoutSyncTimer)
      this.playerLayoutSyncTimer = -1
    }
  }

  private getControlAnimationDuration(): number {
    return this.suppressControlAnimation ? 0 : 260
  }

  private setPlaybackSpeed(newSpeed: number): void {
    this.speed = newSpeed
    this.speedLabel = this.formatPlaybackSpeed(newSpeed)
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(newSpeed)
    }
    if (this.danmakuManager !== null) {
      const renderer = this.danmakuManager.getRenderer()
      if (renderer !== null) {
        renderer.setPlaybackSpeed(newSpeed)
      }
    }
  }

  private formatPlaybackSpeed(value: number): string {
    return value % 1 === 0 ? value.toFixed(0) + 'x' : value.toFixed(2).replace(/0+$/, '').replace(/\.$/, '') + 'x'
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
      if (this.isFullScreen || this.isAnimatingFullscreen) {
        logger.warn('PiP: fullscreen exit did not settle before creating PiP')
        return false
      }
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
      this.pipManager.setNextPreviousEnabled(false, false)
    }
    return success
  }

  private async startPiPFromControl(): Promise<void> {
    if (!this.hasEngine || this.xComponentController === null) {
      this.showHudText('播放器尚未就绪')
      return
    }
    const success = await this.startPiP()
    if (!success) {
      this.showHudText('画中画启动失败')
    }
  }

  private seekByFifteenSeconds(forward: boolean): void {
    if (!this.hasEngine || this.durationMs <= 0) {
      return
    }
    const offsetMs = forward ? 15000 : -15000
    const targetMs = Math.max(0, Math.min(this.positionMs + offsetMs, this.durationMs))
    this.seekTo(targetMs)
    this.showHudText(forward ? '前进 15 秒' : '后退 15 秒')
  }

  private async initializeLocalCastSession(): Promise<void> {
    if (this.videoUri.length === 0) {
      return
    }
    try {
      const path = LocalFilePicker.getFileAccessPath(this.videoUri)
      const sourceFile = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      const fileSize = fileIo.statSync(sourceFile.fd).size
      if (fileSize <= 0) {
        fileIo.closeSync(sourceFile)
        this.castSessionManager.setLocalCastEnabled(false)
        logger.warn('Local cast source file is empty')
        return
      }
      this.closeLocalCastSourceFile()
      this.localCastSourceFile = sourceFile
      this.localCastSourceFileSize = fileSize
      this.castSessionManager.setLocalCastEnabled(true)
      const context = getContext(this) as common.UIAbilityContext
      this.castSessionManager.setCallbacks(this.buildCastCallbacks())
      await this.castSessionManager.ensureVideoSession(context)
      this.syncCastMediaInfo()
    } catch (err) {
      this.closeLocalCastSourceFile()
      this.castSessionManager.setLocalCastEnabled(false)
      logger.warn('Initialize local fd cast session failed: %{public}s',
        err instanceof Error ? err.message : String(err))
    }
  }

  private async stopLocalCastSession(): Promise<void> {
    this.castSessionManager.setLocalCastEnabled(false)
    await this.castSessionManager.destroyVideoSession()
    this.closeLocalCastSourceFile()
  }

  private closeLocalCastSourceFile(): void {
    if (this.localCastSourceFile === null) {
      return
    }
    try {
      fileIo.closeSync(this.localCastSourceFile)
    } catch (_err) {
    }
    this.localCastSourceFile = null
    this.localCastSourceFileSize = 0
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
      this.playNextQueueItem(false)
    }
    callbacks.onPlayPrevious = () => {
      this.playPreviousQueueItem()
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
      if (this.currentQueueIndex >= 0 && this.currentQueueIndex < this.playbackQueue.length - 1) {
        this.playNextQueueItem(true)
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
    if (this.localCastSourceFile === null) {
      this.castSessionManager.setCastSupported(false)
      return
    }
    const info = new CastMediaInfo()
    info.url = this.videoUri
    info.title = this.videoFileName.length > 0 ? this.videoFileName : '本地视频'
    info.subtitle = ''
    info.cover = ''
    info.durationMs = this.durationMs
    info.positionMs = this.positionMs
    info.hasNext = this.currentQueueIndex >= 0 && this.currentQueueIndex < this.playbackQueue.length - 1
    info.hasPrevious = this.currentQueueIndex > 0
    const fdSrc: media.AVFileDescriptor = {
      fd: this.localCastSourceFile.fd,
      offset: 0
    }
    if (this.localCastSourceFileSize > 0) {
      fdSrc.length = this.localCastSourceFileSize
    }
    info.fdSrc = fdSrc
    void this.castSessionManager.updateMedia(info)
    void this.castSessionManager.setCastSupported(true)
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
    this.playbackSessionStore.setActions(actions, 'local-player')
    this.syncPlaybackSessionMedia()
  }

  private syncPlaybackSessionMedia(): void {
    const url = this.videoUri.length > 0 ? this.videoUri : this.playbackOptions.url
    if (url.length === 0) {
      return
    }
    this.playbackSessionStore.updateMedia(url, this.videoFileName.length > 0 ? this.videoFileName : '本地视频',
      '', '', this.durationMs, this.positionMs, false, false, true, 'local-player')
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
      this.syncKeepScreenOnWithPlayback()
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
      this.syncKeepScreenOnWithPlayback()
    }
    return callbacks
  }

  private toggleFullScreen(): void {
    if (this.isAnimatingFullscreen) {
      return
    }
    this.isAnimatingFullscreen = true
    this.autoFullscreenActive = false
    this.autoFullscreenEnterMs = 0
    this.autoFullscreenExitCheckPending = false
    this.prepareFullscreenControlTransition()

    this.runFullscreenOneShotTransition(!this.isFullScreen, true)
  }

  /** 本地视频打开后直接进入横屏沉浸式播放。 */
  private enterFullscreenOnOpen(): void {
    if (this.videoUri.length === 0 || this.isFullScreen) {
      return
    }
    this.isFullScreen = true
    this.setFullScreenMode(true, true)
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
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
        }
        mainWindow.disableLandscapeMultiWindow().catch((err: BusinessError) => {
          logger.warn('disableLandscapeMultiWindow failed: %{public}d', err.code)
        })
        this.fullscreenRestoreOrientation = window.Orientation.UNSPECIFIED
      }
    } catch (_err) {
      logger.warn('Failed to toggle fullscreen mode')
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

  private applyPlayerAutoFullscreenRuntimeState(): void {
    if (this.isFullScreen) {
      return
    }
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
    this.schedulePlayerAspectSync()
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
        logger.info('Ignore local auto fullscreen exit while window is landscape: area=%{public}dx%{public}d window=%{public}dx%{public}d',
          Math.round(areaWidth), Math.round(areaHeight), rect.width, rect.height)
        return
      }
      logger.info('Confirm local auto fullscreen exit: area=%{public}dx%{public}d window=%{public}dx%{public}d',
        Math.round(areaWidth), Math.round(areaHeight), rect.width, rect.height)
      this.exitAutoFullscreen()
    } catch (_err) {
      logger.warn('Confirm local auto fullscreen exit fallback: %{public}s',
        _err instanceof Error ? _err.message : String(_err))
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
    this.prepareFullscreenControlTransition()
    this.runFullscreenOneShotTransition(true, false)
  }

  private exitAutoFullscreen(): void {
    if (this.isAnimatingFullscreen) {
      return
    }
    this.isAnimatingFullscreen = true
    this.autoFullscreenActive = false
    this.autoFullscreenEnterMs = 0
    this.autoFullscreenExitCheckPending = false
    this.prepareFullscreenControlTransition()
    this.runFullscreenOneShotTransition(false, false)
    this.setAutoRotationEnabled(this.playerAutoFullscreen)
  }

  private async setAutoRotationEnabled(enabled: boolean): Promise<void> {
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (this.isPhoneDevice()) {
        if (enabled) {
          await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
        } else {
          await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
        }
      } else {
        // Tablets follow the sensor only while the system rotation lock allows it.
        await mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
      }
    } catch (_err) {
      logger.warn('Failed to set auto rotation: %{public}s', _err instanceof Error ? _err.message : String(_err))
    }
  }

  private isPhoneDevice(): boolean {
    return this.screenWidthVp < 600
  }

  private async requestWindowBrightness(brightness: number): Promise<void> {
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      await mainWindow.setWindowBrightness(brightness)
    } catch (_err) {
      logger.warn('Failed to apply window brightness')
    }
  }

  private applyAspectMode(mode: VideoAspectMode): void {
    this.currentAspectMode = mode
    PreferencesStore.getInstance().setNumber('videoAspectMode', mode).catch((_err: void) => {})
  }

  private async loadAspectModePreference(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      const savedMode = await prefs.getNumber('videoAspectMode', VideoAspectMode.contain)
      this.currentAspectMode = savedMode as VideoAspectMode
    } catch (_err) {
      this.currentAspectMode = VideoAspectMode.contain
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

  private startTemporarySpeed(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(3.0)
      this.speed = 3.0
      this.speedLabel = '3x'
    }
  }

  private endTemporarySpeed(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      const targetSpeed = this.speed === 3.0 ? 1.0 : this.speed
      this.playerEngine.setSpeed(targetSpeed)
      this.speed = targetSpeed
      this.speedLabel = targetSpeed % 1 === 0 ? targetSpeed.toFixed(0) + 'x' : targetSpeed.toFixed(1) + 'x'
    }
  }

  private openDanmakuSettings(): void {
    this.danmakuSettingsOpenVersion++
    if (this.isFullScreen) {
      this.showDanmakuSettingsPanel = true
    } else {
      this.showDanmakuSettingsSheet = true
    }
    this.pauseAutoHideTimer()
  }

  private openDanmakuManageSheet(): void {
    logger.info('Open local danmaku manage sheet')
    this.showDanmakuManageSheet = true
    this.showHudText('弹幕')
    this.pauseAutoHideTimer()
  }

  private runAfterDanmakuManageClosed(action: () => void): void {
    this.showDanmakuManageSheet = false
    setTimeout(() => {
      action()
    }, 80)
  }

  private handleDanmakuPrimaryAction(): void {
    if (this.danmakuFileName.length > 0) {
      this.openDanmakuManageSheet()
      return
    }
    this.pickAndLoadLocalDanmaku()
  }

  private closeDanmakuSettings(): void {
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.startAutoHideTimer()
  }

  private onDanmakuSettingsVersionChanged(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.reloadSettings()
    }
  }

  private async pickAndLoadLocalDanmaku(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const fileResult: LocalFileResult | null = await LocalFilePicker.pickDanmakuFile(context)
      if (fileResult === null) {
        return
      }
      const parseResult: LocalDanmakuParseResult | null = this.parseLocalDanmakuResult(fileResult)
      if (parseResult === null) return

      if (this.danmakuManager !== null && this.danmakuManager.hasDanmakuData()) {
        this.pendingDanmakuItems = parseResult.items
        this.pendingDanmakuFileName = fileResult.fileName
        this.pendingDanmakuFormat = this.formatFormatLabel(parseResult.format)
        this.pendingDanmakuUri = fileResult.uri
        this.showDanmakuLoadDialog = true
      } else {
        this.applyParsedDanmaku(fileResult.fileName, fileResult.uri, parseResult)
        this.showHudText('加载 ' + parseResult.items.length + ' 条弹幕 (' + this.danmakuLoadedFormat + ')')
        this.saveLocalHistory()
      }
    } catch (err) {
      logger.error('加载本地弹幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('加载本地弹幕失败')
    }
  }

  private applyPendingDanmaku(append: boolean): void {
    if (this.danmakuManager !== null) {
      if (append) {
        this.danmakuManager.appendLocalDanmaku(this.pendingDanmakuItems)
        this.danmakuLoadedCount += this.pendingDanmakuItems.length
        this.showHudText('追加 ' + this.pendingDanmakuItems.length + ' 条弹幕')
      } else {
        this.danmakuOffsetMs = 0
        this.danmakuManager.resetDanmakuOffset()
        this.danmakuManager.loadLocalDanmaku(this.pendingDanmakuItems)
        this.danmakuLoadedCount = this.pendingDanmakuItems.length
        this.showHudText('替换为 ' + this.pendingDanmakuItems.length + ' 条弹幕')
      }
      this.danmakuFileName = this.pendingDanmakuFileName
      this.danmakuLoadedFormat = this.pendingDanmakuFormat
      this.danmakuUri = this.pendingDanmakuUri
      this.saveLocalHistory()
    }
    this.pendingDanmakuItems = []
    this.pendingDanmakuFileName = ''
    this.pendingDanmakuFormat = ''
    this.pendingDanmakuUri = ''
  }

  private async pickVideoFile(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const videoResult = await LocalFilePicker.pickVideoFile(context)
      if (videoResult === null) {
        return
      }
      this.videoUri = videoResult.uri
      this.videoFileName = videoResult.fileName
      this.videoFileSize = videoResult.fileSize
      this.positionMs = 0
      this.durationMs = 0
      this.lastKnownPositionMs = 0
      this.clearLivePlaybackPosition()
      this.playbackErrorText = ''
      this.clearDanmakuState()
      this.drmScheme = ''
      this.drmPluginName = ''
      this.drmOfflineKeyId = ''
      const options = new PlaybackOptions()
      options.url = this.videoUri
      options.isLocalFile = true
      options.localFileSize = this.videoFileSize
      options.drmScheme = this.drmScheme
      options.drmPluginName = this.drmPluginName
      options.drmOfflineKeyId = this.drmOfflineKeyId
      this.playbackOptions = options
      logger.info('选择本地视频: %{public}s', videoResult.fileName)
    } catch (err) {
      logger.error('选择视频文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('选择视频文件失败')
    }
  }

  private async authorizeCurrentVideo(): Promise<void> {
    if (this.videoUri.length === 0) {
      return
    }
    try {
      const context = getContext(this) as common.UIAbilityContext
      const authorized = await LocalFilePicker.ensureReadableUri(this.videoUri) ||
        await LocalFilePicker.authorizeExistingUri(context, this.videoUri)
      if (!authorized) {
        this.showHudText('授权失败')
        return
      }
      this.playbackErrorText = ''
      const options = new PlaybackOptions()
      options.url = this.videoUri
      options.isLocalFile = true
      options.localFileSize = this.videoFileSize
      options.drmScheme = this.drmScheme
      options.drmPluginName = this.drmPluginName
      options.drmOfflineKeyId = this.drmOfflineKeyId
      if (this.lastKnownPositionMs > 0) {
        options.startPositionMs = this.lastKnownPositionMs
      }
      this.playbackOptions = options
      this.showHudText('授权成功')
    } catch (err) {
      logger.warn('重新授权本地视频失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('授权失败')
    }
  }

  private canAuthorizeCurrentVideo(): boolean {
    return this.videoUri.length > 0
  }

  private showHudText(text: string): void {
    this.hudText = text
    this.showHud = true
    this.clearHudTimer()
    this.hudTimer = setTimeout(() => {
      this.showHud = false
    }, 1500)
  }

  private startAutoHideTimer(): void {
    this.pauseAutoHideTimer()
    this.controlHideTimer = setTimeout(() => {
      this.isControlVisible = false
    }, 5000)
  }

  private pauseAutoHideTimer(): void {
    if (this.controlHideTimer >= 0) {
      clearTimeout(this.controlHideTimer)
      this.controlHideTimer = -1
    }
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer)
      this.hudTimer = -1
    }
  }

  private adjustDanmakuOffset(deltaMs: number): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.applyDanmakuOffset(deltaMs)
      this.danmakuOffsetMs = this.danmakuManager.getCurrentOffsetMs()
      this.showHudText('弹幕偏移 ' + this.formatOffset(this.danmakuOffsetMs))
      this.saveLocalHistory()
    }
  }

  private resetDanmakuOffset(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.resetDanmakuOffset()
      this.danmakuOffsetMs = 0
      this.showHudText('弹幕偏移已重置')
      this.saveLocalHistory()
    }
  }

  private async saveLocalHistory(captureExitFrame: boolean = false): Promise<void> {
    if (this.videoFileName.length === 0) {
      return
    }
    try {
      if (this.playerEngine !== null) {
        const latestState = this.playerEngine.getState()
        if (latestState.positionMs > this.positionMs) {
          this.positionMs = latestState.positionMs
        }
        if (latestState.positionMs > this.lastKnownPositionMs) {
          this.lastKnownPositionMs = latestState.positionMs
        }
        if (latestState.durationMs > this.durationMs) {
          this.durationMs = latestState.durationMs
        }
      }
      if (this.positionMs <= 0 && this.lastKnownPositionMs > 0) {
        this.positionMs = this.lastKnownPositionMs
      }
      if (this.durationMs > 0 && this.positionMs <= 0) {
        logger.info('Skip local history save with zero position: name=%{public}s duration=%{public}d',
          this.videoFileName, this.durationMs)
        return
      }
      const record = new LocalVideoRecord()
      record.fileUri = this.videoUri
      record.fileName = this.videoFileName
      record.fileSize = this.videoFileSize
      if (captureExitFrame) {
        record.coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(this.videoUri, this.videoFileName, this.videoFileSize, this.positionMs)
      }
      record.durationMs = this.durationMs
      record.positionMs = this.positionMs
      record.lastPlayedAt = Date.now()
      record.danmakuFileName = this.danmakuFileName
      record.danmakuUri = this.danmakuUri
      record.danmakuOffsetMs = this.danmakuOffsetMs
      record.danmakuFormat = this.danmakuLoadedFormat
      record.danmakuCount = this.danmakuLoadedCount
      record.drmScheme = this.drmScheme
      record.drmPluginName = this.drmPluginName
      record.drmOfflineKeyId = this.drmOfflineKeyId
      record.createdAt = Date.now()
      logger.info('Save local history: name=%{public}s position=%{public}d duration=%{public}d',
        this.videoFileName, this.positionMs, this.durationMs)
      await this.localVideoHistoryStore.upsert(record)
    } catch (err) {
      logger.warn('保存本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private restoreDanmakuFromHistory(): void {
    if (this.danmakuUri.length === 0 || this.danmakuFileName.length === 0 || this.danmakuManager === null) {
      return
    }
    LocalFilePicker.ensureReadableUri(this.danmakuUri).then((readable: boolean) => {
      if (!readable) {
        this.showHudText('弹幕文件需要重新选择')
        this.clearDanmakuState()
        return
      }
      const fileResult = LocalFilePicker.readDanmakuFileByUri(this.danmakuUri, this.danmakuFileName)
      if (fileResult === null) {
        this.showHudText('弹幕恢复失败')
        this.clearDanmakuState()
        return
      }
      const parseResult: LocalDanmakuParseResult = DanmakuFileParser.parse(fileResult.fileName, fileResult.content)
      if (parseResult.errorMessage.length > 0 || parseResult.items.length === 0) {
        this.showHudText('弹幕恢复失败')
        this.clearDanmakuState()
        return
      }
      this.danmakuLoadedFormat = this.danmakuLoadedFormat.length > 0 ? this.danmakuLoadedFormat : this.formatFormatLabel(parseResult.format)
      this.danmakuLoadedCount = parseResult.items.length
      if (this.danmakuManager !== null) {
        this.danmakuManager.loadLocalDanmaku(parseResult.items)
        if (this.danmakuOffsetMs !== 0) {
          this.danmakuManager.applyDanmakuOffset(this.danmakuOffsetMs)
        }
      }
      logger.info('历史弹幕恢复成功: %{public}s count=%{public}d', this.danmakuFileName, parseResult.items.length)
      this.saveLocalHistory()
    }).catch((err: Error) => {
      logger.warn('历史弹幕授权恢复失败: %{public}s', err.message)
      this.clearDanmakuState()
    })
  }

  private clearDanmakuState(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.clearLocalDanmaku()
    }
    this.danmakuFileName = ''
    this.danmakuUri = ''
    this.danmakuOffsetMs = 0
    this.danmakuLoadedFormat = ''
    this.danmakuLoadedCount = 0
  }

  private parseLocalDanmakuResult(fileResult: LocalFileResult): LocalDanmakuParseResult | null {
    const parseResult: LocalDanmakuParseResult = DanmakuFileParser.parse(fileResult.fileName, fileResult.content)
    if (parseResult.errorMessage.length > 0) {
      this.showHudText('弹幕解析失败: ' + parseResult.errorMessage)
      return null
    }
    if (parseResult.items.length === 0) {
      this.showHudText('弹幕文件为空')
      return null
    }
    return parseResult
  }

  private applyParsedDanmaku(fileName: string, uri: string, parseResult: LocalDanmakuParseResult): void {
    this.danmakuFileName = fileName
    this.danmakuUri = uri
    this.danmakuLoadedFormat = this.formatFormatLabel(parseResult.format)
    this.danmakuLoadedCount = parseResult.items.length
    this.danmakuOffsetMs = 0
    if (this.danmakuManager !== null) {
      this.danmakuManager.resetDanmakuOffset()
      this.danmakuManager.loadLocalDanmaku(parseResult.items)
    }
  }

  private getAspectModeLabel(): string {
    return VideoAspectModeHelper.getLabel(this.currentAspectMode)
  }

  private formatFileSize(size: number): string {
    if (size <= 0) {
      return '未知大小'
    }
    const mb = size / 1024 / 1024
    if (mb < 1024) {
      return mb.toFixed(mb >= 100 ? 0 : 1) + ' MB'
    }
    const gb = mb / 1024
    return gb.toFixed(gb >= 100 ? 0 : 1) + ' GB'
  }

  private formatOffset(ms: number): string {
    if (ms === 0) {
      return '0s'
    }
    const sign = ms > 0 ? '+' : ''
    const absMs = Math.abs(ms)
    if (absMs >= 1000) {
      const seconds = absMs / 1000
      return sign + (seconds % 1 === 0 ? seconds.toFixed(0) : seconds.toFixed(1)) + 's'
    }
    return sign + absMs + 'ms'
  }

  private formatFormatLabel(format: string): string {
    if (format === 'bilibili-xml') {
      return 'B站 XML'
    }
    if (format === 'dandan-json') {
      return '弹弹 JSON'
    }
    if (format === 'ass') {
      return 'ASS'
    }
    return format.toUpperCase()
  }

  private buildCurrentDanmakuText(): string {
    if (this.danmakuFileName.length === 0) {
      return '未加载弹幕，支持 B站 XML / 弹弹 JSON / ASS'
    }
    let text = this.danmakuLoadedFormat.length > 0 ? this.danmakuLoadedFormat : '本地弹幕'
    if (this.danmakuLoadedCount > 0) {
      text += ' · ' + this.danmakuLoadedCount + ' 条'
    }
    if (this.danmakuOffsetMs !== 0) {
      text += ' · ' + this.formatOffset(this.danmakuOffsetMs)
    }
    text += ' · ' + this.danmakuFileName
    return text
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    if (hours > 0) {
      return hours + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
    }
    return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
  }
}
