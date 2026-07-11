import { avSession } from '@kit.AVSessionKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('CastSessionManager')

export class CastMediaInfo {
  url: string = ''
  title: string = ''
  subtitle: string = ''
  cover: string = ''
  durationMs: number = 0
  positionMs: number = 0
}

export class CastEventCallbacks {
  onPlay?: () => void
  onPause?: () => void
  onSeek?: (positionMs: number) => void
  onPlayNext?: () => void
  onPlayPrevious?: () => void
  onEndOfStream?: () => void
  onRemotePositionChange?: (positionMs: number) => void
  onCastDeviceConnected?: () => void
  onCastDeviceDisconnected?: () => void
}

export class CastSessionManager {
  private static instance: CastSessionManager | null = null

  private session: avSession.AVSession | null = null
  private castController: avSession.AVCastController | null = null
  private currentMedia: CastMediaInfo = new CastMediaInfo()
  private callbacks: CastEventCallbacks = new CastEventCallbacks()
  private isInitialized: boolean = false
  private isCasting: boolean = false
  private lastStartedAssetId: string = ''
  private lastStartedSubtitle: string = ''

  static getInstance(): CastSessionManager {
    if (CastSessionManager.instance === null) {
      CastSessionManager.instance = new CastSessionManager()
    }
    return CastSessionManager.instance
  }

  setCallbacks(callbacks: CastEventCallbacks): void {
    this.callbacks = callbacks
  }

  async ensureVideoSession(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized && this.session !== null) {
      return
    }

    try {
      this.session = await avSession.createAVSession(context, 'kazumi_video_session', 'video')
      await this.session.activate()
      await this.session.setExtras({
        requireAbilityList: ['url-cast']
      })
      this.registerSessionListeners()
      this.isInitialized = true
      logger.info('Video cast session initialized')
    } catch (err) {
      logger.warn('ensureVideoSession failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  async updateMedia(info: CastMediaInfo): Promise<void> {
    const mediaChanged = info.url !== this.currentMedia.url || info.subtitle !== this.currentMedia.subtitle
    this.currentMedia = info
    await this.updateSessionMetadata()
    await this.updatePlaybackState(info.positionMs, false)
    if (this.isCasting && this.castController !== null && info.url.length > 0 && mediaChanged) {
      await this.startRemotePlayback(info.positionMs)
    }
  }

  async updateDuration(durationMs: number): Promise<void> {
    if (durationMs <= 0 || Math.abs(durationMs - this.currentMedia.durationMs) < 1000) {
      return
    }
    this.currentMedia.durationMs = durationMs
    await this.updateSessionMetadata()
  }

  async setCastSupported(supported: boolean): Promise<void> {
    if (this.session === null) {
      return
    }
    if (supported) {
      await this.updateSessionMetadata()
      return
    }

    try {
      await this.session.setAVMetadata({
        assetId: this.currentMedia.url.length > 0 ? this.currentMedia.url : 'unsupported',
        title: this.currentMedia.title.length > 0 ? this.currentMedia.title : '当前资源不可投播',
        subtitle: this.currentMedia.subtitle,
        mediaImage: this.currentMedia.cover,
        duration: this.currentMedia.durationMs,
        filter: 0
      })
    } catch (err) {
      logger.debug('setCastSupported(false) failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  async updatePlaybackState(positionMs: number, playing: boolean): Promise<void> {
    if (this.session === null) {
      return
    }
    this.currentMedia.positionMs = positionMs
    try {
      await this.session.setAVPlaybackState({
        state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: positionMs,
          updateTime: new Date().getTime()
        }
      })
    } catch (err) {
      logger.debug('updatePlaybackState failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  async sendPlay(): Promise<void> {
    await this.sendCastCommand('play')
    await this.updatePlaybackState(this.currentMedia.positionMs, true)
  }

  async sendPause(): Promise<void> {
    await this.sendCastCommand('pause')
    await this.updatePlaybackState(this.currentMedia.positionMs, false)
  }

  async sendSeek(positionMs: number): Promise<void> {
    this.currentMedia.positionMs = positionMs
    await this.sendCastCommand('seek', positionMs)
    await this.updatePlaybackState(positionMs, false)
  }

  private registerSessionListeners(): void {
    if (this.session === null) {
      return
    }

    this.session.on('play', () => {
      if (this.isCasting) {
        this.sendPlay()
      } else if (this.callbacks.onPlay !== undefined) {
        this.callbacks.onPlay()
      }
    })
    this.session.on('pause', () => {
      if (this.isCasting) {
        this.sendPause()
      } else if (this.callbacks.onPause !== undefined) {
        this.callbacks.onPause()
      }
    })
    this.session.on('stop', () => {
      if (this.isCasting) {
        this.sendPause()
      } else if (this.callbacks.onPause !== undefined) {
        this.callbacks.onPause()
      }
    })
    this.session.on('seek', (positionMs: number) => {
      if (this.isCasting) {
        this.sendSeek(positionMs)
      } else if (this.callbacks.onSeek !== undefined) {
        this.callbacks.onSeek(positionMs)
      }
    })
    this.session.on('playNext', () => {
      if (this.callbacks.onPlayNext !== undefined) {
        this.callbacks.onPlayNext()
      }
    })
    this.session.on('playPrevious', () => {
      if (this.callbacks.onPlayPrevious !== undefined) {
        this.callbacks.onPlayPrevious()
      }
    })
    this.session.on('outputDeviceChange', async (connectState: avSession.ConnectionState,
      device: avSession.OutputDeviceInfo) => {
      const currentDevice = device.devices !== undefined && device.devices.length > 0 ? device.devices[0] : null
      if (currentDevice !== null &&
        currentDevice.castCategory === avSession.AVCastCategory.CATEGORY_REMOTE &&
        connectState === avSession.ConnectionState.STATE_CONNECTED) {
        this.isCasting = true
        this.castController = await this.session!.getAVCastController()
        this.registerCastControllerListeners()
        await this.startRemotePlayback(this.currentMedia.positionMs)
        if (this.callbacks.onCastDeviceConnected !== undefined) {
          this.callbacks.onCastDeviceConnected()
        }
        logger.info('Remote cast device connected')
      } else {
        this.isCasting = false
        this.castController = null
        this.lastStartedAssetId = ''
        this.lastStartedSubtitle = ''
        if (this.callbacks.onCastDeviceDisconnected !== undefined) {
          this.callbacks.onCastDeviceDisconnected()
        }
        logger.info('Remote cast device disconnected')
      }
    })
  }

  private registerCastControllerListeners(): void {
    if (this.castController === null) {
      return
    }

    this.castController.on('playbackStateChange', 'all', (state: avSession.AVPlaybackState) => {
      if (state.position !== undefined) {
        this.currentMedia.positionMs = state.position.elapsedTime
        if (this.callbacks.onRemotePositionChange !== undefined) {
          this.callbacks.onRemotePositionChange(state.position.elapsedTime)
        }
      }
    })
    this.castController.on('playNext', () => {
      if (this.callbacks.onPlayNext !== undefined) {
        this.callbacks.onPlayNext()
      }
    })
    this.castController.on('playPrevious', () => {
      if (this.callbacks.onPlayPrevious !== undefined) {
        this.callbacks.onPlayPrevious()
      }
    })
    this.castController.on('endOfStream', () => {
      logger.info('Remote cast endOfStream')
      if (this.callbacks.onEndOfStream !== undefined) {
        this.callbacks.onEndOfStream()
      }
    })
  }

  private async updateSessionMetadata(): Promise<void> {
    if (this.session === null || this.currentMedia.url.length === 0) {
      return
    }

    try {
      await this.session.setAVMetadata({
        assetId: this.currentMedia.url,
        title: this.currentMedia.title.length > 0 ? this.currentMedia.title : '正在播放',
        subtitle: this.currentMedia.subtitle,
        mediaImage: this.currentMedia.cover,
        duration: this.currentMedia.durationMs,
        filter: avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA
      })
    } catch (err) {
      logger.debug('setAVMetadata failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async startRemotePlayback(startPositionMs: number): Promise<void> {
    if (this.castController === null || this.currentMedia.url.length === 0) {
      return
    }
    if (this.lastStartedAssetId === this.currentMedia.url && this.lastStartedSubtitle === this.currentMedia.subtitle) {
      return
    }

    const playItem: avSession.AVQueueItem = {
      itemId: 0,
      description: {
        assetId: this.currentMedia.url,
        title: this.currentMedia.title.length > 0 ? this.currentMedia.title : '正在播放',
        subtitle: this.currentMedia.subtitle,
        mediaUri: this.currentMedia.url,
        mediaType: 'VIDEO',
        duration: this.currentMedia.durationMs,
        startPosition: startPositionMs,
        albumCoverUri: this.currentMedia.cover,
        appName: '小番薯'
      }
    }

    try {
      await this.castController.prepare(playItem)
      await this.castController.start(playItem)
      this.lastStartedAssetId = this.currentMedia.url
      this.lastStartedSubtitle = this.currentMedia.subtitle
      await this.updatePlaybackState(startPositionMs, true)
      logger.info('Remote cast playback started')
    } catch (err) {
      logger.warn('startRemotePlayback failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async sendCastCommand(command: avSession.AVCastControlCommandType, parameter?: number): Promise<void> {
    if (this.castController === null) {
      return
    }
    const avCommand: avSession.AVCastControlCommand = {
      command: command
    }
    if (parameter !== undefined) {
      avCommand.parameter = parameter
    }
    try {
      await this.castController.sendControlCommand(avCommand)
    } catch (err) {
      const businessError = err as BusinessError
      logger.debug('sendCastCommand failed: %{public}s', businessError.message)
    }
  }

  async stopCasting(): Promise<void> {
    if (this.session === null) {
      return
    }
    try {
      await this.session.stopCasting()
      this.isCasting = false
      this.castController = null
      this.lastStartedAssetId = ''
      this.lastStartedSubtitle = ''
    } catch (err) {
      logger.debug('stopCasting failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }
}
