import { webview } from '@kit.ArkWeb'
import { CookieManager } from '../../network/CookieManager'
import { Logger } from '../../utils/Logger'

const logger = new Logger('CaptchaDialog')

@Component
export struct CaptchaDialog {
  @State isVerifying: boolean = false
  @Prop captchaUrl: string = ''
  @Prop captchaType: number = 1
  @Prop captchaScript: string = ''
  @Prop captchaButton: string = ''
  @Prop ruleSourceName: string = ''
  private webController: webview.WebviewController = new webview.WebviewController()
  private timeoutTimer: number = -1
  private verifyTimeoutMs: number = 8000
  onVerified?: () => void
  onCancelled?: () => void

  aboutToAppear(): void {
    this.timeoutTimer = setTimeout(() => {
      this.handleTimeout()
    }, this.verifyTimeoutMs)
  }

  aboutToDisappear(): void {
    this.clearTimer()
    try {
      this.webController.stop()
    } catch (e) {
    }
  }

  build() {
    Column() {
      Row() {
        Text(this.ruleSourceName.length > 0 ? `${this.ruleSourceName} 验证` : '验证码验证')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button('完成')
          .fontSize(13)
          .height(32)
          .backgroundColor($r('app.color.button_info_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => {
            this.handleVerified()
          })

        Button('取消')
          .fontSize(13)
          .height(32)
          .backgroundColor($r('app.color.button_neutral_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(16)
          .onClick(() => {
            this.handleCancel()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.captchaUrl.length > 0) {
        Web({ src: this.captchaUrl, controller: this.webController })
          .width('100%')
          .layoutWeight(1)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageEnd(() => {
            this.onWebViewPageEnd()
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (event && event.error) {
              logger.warn('Captcha WebView error: %{public}s', event.error.getErrorInfo())
            }
          })
      } else {
        Column() {
          Text('验证码页面地址无效')
            .fontSize(14)
            .fontColor($r('app.color.text_error'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('94%')
    .height('78%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(8)
    .shadow({ radius: 18, color: $r('app.color.overlay_topbar_bg'), offsetY: 6 })
  }

  private onWebViewPageEnd(): void {
    if (this.isVerifying) {
      return
    }
    this.isVerifying = true

    if (this.captchaType === 2 && this.captchaButton.length > 0) {
      const script = `var el=document.querySelector('${this.escapeForSingleQuote(this.captchaButton)}'); if(el){el.click(); 'clicked';} else {'missing';}`
      this.webController.runJavaScript(script, (err, result) => {
        if (err) {
          logger.warn('Captcha auto-click failed')
        } else {
          logger.info('Captcha auto-click result: %{public}s', String(result))
        }
        this.isVerifying = false
      })
    } else if (this.captchaType === 3 && this.captchaScript.length > 0) {
      this.webController.runJavaScript(this.captchaScript, (err, result) => {
        if (err) {
          logger.warn('Captcha custom script failed')
        } else {
          logger.info('Captcha custom script result: %{public}s', String(result))
        }
        this.isVerifying = false
      })
    } else {
      this.isVerifying = false
    }
  }

  private handleVerified(): void {
    this.clearTimer()
    this.syncCookies(() => {
      if (this.onVerified) {
        this.onVerified()
      }
    })
  }

  private handleCancel(): void {
    this.clearTimer()
    this.syncCookies(() => {
      if (this.onCancelled) {
        this.onCancelled()
      }
    })
  }

  private handleTimeout(): void {
    this.clearTimer()
    if (this.onCancelled) {
      this.onCancelled()
    }
  }

  private syncCookies(done: () => void): void {
    if (this.captchaUrl.length === 0) {
      done()
      return
    }
    try {
      this.webController.runJavaScript('document.cookie', (err, result) => {
        if (!err && typeof result === 'string' && result.length > 0) {
          CookieManager.getInstance().extractCookiesFromCookieHeader(this.captchaUrl, result)
        }
        done()
      })
    } catch (e) {
      done()
    }
  }

  private clearTimer(): void {
    if (this.timeoutTimer !== -1) {
      clearTimeout(this.timeoutTimer)
      this.timeoutTimer = -1
    }
  }

  private escapeForSingleQuote(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
  }
}
