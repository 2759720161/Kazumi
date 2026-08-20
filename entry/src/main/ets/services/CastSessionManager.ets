import { avSession } from '@kit.AVSessionKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { media } from '@kit.MediaKit'
import { Logger } from '../utils/Logger'
import { PlaybackSessionSnapshot, PlaybackSessionStore } from './PlaybackSessionStore'

const logger = new Logger('CastSessionManager')
const MEDIA_SKIP_INTERVAL_SECONDS: number = 15
const MEDIA_SKIP_INTERVAL_MS: number = MEDIA_SKIP_INTERVAL_SECONDS * 1000
const MEDIA_SKIP_INTERVALS: avSession.SkipIntervals = avSession.SkipIntervals.SECONDS_15

export class CastMediaInfo {
  url: string = ''
  title: string = ''
  subtitle: string = ''
  cover: string = ''
  durationMs: number = 0
  positionMs: number = 0
  hasNext: boolean = false
  hasPrevious: boolean = false
  fdSrc: media.AVFileDescriptor | undefined = undefined
}

export class CastEventCallbacks {
  onPlay?: () => void
  onPause?: () => void
  onSeek?: (positionMs: number) => void
  onFastForward?: (positionMs: number) => void
  onRewind?: (positionMs: number) => void
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
  private localCastEnabled: boolean = false
  private lastStartedAssetId: string = ''
  private lastStartedSubtitle: string = ''
  private playbackStore: PlaybackSessionStore = PlaybackSessionStore.getInstance()
  private playbackStoreListenerId: number = -1
  private isSyncingFromPlaybackStore: boolean = false
  private isDestroyingSession: boolean = false
  private playbackStateUpdateSeq: number = 0
  private lastPlaybackStateDiagMs: number = 0
  private lastPlaybackStateDiagPlaying: boolean = false
  private lastPlaybackStateDiagBucket: number = -1

  static getInstance(): CastSessionManager {
    if (CastSessionManager.instance === null) {
      CastSessionManager.instance = new CastSessionManager()
    }
    return CastSessionManager.instance
  }

  setCallbacks(callbacks: CastEventCallbacks): void {
    this.callbacks = callbacks
  }

  /**
   * Local playback is normally not castable because its URI belongs to the
   * app's sandbox. LocalPlayerPage enables this only after it has started the
   * temporary LAN file server.
   */
  setLocalCastEnabled(enabled: boolean): void {
    this.localCastEnabled = enabled
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
      this.subscribePlaybackStore()
      this.isInitialized = true
      logger.info('Video cast session initialized')
    } catch (err) {
      logger.warn('ensureVideoSession failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  async updateMedia(info: CastMediaInfo): Promise<void> {
    const startMs = Date.now()
    const mediaChanged = info.url !== this.currentMedia.url || info.subtitle !== this.currentMedia.subtitle
    logger.warn('CrashDiag cast updateMedia begin: changed=%{public}s urlHash=%{public}s pos=%{public}d',
      String(mediaChanged), this.shortHash(info.url), info.positionMs)
    this.currentMedia = info
    await this.updateSessionMetadata()
    await this.updatePlaybackState(info.positionMs, false)
    if (this.isCasting && this.castController !== null && info.url.length > 0 && mediaChanged) {
      await this.startRemotePlayback(info.positionMs)
    }
    logger.warn('CrashDiag cast updateMedia end: changed=%{public}s elapsed=%{public}dms',
      String(mediaChanged), Date.now() - startMs)
  }

  private subscribePlaybackStore(): void {
    if (this.playbackStoreListenerId >= 0) {
      return
    }
    this.playbackStoreListenerId = this.playbackStore.subscribe((snapshot: PlaybackSessionSnapshot) => {
      this.syncFromPlaybackStore(snapshot)
    })
  }

  private syncFromPlaybackStore(snapshot: PlaybackSessionSnapshot): void {
    if (snapshot.url.length === 0 && snapshot.owner.length === 0 && !this.isCasting) {
      this.destroyVideoSession()
      return
    }
    if (this.session === null || snapshot.url.length === 0) {
      return
    }
    if (snapshot.isLocalFile && !this.localCastEnabled) {
      this.setCastSupported(false)
      return
    }

    if (snapshot.isLocalFile && (this.currentMedia.url.length === 0 ||
      this.currentMedia.fdSrc === undefined)) {
      this.setCastSupported(false)
      return
    }

    const mediaChanged = snapshot.url !== this.currentMedia.url ||
      snapshot.subtitle !== this.currentMedia.subtitle ||
      snapshot.title !== this.currentMedia.title ||
      snapshot.cover !== this.currentMedia.cover ||
      Math.abs(snapshot.durationMs - this.currentMedia.durationMs) >= 1000 ||
      snapshot.hasNext !== this.currentMedia.hasNext ||
      snapshot.hasPrevious !== this.currentMedia.hasPrevious

    if (!snapshot.isLocalFile) {
      this.currentMedia.url = snapshot.url
    }
    this.currentMedia.title = snapshot.title
    this.currentMedia.subtitle = snapshot.subtitle
    this.currentMedia.cover = snapshot.cover
    this.currentMedia.durationMs = snapshot.durationMs
    this.currentMedia.positionMs = snapshot.positionMs
    this.currentMedia.hasNext = snapshot.hasNext
    this.currentMedia.hasPrevious = snapshot.hasPrevious

    this.isSyncingFromPlaybackStore = true
    logger.warn('CrashDiag cast syncFromPlaybackStore: owner=%{public}s mediaChanged=%{public}s playing=%{public}s pos=%{public}d urlHash=%{public}s',
      snapshot.owner, String(mediaChanged), String(snapshot.playing), snapshot.positionMs, this.shortHash(snapshot.url))
    const metadataTask = mediaChanged ? this.updateSessionMetadata() : Promise.resolve()
    metadataTask.then(() => {
      return this.updatePlaybackState(snapshot.positionMs, snapshot.playing)
    }).finally(() => {
      this.isSyncingFromPlaybackStore = false
    })
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
        skipIntervals: MEDIA_SKIP_INTERVALS,
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
    const seq = ++this.playbackStateUpdateSeq
    const startMs = Date.now()
    const bucket = Math.floor(positionMs / 1000)
    const stateChanged = playing !== this.lastPlaybackStateDiagPlaying ||
      Math.abs(bucket - this.lastPlaybackStateDiagBucket) >= 2
    const now = Date.now()
    const shouldLog = stateChanged || seq % 20 === 0 || now - this.lastPlaybackStateDiagMs >= 1000
    if (shouldLog) {
      this.lastPlaybackStateDiagMs = now
      this.lastPlaybackStateDiagPlaying = playing
      this.lastPlaybackStateDiagBucket = bucket
      logger.warn('CrashDiag cast updatePlaybackState begin: seq=%{public}d playing=%{public}s pos=%{public}d syncing=%{public}s',
        seq, String(playing), positionMs, String(this.isSyncingFromPlaybackStore))
    }
    this.currentMedia.positionMs = positionMs
    if (!this.isSyncingFromPlaybackStore) {
      const owner = this.playbackStore.getSnapshot().owner
      this.playbackStore.updatePlayback(positionMs, playing, owner.length > 0 ? owner : 'cast')
    }
    try {
      await this.session.setAVPlaybackState({
        state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: positionMs,
          updateTime: new Date().getTime()
        }
      })
      const elapsed = Date.now() - startMs
      if (shouldLog || elapsed >= 80) {
        logger.warn('CrashDiag cast updatePlaybackState end: seq=%{public}d elapsed=%{public}dms',
          seq, elapsed)
      }
    } catch (err) {
      logger.warn('CrashDiag cast updatePlaybackState failed: seq=%{public}d elapsed=%{public}dms error=%{public}s',
        seq, Date.now() - startMs, err instanceof Error ? err.message : String(err))
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
      } else if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestPlay()
      } else if (this.callbacks.onPlay !== undefined) {
        this.callbacks.onPlay()
      }
    })
    this.session.on('pause', () => {
      if (this.isCasting) {
        this.sendPause()
      } else if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestPause()
      } else if (this.callbacks.onPause !== undefined) {
        this.callbacks.onPause()
      }
    })
    this.session.on('stop', () => {
      if (this.isCasting) {
        this.sendPause()
      } else if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestPause()
      } else if (this.callbacks.onPause !== undefined) {
        this.callbacks.onPause()
      }
    })
    this.session.on('seek', (positionMs: number) => {
      if (this.isCasting) {
        this.sendSeek(positionMs)
      } else if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestSeek(positionMs)
      } else if (this.callbacks.onSeek !== undefined) {
        this.callbacks.onSeek(positionMs)
      }
    })
    this.session.on('fastForward', () => {
      const targetPositionMs = this.clampPosition(this.currentMedia.positionMs + MEDIA_SKIP_INTERVAL_MS)
      if (this.isCasting) {
        this.sendFastForward()
      } else if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestFastForward(targetPositionMs)
      } else if (this.callbacks.onFastForward !== undefined) {
        this.callbacks.onFastForward(targetPositionMs)
      }
      this.updatePlaybackState(targetPositionMs, true)
    })
    this.session.on('rewind', () => {
      const targetPositionMs = this.clampPosition(this.currentMedia.positionMs - MEDIA_SKIP_INTERVAL_MS)
      if (this.isCasting) {
        this.sendRewind()
      } else if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestRewind(targetPositionMs)
      } else if (this.callbacks.onRewind !== undefined) {
        this.callbacks.onRewind(targetPositionMs)
      }
      this.updatePlaybackState(targetPositionMs, true)
    })
    this.session.on('playNext', () => {
      if (!this.currentMedia.hasNext) {
        return
      }
      if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestNext()
        return
      }
      if (this.callbacks.onPlayNext !== undefined) {
        this.callbacks.onPlayNext()
      }
    })
    this.session.on('playPrevious', () => {
      if (!this.currentMedia.hasPrevious) {
        return
      }
      if (this.hasPlaybackStoreOwner()) {
        this.playbackStore.requestPrevious()
        return
      }
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

  private unregisterSessionListeners(): void {
    if (this.session === null) {
      return
    }
    try {
      this.session.off('play')
      this.session.off('pause')
      this.session.off('stop')
      this.session.off('seek')
      this.session.off('fastForward')
      this.session.off('rewind')
      this.session.off('playNext')
      this.session.off('playPrevious')
      this.session.off('outputDeviceChange')
    } catch (err) {
      logger.debug('unregisterSessionListeners failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private hasPlaybackStoreOwner(): boolean {
    const owner = this.playbackStore.getSnapshot().owner
    return owner.length > 0 && owner !== 'cast'
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
      if (!this.currentMedia.hasNext) {
        return
      }
      if (this.callbacks.onPlayNext !== undefined) {
        this.callbacks.onPlayNext()
      }
    })
    this.castController.on('playPrevious', () => {
      if (!this.currentMedia.hasPrevious) {
        return
      }
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
    const startMs = Date.now()
    logger.warn('CrashDiag cast updateMetadata begin: urlHash=%{public}s titleLen=%{public}d coverLen=%{public}d duration=%{public}d',
      this.shortHash(this.currentMedia.url), this.currentMedia.title.length, this.currentMedia.cover.length,
      this.currentMedia.durationMs)

    const metadata: avSession.AVMetadata = {
        assetId: this.currentMedia.url,
        title: this.currentMedia.title.length > 0 ? this.currentMedia.title : '正在播放',
        subtitle: this.currentMedia.subtitle,
        mediaImage: this.currentMedia.cover,
        duration: this.currentMedia.durationMs,
        skipIntervals: MEDIA_SKIP_INTERVALS,
        filter: avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA
    }
    if (this.currentMedia.hasPrevious) {
      metadata.previousAssetId = this.currentMedia.url + '#previous'
    }
    if (this.currentMedia.hasNext) {
      metadata.nextAssetId = this.currentMedia.url + '#next'
    }

    try {
      await this.session.setAVMetadata(metadata)
      logger.warn('CrashDiag cast updateMetadata end: elapsed=%{public}dms', Date.now() - startMs)
    } catch (err) {
      logger.warn('CrashDiag cast updateMetadata failed: elapsed=%{public}dms error=%{public}s',
        Date.now() - startMs, err instanceof Error ? err.message : String(err))
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

    const description: avSession.AVMediaDescription = {
      assetId: this.currentMedia.url,
      title: this.currentMedia.title.length > 0 ? this.currentMedia.title : '正在播放',
      subtitle: this.currentMedia.subtitle,
      mediaType: 'VIDEO',
      duration: this.currentMedia.durationMs,
      startPosition: startPositionMs,
      albumCoverUri: this.currentMedia.cover,
      appName: '小番薯'
    }
    if (this.currentMedia.fdSrc !== undefined) {
      description.fdSrc = this.currentMedia.fdSrc
    } else {
      description.mediaUri = this.currentMedia.url
    }
    const playItem: avSession.AVQueueItem = {
      itemId: 0,
      description: description
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

  private async sendFastForward(): Promise<void> {
    const targetPositionMs = this.clampPosition(this.currentMedia.positionMs + MEDIA_SKIP_INTERVAL_MS)
    await this.sendCastCommand('fastForward', MEDIA_SKIP_INTERVALS)
    await this.updatePlaybackState(targetPositionMs, true)
  }

  private async sendRewind(): Promise<void> {
    const targetPositionMs = this.clampPosition(this.currentMedia.positionMs - MEDIA_SKIP_INTERVAL_MS)
    await this.sendCastCommand('rewind', MEDIA_SKIP_INTERVALS)
    await this.updatePlaybackState(targetPositionMs, true)
  }

  private clampPosition(positionMs: number): number {
    const lowerBound = 0
    if (this.currentMedia.durationMs <= 0) {
      return Math.max(lowerBound, positionMs)
    }
    return Math.max(lowerBound, Math.min(positionMs, this.currentMedia.durationMs))
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

  async destroyVideoSession(): Promise<void> {
    if (this.session === null || this.isDestroyingSession) {
      return
    }
    this.isDestroyingSession = true
    const sessionToDestroy = this.session
    try {
      if (this.isCasting) {
        try {
          await sessionToDestroy.stopCasting()
        } catch (_err) {
        }
      }
      this.unregisterSessionListeners()
      try {
        await sessionToDestroy.deactivate()
      } catch (_err) {
      }
      await sessionToDestroy.destroy()
      logger.info('Video cast session destroyed')
    } catch (err) {
      logger.debug('destroyVideoSession failed: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.session = null
      this.castController = null
      this.currentMedia = new CastMediaInfo()
      this.callbacks = new CastEventCallbacks()
      this.isInitialized = false
      this.isCasting = false
      this.lastStartedAssetId = ''
      this.lastStartedSubtitle = ''
      this.isSyncingFromPlaybackStore = false
      this.localCastEnabled = false
      this.isDestroyingSession = false
    }
  }

  private shortHash(value: string): string {
    let hash = 0
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
    }
    return String(value.length) + ':' + String(hash)
  }
}
