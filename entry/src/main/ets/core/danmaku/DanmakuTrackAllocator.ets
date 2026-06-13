import { DanmakuItem } from '../../models/DanmakuItem'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuTrackAllocator')

const TRACK_GAP = 20
const DEFAULT_FONT_SIZE = 25
const LINE_HEIGHT_RATIO = 1.4

export class DanmakuTrackAllocator {
  private trackCount: number = 0
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private trackRightBounds: number[] = []
  private discardCount: number = 0

  updateCanvasSize(width: number, height: number): void {
    this.canvasWidth = width
    this.canvasHeight = height
    this.recalculateTracks()
  }

  allocateTrack(item: DanmakuItem): number {
    if (this.trackCount === 0) {
      this.discardCount++
      return -1
    }

    const textWidth = item.textWidth > 0 ? item.textWidth : 200
    const itemRightEdge = this.canvasWidth + textWidth + TRACK_GAP

    for (let i = 0; i < this.trackCount; i++) {
      const bound = this.trackRightBounds[i]
      if (bound < 0 || bound <= this.canvasWidth) {
        this.trackRightBounds[i] = itemRightEdge
        return i
      }
    }

    this.discardCount++
    if (this.discardCount % 50 === 1) {
      logger.info('弹幕轨道溢出：已丢弃%{public}d条弹幕', this.discardCount)
    }
    return -1
  }

  releaseTrack(trackIndex: number): void {
    if (trackIndex >= 0 && trackIndex < this.trackCount) {
      this.trackRightBounds[trackIndex] = -1
    }
  }

  updateTrackBound(trackIndex: number, rightBound: number): void {
    if (trackIndex >= 0 && trackIndex < this.trackCount) {
      this.trackRightBounds[trackIndex] = rightBound
    }
  }

  getTrackY(trackIndex: number): number {
    if (trackIndex < 0 || trackIndex >= this.trackCount) {
      return 0
    }
    const lineHeight = Math.round(DEFAULT_FONT_SIZE * LINE_HEIGHT_RATIO)
    return trackIndex * lineHeight + Math.round(lineHeight / 2)
  }

  getTrackCount(): number {
    return this.trackCount
  }

  getDiscardCount(): number {
    return this.discardCount
  }

  reset(): void {
    for (let i = 0; i < this.trackCount; i++) {
      this.trackRightBounds[i] = -1
    }
    this.discardCount = 0
  }

  private recalculateTracks(): void {
    if (this.canvasHeight <= 0) {
      this.trackCount = 0
      this.trackRightBounds = []
      return
    }

    const lineHeight = Math.round(DEFAULT_FONT_SIZE * LINE_HEIGHT_RATIO)
    const newTrackCount = Math.floor(this.canvasHeight / lineHeight)

    if (newTrackCount === this.trackCount) {
      return
    }

    logger.info('轨道数量变更: %{public}d -> %{public}d', this.trackCount, newTrackCount)
    this.trackCount = newTrackCount
    this.trackRightBounds = []
    for (let i = 0; i < this.trackCount; i++) {
      this.trackRightBounds.push(-1)
    }
  }
}