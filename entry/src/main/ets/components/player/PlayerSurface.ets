import { IPlayerEngine, PlaybackOptions, PlayerState } from '../../core/player/IPlayerEngine'
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
  @State surfaceId: string = '';
  private playerEngine: IPlayerEngine | null = null;
  private hasEngine: boolean = false;
  private xComponentController: XComponentController = new XComponentController();
  private engineType: string = 'avplayer';
  onPlayerReady?: () => void;
  onStateChange?: (state: PlayerState) => void;
  onEngineReady?: (engine: IPlayerEngine) => void;

  aboutToDisappear(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.release();
    }
  }

  build() {
    XComponent({
      id: 'videoXComponent',
      type: XComponentType.SURFACE,
      controller: this.xComponentController
    })
      .onLoad(async () => {
        this.surfaceId = this.xComponentController.getXComponentSurfaceId();
        logger.info('Surface created: %{public}s', this.surfaceId);
        await this.loadEngineType();
        this.initPlayer();
      })
      .width('100%')
      .aspectRatio(16 / 9)
  }

  private async loadEngineType(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      this.engineType = await prefs.getString('defaultPlayerEngine', 'avplayer')
    } catch (err) {
      this.engineType = 'avplayer'
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
      if (this.onStateChange) {
        this.onStateChange(state);
      }
    });

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
      const hwdecMode = await prefs.getString('mpvHwdecMode', 'ohcodec')
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
