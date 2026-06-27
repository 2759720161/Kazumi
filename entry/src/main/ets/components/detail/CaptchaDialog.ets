import { webview } from '@kit.ArkWeb'
import { CookieManager } from '../../network/CookieManager'
import { Logger } from '../../utils/Logger'

const logger = new Logger('CaptchaDialog')

function normalizeScriptStringResult(result: Object): string {
  const raw = String(result).trim()
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    try {
      return String(JSON.parse(raw))
    } catch (e) {
    }
  }
  if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
    return raw.substring(1, raw.length - 1)
  }
  return raw
}

class CaptchaBridgeProxy {
  private onMessage: (message: string) => void

  constructor(onMessage: (message: string) => void) {
    this.onMessage = onMessage
  }

  postMessage(message: string): void {
    this.onMessage(message)
  }
}

enum CaptchaState {
  LOADING_IMAGE,
  IMAGE_READY,
  SUBMITTING,
  WAITING_DISAPPEAR,
  VERIFIED_SAVING_COOKIE,
  RETRYING_SEARCH,
  FAILED
}

@Component
export struct CaptchaDialog {
  @State private state: CaptchaState = CaptchaState.LOADING_IMAGE
  @State hasVerified: boolean = false
  @State verifyHint: string = '正在加载验证码图片...'
  @State captchaImageUrl: string = ''
  @State captchaCode: string = ''
  @Prop captchaUrl: string = ''
  @Prop captchaType: number = 1
  @Prop captchaImage: string = ''
  @Prop captchaInput: string = ''
  @Prop captchaScript: string = ''
  @Prop captchaButton: string = ''
  @Prop ruleSourceName: string = ''
  @Prop ruleSourceId: number = -1
  private webController: webview.WebviewController = new webview.WebviewController()
  private timeoutTimer: number = -1
  private pollTimer: number = -1
  private verifyTimeoutMs: number = 15000
  private captchaWasFound: boolean = false
  private pageLoaded: boolean = false
  private watcherInjected: boolean = false
  private cookiesBeforeSubmit: string = ''
  onVerified?: () => void
  onCancelled?: () => void

  aboutToAppear(): void {
    this.hasVerified = false
    this.captchaWasFound = false
    this.pageLoaded = false
    this.watcherInjected = false
    this.captchaImageUrl = ''
    this.captchaCode = ''
    this.cookiesBeforeSubmit = ''
    this.state = CaptchaState.LOADING_IMAGE
    this.verifyHint = this.captchaType === 1 ? '正在加载验证码图片...' : '请在页面中完成验证'
    logger.info('Captcha open: rule=%{public}s, type=%{public}d, url=%{public}s',
      this.ruleSourceName, this.captchaType, this.captchaUrl.substring(0, 60))
  }

  aboutToDisappear(): void {
    this.clearTimer()
    this.clearPollTimer()
    try {
      this.webController.stop()
    } catch (e) {
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.captchaType === 1) {
        this.ImageCaptchaDialog()
      } else {
        this.WebCaptchaDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ImageCaptchaDialog() {
    Column() {
      if (this.captchaUrl.length > 0) {
        Web({ src: this.captchaUrl, controller: this.webController })
          .width(1)
          .height(1)
          .opacity(0.01)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy({
            object: new CaptchaBridgeProxy((message: string) => {
              this.handleCaptchaBridgeMessage(message)
            }),
            name: 'KazumiCaptchaBridge',
            methodList: ['postMessage'],
            controller: this.webController
          })
          .onPageBegin(() => {
            this.onWebViewPageBegin()
          })
          .onPageEnd(() => {
            this.onWebViewPageEnd()
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (event && event.error) {
              logger.warn('Captcha WebView error: %{public}s', event.error.getErrorInfo())
            }
          })
      }

      Text('验证码验证')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24 })

      Text(`${this.ruleSourceName.length > 0 ? this.ruleSourceName : '当前规则'} 需要验证码验证`)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 6, bottom: 20 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.captchaImageUrl.length > 0) {
        Image(this.captchaImageUrl)
          .width('82%')
          .height(96)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(6)
          .margin({ bottom: 16 })
      } else {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.text_secondary'))
          Text(this.captchaUrl.length > 0 ? this.verifyHint : '验证码页面地址无效')
            .fontSize(13)
            .fontColor(this.captchaUrl.length > 0 ? $r('app.color.text_secondary') : $r('app.color.text_error'))
            .margin({ top: 10 })
        }
        .width('82%')
        .height(96)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(6)
        .margin({ bottom: 16 })
      }

      TextInput({ placeholder: '请输入验证码', text: this.captchaCode })
        .width('82%')
        .height(54)
        .fontSize(16)
        .enabled(this.state === CaptchaState.IMAGE_READY)
        .onChange((value: string) => {
          this.captchaCode = value
        })

      Text(this.verifyHint)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('82%')
        .margin({ top: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Button('取消')
          .fontSize(15)
          .height(42)
          .backgroundColor($r('app.color.button_neutral_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .margin({ right: 16 })
          .onClick(() => {
            this.handleCancel()
          })

        Button(this.state === CaptchaState.SUBMITTING ? '提交中' : '提交')
          .fontSize(15)
          .height(42)
          .backgroundColor($r('app.color.button_accent_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .enabled(this.state === CaptchaState.IMAGE_READY)
          .onClick(() => {
            this.submitImageCaptcha()
          })
      }
      .justifyContent(FlexAlign.End)
      .width('82%')
      .margin({ top: 20, bottom: 24 })
    }
    .width('78%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(24)
    .shadow({ radius: 18, color: $r('app.color.overlay_topbar_bg'), offsetY: 6 })
  }

  @Builder
  private WebCaptchaDialog() {
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
      Text(this.verifyHint)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('94%')
    .height('78%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(8)
    .shadow({ radius: 18, color: $r('app.color.overlay_topbar_bg'), offsetY: 6 })
  }

  private onWebViewPageBegin(): void {
    if (this.captchaType !== 1 || this.captchaImage.length === 0) {
      return
    }
    logger.info('Captcha onPageBegin: injecting watcher (main path)')
    this.injectCaptchaWatcher()
  }

  private onWebViewPageEnd(): void {
    this.pageLoaded = true
    if (this.captchaType === 1) {
      if (!this.watcherInjected && this.captchaImage.length > 0 && !this.hasVerified) {
        logger.info('Captcha onPageEnd: watcher not yet injected, injecting as fallback')
        this.injectCaptchaWatcher()
      }
      if (this.captchaImageUrl.length === 0 && !this.hasVerified) {
        this.extractCaptchaImage()
      }
      this.scheduleCaptchaCheck(500)
      return
    }
    if (this.isVerifying()) {
      return
    }
    if (this.captchaType === 2 && this.captchaButton.length > 0) {
      this.verifyHint = '正在自动点击验证按钮'
      const script = this.buildClickXPathScript(this.captchaButton)
      this.webController.runJavaScript(script, (err, result) => {
        if (err) {
          logger.warn('Captcha auto-click failed')
        } else {
          logger.info('Captcha auto-click result: %{public}s', String(result))
        }
        this.startAutoVerifyTimeout()
        this.scheduleCaptchaCheck(500)
      })
    } else if (this.captchaType === 3 && this.captchaScript.length > 0) {
      this.verifyHint = '正在执行验证脚本'
      this.webController.runJavaScript(this.captchaScript, (err, result) => {
        if (err) {
          logger.warn('Captcha custom script failed')
        } else {
          logger.info('Captcha custom script result: %{public}s', String(result))
        }
        if (this.isTruthyScriptResult(result)) {
          this.handleVerified()
        } else {
          this.startAutoVerifyTimeout()
          this.scheduleCaptchaCheck(500)
        }
      })
    } else {
      this.verifyHint = '请完成验证码，验证通过后会自动继续'
      this.scheduleCaptchaCheck(500)
    }
  }

  private isVerifying(): boolean {
    return this.state === CaptchaState.SUBMITTING || this.state === CaptchaState.WAITING_DISAPPEAR
  }

  private injectCaptchaWatcher(): void {
    if (this.hasVerified || this.captchaType !== 1 || this.captchaImage.length === 0) {
      return
    }
    const script = this.buildCaptchaWatcherScript(this.captchaImage, this.captchaInput)
    this.webController.runJavaScript(script, (err, result) => {
      if (err) {
        logger.warn('Captcha watcher inject failed: %{public}s', String(err))
        this.watcherInjected = false
        return
      }
      const status = String(result)
      logger.info('Captcha watcher inject: result=%{public}s', status)
      if (status === 'started' || status === 'polling' || status === 'image-captured') {
        this.watcherInjected = true
      } else if (status === 'dom-not-ready') {
        logger.info('Captcha watcher: DOM not ready, will retry')
        this.watcherInjected = false
        setTimeout(() => {
          this.injectCaptchaWatcher()
        }, 200)
      } else if (status === 'already') {
        this.watcherInjected = true
      }
    })
  }

  private handleCaptchaBridgeMessage(message: string): void {
    if (this.hasVerified || message.length === 0) {
      return
    }
    logger.debug('Captcha bridge: %{public}s', message.substring(0, 60))
    if (message.startsWith('image:')) {
      const imageUrl = message.substring(6)
      if (imageUrl.startsWith('data:image')) {
        this.captchaImageUrl = imageUrl
        this.captchaWasFound = true
        this.pageLoaded = true
        this.state = CaptchaState.IMAGE_READY
        this.verifyHint = '请输入验证码'
        logger.info('Captcha image shown: length=%{public}d', imageUrl.length)
      }
      return
    }
    if (message === 'status:present') {
      this.captchaWasFound = true
      this.pageLoaded = true
      if (this.captchaImageUrl.length === 0) {
        this.verifyHint = '已检测到验证码，正在读取图片'
      }
      logger.info('Captcha bridge: status=present')
      return
    }
    if (message === 'status:absent') {
      if (this.captchaWasFound) {
        logger.info('Captcha disappeared: source=bridge')
        this.handleVerified()
      } else {
        logger.info('Captcha bridge: status=absent (not yet found)')
      }
      return
    }
    if (message.startsWith('log:')) {
      logger.debug('Captcha JS: %{public}s', message.substring(4))
    }
  }

  private handleVerified(): void {
    if (this.hasVerified) {
      return
    }
    this.hasVerified = true
    this.state = CaptchaState.VERIFIED_SAVING_COOKIE
    this.clearTimer()
    this.clearPollTimer()
    this.verifyHint = '验证通过，正在保存 Cookie'
    logger.info('Captcha verified, saving cookies')
    this.syncCookies(() => {
      if (this.onVerified) {
        this.onVerified()
      }
    })
  }

  private extractCaptchaImage(): void {
    if (this.captchaImage.length === 0 || this.hasVerified) {
      return
    }
    this.webController.runJavaScript(this.buildCaptureCaptchaImageScript(this.captchaImage, this.captchaInput), (err, result) => {
      if (this.hasVerified) {
        return
      }
      if (err) {
        logger.warn('Captcha image capture failed')
        return
      }
      const imageUrl = normalizeScriptStringResult(result)
      if (imageUrl.startsWith('data:image')) {
        this.captchaImageUrl = imageUrl
        this.captchaWasFound = true
        this.state = CaptchaState.IMAGE_READY
        this.verifyHint = '请输入验证码'
        logger.info('Captcha image capture OK: length=%{public}d', imageUrl.length)
        return
      }
      if (imageUrl.indexOf('missing') !== -1) {
        this.verifyHint = '未检测到验证码图片，可能已通过验证'
        return
      }
      logger.warn('Captcha image capture returned: %{public}s', imageUrl.substring(0, 60))
    })
  }

  private async submitImageCaptcha(): Promise<void> {
    if (this.state !== CaptchaState.IMAGE_READY || this.hasVerified) {
      return
    }
    const code = this.captchaCode.trim()
    if (code.length === 0) {
      this.verifyHint = '请输入验证码'
      return
    }
    if (this.captchaInput.length === 0 || this.captchaButton.length === 0) {
      this.verifyHint = '验证码输入框或提交按钮规则为空'
      return
    }

    this.state = CaptchaState.SUBMITTING
    this.verifyHint = '正在提交验证码'
    this.saveCurrentCookies()
    this.webController.runJavaScript(this.buildSubmitCaptchaScript(code, this.captchaInput, this.captchaButton), (err, result) => {
      if (this.hasVerified) {
        return
      }
      if (err) {
        logger.warn('Captcha submit failed')
        this.state = CaptchaState.IMAGE_READY
        this.verifyHint = '提交失败，请重试'
        return
      }

      const status = normalizeScriptStringResult(result)
      logger.info('Captcha submit: inputXpath=%{public}s, buttonXpath=%{public}s, result=%{public}s',
        this.captchaInput.length > 0 ? 'ok' : 'empty', this.captchaButton.length > 0 ? 'ok' : 'empty', status)
      if (status.indexOf('missing-input') !== -1) {
        this.state = CaptchaState.IMAGE_READY
        this.verifyHint = '未找到验证码输入框'
        return
      }
      if (status.indexOf('missing-button') !== -1) {
        this.state = CaptchaState.IMAGE_READY
        this.verifyHint = '未找到验证码提交按钮'
        return
      }
      if (status.indexOf('error') !== -1) {
        this.state = CaptchaState.IMAGE_READY
        this.verifyHint = '验证码提交脚本执行失败'
        return
      }

      this.state = CaptchaState.WAITING_DISAPPEAR
      this.verifyHint = '已提交验证码，等待验证结果'
      this.startAutoVerifyTimeout()
      this.scheduleCaptchaCheck(300)
    })
  }

  private saveCurrentCookies(): void {
    if (this.captchaUrl.length === 0) {
      return
    }
    try {
      this.cookiesBeforeSubmit = CookieManager.getInstance().getCookieHeaderForUrl(this.captchaUrl, this.ruleSourceId)
    } catch (e) {
      this.cookiesBeforeSubmit = ''
    }
  }

  private handleCancel(): void {
    this.clearTimer()
    this.clearPollTimer()
    const hadCookie = this.hasNewCookies()
    this.syncCookies(() => {
      if (hadCookie && this.onVerified) {
        logger.info('Captcha cancel but has new cookies, retrying as verified')
        this.onVerified()
        return
      }
      if (this.onCancelled) {
        this.onCancelled()
      }
    })
  }

  private hasNewCookies(): boolean {
    if (this.captchaUrl.length === 0) {
      return false
    }
    try {
      const current = CookieManager.getInstance().getCookieHeaderForUrl(this.captchaUrl, this.ruleSourceId)
      if (current.length > 0 && this.cookiesBeforeSubmit.length === 0) {
        return true
      }
      if (current.length > this.cookiesBeforeSubmit.length + 5) {
        return true
      }
    } catch (e) {
    }
    return false
  }

  private syncCookies(done: () => void): void {
    if (this.captchaUrl.length === 0) {
      done()
      return
    }
    try {
      CookieManager.getInstance().syncFromWebView(this.captchaUrl)
      this.webController.runJavaScript('document.cookie', (err, result) => {
        if (!err && typeof result === 'string' && result.length > 0) {
          const cookieStr = normalizeScriptStringResult(result)
          CookieManager.getInstance().extractCookiesFromCookieHeader(this.captchaUrl, cookieStr, this.ruleSourceId)
          logger.info('Captcha cookies saved: domain=%{public}s, length=%{public}d',
            this.captchaUrl.substring(0, 40), cookieStr.length)
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

  private clearPollTimer(): void {
    if (this.pollTimer !== -1) {
      clearTimeout(this.pollTimer)
      this.pollTimer = -1
    }
  }

  private startAutoVerifyTimeout(): void {
    this.clearTimer()
    this.timeoutTimer = setTimeout(() => {
      logger.warn('Captcha auto verification timed out')
      this.timeoutTimer = -1
      if (this.hasNewCookies()) {
        logger.info('Captcha timeout but has new cookies, treating as verified')
        this.handleVerified()
        return
      }
      this.state = CaptchaState.FAILED
      this.verifyHint = '未检测到验证完成，请手动确认或重试'
    }, this.verifyTimeoutMs)
  }

  private scheduleCaptchaCheck(delayMs: number = 500): void {
    this.clearPollTimer()
    if (this.hasVerified || !this.pageLoaded) {
      return
    }
    this.pollTimer = setTimeout(() => {
      this.pollTimer = -1
      this.checkCaptchaStatus()
    }, delayMs)
  }

  private checkCaptchaStatus(): void {
    if (this.hasVerified) {
      return
    }
    const xpath = this.captchaImage.length > 0 ? this.captchaImage : this.captchaButton
    if (xpath.length === 0) {
      this.scheduleCaptchaCheck(1000)
      return
    }

    this.webController.runJavaScript(this.buildXPathPresenceScript(xpath), (err, result) => {
      if (this.hasVerified) {
        return
      }
      if (err) {
        logger.warn('Captcha status check failed')
        this.scheduleCaptchaCheck(1000)
        return
      }

      const status = normalizeScriptStringResult(result)
      if (status.indexOf('present') !== -1) {
        this.captchaWasFound = true
        this.verifyHint = '已检测到验证码，请完成验证'
        this.scheduleCaptchaCheck(700)
        return
      }

      if (status.indexOf('absent') !== -1 && this.captchaWasFound) {
        logger.info('Captcha disappeared: source=poll')
        this.handleVerified()
        return
      }

      this.scheduleCaptchaCheck(700)
    })
  }

  private buildXPathPresenceScript(xpath: string): string {
    const escaped = this.escapeForSingleQuote(xpath)
    return `(function(){try{var r=document.evaluate('${escaped}',document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null);return r.singleNodeValue?'present':'absent';}catch(e){return 'error';}})();`
  }

  private buildClickXPathScript(xpath: string): string {
    const escaped = this.escapeForSingleQuote(xpath)
    return `(function(){try{var r=document.evaluate('${escaped}',document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null);var el=r.singleNodeValue;if(el){el.click();return 'clicked';}return 'missing';}catch(e){return 'error';}})();`
  }

  private buildCaptureCaptchaImageScript(imageXpath: string, inputXpath: string): string {
    const escapedImage = this.escapeForSingleQuote(imageXpath)
    const escapedInput = this.escapeForSingleQuote(inputXpath)
    return `(function(){try{function evalXpath(xpath){try{var r=document.evaluate(xpath,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null);return r.singleNodeValue;}catch(e){return null;}}var inputXpath='${escapedInput}';if(inputXpath){var inputEl=evalXpath(inputXpath);if(inputEl){try{inputEl.focus();}catch(e){}}}var img=evalXpath('${escapedImage}');if(!img){return 'missing';}var canvas=document.createElement('canvas');canvas.width=img.naturalWidth||img.width||120;canvas.height=img.naturalHeight||img.height||48;var ctx=canvas.getContext('2d');ctx.drawImage(img,0,0);return canvas.toDataURL('image/png');}catch(e){return 'error:'+((e&&e.message)?e.message:e);}})();`
  }

  private buildCaptchaWatcherScript(imageXpath: string, inputXpath: string): string {
    const escapedImage = this.escapeForSingleQuote(imageXpath)
    const escapedInput = this.escapeForSingleQuote(inputXpath)
    return `(function(){
try {
  if (window.__kazumiCaptchaWatcherStarted) return 'already';
  var root = document.documentElement || document.body;
  if (!root) return 'dom-not-ready';
  window.__kazumiCaptchaWatcherStarted = true;
  var captchaXpath = '${escapedImage}';
  var inputXpath = '${escapedInput}';
  var _disappearObserver = null;
  function post(msg) {
    try { window.KazumiCaptchaBridge.postMessage(msg); } catch(e) {}
  }
  function evalXpath(xpath) {
    try {
      var r = document.evaluate(xpath, document, null,
        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
      return r.singleNodeValue;
    } catch(e) { return null; }
  }
  function focusInput() {
    if (!inputXpath) return;
    var inputEl = evalXpath(inputXpath);
    if (inputEl) {
      try { inputEl.focus(); } catch(e) {}
    }
  }
  function capture(img) {
    function done() {
      try {
        var canvas = document.createElement('canvas');
        canvas.width = img.naturalWidth || img.width || 120;
        canvas.height = img.naturalHeight || img.height || 48;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);
        var dataUrl = canvas.toDataURL('image/png');
        if (dataUrl) {
          post('image:' + dataUrl);
        }
      } catch(e) {
        post('log:capture-failed:' + (e && e.message ? e.message : e));
      }
    }
    if (img.complete && img.naturalWidth > 0) {
      done();
    } else {
      img.addEventListener('load', done, { once: true });
    }
  }
  function startDisappearMonitor() {
    if (_disappearObserver) return;
    _disappearObserver = new MutationObserver(function() {
      var node = evalXpath(captchaXpath);
      if (!node) {
        _disappearObserver.disconnect();
        _disappearObserver = null;
        post('status:absent');
      }
    });
    var observeRoot = document.documentElement || document.body;
    if (observeRoot) {
      _disappearObserver.observe(observeRoot, {
        childList: true, subtree: true, attributes: true
      });
    }
  }
  function checkForCaptcha() {
    focusInput();
    var img = evalXpath(captchaXpath);
    if (img) {
      post('status:present');
      capture(img);
      startDisappearMonitor();
      return true;
    }
    return false;
  }
  if (checkForCaptcha()) {
    return 'image-captured';
  }
  var pollCount = 0;
  var _captchaPoller = setInterval(function() {
    pollCount++;
    if (checkForCaptcha()) {
      clearInterval(_captchaPoller);
      _captchaPoller = null;
      return;
    }
    if (pollCount >= 60) {
      clearInterval(_captchaPoller);
      _captchaPoller = null;
      post('log:poll-timeout');
    }
  }, 500);
  window.addEventListener('DOMContentLoaded', function() {
    post('log:dom-ready');
    checkForCaptcha();
  });
  return 'polling';
} catch(e) {
  return 'error:' + ((e && e.message) ? e.message : e);
}
})();`
  }

  private buildSubmitCaptchaScript(code: string, inputXpath: string, buttonXpath: string): string {
    const escapedCode = this.escapeForSingleQuote(code)
    const escapedInput = this.escapeForSingleQuote(inputXpath)
    const escapedButton = this.escapeForSingleQuote(buttonXpath)
    return `(function(){try{function evalXpath(xpath){try{var r=document.evaluate(xpath,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null);return r.singleNodeValue;}catch(e){return null;}}var inputEl=evalXpath('${escapedInput}');if(!inputEl){return 'missing-input';}inputEl.focus();var descriptor=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value')||Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value');if(descriptor&&descriptor.set){descriptor.set.call(inputEl,'${escapedCode}');}else{inputEl.value='${escapedCode}';}inputEl.dispatchEvent(new Event('input',{bubbles:true}));inputEl.dispatchEvent(new Event('change',{bubbles:true}));var btnEl=evalXpath('${escapedButton}');if(!btnEl){return 'missing-button';}btnEl.click();return 'submitted';}catch(e){return 'error:'+((e&&e.message)?e.message:e);}})();`
  }

  private isTruthyScriptResult(result: Object): boolean {
    const text = normalizeScriptStringResult(result).toLowerCase()
    return text === 'true' || text.indexOf('done') !== -1 || text.indexOf('verified') !== -1
  }

  private escapeForSingleQuote(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
  }
}
