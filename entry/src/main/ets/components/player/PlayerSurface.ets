import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode } from '../../core/player/IPlayerEngine'
import { AVPlayerEngine } from '../../core/player/AVPlayerEngine'
import { MpvPlayerEngine } from '../../core/player/MpvPlayerEngine'
import { PlayerEngineFactory } from '../../core/player/PlayerEngineFactory'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

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
  private xComponentController: XComponentController = new XComponentController();
  private engineType: string = 'mpv';
  onPlayerReady?: () => void;
  onStateChange?: (state: PlayerState) => void;
  onEngineReady?: (engine: IPlayerEngine) => void;

  aboutToDisappear(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.release();
      this.playerEngine = null;
      this.hasEngine = false;
    }
  }

  build() {
    Stack() {
      XComponent({
        id: 'videoXComponent',
        type: XComponentType.TEXTURE,
        controller: this.xComponentController
      })
        .onLoad(async () => {
          this.surfaceId = this.xComponentController.getXComponentSurfaceId();
          logger.info('Surface created: %{public}s', this.surfaceId);
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

  private onVideoUrlChange(): void {
    if (this.videoUrl.length > 0) {
      if (!this.arePlaybackOptionsReady()) {
        logger.info('Video URL changed but playback options are not ready');
        return;
      }
      logger.info('Video URL changed, re-preparing player');
      if (this.hasEngine && this.playerEngine !== null) {
        this.playerEngine.release();
        this.playerEngine = null;
        this.hasEngine = false;
      }
      this.initPlayer();
    }
  }

  private onPlaybackOptionsChange(): void {
    if (this.videoUrl.length > 0 && this.arePlaybackOptionsReady() && !this.hasEngine) {
      logger.info('Playback options became ready, preparing player');
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

    if (this.engineType === 'mpv' && PlayerEngineFactory.isMpvNapiAvailableSync()) {
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
    let headerKeys = Object.keys(this.playbackOptions.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      let key = headerKeys[i]
      options.headers[key] = this.playbackOptions.headers[key]
    }

    this.playerEngine!.prepare(options);
    this.hasEngine = true;

    if (this.onEngineReady) {
      this.onEngineReady(this.playerEngine!);
    }

    if (this.onPlayerReady) {
      this.onPlayerReady();
    }
  }

  private async applyMpvSettings(engine: MpvPlayerEngine): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      const hwdecMode = await prefs.getString('mpvHwdecMode', 'auto')
      const hlsAdFilter = await prefs.getBoolean('mpvHlsAdFilter', true)
      const segAllowImg = await prefs.getBoolean('mpvSegAllowImg', true)
      engine.setHwdecMode(hwdecMode)
      engine.setHlsAdFilterEnabled(hlsAdFilter)
      engine.setSegAllowImgEnabled(segAllowImg)
    } catch (err) {
      logger.warn('applyMpvSettings failed, using defaults')
    }
  }

  private arePlaybackOptionsReady(): boolean {
    return this.playbackOptions.url.length > 0;
  }
}
