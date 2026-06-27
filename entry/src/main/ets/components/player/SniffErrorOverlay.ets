@Component
export struct SniffErrorOverlay {
  @Prop status: string = 'error'
  @Prop message: string = ''
  @Prop retryCount: number = 0
  onRetry?: () => void
  onBack?: () => void

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#FF050505', 0.0], ['#FF11151B', 0.58], ['#FF050505', 1.0]]
        })

      Column() {
        Text(this.getDisplayTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .margin({ bottom: 8 })

        Text(this.getDisplayMessage())
          .fontSize(13)
          .fontColor('#BFFFFFFF')
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ bottom: 22 })

        Row() {
          Button('重试')
            .onClick(() => {
              if (this.onRetry) {
                this.onRetry()
              }
            })
            .width(112)
            .height(42)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(21)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 14, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
            .margin({ right: 12 })

          Button('返回')
            .onClick(() => {
              if (this.onBack) {
                this.onBack()
              }
            })
            .width(112)
            .height(42)
            .backgroundColor('#22FFFFFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(21)
            .border({ width: 0.5, color: '#33FFFFFF' })
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('78%')
      .padding({ left: 26, right: 26, top: 26, bottom: 24 })
      .borderRadius(24)
      .backgroundColor('#66000000')
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: '#33FFFFFF' })
      .shadow({ radius: 28, color: '#99000000', offsetY: 10 })
    }
    .width('100%')
    .height('100%')
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
