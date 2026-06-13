import { media } from '@kit.MediaKit'
import { IPlayerEngine, PlaybackOptions, PlayerState } from './IPlayerEngine'
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

  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId
  }

  prepare(options: PlaybackOptions): void {
    this.clearPrepareTimeout()
    this.resetState()
    this.currentOptions = options
    this.state.stateName = 'creating'
    this.notifyStateChange()

    let hasHeaders = options.referer.length > 0 || options.userAgent.length > 0 ||
      Object.keys(options.headers).length > 0

    if (hasHeaders) {
      this.prepareWithMediaSource(options)
    } else {
      this.prepareWithUrl(options)
    }
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

  private prepareWithMediaSource(options: PlaybackOptions): void {
    logger.info('Headers requested but current SDK does not support MediaSource')
    if (options.referer.length > 0) {
      logger.info('  Referer (not applied): %{public}s', options.referer.substring(0, 60))
    }
    if (options.userAgent.length > 0) {
      logger.info('  UserAgent (not applied): %{public}s', options.userAgent.substring(0, 40))
    }
    let headerKeys = Object.keys(options.headers)
    if (headerKeys.length > 0) {
      logger.info('  Custom headers (not applied): %{public}d', headerKeys.length)
    }
    this.state.stateName = 'error'
    this.state.error = '当前播放器不支持该源的请求头设置，建议等待高级播放器'
    this.state.playing = false
    this.notifyStateChange()
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
          }
          if (this.avPlayer) {
            this.avPlayer.play()
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
          this.state.playing = false
          break
        case 'error':
          this.clearPrepareTimeout()
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

    this.avPlayer.on('error', (err: Error) => {
      this.clearPrepareTimeout()
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('AVPlayer error callback: %{public}s', msg)
      this.state.error = msg.length > 0 ? 'AVPlayer error: ' + msg : 'AVPlayer error (check URL format and network)'
      this.state.stateName = 'error'
      this.notifyStateChange()
    })
  }

  play(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.play()
      } catch (e) {
        this.state.error = 'play error'
      }
    }
  }

  pause(): void {
    if (this.avPlayer) {
      try {
        this.avPlayer.pause()
      } catch (e) {
        this.state.error = 'pause error'
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
      if (speed <= 0.25) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_25_X
      } else if (speed <= 0.5) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_50_X
      } else if (speed <= 0.75) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
      } else if (speed <= 1.0) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
      } else if (speed <= 1.25) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
      } else if (speed <= 1.75) {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
      } else {
        playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
      }
      this.avPlayer.setSpeed(playbackSpeed)
    }
  }

  setVolume(volume: number): void {
    if (this.avPlayer) {
      this.avPlayer.setVolume(volume)
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

  private failPlayback(message: string): void {
    this.clearPrepareTimeout()
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
