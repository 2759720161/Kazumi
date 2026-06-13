@Component
export struct ErrorRetry {
  @Prop message: string = '加载失败';
  onRetry?: () => void;

  build() {
    Column() {
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 12 })

      Button('重试')
        .height(40)
        .padding({ left: 22, right: 22 })
        .borderRadius(20)
        .backgroundColor($r('app.color.button_primary_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .shadow({ radius: 14, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
        .onClick(() => {
          if (this.onRetry) {
            this.onRetry();
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
