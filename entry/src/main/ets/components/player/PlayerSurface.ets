import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode } from '../../core/player/IPlayerEngine'
import { AVPlayerEngine } from '../../core/player/AVPlayerEngine'
import { MpvPlayerEngine } from '../../core/player/MpvPlayerEngine'
import { PlayerEngineFactory } from '../../core/player/PlayerEngineFactory'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import {
  MPV_DETAIL_ENHANCER_ENABLED_DEFAULT,
  MPV_DETAIL_ENHANCER_QUALITY_DEFAULT,
  PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED,
  PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY
} from '../../utils/MpvSettings'

const logger = new Logger('PlayerSurface')
const PLAYER_LIVE_URL_KEY: string = 'playerLivePlaybackUrl'
const PLAYER_LIVE_POSITION_KEY: string = 'playerLivePlaybackPositionMs'
const RETAINED_PLAYER_SESSION_TIMEOUT_MS: number = 6000
let playerSurfaceInitSeq: number = 0

interface RetainedPlayerSession {
  targetUrl: string
  engineType: string
  engine: IPlayerEngine
  expiryTimer: number
}

let retainedPlayerSession: RetainedPlayerSession | null = null

export function releaseRetainedPlayerSession(): void {
  if (retainedPlayerSession === null) {
    return
  }
  if (retainedPlayerSession.expiryTimer >= 0) {
    clearTimeout(retainedPlayerSession.expiryTimer)
  }
  try {
    retainedPlayerSession.engine.release()
  } catch (_err) {
  }
  retainedPlayerSession = null
}

function retainPlayerSession(targetUrl: string, engineType: string, engine: IPlayerEngine): void {
  releaseRetainedPlayerSession()
  const session: RetainedPlayerSession = {
    targetUrl: targetUrl,
    engineType: engineType,
    engine: engine,
    expiryTimer: -1
  }
  retainedPlayerSession = session
  session.expiryTimer = setTimeout(() => {
    if (retainedPlayerSession === session) {
      logger.warn('CrashDiag PlayerSurface retained engine expired: urlHash=%{public}s',
        shortPlayerSurfaceHash(targetUrl))
      releaseRetainedPlayerSession()
    }
  }, RETAINED_PLAYER_SESSION_TIMEOUT_MS)
}

function takeRetainedPlayerSession(targetUrl: string): RetainedPlayerSession | null {
  if (retainedPlayerSession === null) {
    return null
  }
  if (retainedPlayerSession.targetUrl !== targetUrl) {
    releaseRetainedPlayerSession()
    return null
  }
  const session = retainedPlayerSession
  if (session.expiryTimer >= 0) {
    clearTimeout(session.expiryTimer)
  }
  retainedPlayerSession = null
  return session
}

function shortPlayerSurfaceHash(value: string): string {
  let hash = 0
  for (let i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
  }
  return String(value.length) + ':' + String(hash)
}

@Component
export struct PlayerSurface {
  @Prop @Watch('onVideoUrlChange') videoUrl: string = '';
  @Prop @Watch('onPlaybackOptionsChange') playbackOptions: PlaybackOptions = new PlaybackOptions();
  @Prop liveStartPositionMs: number = 0;
  @Prop fillParent: boolean = false;
  @Prop @Watch('onAspectModeChanged') aspectMode: VideoAspectMode = VideoAspectMode.contain;
  @Prop keepAliveOnDisappear: boolean = false;
  @State surfaceId: string = '';
  @State @Watch('onLayoutInputsChanged') videoWidth: number = 0;
  @State @Watch('onLayoutInputsChanged') videoHeight: number = 0;
  @State @Watch('onLayoutInputsChanged') parentWidth: number = 0;
  @State @Watch('onLayoutInputsChanged') parentHeight: number = 0;
  @State xComponentWidth: number = 0;
  @State xComponentHeight: number = 0;
  @State xComponentOffsetX: number = 0;
  @State xComponentOffsetY: number = 0;
  private playerEngine: IPlayerEngine | null = null;
  private hasEngine: boolean = false;
  private isDestroyed: boolean = false;
  private pendingPrepareTimer: number = -1;
  private activeInitSeq: number = 0;
  private preparedUrl: string = '';
  private preparingUrl: string = '';
  private lastRequestedUrl: string = '';
  private playbackFailed: boolean = false;
  private xComponentController: XComponentController = new XComponentController();
  private engineType: string = 'mpv';
  onPlayerReady?: () => void;
  onStateChange?: (state: PlayerState) => void;
  onEngineReady?: (engine: IPlayerEngine) => void;
  onSurfaceReady?: (controller: XComponentController) => void;
  onVideoLayoutChange?: (width: number, height: number, offsetX: number, offsetY: number) => void;

  aboutToDisappear(): void {
    const pageActive = AppStorage.get<boolean>('playerPageActive') ?? false
    const targetUrl = this.getTargetUrl()
    if (!this.playbackFailed && (this.keepAliveOnDisappear || pageActive) &&
      this.hasEngine && this.playerEngine !== null &&
      targetUrl.length > 0) {
      logger.warn('CrashDiag PlayerSurface retain engine on rebuild: seq=%{public}d engine=%{public}s urlHash=%{public}s',
        this.activeInitSeq, this.engineType, this.shortHash(targetUrl))
      retainPlayerSession(targetUrl, this.engineType, this.playerEngine)
      this.playerEngine = null
      this.hasEngine = false
      this.preparedUrl = ''
      this.preparingUrl = ''
      this.isDestroyed = true
      return
    }
    if (this.playbackFailed) {
      logger.warn('CrashDiag PlayerSurface release failed engine on disappear: seq=%{public}d urlHash=%{public}s',
        this.activeInitSeq, this.shortHash(targetUrl))
    }
    this.isDestroyed = true;
    if (this.keepAliveOnDisappear && !this.playbackFailed) {
      logger.info('PlayerSurface keep engine alive on disappear')
      return
    }
    this.releaseEngine();
  }

  build() {
    Stack() {
      XComponent({
        id: 'videoXComponent',
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .onLoad(async () => {
          this.isDestroyed = false
          this.surfaceId = this.xComponentController.getXComponentSurfaceId();
          logger.info('Surface created: %{public}s', this.surfaceId);
          if (this.onSurfaceReady) {
            this.onSurfaceReady(this.xComponentController);
          }
          if (this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.setSurfaceId(this.surfaceId)
            return
          }
          const retainedSession = takeRetainedPlayerSession(this.getTargetUrl())
          if (retainedSession !== null) {
            this.engineType = retainedSession.engineType
            this.playerEngine = retainedSession.engine
            this.hasEngine = true
            this.preparedUrl = retainedSession.targetUrl
            this.lastRequestedUrl = retainedSession.targetUrl
            this.bindEngineCallbacks(this.playerEngine)
            this.playerEngine.setSurfaceId(this.surfaceId)
            this.playerEngine.setAspectMode(this.aspectMode)
            logger.warn('CrashDiag PlayerSurface reused engine after rebuild: seq=%{public}d engine=%{public}s urlHash=%{public}s',
              this.activeInitSeq, this.engineType, this.shortHash(retainedSession.targetUrl))
            if (this.onEngineReady) {
              this.onEngineReady(this.playerEngine)
            }
            if (this.onStateChange) {
              this.onStateChange(this.playerEngine.getState())
            }
            if (this.onPlayerReady) {
              this.onPlayerReady()
            }
            return
          }
          await this.loadEngineType();
          this.initPlayer();
        })
        .width(this.xComponentWidth > 0 ? this.xComponentWidth : '100%')
        .height(this.xComponentHeight > 0 ? this.xComponentHeight : '100%')
        .position({ x: this.xComponentOffsetX, y: this.xComponentOffsetY })
        .opacity(this.videoWidth > 0 && this.videoHeight > 0 ? 1 : 0)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w = Number(newArea.width)
      const h = Number(newArea.height)
      if (w > 0 && h > 0 && (w !== this.parentWidth || h !== this.parentHeight)) {
        this.parentWidth = w
        this.parentHeight = h
      }
    })
  }

  private onAspectModeChanged(): void {
    this.calculateBoxFitLayout()
    if (this.hasEngine && this.playerEngine !== null) {
      logger.info('PlayerSurface forward aspect mode: mode=%{public}s', this.getAspectModeName(this.aspectMode))
      this.playerEngine.setAspectMode(this.aspectMode)
    }
  }

  private onLayoutInputsChanged(): void {
    this.calculateBoxFitLayout()
  }

  private calculateBoxFitLayout(): void {
    if (this.parentWidth <= 0 || this.parentHeight <= 0) {
      return
    }

    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      const targetW = this.parentWidth
      const targetH = this.parentHeight
      const changed = targetW !== this.xComponentWidth || targetH !== this.xComponentHeight ||
        this.xComponentOffsetX !== 0 || this.xComponentOffsetY !== 0
      this.xComponentWidth = targetW
      this.xComponentHeight = targetH
      this.xComponentOffsetX = 0
      this.xComponentOffsetY = 0
      if (this.onVideoLayoutChange) {
        this.onVideoLayoutChange(targetW, targetH, 0, 0)
      }
      if (changed) {
        logger.warn('CrashDiag PlayerSurface aspect layout waiting for video size: parent=%{public}dx%{public}d',
          Math.round(targetW), Math.round(targetH))
      }
      return
    }

    const videoW = this.videoWidth
    const videoH = this.videoHeight

    const parentW = this.parentWidth
    const parentH = this.parentHeight
    let targetW: number = 0
    let targetH: number = 0

    switch (this.aspectMode) {
      case VideoAspectMode.contain: {
        const scale = Math.min(parentW / videoW, parentH / videoH)
        targetW = videoW * scale
        targetH = videoH * scale
        break
      }
      case VideoAspectMode.cover: {
        const scale = Math.max(parentW / videoW, parentH / videoH)
        targetW = videoW * scale
        targetH = videoH * scale
        break
      }
      case VideoAspectMode.fill:
      default: {
        targetW = parentW
        targetH = parentH
        break
      }
    }

    const targetX = (parentW - targetW) / 2
    const targetY = (parentH - targetH) / 2
    const changed = targetW !== this.xComponentWidth || targetH !== this.xComponentHeight ||
      targetX !== this.xComponentOffsetX || targetY !== this.xComponentOffsetY

    this.xComponentWidth = targetW
    this.xComponentHeight = targetH
    this.xComponentOffsetX = targetX
    this.xComponentOffsetY = targetY
    if (this.onVideoLayoutChange) {
      this.onVideoLayoutChange(targetW, targetH, targetX, targetY)
    }

    if (changed) {
      logger.warn('CrashDiag PlayerSurface aspect layout: mode=%{public}s, params=boxFit=%{public}s,parent=%{public}dx%{public}d,video=%{public}dx%{public}d,surface=%{public}dx%{public}d,offset=%{public}d,%{public}d',
        this.getAspectModeName(this.aspectMode), this.getBoxFitName(this.aspectMode),
        Math.round(parentW), Math.round(parentH), Math.round(videoW), Math.round(videoH),
        Math.round(targetW), Math.round(targetH), Math.round(targetX), Math.round(targetY))
    }
  }

  private getAspectModeName(mode: VideoAspectMode): string {
    switch (mode) {
      case VideoAspectMode.contain:
        return 'contain(自动适应)'
      case VideoAspectMode.cover:
        return 'cover(裁切填充)'
      case VideoAspectMode.fill:
        return 'fill(拉伸填充)'
      default:
        return 'unknown'
    }
  }

  private getBoxFitName(mode: VideoAspectMode): string {
    switch (mode) {
      case VideoAspectMode.contain:
        return 'contain'
      case VideoAspectMode.cover:
        return 'cover'
      case VideoAspectMode.fill:
        return 'fill'
      default:
        return 'contain'
    }
  }

  private async loadEngineType(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      this.engineType = await prefs.getString('defaultPlayerEngine', 'mpv')
    } catch (err) {
      this.engineType = 'mpv'
    }
  }

  private cancelPendingPrepare(): void {
    if (this.pendingPrepareTimer >= 0) {
      logger.warn('CrashDiag PlayerSurface cancel pending prepare: seq=%{public}d', this.activeInitSeq)
      clearTimeout(this.pendingPrepareTimer);
      this.pendingPrepareTimer = -1;
    }
  }

  private releaseEngine(): void {
    const startMs = Date.now()
    this.cancelPendingPrepare();
    if (this.hasEngine && this.playerEngine !== null) {
      logger.warn('CrashDiag PlayerSurface releaseEngine begin: seq=%{public}d hasEngine=%{public}s urlHash=%{public}s',
        this.activeInitSeq, String(this.hasEngine), this.shortHash(this.videoUrl))
      this.playerEngine.release();
      this.playerEngine = null;
      this.hasEngine = false;
      this.preparedUrl = '';
      this.preparingUrl = '';
      logger.warn('CrashDiag PlayerSurface releaseEngine end: seq=%{public}d elapsed=%{public}dms',
        this.activeInitSeq, Date.now() - startMs)
    }
  }

  private onVideoUrlChange(): void {
    const targetUrl = this.getTargetUrl()
    if (targetUrl.length > 0) {
      if (!this.arePlaybackOptionsReady()) {
        logger.info('Video URL changed but playback options are not ready');
        return;
      }
      if (this.isSamePlaybackTarget(targetUrl)) {
        logger.info('CrashDiag PlayerSurface videoUrl change ignored: same target urlHash=%{public}s',
          this.shortHash(targetUrl))
        return
      }
      logger.info('Video URL changed, re-preparing player');
      this.releaseEngine();
      this.initPlayer();
    }
  }

  private onPlaybackOptionsChange(): void {
    const targetUrl = this.getTargetUrl()
    if (targetUrl.length === 0 || !this.arePlaybackOptionsReady()) {
      return
    }
    if (this.isSamePlaybackTarget(targetUrl)) {
      logger.info('CrashDiag PlayerSurface playbackOptions change ignored: same target urlHash=%{public}s',
        this.shortHash(targetUrl))
      return
    }
    if (this.hasEngine && this.playerEngine !== null) {
      logger.info('Playback options changed, re-preparing player')
      this.releaseEngine()
      this.initPlayer()
    } else {
      logger.info('Playback options became ready, preparing player')
      this.initPlayer();
    }
  }

  private async initPlayer(): Promise<void> {
    const seq = ++playerSurfaceInitSeq;
    this.activeInitSeq = seq;
    this.playbackFailed = false;
    const initStartMs = Date.now();
    const targetUrl = this.getTargetUrl()
    if (targetUrl.length === 0) {
      logger.info('CrashDiag PlayerSurface init skip: seq=%{public}d reason=empty-url', seq)
      return;
    }
    if (!this.arePlaybackOptionsReady()) {
      logger.info('CrashDiag PlayerSurface init skip: seq=%{public}d reason=options-not-ready urlHash=%{public}s',
        seq, this.shortHash(this.videoUrl))
      return;
    }
    if (this.isSamePlaybackTarget(targetUrl)) {
      logger.info('CrashDiag PlayerSurface init skip: seq=%{public}d reason=same-target urlHash=%{public}s',
        seq, this.shortHash(targetUrl))
      return
    }
    this.lastRequestedUrl = targetUrl
    this.preparingUrl = targetUrl

    if (this.playbackOptions.isLocalFile) {
      logger.info('CrashDiag PlayerSurface init begin: seq=%{public}d engine=avplayer-local surface=%{public}s urlHash=%{public}s',
        seq, this.surfaceId, this.shortHash(this.videoUrl))
      logger.info('Creating AVPlayer engine for local file')
      const avEngine = new AVPlayerEngine()
      avEngine.setSurfaceId(this.surfaceId)
      this.playerEngine = avEngine
    } else if (this.engineType === 'mpv' && PlayerEngineFactory.isMpvNapiAvailableSync()) {
      logger.info('CrashDiag PlayerSurface init begin: seq=%{public}d engine=mpv surface=%{public}s urlHash=%{public}s',
        seq, this.surfaceId, this.shortHash(this.videoUrl))
      logger.info('Creating mpv player engine')
      const mpvEngine = new MpvPlayerEngine()
      mpvEngine.setSurfaceId(this.surfaceId)
      await this.applyMpvSettings(mpvEngine)
      if (this.isDestroyed || this.activeInitSeq !== seq || this.lastRequestedUrl !== targetUrl) {
        logger.warn('CrashDiag PlayerSurface init stale after settings: seq=%{public}d targetHash=%{public}s',
          seq, this.shortHash(targetUrl))
        mpvEngine.release()
        return
      }
      this.playerEngine = mpvEngine
    } else {
      logger.info('CrashDiag PlayerSurface init begin: seq=%{public}d engine=avplayer requested=%{public}s surface=%{public}s urlHash=%{public}s',
        seq, this.engineType, this.surfaceId, this.shortHash(this.videoUrl))
      logger.info('Creating AVPlayer engine, requested=%{public}s', this.engineType)
      const avEngine = new AVPlayerEngine()
      avEngine.setSurfaceId(this.surfaceId)
      this.playerEngine = avEngine
    }

    this.bindEngineCallbacks(this.playerEngine!);

    this.playerEngine!.setAspectMode(this.aspectMode);

    const options = new PlaybackOptions();
    options.url = targetUrl;
    options.startPositionMs = this.resolveStartPositionMs(targetUrl);
    options.referer = this.playbackOptions.referer;
    options.userAgent = this.playbackOptions.userAgent;
    options.proxy = this.playbackOptions.proxy;
    options.isLocalFile = this.playbackOptions.isLocalFile;
    options.localFileSize = this.playbackOptions.localFileSize;
    options.drmScheme = this.playbackOptions.drmScheme;
    options.drmPluginName = this.playbackOptions.drmPluginName;
    options.drmOfflineKeyId = this.playbackOptions.drmOfflineKeyId;
    options.drmMimeType = this.playbackOptions.drmMimeType;
    let headerKeys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      let key = headerKeys[i]
      options.headers[key] = this.playbackOptions.headers[key]
    }

    this.hasEngine = true;
    const engine = this.playerEngine!
    const engineReadyCb = this.onEngineReady
    const playerReadyCb = this.onPlayerReady
    logger.info('CrashDiag PlayerSurface init ready: seq=%{public}d elapsed=%{public}dms pendingPrepare=scheduled',
      seq, Date.now() - initStartMs)
    this.pendingPrepareTimer = setTimeout(() => {
      this.pendingPrepareTimer = -1;
      if (this.isDestroyed) {
        logger.warn('CrashDiag PlayerSurface prepare skipped: seq=%{public}d reason=destroyed', seq)
        return;
      }
      if (this.activeInitSeq !== seq || this.lastRequestedUrl !== options.url || engine !== this.playerEngine) {
        logger.warn('CrashDiag PlayerSurface prepare skipped: seq=%{public}d reason=stale currentSeq=%{public}d',
          seq, this.activeInitSeq)
        return
      }
      const prepareStartMs = Date.now()
      logger.warn('CrashDiag PlayerSurface prepare begin: seq=%{public}d urlHash=%{public}s',
        seq, this.shortHash(options.url))
      if (options.startPositionMs > 0) {
        logger.warn('CrashDiag PlayerSurface prepare resume: seq=%{public}d startPosition=%{public}d',
          seq, options.startPositionMs)
      }
      engine.prepare(options);
      logger.warn('CrashDiag PlayerSurface prepare returned: seq=%{public}d elapsed=%{public}dms',
        seq, Date.now() - prepareStartMs)
      this.preparedUrl = options.url
      this.preparingUrl = ''
      if (engineReadyCb) {
        engineReadyCb(engine);
      }
      if (playerReadyCb) {
        playerReadyCb();
      }
    }, 0);
  }

  private async applyMpvSettings(engine: MpvPlayerEngine): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      const hwdecMode = await prefs.getString('mpvHwdecMode', 'auto')
      const hlsAdFilter = await prefs.getBoolean('mpvHlsAdFilter', true)
      const segAllowImg = await prefs.getBoolean('mpvSegAllowImg', true)
      const hasDetailEnhancerQuality = await prefs.has(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY)
      const detailEnhancerQuality = await prefs.getNumber(
        PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY,
        2
      )
      const detailEnhancerEnabled = await prefs.getBoolean(
        PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED,
        hasDetailEnhancerQuality ? detailEnhancerQuality >= 0 : MPV_DETAIL_ENHANCER_ENABLED_DEFAULT
      )
      engine.setHwdecMode(hwdecMode)
      engine.setHlsAdFilterEnabled(hlsAdFilter)
      engine.setSegAllowImgEnabled(segAllowImg)
      engine.setDetailEnhancerQuality(detailEnhancerEnabled ? detailEnhancerQuality : MPV_DETAIL_ENHANCER_QUALITY_DEFAULT)
    } catch (err) {
      logger.warn('applyMpvSettings failed, using defaults')
    }
  }

  private arePlaybackOptionsReady(): boolean {
    return this.playbackOptions.url.length > 0;
  }

  private getTargetUrl(): string {
    return this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUrl
  }

  private resolveStartPositionMs(targetUrl: string): number {
    if (this.liveStartPositionMs > 0) {
      return this.liveStartPositionMs
    }
    const cachedUrl = AppStorage.get<string>(PLAYER_LIVE_URL_KEY) ?? ''
    if (cachedUrl === targetUrl) {
      const cachedPosition = AppStorage.get<number>(PLAYER_LIVE_POSITION_KEY) ?? 0
      if (cachedPosition > 0) {
        return cachedPosition
      }
    }
    return this.playbackOptions.startPositionMs
  }

  private bindEngineCallbacks(engine: IPlayerEngine): void {
    engine.onStateChange((state: PlayerState) => {
      if (this.isDestroyed) {
        return
      }
      if (state.stateName === 'error' && state.error.length > 0) {
        this.playbackFailed = true
      }
      if (state.videoWidth > 0 && state.videoHeight > 0 &&
        (state.videoWidth !== this.videoWidth || state.videoHeight !== this.videoHeight)) {
        this.videoWidth = state.videoWidth
        this.videoHeight = state.videoHeight
      }
      if (this.onStateChange) {
        this.onStateChange(state)
      }
    })
  }

  private isSamePlaybackTarget(targetUrl: string): boolean {
    if (targetUrl.length === 0) {
      return false
    }
    return targetUrl === this.preparedUrl || targetUrl === this.preparingUrl
  }

  private shortHash(value: string): string {
    let hash = 0
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
    }
    return String(value.length) + ':' + String(hash)
  }
}
