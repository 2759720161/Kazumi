@Component
export struct GestureLayer {
  @Prop durationMs: number = 0
  @Prop positionMs: number = 0
  @Prop volume: number = 1.0
  @Prop screenBrightness: number = 0.5
  @Prop isPlaying: boolean = false
  @Prop isControlVisible: boolean = false
  @State gestureType: number = 0
  @State gestureValue: number = 0
  @State seekDeltaMs: number = 0
  onSeek?: (positionMs: number) => void
  onVolumeChange?: (volume: number) => void
  onBrightnessChange?: (brightness: number) => void
  onTogglePlayPause?: () => void
  onShowControls?: () => void
  onToggleControls?: () => void
  onTemporarySpeedStart?: () => void
  onTemporarySpeedEnd?: () => void

  private readonly GESTURE_NONE: number = 0
  private readonly GESTURE_SEEK: number = 1
  private readonly GESTURE_VOLUME: number = 2
  private readonly GESTURE_BRIGHTNESS: number = 3
  private readonly MIN_BRIGHTNESS: number = 0.05
  private readonly VERTICAL_GESTURE_RANGE_RATIO: number = 0.72
  @State private layerWidth: number = 360
  @State private layerHeight: number = 640
  private panStartX: number = 0
  private panStartY: number = 0
  private gestureStartValue: number = 0
  private isLongPressActive: boolean = false

  build() {
    Column() {
      if (this.gestureType === this.GESTURE_SEEK) {
        Column() {
          Text(this.seekDeltaMs >= 0 ? `快进 ${this.formatDelta(this.seekDeltaMs)}` : `快退 ${this.formatDelta(-this.seekDeltaMs)}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_on_primary'))

          Text(this.formatTime(this.positionMs + this.seekDeltaMs) + ' / ' + this.formatTime(this.durationMs))
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))
            .margin({ top: 4 })
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor($r('app.color.overlay_topbar_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      } else if (this.gestureType === this.GESTURE_VOLUME) {
        Column() {
          Text('音量')
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))

          Progress({ value: this.gestureValue * 100, type: ProgressType.Linear })
            .width(120)
            .color($r('app.color.accent_blue_light'))
            .margin({ top: 6 })

          Text(`${Math.round(this.gestureValue * 100)}%`)
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))
            .margin({ top: 4 })
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor($r('app.color.overlay_topbar_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      } else if (this.gestureType === this.GESTURE_BRIGHTNESS) {
        Column() {
          Text('亮度')
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))

          Progress({ value: this.gestureValue * 100, type: ProgressType.Linear })
            .width(120)
            .color($r('app.color.accent_blue_light'))
            .margin({ top: 6 })

          Text(`${Math.round(this.gestureValue * 100)}%`)
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))
            .margin({ top: 4 })
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor($r('app.color.overlay_topbar_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_transparent'))
    .hitTestBehavior(HitTestMode.Default)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = Number(newArea.width)
      const height = Number(newArea.height)
      if (width > 0) {
        this.layerWidth = width
      }
      if (height > 0) {
        this.layerHeight = height
      }
    })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 20 })
          .onActionStart((event: GestureEvent) => {
            this.gestureType = this.GESTURE_SEEK
            this.seekDeltaMs = 0
            if (event && event.fingerList.length > 0) {
              this.panStartX = event.fingerList[0].globalX
              this.panStartY = event.fingerList[0].globalY
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.gestureType !== this.GESTURE_SEEK || !event || event.fingerList.length === 0) {
              return
            }
            const dx = event.fingerList[0].globalX - this.panStartX
            this.updateSeekDelta(dx)
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.gestureType === this.GESTURE_SEEK && this.seekDeltaMs !== 0 && this.onSeek) {
              const targetMs = Math.max(0, Math.min(this.durationMs, this.positionMs + this.seekDeltaMs))
              this.onSeek(targetMs)
            }
            this.resetGestureState()
          }),

        PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 20 })
          .onActionStart((event: GestureEvent) => {
            if (!event || event.fingerList.length === 0) {
              return
            }
            this.panStartX = event.fingerList[0].globalX
            this.panStartY = event.fingerList[0].globalY
            if (this.panStartX < this.layerWidth / 2) {
              this.gestureType = this.GESTURE_BRIGHTNESS
              this.gestureStartValue = this.clampBrightness(this.screenBrightness)
              this.gestureValue = this.gestureStartValue
            } else {
              this.gestureType = this.GESTURE_VOLUME
              this.gestureStartValue = this.clamp01(this.volume)
              this.gestureValue = this.gestureStartValue
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!event || event.fingerList.length === 0) {
              return
            }
            const dy = event.fingerList[0].globalY - this.panStartY
            if (this.gestureType === this.GESTURE_VOLUME) {
              this.updateVolumeDelta(dy)
            } else if (this.gestureType === this.GESTURE_BRIGHTNESS) {
              this.updateBrightnessDelta(dy)
            }
          })
          .onActionEnd(() => {
            this.resetGestureState()
          }),

        LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
          .onAction(() => {
            this.isLongPressActive = true
            if (this.onTemporarySpeedStart) {
              this.onTemporarySpeedStart()
            }
          })
          .onActionEnd(() => {
            this.isLongPressActive = false
            if (this.onTemporarySpeedEnd) {
              this.onTemporarySpeedEnd()
            }
          }),

        TapGesture({ count: 2 })
          .onAction(() => {
            if (this.onTogglePlayPause) {
              this.onTogglePlayPause()
            }
          }),

        TapGesture({ count: 1 })
          .onAction(() => {
            if (this.onToggleControls) {
              this.onToggleControls()
            } else if (this.onShowControls) {
              this.onShowControls()
            }
          })
      )
    )
  }

  private resetGestureState(): void {
    this.gestureType = this.GESTURE_NONE
    this.seekDeltaMs = 0
    this.gestureStartValue = 0
  }

  private updateSeekDelta(dx: number): void {
    if (this.durationMs <= 0) {
      return
    }
    const seekPerPx = this.durationMs / Math.max(this.layerWidth, 1)
    this.seekDeltaMs = Math.round(dx * seekPerPx)
  }

  private updateVolumeDelta(dy: number): void {
    const delta = -dy / this.getVerticalGestureRange()
    const newVolume = this.normalizePercent(this.clamp01(this.gestureStartValue + delta))
    if (Math.abs(newVolume - this.gestureValue) < 0.001) {
      return
    }
    this.gestureValue = newVolume
    if (this.onVolumeChange) {
      this.onVolumeChange(newVolume)
    }
  }

  private updateBrightnessDelta(dy: number): void {
    const delta = -dy / this.getVerticalGestureRange()
    const newBrightness = this.normalizePercent(this.clampBrightness(this.gestureStartValue + delta))
    if (Math.abs(newBrightness - this.gestureValue) < 0.001) {
      return
    }
    this.gestureValue = newBrightness
    if (this.onBrightnessChange) {
      this.onBrightnessChange(newBrightness)
    }
  }

  private getVerticalGestureRange(): number {
    return Math.max(this.layerHeight * this.VERTICAL_GESTURE_RANGE_RATIO, 1)
  }

  private clamp01(value: number): number {
    if (value < 0) {
      return 0
    }
    if (value > 1) {
      return 1
    }
    return value
  }

  private clampBrightness(value: number): number {
    if (value < this.MIN_BRIGHTNESS) {
      return this.MIN_BRIGHTNESS
    }
    if (value > 1) {
      return 1
    }
    return value
  }

  private normalizePercent(value: number): number {
    return Math.round(value * 100) / 100
  }

  private formatTime(ms: number): string {
    if (ms < 0) {
      ms = 0
    }
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`
  }

  private formatDelta(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000)
    if (totalSeconds < 60) {
      return `${totalSeconds}秒`
    }
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}分${seconds > 0 ? seconds + '秒' : ''}`
  }
}
