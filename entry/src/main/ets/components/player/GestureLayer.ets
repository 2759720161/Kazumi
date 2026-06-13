@Component
export struct GestureLayer {
  @Prop durationMs: number = 0
  @Prop positionMs: number = 0
  @Prop volume: number = 1.0
  @Prop screenBrightness: number = 0.5
  @Prop isPlaying: boolean = false
  @State gestureType: number = 0
  @State gestureValue: number = 0
  @State seekDeltaMs: number = 0
  onSeek?: (positionMs: number) => void
  onVolumeChange?: (volume: number) => void
  onBrightnessChange?: (brightness: number) => void
  onTogglePlayPause?: () => void
  onShowControls?: () => void

  private readonly GESTURE_NONE: number = 0
  private readonly GESTURE_SEEK: number = 1
  private readonly GESTURE_VOLUME: number = 2
  private readonly GESTURE_BRIGHTNESS: number = 3
  private startX: number = 0
  private startY: number = 0
  private lastTapTimeMs: number = 0
  private readonly DOUBLE_TAP_INTERVAL: number = 300

  build() {
    Column() {
      if (this.gestureType === this.GESTURE_SEEK) {
        this.SeekIndicator()
      } else if (this.gestureType === this.GESTURE_VOLUME) {
        this.VolumeIndicator()
      } else if (this.gestureType === this.GESTURE_BRIGHTNESS) {
        this.BrightnessIndicator()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event)
    })
  }

  @Builder
  private SeekIndicator() {
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
  }

  @Builder
  private VolumeIndicator() {
    Column() {
      Text('音量')
        .fontSize(12)
        .fontColor($r('app.color.text_on_primary'))

      Progress({ value: this.gestureValue * 100, type: ProgressType.Linear })
        .width(120)
        .color($r('app.color.accent_green_light'))
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

  @Builder
  private BrightnessIndicator() {
    Column() {
      Text('亮度')
        .fontSize(12)
        .fontColor($r('app.color.text_on_primary'))

      Progress({ value: this.gestureValue * 100, type: ProgressType.Linear })
        .width(120)
        .color($r('app.color.accent_green_light'))
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

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return
    }
    const touch = event.touches[0]
    if (event.type === TouchType.Down) {
      this.startX = touch.x
      this.startY = touch.y
      this.gestureType = this.GESTURE_NONE
      this.checkDoubleTap()
    } else if (event.type === TouchType.Move) {
      const dx = touch.x - this.startX
      const dy = touch.y - this.startY
      if (this.gestureType === this.GESTURE_NONE) {
        if (Math.abs(dx) > 20 || Math.abs(dy) > 20) {
          if (Math.abs(dx) > Math.abs(dy)) {
            this.gestureType = this.GESTURE_SEEK
          } else {
            const windowWidth = 360
            if (this.startX < windowWidth / 2) {
              this.gestureType = this.GESTURE_BRIGHTNESS
              this.gestureValue = this.screenBrightness
            } else {
              this.gestureType = this.GESTURE_VOLUME
              this.gestureValue = this.volume
            }
          }
        }
      }
      if (this.gestureType === this.GESTURE_SEEK) {
        this.updateSeekDelta(dx)
      } else if (this.gestureType === this.GESTURE_VOLUME) {
        this.updateVolumeDelta(dy)
      } else if (this.gestureType === this.GESTURE_BRIGHTNESS) {
        this.updateBrightnessDelta(dy)
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.gestureType === this.GESTURE_SEEK && this.seekDeltaMs !== 0) {
        if (this.onSeek) {
          const targetMs = Math.max(0, Math.min(this.durationMs, this.positionMs + this.seekDeltaMs))
          this.onSeek(targetMs)
        }
      }
      this.gestureType = this.GESTURE_NONE
      this.seekDeltaMs = 0
    }
  }

  private checkDoubleTap(): void {
    const now = Date.now()
    if (now - this.lastTapTimeMs < this.DOUBLE_TAP_INTERVAL) {
      if (this.onTogglePlayPause) {
        this.onTogglePlayPause()
      }
      this.lastTapTimeMs = 0
    } else {
      this.lastTapTimeMs = now
    }
  }

  private updateSeekDelta(dx: number): void {
    if (this.durationMs <= 0) {
      return
    }
    const windowWidth = 360
    const seekPerPx = this.durationMs / windowWidth
    this.seekDeltaMs = Math.round(dx * seekPerPx)
  }

  private updateVolumeDelta(dy: number): void {
    const windowHeight = 640
    const delta = -dy / windowHeight
    let newVolume = this.volume + delta
    if (newVolume < 0) {
      newVolume = 0
    }
    if (newVolume > 1) {
      newVolume = 1
    }
    this.gestureValue = newVolume
    if (this.onVolumeChange) {
      this.onVolumeChange(newVolume)
    }
  }

  private updateBrightnessDelta(dy: number): void {
    const windowHeight = 640
    const delta = -dy / windowHeight
    let newBrightness = this.screenBrightness + delta
    if (newBrightness < 0.01) {
      newBrightness = 0.01
    }
    if (newBrightness > 1) {
      newBrightness = 1
    }
    this.gestureValue = newBrightness
    if (this.onBrightnessChange) {
      this.onBrightnessChange(newBrightness)
    }
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
