@Component
export struct SpeedPicker {
  @Prop currentSpeed: number = 1.0;
  private speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  private onSpeedSelected?: (speed: number) => void;

  build() {
    Row() {
      ForEach(this.speeds, (speed: number) => {
        Button(`${speed}x`)
          .height(36)
          .fontSize(13)
          .margin({ right: 8 })
          .backgroundColor(speed === this.currentSpeed ? $r('app.color.button_primary_bg') : $r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: speed === this.currentSpeed ? $r('app.color.border_specular') : $r('app.color.border_subtle') })
          .shadow({
            radius: speed === this.currentSpeed ? 12 : 6,
            color: speed === this.currentSpeed ? $r('app.color.shadow_button_primary') : $r('app.color.shadow_light'),
            offsetY: speed === this.currentSpeed ? 4 : 2
          })
          .fontColor(speed === this.currentSpeed ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
          .onClick(() => {
            if (this.onSpeedSelected) {
              this.onSpeedSelected(speed);
            }
          })
      }, (speed: number) => `speed_${speed}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}
