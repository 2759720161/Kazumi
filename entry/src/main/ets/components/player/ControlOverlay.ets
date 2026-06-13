@Component
export struct ControlOverlay {
  @Prop isPlaying: boolean = false;
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop speed: number = 1.0;
  @Prop volume: number = 1.0;
  @Prop isVisible: boolean = true;
  @Prop hasEpisodes: boolean = false;
  @Prop bottomInset: number = 0;
  onPlayPause?: () => void;
  onSeek?: (positionMs: number) => void;
  onSpeedChange?: (speed: number) => void;
  onVolumeChange?: (volume: number) => void;
  onFullscreen?: () => void;
  onEpisodePanel?: () => void;

  build() {
    if (this.isVisible) {
      Column() {
        Row() {
          Text(this.formatTime(this.positionMs))
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))

        Slider({
          value: this.durationMs > 0 ? this.positionMs : 0,
          min: 0,
          max: this.durationMs > 0 ? this.durationMs : 1,
          step: 1000
        })
          .layoutWeight(1)
          .trackColor($r('app.color.track_slider'))
          .selectedColor($r('app.color.loading_color'))

          .onChange((value: number) => {
            if (this.onSeek) {
              this.onSeek(value);
            }
          })

          Text(this.formatTime(this.durationMs))
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 2 })

        Row() {
          Button() {
            Row() {
              if (this.isPlaying) {
                Text('暂停')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_on_primary'))
              } else {
                SymbolGlyph($r('sys.symbol.play_fill'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_on_primary')])
                Text('播放')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_on_primary'))
                  .margin({ left: 5 })
              }
            }
            .justifyContent(FlexAlign.Center)
          }
            .height(40)
            .padding({ left: 16, right: 18 })
            .borderRadius(20)
            .backgroundColor($r('app.color.border_specular'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.surface_button_bg') })
            .onClick(() => {
              if (this.onPlayPause) {
                this.onPlayPause();
              }
            })

          Text(`${this.speed}x`)
            .fontSize(12)
            .fontColor($r('app.color.text_on_primary'))
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .borderRadius(18)
            .backgroundColor($r('app.color.surface_button_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_light') })
            .margin({ left: 12 })
            .onClick(() => {
              if (this.onSpeedChange) {
                const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
                const currentIdx = speeds.indexOf(this.speed);
                const nextIdx = (currentIdx + 1) % speeds.length;
                this.onSpeedChange(speeds[nextIdx]);
              }
            })

          Blank()

          Button() {
            Text('选集')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.hasEpisodes ? $r('app.color.text_on_primary') : $r('app.color.track_slider'))
          }
            .height(40)
            .padding({ left: 16, right: 16 })
            .borderRadius(20)
            .backgroundColor(this.hasEpisodes ? $r('app.color.border_specular') : $r('app.color.border_faint'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .onClick(() => {
              if (this.hasEpisodes && this.onEpisodePanel) {
                this.onEpisodePanel();
              }
            })

          if (this.onFullscreen) {
            Button('全屏')
              .height(40)
              .padding({ left: 16, right: 16 })
              .borderRadius(20)
              .backgroundColor($r('app.color.border_specular'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: $r('app.color.border_specular') })
              .onClick(() => {
                if (this.onFullscreen) {
                  this.onFullscreen();
                }
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 0 })
      }
      .width('100%')
      .backgroundColor($r('app.color.overlay_control_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .padding({ top: 12, bottom: Math.max(10, this.bottomInset + 8) })
      .align(Alignment.Bottom)
    }
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }
}
