import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuRenderer')

const TARGET_FPS = 30
const FRAME_INTERVAL_MS = 1000 / TARGET_FPS
const SCROLL_DURATION_SEC = 8
const FPS_LOW_THRESHOLD = 20
const FPS_CRITICAL_THRESHOLD = 15
const FPS_LOW_DURATION_MS = 3000
const FPS_CRITICAL_DURATION_MS = 5000
const DENSITY_REDUCTION_RATIO = 0.7

export class DanmakuRenderer {
  private trackAllocator: DanmakuTrackAllocator
  private canvasContext: CanvasRenderingContext2D | null = null
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private activeDanmaku: DanmakuItem[] = []
  private scrollSpeed: number = 0
  private maxVisibleCount: number = 0
  private isRendering: boolean = false
  private isPaused: boolean = false
  private renderTimerId: number = -1
  private lastFrameTimeMs: number = 0
  private playbackSpeed: number = 1.0
  private frameTimestamps: number[] = []
  private currentFps: number = 0
  private lowFpsStartMs: number = 0
  private criticalFpsStartMs: number = 0
  private densityReduced: boolean = false
  private criticalStopped: boolean = false

  constructor(trackAllocator: DanmakuTrackAllocator) {
    this.trackAllocator = trackAllocator
  }

  setCanvasContext(context: CanvasRenderingContext2D, width: number, height: number): void {
    this.canvasContext = context
    this.canvasWidth = width
    this.canvasHeight = height
    this.recalculateParams()
  }

  updateCanvasSize(width: number, height: number): void {
    this.canvasWidth = width
    this.canvasHeight = height
    this.recalculateParams()

  }

  getCanvasWidth(): number {
    return this.canvasWidth
  }

  addActiveDanmaku(item: DanmakuItem): void {
    if (this.activeDanmaku.length >= this.maxVisibleCount) {
      return
    }
    this.activeDanmaku.push(item)
  }

  startRendering(): void {
    if (this.isRendering || this.canvasContext === null) {
      return
    }
    this.isRendering = true
    this.isPaused = false
    this.lastFrameTimeMs = Date.now()
    this.renderTimerId = setInterval(() => {
      this.renderFrame()
    }, FRAME_INTERVAL_MS)
  }

  pauseRendering(): void {
    this.isPaused = true
  }

  resumeRendering(): void {
    if (!this.isRendering) {
      this.criticalStopped = false
      this.startRendering()
      return
    }
    this.isPaused = false
    this.lastFrameTimeMs = Date.now()
    if (this.criticalStopped) {
      this.criticalStopped = false
      this.densityReduced = false
      this.recalculateParams()
      logger.info('弹幕渲染从critical状态恢复')
    }
  }

  stopRendering(): void {
    this.isRendering = false
    this.isPaused = false
    if (this.renderTimerId >= 0) {
      clearInterval(this.renderTimerId)
      this.renderTimerId = -1
    }
  }

  setPlaybackSpeed(speed: number): void {
    this.playbackSpeed = speed
  }

  clearAll(): void {
    this.activeDanmaku = []
    this.trackAllocator.reset()
    this.densityReduced = false
    this.criticalStopped = false
  }

  release(): void {
    this.stopRendering()
    this.canvasContext = null
    this.activeDanmaku = []
    this.frameTimestamps = []
    this.densityReduced = false
    this.criticalStopped = false
  }

  private recalculateParams(): void {
    if (this.canvasWidth <= 0) {
      return
    }
    this.scrollSpeed = this.canvasWidth / (SCROLL_DURATION_SEC * TARGET_FPS)
    const trackCount = this.trackAllocator.getTrackCount()
    this.maxVisibleCount = trackCount * 2
    if (this.densityReduced) {
      this.maxVisibleCount = Math.floor(this.maxVisibleCount * DENSITY_REDUCTION_RATIO)
    }
  }

  private renderFrame(): void {
    if (!this.isRendering) {
      return
    }

    const now = Date.now()
    this.lastFrameTimeMs = now

    if (!this.isPaused && this.canvasContext !== null) {
      this.updatePositions()
      this.drawFrame()
      this.cleanupExpiredDanmaku()
      this.monitorFps(now)
    }
  }

  private updatePositions(): void {
    const speed = this.scrollSpeed * this.playbackSpeed
    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      item.x -= speed

      const textWidth = item.textWidth > 0 ? item.textWidth : 200
      const rightBound = item.x + textWidth
      this.trackAllocator.updateTrackBound(item.trackIndex, rightBound)
    }
  }

  private drawFrame(): void {
    if (this.canvasContext === null) {
      return
    }

    const ctx = this.canvasContext
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight)

    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      try {
        this.drawDanmakuItem(ctx, item)
      } catch (_drawErr) {
        logger.warn('弹幕绘制异常：跳过')
      }
    }
  }

  private drawDanmakuItem(ctx: CanvasRenderingContext2D, item: DanmakuItem): void {
    if (item.x + (item.textWidth > 0 ? item.textWidth : 200) < 0) {
      return
    }

    ctx.font = `${item.fontSize}px sans-serif`
    ctx.fillStyle = item.color
    ctx.textBaseline = 'middle'
    ctx.fillText(item.content, item.x, this.trackAllocator.getTrackY(item.trackIndex))

    if (item.textWidth === 0) {
      const measured = ctx.measureText(item.content)
      item.textWidth = measured.width > 0 ? measured.width : 200
    }
  }

  private cleanupExpiredDanmaku(): void {
    let writeIdx = 0
    for (let i = 0; i < this.activeDanmaku.length; i++) {
      const item = this.activeDanmaku[i]
      const textWidth = item.textWidth > 0 ? item.textWidth : 200
      if (item.x + textWidth < 0) {
        item.isAlive = false
        this.trackAllocator.releaseTrack(item.trackIndex)
      } else {
        if (writeIdx !== i) {
          this.activeDanmaku[writeIdx] = item
        }
        writeIdx++
      }
    }
    if (writeIdx < this.activeDanmaku.length) {
      this.activeDanmaku.length = writeIdx
    }
  }

  private monitorFps(now: number): void {
    this.frameTimestamps.push(now)
    const oneSecAgo = now - 1000
    while (this.frameTimestamps.length > 0 &&
           this.frameTimestamps[0] < oneSecAgo) {
      this.frameTimestamps.shift()
    }
    this.currentFps = this.frameTimestamps.length

    if (this.currentFps < FPS_LOW_THRESHOLD) {
      if (this.lowFpsStartMs === 0) {
        this.lowFpsStartMs = now
      }
      if (now - this.lowFpsStartMs >= FPS_LOW_DURATION_MS && !this.densityReduced) {
        this.densityReduced = true
        this.recalculateParams()
        logger.warn('帧率过低(%{public}dfps)，降低弹幕密度30%%', this.currentFps)
      }

      if (this.currentFps < FPS_CRITICAL_THRESHOLD) {
        if (this.criticalFpsStartMs === 0) {
          this.criticalFpsStartMs = now
        }
        if (now - this.criticalFpsStartMs >= FPS_CRITICAL_DURATION_MS) {
          this.criticalStopped = true
          this.stopRendering()
          logger.error('帧率持续过低(%{public}dfps)，暂停弹幕渲染，将在下次resume时恢复', this.currentFps)
        }
      }
    } else {
      this.lowFpsStartMs = 0
      this.criticalFpsStartMs = 0
      if (this.densityReduced && this.currentFps > 24) {
        this.densityReduced = false
        this.recalculateParams()
        logger.info('帧率恢复(%{public}dfps)，恢复弹幕密度', this.currentFps)
      }
    }
  }
}
