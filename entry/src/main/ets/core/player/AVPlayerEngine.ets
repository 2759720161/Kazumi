import { media } from '@kit.MediaKit'
import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode } from './IPlayerEngine'
import { Logger } from '../../utils/Logger'

const logger = new Logger('AVPlayerEngine')

export class AVPlayerEngine implements IPlayerEngine {
  private avPlayer: media.AVPlayer | null = null
  private state: PlayerState = new PlayerState()
  private stateCallback: ((state: PlayerState) => void) | null = null
  private surfaceId: string = ''
  private currentOptions: PlaybackOptions | null = null
  private prepareTimeoutTimer: number = -1
  private readonly prepareTimeoutMs: number = 12000
  private pendingAspectMode: VideoAspectMode | null = null
  private pendingInitialPlayAfterSeek: boolean = false
  private pendingInitialSeekMs: number = -1
  private initialSeekFallbackTimer: number = -1

  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId
    if (this.avPlayer !== null && surfaceId.length > 0) {
      try {
        this.avPlayer.surfaceId = surfaceId
        logger.info('AVPlayer surface rebound: %{public}s', surfaceId)
      } catch (_err) {
        logger.warn('AVPlayer surface rebind failed')
      }
    }
  }

  prepare(options: PlaybackOptions): void {
    this.clearPrepareTimeout()
    this.clearInitialSeekState()
    this.resetState()
    this.currentOptions = options
    this.state.stateName = 'creating'
    this.notifyStateChange()

    this.logIgnoredRequestHeaders(options)
    this.logStreamMetadata(options)
    this.prepareWithUrl(options)
  }

  private prepareWithUrl(options: PlaybackOptions): void {
    media.createAVPlayer().then((player: media.AVPlayer) => {
      this.avPlayer = player
      this.registerListeners()
      if (options.url.length > 0) {
        try {
          player.url = options.url
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err)
          logger.error('Set AVPlayer url failed: %{public}s', msg)
          this.failPlayback('AVPlayer set url failed: ' + msg)
        }
      }
    }).catch((err: Error) => {
      this.failPlayback('Create AVPlayer failed: ' + err.message)
    })
  }

  private logIgnoredRequestHeaders(options: PlaybackOptions): void {
    const headerKeys = Object.keys(options.headers)
    const hasHeaders = options.referer.length > 0 || options.userAgent.length > 0 || headerKeys.length > 0
    if (!hasHeaders) {
      return
    }
    logger.warn('AVPlayer does not support request headers in current implementation; trying direct URL playback')
    if (options.referer.length > 0) {
      logger.info('  Referer (not applied): %{public}s', options.referer.substring(0, 60))
    }
    if (options.userAgent.length > 0) {
      logger.info('  UserAgent (not applied): %{public}s', options.userAgent.substring(0, 40))
    }
    if (headerKeys.length > 0) {
      logger.info('  Custom headers (not applied): %{public}d', headerKeys.length)
    }
  }

  private logStreamMetadata(options: PlaybackOptions): void {
    if (options.streamMetadata === null || options.streamMetadata.isEmpty()) {
      return
    }
    logger.info('AVPlayer stream metadata: %{public}s', options.streamMetadata.summary())
    if (options.streamMetadata.hasDolbyVision || options.streamMetadata.hasHdrCodecHint) {
      logger.warn('AVPlayer stream has HDR/Dolby codec hints; playback depends on device decoder/display')
    }
  }

  private registerListeners(): void {
    if (!this.avPlayer) {
      return
    }

    this.avPlayer.on('stateChange', (avState: string) => {
      this.state.stateName = avState
      switch (avState) {
        case 'idle':
          this.state.playing = false
          this.state.buffering = false
          break
        case 'initialized':
          if (this.avPlayer && this.surfaceId) {
            this.avPlayer.surfaceId = this.surfaceId
          }
          if (this.avPlayer) {
            this.startPrepareTimeout()
            this.avPlayer.prepare().catch((err: Error) => {
              this.clearPrepareTimeout()
              const msg = err instanceof Error ? err.message : String(err)
              logger.error('AVPlayer prepare promise failed: %{public}s', msg)
              this.failPlayback('AVPlayer prepare failed: ' + msg)
            })
          }
          break
        case 'prepared':
          this.clearPrepareTimeout()
          this.state.playing = false
          this.state.buffering = false
          if (this.avPlayer) {
            this.state.durationMs = this.avPlayer.duration
            const w = this.avPlayer.width
            const h = this.avPlayer.height
            if (w > 0 && h > 0) {
              this.state.videoWidth = w
              this.state.videoHeight = h
              logger.info('AVPlayer video size: %{public}dx%{public}d', w, h)
            }
          }
          if (this.avPlayer && this.currentOptions !== null && this.currentOptions.startPositionMs > 0) {
            const startPos = this.currentOptions.startPositionMs
            this.seekBeforeInitialPlay(startPos)
          } else if (this.avPlayer) {
            this.avPlayer.play()
          }
          if (this.pendingAspectMode !== null) {
            this.setAspectMode(this.pendingAspectMode)
          }
          break
        case 'playing':
          this.state.playing = true
          this.state.buffering = false
          break
        case 'paused':
          this.state.playing = false
          break
        case 'completed':
          this.state.playing = false
          this.state.completed = true
          break
        case 'stopped':
          this.state.playing = false
          break
        case 'released':
          this.clearPrepareTimeout()
          this.clearInitialSeekState()
          this.state.playing = false
          break
        case 'error':
          this.clearPrepareTimeout()
          this.clearInitialSeekState()
          this.state.playing = false
          this.state.error = 'Player error'
          break
        default:
          break
      }
      this.notifyStateChange()
    })

    this.avPlayer.on('timeUpdate', (time: number) => {
      this.state.positionMs = time
      this.notifyStateChange()
    })

    this.avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.state.buffering = true
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.state.buffering = false
      } else if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
        if (value >= 0) {
          this.state.bufferMs = Math.floor(this.state.durationMs * value / 100)
        }
      } else if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        this.state.bufferMs = value
      }
      this.notifyStateChange()
    })

    this.avPlayer.on('seekDone', (seekDoneTime: number) => {
      this.handleSeekDone(seekDoneTime)
    })

    this.avPlayer.on('error', (err: Error) => {
      this.clearPrepareTimeout()
      this.clearInitialSeekState()
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('AVPlayer error callback: %{public}s', msg)
      this.state.error = msg.length > 0 ? 'AVPlayer error: ' + msg : 'AVPlayer error (check URL format and network)'
      this.state.stateName = 'error'
      this.notifyStateChange()
    })
  }

  private seekBeforeInitialPlay(positionMs: number): void {
    if (!this.avPlayer) {
      return
    }
    try {
      logger.info('AVPlayer initial seek before play: %{public}dms', positionMs)
      this.pendingInitialPlayAfterSeek = true
      this.pendingInitialSeekMs = positionMs
      this.avPlayer.seek(positionMs)
      this.startInitialSeekFallbackTimer()
    } catch (err) {
      logger.warn('AVPlayer initial seek threw, fallback to direct play: %{public}s',
        err instanceof Error ? err.message : String(err))
      this.clearInitialSeekState()
      if (this.avPlayer) {
        this.avPlayer.play()
      }
    }
  }

  private handleSeekDone(seekDoneTime: number): void {
    if (!this.pendingInitialPlayAfterSeek) {
      return
    }
    logger.info('AVPlayer initial seek done: %{public}dms', seekDoneTime)
    this.playAfterInitialSeek()
  }

  private playAfterInitialSeek(): void {
    this.clearInitialSeekState()
    if (!this.avPlayer || this.state.stateName === 'released' || this.state.stateName === 'error') {
      return
    }
    this.avPlayer.play()
  }

  play(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.play()
        this.state.playing = true
        this.state.stateName = 'playing'
        this.notifyStateChange()
      } catch (e) {
        this.state.error = 'play error'
        this.notifyStateChange()
      }
    }
  }

  pause(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.pause()
        this.state.playing = false
        this.state.stateName = 'paused'
        this.notifyStateChange()
      } catch (e) {
        this.state.error = 'pause error'
        this.notifyStateChange()
      }
    }
  }

  stop(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.stop()
      } catch (e) {
        this.state.error = 'stop error'
      }
    }
  }

  seek(positionMs: number): void {
    if (this.avPlayer) {
      this.avPlayer.seek(positionMs)
    }
  }

  setSpeed(speed: number): void {
    if (this.avPlayer) {
      let playbackSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
      let normalizedSpeed = 1.0
      if (speed <= 0.25) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_25_X
        normalizedSpeed = 0.25
      } else if (speed <= 0.5) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_50_X
        normalizedSpeed = 0.5
      } else if (speed <= 0.75) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
        normalizedSpeed = 0.75
      } else if (speed <= 1.0) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
        normalizedSpeed = 1.0
      } else if (speed <= 1.25) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
        normalizedSpeed = 1.25
      } else if (speed <= 1.75) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
        normalizedSpeed = 1.75
      } else {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
        normalizedSpeed = 2.0
      }
      this.avPlayer.setSpeed(playbackSpeed)
      this.state.speed = normalizedSpeed
      this.notifyStateChange()
    }
  }

  setVolume(volume: number): void {
    if (this.avPlayer) {
      const normalizedVolume = Math.max(0, Math.min(1, volume))
      this.avPlayer.setVolume(normalizedVolume)
      this.state.volume = normalizedVolume
      this.notifyStateChange()
    }
  }

  setAspectMode(mode: VideoAspectMode): void {
    this.pendingAspectMode = mode
    if (this.avPlayer !== null) {
      try {
        const modeName = this.getAspectModeName(mode)
        const scaleType = this.getVideoScaleType(mode)
        this.avPlayer.videoScaleType = scaleType
        this.pendingAspectMode = null
        logger.info('AVPlayer setAspectMode ok: mode=%{public}s, params=videoScaleType=%{public}d',
          modeName, scaleType)
      } catch (err) {
        logger.warn('AVPlayer setAspectMode failed: %{public}s', String(err))
      }
    }
  }

  private getVideoScaleType(mode: VideoAspectMode): media.VideoScaleType {
    switch (mode) {
      case VideoAspectMode.contain:
        return media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT
      case VideoAspectMode.cover:
        return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP
      case VideoAspectMode.fill:
      default:
        return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT
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

  getState(): PlayerState {
    return this.state
  }

  onStateChange(callback: (state: PlayerState) => void): void {
    this.stateCallback = callback
  }

  release(): void {
    this.clearPrepareTimeout()
    this.clearInitialSeekState()
    if (this.avPlayer) {
      try {
        this.avPlayer.release()
      } catch (e) {
      }
      this.avPlayer = null
    }
    this.currentOptions = null
    this.resetState()
  }

  private startPrepareTimeout(): void {
    this.clearPrepareTimeout()
    this.prepareTimeoutTimer = setTimeout(() => {
      this.prepareTimeoutTimer = -1
      if (this.state.stateName === 'initialized' || this.state.stateName === 'creating') {
        const url = this.currentOptions !== null ? this.currentOptions.url.substring(0, 80) : ''
        logger.error('AVPlayer prepare timeout after %{public}dms: %{public}s',
          this.prepareTimeoutMs, url)
        this.failPlayback('AVPlayer prepare timeout')
      }
    }, this.prepareTimeoutMs)
  }

  private clearPrepareTimeout(): void {
    if (this.prepareTimeoutTimer >= 0) {
      clearTimeout(this.prepareTimeoutTimer)
      this.prepareTimeoutTimer = -1
    }
  }

  private startInitialSeekFallbackTimer(): void {
    this.clearInitialSeekFallbackTimer()
    this.initialSeekFallbackTimer = setTimeout(() => {
      this.initialSeekFallbackTimer = -1
      if (!this.pendingInitialPlayAfterSeek) {
        return
      }
      logger.warn('AVPlayer initial seek timeout, fallback to play: %{public}dms', this.pendingInitialSeekMs)
      this.playAfterInitialSeek()
    }, 1600)
  }

  private clearInitialSeekFallbackTimer(): void {
    if (this.initialSeekFallbackTimer >= 0) {
      clearTimeout(this.initialSeekFallbackTimer)
      this.initialSeekFallbackTimer = -1
    }
  }

  private clearInitialSeekState(): void {
    this.clearInitialSeekFallbackTimer()
    this.pendingInitialPlayAfterSeek = false
    this.pendingInitialSeekMs = -1
  }

  private failPlayback(message: string): void {
    this.clearPrepareTimeout()
    this.clearInitialSeekState()
    this.state.error = message
    this.state.stateName = 'error'
    this.state.playing = false
    this.notifyStateChange()
    if (this.avPlayer) {
      try {
        this.avPlayer.release()
      } catch (e) {
      }
      this.avPlayer = null
    }
  }

  private resetState(): void {
    this.state = new PlayerState()
  }

  private notifyStateChange(): void {
    if (this.stateCallback) {
      this.stateCallback(this.state)
    }
  }
}
