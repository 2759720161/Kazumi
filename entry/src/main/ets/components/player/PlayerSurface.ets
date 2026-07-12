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

@Component
export struct PlayerSurface {
  @Prop @Watch('onVideoUrlChange') videoUrl: string = '';
  @Prop @Watch('onPlaybackOptionsChange') playbackOptions: PlaybackOptions = new PlaybackOptions();
  @Prop fillParent: boolean = false;
  @Prop @Watch('onAspectModeChanged') aspectMode: VideoAspectMode = VideoAspectMode.contain;
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
  private xComponentController: XComponentController = new XComponentController();
  private engineType: string = 'mpv';
  onPlayerReady?: () => void;
  onStateChange?: (state: PlayerState) => void;
  onEngineReady?: (engine: IPlayerEngine) => void;
  onSurfaceReady?: (controller: XComponentController) => void;

  aboutToDisappear(): void {
    this.isDestroyed = true;
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
          this.surfaceId = this.xComponentController.getXComponentSurfaceId();
          logger.info('Surface created: %{public}s', this.surfaceId);
          if (this.onSurfaceReady) {
            this.onSurfaceReady(this.xComponentController);
          }
          if (this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.setSurfaceId(this.surfaceId)
            return
          }
          await this.loadEngineType();
          this.initPlayer();
        })
        .width(this.xComponentWidth > 0 ? this.xComponentWidth : '100%')
        .height(this.xComponentHeight > 0 ? this.xComponentHeight : '100%')
        .position({ x: this.xComponentOffsetX, y: this.xComponentOffsetY })
    }
    .width('100%')
    .height('100%')
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

    let videoW = this.videoWidth
    let videoH = this.videoHeight
    if (videoW <= 0 || videoH <= 0) {
      videoW = 16
      videoH = 9
    }

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

    if (changed) {
      logger.info('PlayerSurface aspect layout: mode=%{public}s, params=boxFit=%{public}s,parent=%{public}dx%{public}d,video=%{public}dx%{public}d,surface=%{public}dx%{public}d,offset=%{public}d,%{public}d',
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
      clearTimeout(this.pendingPrepareTimer);
      this.pendingPrepareTimer = -1;
    }
  }

  private releaseEngine(): void {
    this.cancelPendingPrepare();
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.release();
      this.playerEngine = null;
      this.hasEngine = false;
    }
  }

  private onVideoUrlChange(): void {
    if (this.videoUrl.length > 0) {
      if (!this.arePlaybackOptionsReady()) {
        logger.info('Video URL changed but playback options are not ready');
        return;
      }
      logger.info('Video URL changed, re-preparing player');
      this.releaseEngine();
      this.initPlayer();
    }
  }

  private onPlaybackOptionsChange(): void {
    if (this.videoUrl.length === 0 || !this.arePlaybackOptionsReady()) {
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
    if (this.videoUrl.length === 0) {
      return;
    }
    if (!this.arePlaybackOptionsReady()) {
      return;
    }

    if (this.playbackOptions.isLocalFile) {
      logger.info('Creating AVPlayer engine for local file')
      const avEngine = new AVPlayerEngine()
      avEngine.setSurfaceId(this.surfaceId)
      this.playerEngine = avEngine
    } else if (this.engineType === 'mpv' && PlayerEngineFactory.isMpvNapiAvailableSync()) {
      logger.info('Creating mpv player engine')
      const mpvEngine = new MpvPlayerEngine()
      mpvEngine.setSurfaceId(this.surfaceId)
      await this.applyMpvSettings(mpvEngine)
      this.playerEngine = mpvEngine
    } else {
      logger.info('Creating AVPlayer engine, requested=%{public}s', this.engineType)
      const avEngine = new AVPlayerEngine()
      avEngine.setSurfaceId(this.surfaceId)
      this.playerEngine = avEngine
    }

    this.playerEngine!.onStateChange((state: PlayerState) => {
      if (this.isDestroyed) {
        return
      }
      if (state.videoWidth > 0 && state.videoHeight > 0 &&
        (state.videoWidth !== this.videoWidth || state.videoHeight !== this.videoHeight)) {
        this.videoWidth = state.videoWidth
        this.videoHeight = state.videoHeight
      }
      if (this.onStateChange) {
        this.onStateChange(state);
      }
    });

    this.playerEngine!.setAspectMode(this.aspectMode);

    const options = new PlaybackOptions();
    options.url = this.playbackOptions.url.length > 0 ? this.playbackOptions.url : this.videoUrl;
    options.startPositionMs = this.playbackOptions.startPositionMs;
    options.referer = this.playbackOptions.referer;
    options.userAgent = this.playbackOptions.userAgent;
    options.proxy = this.playbackOptions.proxy;
    options.isLocalFile = this.playbackOptions.isLocalFile;
    options.localFileSize = this.playbackOptions.localFileSize;
    let headerKeys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      let key = headerKeys[i]
      options.headers[key] = this.playbackOptions.headers[key]
    }

    this.hasEngine = true;
    const engine = this.playerEngine!
    const engineReadyCb = this.onEngineReady
    const playerReadyCb = this.onPlayerReady
    this.pendingPrepareTimer = setTimeout(() => {
      this.pendingPrepareTimer = -1;
      if (this.isDestroyed) {
        return;
      }
      engine.prepare(options);
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
}
