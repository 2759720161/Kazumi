@Component
export struct SniffErrorOverlay {
  @Prop status: string = 'error'
  @Prop message: string = ''
  @Prop retryCount: number = 0
  onRetry?: () => void
  onBack?: () => void

  build() {
    Column() {
      Text(this.getDisplayTitle())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .margin({ bottom: 8 })

      Text(this.getDisplayMessage())
        .fontSize(14)
        .fontColor($r('app.color.text_overlay_sub'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('80%')
        .margin({ bottom: 32 })

      Row() {
        Button('重试嗅探')
          .onClick(() => {
            if (this.onRetry) {
              this.onRetry()
            }
          })
          .width(120)
          .height(44)
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(22)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .shadow({ radius: 14, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .margin({ right: 16 })

        Button('返回详情')
          .onClick(() => {
            if (this.onBack) {
              this.onBack()
            }
          })
          .width(120)
          .height(44)
          .backgroundColor($r('app.color.surface_button_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(22)
          .border({ width: 0.5, color: $r('app.color.border_light') })
          .shadow({ radius: 14, color: $r('app.color.shadow_surface'), offsetY: 4 })
      }
      .justifyContent(FlexAlign.Center)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.tab_bar_background'))
  }

  private getDisplayTitle(): string {
    if (this.status === 'timeout') {
      return '嗅探超时'
    }
    if (this.status === 'captcha') {
      return '遇到验证码'
    }
    return '嗅探失败'
  }

  private getDisplayMessage(): string {
    if (this.message.length > 0) {
      return this.message
    }
    if (this.status === 'timeout') {
      return '未能在超时时间内找到视频流地址，请检查网络或尝试其他源'
    }
    if (this.status === 'captcha') {
      return '该播放源需要验证码验证，暂不支持自动处理'
    }
    return '未能从该页面找到可播放的视频流'
  }
}
