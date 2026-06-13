import { PlayerState } from '../player/IPlayerEngine'
import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { DanmakuRenderer } from './DanmakuRenderer'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuTimeSync')

const SEEK_THRESHOLD_MS = 5000
const DISPATCH_POLL_INTERVAL_MS = 100

export class DanmakuTimeSync {
  private trackAllocator: DanmakuTrackAllocator
  private renderer: DanmakuRenderer
  private allDanmaku: DanmakuItem[] = []
  private lastPositionMs: number = 0
  private lastPlaying: boolean = false
  private lastSpeed: number = 1.0
  private durationMs: number = 0
  private dispatchIndex: number = 0
  private isSeeking: boolean = false
  private currentPositionMs: number = 0
  private currentPlaying: boolean = false
  private currentSpeed: number = 1.0
  private pollTimerId: number = -1

  constructor(trackAllocator: DanmakuTrackAllocator, renderer: DanmakuRenderer) {
    this.trackAllocator = trackAllocator
    this.renderer = renderer
  }

  setDanmakuData(items: DanmakuItem[]): void {
    this.allDanmaku = items
    this.dispatchIndex = 0
  }

  onPlayerStateUpdate(state: PlayerState): void {
    const positionMs = this.clampPosition(state.positionMs, state.durationMs)
    this.durationMs = state.durationMs
    this.currentPositionMs = positionMs
    this.currentSpeed = state.speed > 0 ? state.speed : 1.0

    if (this.lastPlaying && Math.abs(positionMs - this.lastPositionMs) > SEEK_THRESHOLD_MS) {
      this.handleSeek(positionMs)
    }

    if (state.playing !== this.lastPlaying) {
      this.currentPlaying = state.playing
      if (state.playing) {
        this.renderer.resumeRendering()
        this.startDispatchPoll()
      } else {
        this.renderer.pauseRendering()
        this.stopDispatchPoll()
      }
    }

    if (state.speed !== this.lastSpeed && state.speed > 0) {
      this.renderer.setPlaybackSpeed(state.speed)
    }

    if (state.stateName === 'completed' || state.stateName === 'error' || state.stateName === 'stopped') {
      this.currentPlaying = false
      this.stopDispatchPoll()
      this.renderer.stopRendering()
      this.renderer.clearAll()
    }

    if (state.playing) {
      this.dispatchDanmaku(positionMs)
    }

    this.lastPositionMs = positionMs
    this.lastPlaying = state.playing
    this.lastSpeed = state.speed
  }

  reset(): void {
    this.stopDispatchPoll()
    this.allDanmaku = []
    this.dispatchIndex = 0
    this.lastPositionMs = 0
    this.lastPlaying = false
    this.lastSpeed = 1.0
    this.isSeeking = false
    this.currentPositionMs = 0
    this.currentPlaying = false
    this.currentSpeed = 1.0
  }

  resyncAfterResize(): void {
    if (this.renderer !== null) {
      this.renderer.clearAll()
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.reset()
    }
    this.dispatchIndex = this.findDispatchIndex(this.currentPositionMs)
  }

  private startDispatchPoll(): void {
    if (this.pollTimerId >= 0) {
      return
    }
    this.pollTimerId = setInterval(() => {
      this.onDispatchPollTick()
    }, DISPATCH_POLL_INTERVAL_MS)
  }

  private stopDispatchPoll(): void {
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId)
      this.pollTimerId = -1
    }
  }

  private onDispatchPollTick(): void {
    if (!this.currentPlaying) {
      return
    }
    const elapsed = DISPATCH_POLL_INTERVAL_MS * this.currentSpeed
    this.currentPositionMs += elapsed
    if (this.durationMs > 0 && this.currentPositionMs > this.durationMs) {
      this.currentPositionMs = this.durationMs
    }
    this.dispatchDanmaku(this.currentPositionMs)
  }

  private handleSeek(newPositionMs: number): void {
    logger.info('检测到seek, newPositionMs=%{public}d', newPositionMs)
    this.renderer.clearAll()
    this.trackAllocator.reset()
    this.dispatchIndex = this.findDispatchIndex(newPositionMs)
    this.isSeeking = true
  }

  private dispatchDanmaku(positionMs: number): void {
    if (this.allDanmaku.length === 0) {
      return
    }

    while (this.dispatchIndex < this.allDanmaku.length) {
      const item = this.allDanmaku[this.dispatchIndex]
      if (item.timeMs > positionMs) {
        break
      }

      const trackIndex = this.trackAllocator.allocateTrack(item)
      if (trackIndex >= 0) {
        item.trackIndex = trackIndex
        item.x = this.renderer.getCanvasWidth()
        item.isAlive = true
        this.renderer.addActiveDanmaku(item)
      }

      this.dispatchIndex++
    }
  }

  private findDispatchIndex(targetMs: number): number {
    let left = 0
    let right = this.allDanmaku.length
    while (left < right) {
      const mid = Math.floor((left + right) / 2)
      if (this.allDanmaku[mid].timeMs <= targetMs) {
        left = mid + 1
      } else {
        right = mid
      }
    }
    return left
  }

  private clampPosition(positionMs: number, durationMs: number): number {
    if (positionMs < 0) {
      logger.warn('播放进度异常：positionMs=%{public}d', positionMs)
      return 0
    }
    if (durationMs > 0 && positionMs > durationMs) {
      logger.warn('播放进度异常：positionMs=%{public}d > durationMs=%{public}d',
        positionMs, durationMs)
      return durationMs
    }
    return positionMs
  }
}