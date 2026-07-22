import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode } from './IPlayerEngine'
import { Logger } from '../../utils/Logger'
import mpvNapi from 'libmpv_napi.so'

const logger = new Logger('MpvPlayerEngine')
let mpvEngineSeq: number = 0

const MPV_FORMAT_FLAG = 3
const MPV_FORMAT_DOUBLE = 5
const MPV_EVENT_LOG_MESSAGE = 2
const MPV_EVENT_START_FILE = 6
const MPV_EVENT_FILE_LOADED = 8
const MPV_EVENT_END_FILE = 7
const MPV_EVENT_PROPERTY_CHANGE = 22

interface MpvNapiInterface {
  nativeCreate(): number
  nativeInitialize(ctxId: number): number
  nativeCommand(ctxId: number, args: string[]): number
  nativeCommandAsync(ctxId: number, args: string[]): number
  nativeSetProperty(ctxId: number, name: string, value: string): number
  nativeGetProperty(ctxId: number, name: string): string | null
  nativeObserveProperty(ctxId: number, replyUserdata: number, name: string, format: number): number
  nativeDestroy(ctxId: number): void
  nativeSetSurfaceId(ctxId: number, surfaceId: string): number
  nativeApiVersion(): number
  nativeOnEvent(ctxId: number, callback: (event: MpvEventData) => void): number
  nativeVpCreate(qualityLevel: number): number
  nativeVpSetOutputSurface(surfaceId: string): number
  nativeVpGetInputSurfaceId(): string | null
  nativeVpSetQualityLevel(qualityLevel: number): number
  nativeVpStart(): number
  nativeVpStop(): number
  nativeVpDestroy(): void
}

interface MpvEventData {
  ctxId: number
  eventId: number
  errorCode: number
  propertyName: string
  propertyValueStr: string
  propertyValueDouble: number
  reason: number
  logPrefix: string
  logLevel: string
  logText: string
}

function isValidMpvNapi(module: MpvNapiInterface | null | undefined): boolean {
  return module !== null && module !== undefined &&
    module.nativeCreate !== undefined &&
    module.nativeInitialize !== undefined &&
    module.nativeCommand !== undefined &&
    module.nativeSetProperty !== undefined &&
    module.nativeSetSurfaceId !== undefined
}

const importedNapi = mpvNapi as MpvNapiInterface
let napi: MpvNapiInterface | null = null
if (isValidMpvNapi(importedNapi)) {
  napi = importedNapi
  logger.info('mpv_napi native module loaded successfully')
} else {
  logger.warn('mpv_napi native module not available or missing exports')
  logger.warn('mpv engine will throw on prepare - AVPlayerEngine will be used as fallback')
}

export function isMpvNapiLoaded(): boolean {
  return isValidMpvNapi(napi)
}

function formatNativeError(err: Object): string {
  if (err instanceof Error) {
    return `${err.name}: ${err.message}`
  }

  const errObj = err as Record<string, Object>
  const parts: string[] = []
  if (errObj !== null && errObj !== undefined) {
    if (errObj['name'] !== undefined) {
      parts.push('name=' + String(errObj['name']))
    }
    if (errObj['message'] !== undefined) {
      parts.push('message=' + String(errObj['message']))
    }
    if (errObj['code'] !== undefined) {
      parts.push('code=' + String(errObj['code']))
    }
    if (errObj['stack'] !== undefined) {
      parts.push('stack=' + String(errObj['stack']))
    }
  }
  if (parts.length > 0) {
    return parts.join(', ')
  }
  return String(err)
}

export class MpvPlayerEngine implements IPlayerEngine {
  private readonly diagId: number = ++mpvEngineSeq
  private state: PlayerState = new PlayerState()
  private stateCallback: ((state: PlayerState) => void) | null = null
  private surfaceId: string = ''
  private isInitialized: boolean = false
  private ctxId: number = -1
  private readonly prepareTimeoutMs: number = 15000
  private prepareTimeoutTimer: number = -1
  private hwdecMode: string = 'auto'
  private hlsAdFilterEnabled: boolean = true
  private segAllowImgEnabled: boolean = true
  private detailEnhancerQuality: number = -1
  private pendingAspectMode: VideoAspectMode | null = null
  private isReleasing: boolean = false

  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId
    if (this.isInitialized && !this.isReleasing && this.ctxId >= 0 && napi !== null && surfaceId.length > 0) {
      try {
        const targetSurfaceId = this.getEffectiveSurfaceId(surfaceId)
        const err = napi.nativeSetSurfaceId(this.ctxId, targetSurfaceId)
        if (err < 0) {
          logger.warn('mpv surface rebind failed: %{public}d', err)
        } else {
          logger.info('mpv surface rebound: %{public}s (vp=%{public}s)', targetSurfaceId,
            this.detailEnhancerQuality >= 0 ? 'on' : 'off')
        }
      } catch (_err) {
        logger.warn('mpv surface rebind threw')
      }
    }
  }

  private getEffectiveSurfaceId(displaySurfaceId: string): string {
    if (this.detailEnhancerQuality < 0 || napi === null) {
      return displaySurfaceId
    }
    try {
      const createRet = napi.nativeVpCreate(this.detailEnhancerQuality)
      if (createRet !== 0) {
        logger.warn('VideoProcessing create failed: %{public}d, falling back to direct surface', createRet)
        return displaySurfaceId
      }
      const setSurfaceRet = napi.nativeVpSetOutputSurface(displaySurfaceId)
      if (setSurfaceRet !== 0) {
        logger.warn('VideoProcessing set output surface failed: %{public}d', setSurfaceRet)
        napi.nativeVpDestroy()
        return displaySurfaceId
      }
      const inputSurfaceId = napi.nativeVpGetInputSurfaceId()
      if (inputSurfaceId === null || inputSurfaceId.length === 0) {
        logger.warn('VideoProcessing get input surface id failed')
        napi.nativeVpDestroy()
        return displaySurfaceId
      }
      const startRet = napi.nativeVpStart()
      if (startRet !== 0) {
        logger.warn('VideoProcessing start failed: %{public}d', startRet)
        napi.nativeVpDestroy()
        return displaySurfaceId
      }
      logger.info('VideoProcessing pipeline active: mpv→VP(%{public}d)→display', this.detailEnhancerQuality)
      return inputSurfaceId
    } catch (err) {
      logger.warn('VideoProcessing setup threw: %{public}s', String(err))
      return displaySurfaceId
    }
  }

  setHwdecMode(mode: string): void {
    this.hwdecMode = mode
  }

  setHlsAdFilterEnabled(enabled: boolean): void {
    this.hlsAdFilterEnabled = enabled
  }

  setSegAllowImgEnabled(enabled: boolean): void {
    this.segAllowImgEnabled = enabled
  }

  setDetailEnhancerQuality(quality: number): void {
    this.detailEnhancerQuality = quality
  }

  prepare(options: PlaybackOptions): void {
    const prepareStartMs = Date.now()
    logger.warn('CrashDiag mpv prepare start: id=%{public}d urlLength=%{public}d surfaceId=%{public}s',
      this.diagId, options.url.length, this.surfaceId)
    logger.info('mpv prepare start, urlLength=%{public}d, surfaceId=%{public}s', options.url.length, this.surfaceId)
    this.clearPrepareTimeout()
    this.isReleasing = false
    this.resetState()
    this.state.stateName = 'creating'
    this.notifyStateChange()

    if (napi === null) {
      this.failPlayback('libmpv NAPI bridge not available - native library not compiled')
      return
    }

    try {
      let stepStartMs = Date.now()
      logger.info('mpv nativeCreate begin')
      this.ctxId = napi.nativeCreate()
      logger.warn('CrashDiag mpv nativeCreate returned: id=%{public}d ctxId=%{public}d elapsed=%{public}dms',
        this.diagId, this.ctxId, Date.now() - stepStartMs)
      if (this.ctxId < 0) {
        this.failPlayback('mpv_create failed')
        return
      }
      logger.info('mpv instance created, ctxId=%{public}d', this.ctxId)

      if (this.surfaceId.length > 0) {
        stepStartMs = Date.now()
        logger.info('mpv nativeSetSurfaceId begin, ctxId=%{public}d, surfaceId=%{public}s', this.ctxId, this.surfaceId)
        const surfaceErr = napi.nativeSetSurfaceId(this.ctxId, this.surfaceId)
        logger.warn('CrashDiag mpv nativeSetSurfaceId returned: id=%{public}d ctxId=%{public}d err=%{public}d elapsed=%{public}dms',
          this.diagId, this.ctxId, surfaceErr, Date.now() - stepStartMs)
        if (surfaceErr < 0) {
          logger.warn('nativeSetSurfaceId failed: %{public}d, continuing without surface', surfaceErr)
        } else {
          logger.info('mpv nativeSetSurfaceId ok')
        }
      }

      logger.info('mpv apply options begin')
      this.applyMpvOptions(options)
      logger.info('mpv apply options done')

      stepStartMs = Date.now()
      logger.info('mpv nativeInitialize begin, ctxId=%{public}d', this.ctxId)
      const initErr = napi.nativeInitialize(this.ctxId)
      logger.warn('CrashDiag mpv nativeInitialize returned: id=%{public}d ctxId=%{public}d err=%{public}d elapsed=%{public}dms',
        this.diagId, this.ctxId, initErr, Date.now() - stepStartMs)
      if (initErr < 0) {
        this.failPlayback('mpv_initialize failed: ' + String(initErr))
        return
      }
      this.isInitialized = true
      logger.info('mpv initialized successfully')

      if (this.pendingAspectMode !== null) {
        this.setAspectMode(this.pendingAspectMode)
      }

      const eventCtxId = this.ctxId
      napi.nativeOnEvent(eventCtxId, (event: MpvEventData) => {
        if (this.isReleasing || this.ctxId !== eventCtxId || event.ctxId !== eventCtxId) {
          return
        }
        this.handleMpvEvent(event)
      })

      this.observeKeyProperties()

      if (options.url.length > 0) {
        const loadArgs: string[] = ['loadfile', options.url]
        stepStartMs = Date.now()
        const loadErr = napi.nativeCommand(this.ctxId, loadArgs)
        logger.warn('CrashDiag mpv loadfile returned: id=%{public}d ctxId=%{public}d err=%{public}d elapsed=%{public}dms total=%{public}dms',
          this.diagId, this.ctxId, loadErr, Date.now() - stepStartMs, Date.now() - prepareStartMs)
        logger.info('mpv loadfile command result: %{public}d', loadErr)
        if (loadErr < 0) {
          this.failPlayback('mpv loadfile failed: ' + String(loadErr))
          return
        }
        this.state.stateName = 'preparing'
        this.notifyStateChange()
        this.startPrepareTimeout()
      }
    } catch (err) {
      const errorMsg = formatNativeError(err)
      logger.error('mpv prepare threw: %{public}s', errorMsg)
      this.failPlayback('mpv初始化失败: ' + errorMsg)
    }
  }

  play(): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const startMs = Date.now()
      logger.warn('CrashDiag mpv play begin: id=%{public}d ctxId=%{public}d', this.diagId, this.ctxId)
      const err = this.commandControlPause(false)
      logger.warn('CrashDiag mpv play returned: id=%{public}d ctxId=%{public}d err=%{public}d elapsed=%{public}dms',
        this.diagId, this.ctxId, err, Date.now() - startMs)
      this.state.playing = true
      this.state.stateName = 'playing'
      this.notifyStateChange()
    } catch (_err) {
      logger.error('mpv play failed')
    }
  }

  pause(): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const startMs = Date.now()
      logger.warn('CrashDiag mpv pause begin: id=%{public}d ctxId=%{public}d', this.diagId, this.ctxId)
      const err = this.commandControlPause(true)
      logger.warn('CrashDiag mpv pause returned: id=%{public}d ctxId=%{public}d err=%{public}d elapsed=%{public}dms',
        this.diagId, this.ctxId, err, Date.now() - startMs)
      this.state.playing = false
      this.state.stateName = 'paused'
      this.notifyStateChange()
    } catch (_err) {
      logger.error('mpv pause failed')
    }
  }

  stop(): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const startMs = Date.now()
      logger.warn('CrashDiag mpv stop begin: id=%{public}d ctxId=%{public}d', this.diagId, this.ctxId)
      const err = napi.nativeCommandAsync !== undefined ?
        napi.nativeCommandAsync(this.ctxId, ['stop']) :
        napi.nativeCommand(this.ctxId, ['stop'])
      logger.warn('CrashDiag mpv stop returned: id=%{public}d ctxId=%{public}d err=%{public}d elapsed=%{public}dms',
        this.diagId, this.ctxId, err, Date.now() - startMs)
      this.state.playing = false
      this.state.stateName = 'stopped'
      this.notifyStateChange()
    } catch (_err) {
      logger.error('mpv stop failed')
    }
  }

  seek(positionMs: number): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const positionSec = positionMs / 1000
      napi.nativeCommand(this.ctxId, ['seek', String(positionSec), 'absolute'])
      this.state.positionMs = positionMs
    } catch (_err) {
      logger.error('mpv seek failed')
    }
  }

  setSpeed(speed: number): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      napi.nativeSetProperty(this.ctxId, 'speed', String(speed))
      this.state.speed = speed
      this.notifyStateChange()
    } catch (_err) {
      logger.error('mpv setSpeed failed')
    }
  }

  setVolume(volume: number): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const volumePercent = Math.round(volume * 100)
      napi.nativeSetProperty(this.ctxId, 'volume', String(volumePercent))
      this.state.volume = volume
      this.notifyStateChange()
    } catch (_err) {
      logger.error('mpv setVolume failed')
    }
  }

  setAspectMode(mode: VideoAspectMode): void {
    this.pendingAspectMode = mode
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const modeName = this.getAspectModeName(mode)
      const keepAspect = this.getMpvKeepAspectValue(mode)
      const err = napi.nativeSetProperty(this.ctxId, 'keepaspect', keepAspect)
      if (err < 0) {
        logger.warn('mpv setAspectMode failed: mode=%{public}s, keepaspect=%{public}s, err=%{public}d',
          modeName, keepAspect, err)
        return
      }
      this.pendingAspectMode = null
      logger.info('mpv setAspectMode ok: mode=%{public}s, params=keepaspect=%{public}s',
        modeName, keepAspect)
    } catch (err) {
      logger.warn('mpv setAspectMode threw: %{public}s', String(err))
    }
  }

  getState(): PlayerState {
    return this.state
  }

  private commandControlPause(paused: boolean): number {
    if (napi === null || this.ctxId < 0) {
      return -1
    }
    const value = paused ? 'yes' : 'no'
    if (napi.nativeCommandAsync !== undefined) {
      return napi.nativeCommandAsync(this.ctxId, ['set', 'pause', value])
    }
    return napi.nativeSetProperty(this.ctxId, 'pause', value)
  }

  onStateChange(callback: (state: PlayerState) => void): void {
    this.stateCallback = callback
  }

  release(): void {
    const releaseStartMs = Date.now()
    logger.warn('CrashDiag mpv release begin: id=%{public}d ctxId=%{public}d initialized=%{public}s releasing=%{public}s',
      this.diagId, this.ctxId, String(this.isInitialized), String(this.isReleasing))
    this.clearPrepareTimeout()
    if (this.isReleasing) {
      logger.warn('CrashDiag mpv release skipped: id=%{public}d reason=already-releasing', this.diagId)
      return
    }
    if (napi !== null && this.detailEnhancerQuality >= 0) {
      try {
        napi.nativeVpStop()
        napi.nativeVpDestroy()
        logger.info('VideoProcessing destroyed on release')
      } catch (_err) {
        logger.warn('VideoProcessing destroy on release failed')
      }
    }
    if (this.ctxId >= 0 && napi !== null) {
      const releasingCtxId = this.ctxId
      this.isReleasing = true
      this.isInitialized = false
      this.ctxId = -1
      try {
        const destroyStartMs = Date.now()
        napi.nativeDestroy(releasingCtxId)
        logger.warn('CrashDiag mpv nativeDestroy returned: id=%{public}d ctxId=%{public}d elapsed=%{public}dms',
          this.diagId, releasingCtxId, Date.now() - destroyStartMs)
        logger.info('mpv instance destroy scheduled, ctxId=%{public}d', releasingCtxId)
      } catch (_err) {
        logger.error('mpv destroy failed')
      }
    }
    this.resetState()
    logger.warn('CrashDiag mpv release end: id=%{public}d elapsed=%{public}dms',
      this.diagId, Date.now() - releaseStartMs)
  }

  addSubtitle(path: string): void {
    if (!this.isInitialized || this.ctxId < 0 || napi === null) {
      return
    }
    try {
      napi.nativeCommand(this.ctxId, ['sub-add', path])
      logger.info('Subtitle added: %{public}s', path.substring(0, 80))
    } catch (_err) {
      logger.error('mpv addSubtitle failed')
    }
  }

  handleMpvEvent(event: MpvEventData): void {
    if (!this.isInitialized || this.ctxId < 0) {
      return
    }

    switch (event.eventId) {
      case MPV_EVENT_START_FILE:
        this.state.stateName = 'preparing'
        this.state.playing = false
        this.notifyStateChange()
        logger.info('CrashDiag mpv event: id=%{public}d start-file', this.diagId)
        logger.info('mpv event: start-file')
        break

      case MPV_EVENT_LOG_MESSAGE:
        this.handleLogMessage(event)
        break

      case MPV_EVENT_FILE_LOADED:
        this.clearPrepareTimeout()
        this.state.stateName = 'playing'
        this.state.playing = true
        this.fetchVideoSize()
        this.notifyStateChange()
        logger.info('CrashDiag mpv event: id=%{public}d file-loaded', this.diagId)
        logger.info('mpv event: file-loaded')
        break

      case MPV_EVENT_END_FILE:
        this.clearPrepareTimeout()
        if (event.reason === 0) {
          this.state.completed = true
          this.state.playing = false
          this.state.stateName = 'completed'
          logger.info('mpv event: end-file (completed)')
        } else {
          if (event.errorCode !== 0) {
            this.state.stateName = 'error'
            this.state.error = 'mpv playback error, code=' + String(event.errorCode)
            logger.error('CrashDiag mpv event: id=%{public}d end-file-error code=%{public}d reason=%{public}d',
              this.diagId, event.errorCode, event.reason)
            logger.error('mpv event: end-file (error), code=%{public}d, reason=%{public}d', event.errorCode, event.reason)
          } else {
            this.state.stateName = 'stopped'
            logger.info('mpv event: end-file (reason=%{public}d)', event.reason)
          }
          this.state.playing = false
        }
        this.notifyStateChange()
        break

      case MPV_EVENT_PROPERTY_CHANGE:
        this.handlePropertyChange(event)
        break

      default:
        break
    }
  }

  private handleLogMessage(event: MpvEventData): void {
    if (event.logText.length === 0) {
      return
    }
    const prefix = event.logPrefix.length > 0 ? event.logPrefix : 'mpv'
    const level = event.logLevel.length > 0 ? event.logLevel : 'info'
    const text = event.logText.length > 900 ? event.logText.substring(0, 900) : event.logText
    if (level === 'fatal' || level === 'error') {
      logger.error('mpv log [%{public}s/%{public}s] %{public}s', prefix, level, text)
    } else if (level === 'warn') {
      logger.warn('mpv log [%{public}s/%{public}s] %{public}s', prefix, level, text)
    } else {
      logger.info('mpv log [%{public}s/%{public}s] %{public}s', prefix, level, text)
    }
  }

  private handlePropertyChange(event: MpvEventData): void {
    const name = event.propertyName
    if (name.length === 0) {
      return
    }

    switch (name) {
      case 'time-pos':
        if (event.propertyValueDouble >= 0) {
          this.state.positionMs = Math.max(0, Math.round(event.propertyValueDouble * 1000))
        }
        break

      case 'duration':
        if (event.propertyValueDouble > 0) {
          this.state.durationMs = Math.max(0, Math.round(event.propertyValueDouble * 1000))
          logger.info('mpv duration updated: %{public}dms', this.state.durationMs)
        }
        break

      case 'pause':
        this.state.playing = !this.readMpvFlag(event)
        if (this.state.playing && this.state.stateName !== 'completed') {
          this.state.stateName = 'playing'
        } else if (!this.state.playing && this.state.stateName !== 'completed' && this.state.stateName !== 'error') {
          this.state.stateName = 'paused'
        }
        break

      case 'eof-reached':
        if (this.readMpvFlag(event)) {
          this.state.completed = true
          this.state.playing = false
          this.state.stateName = 'completed'
        }
        break

      case 'buffering-state':
        this.state.buffering = event.propertyValueDouble > 0
        break

      default:
        break
    }
    this.notifyStateChange()
  }

  private applyMpvOptions(options: PlaybackOptions): void {
    if (this.ctxId < 0 || napi === null) {
      return
    }
    try {
      napi.nativeSetProperty(this.ctxId, 'vo', 'ohcodec')
      napi.nativeSetProperty(this.ctxId, 'ao', 'ohaudio')
      napi.nativeSetProperty(this.ctxId, 'hwdec', this.hwdecMode)
      napi.nativeSetProperty(this.ctxId, 'keepaspect', 'no')

      const demuxerOpts: string[] = []
      if (this.hlsAdFilterEnabled) {
        demuxerOpts.push('hls_ad_filter=1')
      }
      if (this.segAllowImgEnabled) {
        demuxerOpts.push('seg_allow_img=1')
      }
      if (demuxerOpts.length > 0) {
        napi.nativeSetProperty(this.ctxId, 'demuxer-lavf-o', demuxerOpts.join(','))
        logger.info('HLS options set: demuxer-lavf-o=%{public}s', demuxerOpts.join(','))
      }

      if (options.referer.length > 0) {
        napi.nativeSetProperty(this.ctxId, 'referrer', options.referer)
      }
      if (options.userAgent.length > 0) {
        napi.nativeSetProperty(this.ctxId, 'user-agent', options.userAgent)
      }
      if (options.proxy.length > 0) {
        napi.nativeSetProperty(this.ctxId, 'http-proxy', options.proxy)
      }
      if (options.streamMetadata !== null && !options.streamMetadata.isEmpty()) {
        logger.info('mpv stream metadata: %{public}s', options.streamMetadata.summary())
        if (options.streamMetadata.hasDolbyVision || options.streamMetadata.hasHdrCodecHint) {
          logger.warn('mpv stream has HDR/Dolby codec hints; hardware capability depends on device decoder/display')
        }
        if (options.streamMetadata.hasAacAudio) {
          logger.info('mpv stream includes AAC audio')
        }
      }
      const headerKeys = Object.keys(options.headers)
      if (headerKeys.length > 0) {
        const headerParts: string[] = []
        for (let i = 0; i < headerKeys.length; i++) {
          const key = headerKeys[i]
          const headerLine = this.buildSafeMpvHeaderLine(key, options.headers[key])
          if (headerLine.length > 0) {
            headerParts.push(headerLine)
          }
        }
        if (headerParts.length > 0) {
          napi.nativeSetProperty(this.ctxId, 'http-header-fields', headerParts.join(','))
          logger.info('mpv http headers applied: count=%{public}d names=%{public}s',
            headerParts.length, this.describeHeaderNames(headerParts))
        }
      }
      if (options.startPositionMs > 0) {
        napi.nativeSetProperty(this.ctxId, 'start', String(options.startPositionMs / 1000))
      }
    } catch (_err) {
      logger.warn('applyMpvOptions partially failed (non-fatal)')
    }
  }

  private describeHeaderNames(headerParts: string[]): string {
    const names: string[] = []
    for (let i = 0; i < headerParts.length; i++) {
      const colonIndex = headerParts[i].indexOf(':')
      if (colonIndex > 0) {
        names.push(headerParts[i].substring(0, colonIndex))
      }
    }
    return names.join('|')
  }

  private buildSafeMpvHeaderLine(key: string, value: string): string {
    const headerName = this.normalizeMpvHeaderName(key)
    if (headerName.length === 0) {
      return ''
    }
    const headerValue = value.trim()
    if (headerValue.length === 0) {
      return ''
    }
    if (headerValue.indexOf('\r') >= 0 || headerValue.indexOf('\n') >= 0 || headerValue.indexOf(',') >= 0) {
      logger.warn('Skip unsafe mpv http header: %{public}s', headerName)
      return ''
    }
    return `${headerName}: ${headerValue}`
  }

  private normalizeMpvHeaderName(key: string): string {
    const lowerKey = key.trim().toLowerCase()
    switch (lowerKey) {
      case 'cookie':
        return 'Cookie'
      case 'origin':
        return 'Origin'
      case 'accept':
        return 'Accept'
      case 'referer':
      case 'referrer':
        return 'Referer'
      case 'user-agent':
        return 'User-Agent'
      default:
        return ''
    }
  }

  private fetchVideoSize(): void {
    if (this.ctxId < 0 || napi === null) {
      return
    }
    try {
      const dwStr = napi.nativeGetProperty(this.ctxId, 'dwidth')
      const dhStr = napi.nativeGetProperty(this.ctxId, 'dheight')
      if (dwStr !== null && dhStr !== null) {
        const dw = parseInt(dwStr, 10)
        const dh = parseInt(dhStr, 10)
        if (!isNaN(dw) && !isNaN(dh) && dw > 0 && dh > 0) {
          this.state.videoWidth = dw
          this.state.videoHeight = dh
          logger.info('mpv video size: %{public}dx%{public}d', dw, dh)
        } else {
          logger.warn('mpv video size invalid: dwidth=%{public}s, dheight=%{public}s', dwStr, dhStr)
        }
      }
    } catch (err) {
      logger.warn('mpv fetchVideoSize failed: %{public}s', String(err))
    }
  }

  private observeKeyProperties(): void {
    if (this.ctxId < 0 || napi === null) {
      return
    }
    try {
      napi.nativeObserveProperty(this.ctxId, 1, 'time-pos', MPV_FORMAT_DOUBLE)
      napi.nativeObserveProperty(this.ctxId, 2, 'duration', MPV_FORMAT_DOUBLE)
      napi.nativeObserveProperty(this.ctxId, 3, 'pause', MPV_FORMAT_FLAG)
      napi.nativeObserveProperty(this.ctxId, 4, 'eof-reached', MPV_FORMAT_FLAG)
      napi.nativeObserveProperty(this.ctxId, 5, 'buffering-state', MPV_FORMAT_DOUBLE)
    } catch (_err) {
      logger.warn('observe properties failed (non-fatal)')
    }
  }

  private readMpvFlag(event: MpvEventData): boolean {
    if (event.propertyValueStr === 'yes' || event.propertyValueStr === 'true' || event.propertyValueStr === '1') {
      return true
    }
    if (event.propertyValueStr === 'no' || event.propertyValueStr === 'false' || event.propertyValueStr === '0') {
      return false
    }
    return event.propertyValueDouble > 0
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

  private getMpvKeepAspectValue(mode: VideoAspectMode): string {
    switch (mode) {
      case VideoAspectMode.contain:
      case VideoAspectMode.cover:
        return 'yes'
      case VideoAspectMode.fill:
        return 'no'
      default:
        return 'yes'
    }
  }

  private resetState(): void {
    this.state = new PlayerState()
  }

  private notifyStateChange(): void {
    if (this.stateCallback !== null) {
      this.stateCallback(this.state)
    }
  }

  private failPlayback(errorMsg: string): void {
    logger.error('mpv playback failed: %{public}s', errorMsg)
    this.state.stateName = 'error'
    this.state.error = errorMsg
    this.state.playing = false
    this.notifyStateChange()
  }

  private startPrepareTimeout(): void {
    this.prepareTimeoutTimer = setTimeout(() => {
      if (this.state.stateName === 'preparing') {
        logger.error('mpv prepare timeout after %{public}d ms', this.prepareTimeoutMs)
        this.failPlayback('mpv prepare timeout')
      }
    }, this.prepareTimeoutMs)
  }

  private clearPrepareTimeout(): void {
    if (this.prepareTimeoutTimer >= 0) {
      clearTimeout(this.prepareTimeoutTimer)
      this.prepareTimeoutTimer = -1
    }
  }
}
