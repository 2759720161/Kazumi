import { webview } from '@kit.ArkWeb'
import { VideoSniffer } from '../core/sniffer/VideoSniffer'
import { SnifferResult } from '../core/sniffer/SnifferResult'
import { JSInjector } from '../core/sniffer/JSInjector'
import { CandidateUrlFilter } from '../core/sniffer/CandidateUrlFilter'
import { RequestInterceptor } from '../core/sniffer/RequestInterceptor'
import { TimeoutController } from '../core/sniffer/TimeoutController'

class UrlTestCase {
  url: string = ''
  expected: boolean = false
  constructor(url: string, expected: boolean) {
    this.url = url
    this.expected = expected
  }
}

@Entry
@Component
struct WebViewSnifferPocPage {
  @State testUrl: string = 'https://www.bilibili.com'
  @State sniffStatus: string = 'idle'
  @State sniffResults: SnifferResult[] = []
  @State logMessages: string[] = []
  @State currentTestIndex: number = -1
  @State jsBridgeMessages: string[] = []
  @State scriptHashValid: boolean = false
  @State filterTestResults: string[] = []
  webController: webview.WebviewController = new webview.WebviewController()
  private sniffer: VideoSniffer = new VideoSniffer()
  private maxLogLines: number = 50

  aboutToAppear(): void {
    this.sniffer.setWebController(this.webController)
    this.sniffer.setResultCallback((result: SnifferResult) => {
      this.addLog('[RESULT] ' + result.toString())
      this.sniffResults = [...this.sniffResults, result]
    })
    this.sniffer.setCompleteCallback(() => {
      this.addLog('[COMPLETE] Found ' + this.sniffResults.length + ' video URLs')
      this.sniffStatus = 'complete'
    })
    this.sniffer.setErrorCallback((error: string) => {
      this.addLog('[ERROR] ' + error)
      this.sniffStatus = 'error'
    })
    this.sniffer.setStatusCallback((status: string) => {
      this.addLog('[STATUS] ' + status)
      this.sniffStatus = status
    })
  }

  addLog(msg: string): void {
    let time = new Date().toLocaleTimeString()
    this.logMessages = ['[' + time + '] ' + msg, ...this.logMessages].slice(0, this.maxLogLines)
  }

  startSniff(): void {
    this.sniffResults = []
    this.sniffStatus = 'loading'
    this.addLog('[START] Sniffing: ' + this.testUrl)
    this.sniffer.sniff(this.testUrl)
  }

  cancelSniff(): void {
    this.sniffer.cancel()
    this.addLog('[CANCEL] Sniffing cancelled')
  }

  runFilterTests(): void {
    this.filterTestResults = []
    let filter = new CandidateUrlFilter()

    let testCases: UrlTestCase[] = [
      new UrlTestCase('https://example.com/video.m3u8', true),
      new UrlTestCase('https://example.com/video.mp4', true),
      new UrlTestCase('https://example.com/video.flv', true),
      new UrlTestCase('https://example.com/segment.ts', true),
      new UrlTestCase('https://example.com/page.html', false),
      new UrlTestCase('https://example.com/image.jpg', false),
      new UrlTestCase('data:image/png;base64,abc', false),
      new UrlTestCase('blob:https://example.com/uuid', false),
      new UrlTestCase('https://doubleclick.net/ad.m3u8', false),
      new UrlTestCase('https://example.com/1080p/index.m3u8', true),
      new UrlTestCase('https://example.com/720p/video.mp4', true),
    ]

    let passCount = 0
    for (let i = 0; i < testCases.length; i++) {
      let tc = testCases[i]
      let result = filter.filter(tc.url, 'test')
      let isVideo = result !== null
      let pass = isVideo === tc.expected
      if (pass) {
        passCount++
      }
      this.filterTestResults = [...this.filterTestResults,
        (pass ? 'PASS' : 'FAIL') + ': ' + tc.url + ' -> ' + (isVideo ? 'video' : 'filtered') + ' (expected: ' + (tc.expected ? 'video' : 'filtered') + ')']
    }
    this.filterTestResults = [...this.filterTestResults,
      '--- Total: ' + passCount + '/' + testCases.length + ' passed ---']
  }

  runJsInjectorTests(): void {
    this.scriptHashValid = JSInjector.validateScriptHash(JSInjector.getScriptHash())
    let script = JSInjector.getSnifferScript(false)
    this.addLog('[JS_TEST] Script length: ' + script.length + ' chars')
    this.addLog('[JS_TEST] Hash valid: ' + this.scriptHashValid)
    this.addLog('[JS_TEST] Contains MutationObserver: ' + (script.indexOf('MutationObserver') !== -1))
    this.addLog('[JS_TEST] Contains XMLHttpRequest: ' + (script.indexOf('XMLHttpRequest') !== -1))
    this.addLog('[JS_TEST] Contains fetch: ' + (script.indexOf('window.fetch') !== -1))
    this.addLog('[JS_TEST] Contains jsBridge: ' + (script.indexOf('jsBridge') !== -1))
    this.addLog('[JS_TEST] Contains iframe: ' + (script.indexOf('iframe') !== -1))
    this.addLog('[JS_TEST] Contains video tag: ' + (script.indexOf('video_tag') !== -1))
    this.addLog('[JS_TEST] Contains #EXTM3U: ' + (script.indexOf('#EXTM3U') !== -1))
  }

  runRequestInterceptorTests(): void {
    let interceptor = new RequestInterceptor()
    let testCases: UrlTestCase[] = [
      new UrlTestCase('https://cdn.example.com/stream/index.m3u8', true),
      new UrlTestCase('https://cdn.example.com/video.mp4', true),
      new UrlTestCase('https://cdn.example.com/video.flv', true),
      new UrlTestCase('https://cdn.example.com/segment0.ts', true),
      new UrlTestCase('https://example.com/api/data', false),
      new UrlTestCase('https://example.com/style.css', false),
    ]

    let passCount = 0
    for (let i = 0; i < testCases.length; i++) {
      let tc = testCases[i]
      let intercepted = interceptor.shouldIntercept(tc.url)
      let pass = intercepted === tc.expected
      if (pass) {
        passCount++
      }
      this.addLog('[INTERCEPT_TEST] ' + (pass ? 'PASS' : 'FAIL') + ': ' + tc.url)
    }
    this.addLog('[INTERCEPT_TEST] Total: ' + passCount + '/' + testCases.length + ' passed')
  }

  build() {
    Column() {
      Text('T0.2 WebView Sniffer POC')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      Scroll() {
        Column() {
          Row() {
            TextInput({ text: this.testUrl, placeholder: 'Enter URL to sniff' })
              .onChange((value: string) => { this.testUrl = value })
              .layoutWeight(1)
              .height(40)
            Button('Sniff')
              .onClick(() => this.startSniff())
              .enabled(this.sniffStatus !== 'loading')
              .height(40)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
              .margin({ left: 8 })
            Button('Cancel')
              .onClick(() => this.cancelSniff())
              .height(40)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
              .margin({ left: 4 })
          }
          .width('100%')
          .margin({ bottom: 8 })

          Row() {
            Text('Status: ')
              .fontSize(14)
            Text(this.sniffStatus)
              .fontSize(14)
              .fontColor(this.sniffStatus === 'found' ? Color.Green :
                         this.sniffStatus === 'timeout' ? Color.Orange :
                         this.sniffStatus === 'error' ? Color.Red : Color.Black)
          }
          .width('100%')
          .margin({ bottom: 8 })

          Text('WebView (hidden sniffer):')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ bottom: 4 })

          Web({ src: '', controller: this.webController })
            .width('100%')
            .height(200)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onInterceptRequest((event) => {
              if (event && event.request && event.request.getRequestUrl()) {
                let url = event.request.getRequestUrl()
                if (this.sniffer.getIsSniffing()) {
                  let headers: Record<string, string> = {}
                  const requestHeaders = event.request.getRequestHeader()
                  for (let i = 0; i < requestHeaders.length; i++) {
                    const header = requestHeaders[i]
                    if (header.headerKey.length > 0) {
                      headers[header.headerKey] = header.headerValue
                    }
                  }
                  this.sniffer.handleInterceptedRequest(url, headers)
                }
              }
              return null
            })
            .onPageEnd(() => {
              this.addLog('[PAGE_END] Page loaded, injecting sniffer script')
              this.sniffer.onPageEnd()
            })
            .onErrorReceive((event) => {
              if (event) {
                this.addLog('[WEB_ERROR] ' + event.error.getErrorInfo())
              }
            })
            .margin({ bottom: 8 })

          Text('Sniff Results (' + this.sniffResults.length + '):')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ bottom: 4 })

          if (this.sniffResults.length === 0) {
            Text('No results yet')
              .fontSize(12)
              .fontColor(Color.Gray)
              .width('100%')
              .margin({ bottom: 8 })
          } else {
            ForEach(this.sniffResults, (result: SnifferResult, index?: number) => {
              Row() {
                Text('[' + result.type + ']')
                  .fontSize(11)
                  .fontColor(Color.Blue)
                  .margin({ right: 4 })
                Text(result.url)
                  .fontSize(11)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(result.quality)
                  .fontSize(11)
                  .fontColor(Color.Orange)
                  .margin({ left: 4 })
              }
              .width('100%')
              .margin({ bottom: 2 })
            }, (result: SnifferResult, index?: number) => index?.toString() ?? '')
          }

          Divider().margin({ top: 8, bottom: 8 })

          Text('Unit Tests:')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ bottom: 8 })

          Button('Test 1: CandidateUrlFilter')
            .onClick(() => this.runFilterTests())
            .width('100%')
            .backgroundColor('#D9007DFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: '#4DFFFFFF' })
            .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            .margin({ bottom: 4 })

          if (this.filterTestResults.length > 0) {
            ForEach(this.filterTestResults, (result: string, index?: number) => {
              Text(result)
                .fontSize(11)
                .fontColor(result.indexOf('PASS') !== -1 ? Color.Green :
                           result.indexOf('FAIL') !== -1 ? Color.Red : Color.Black)
                .width('100%')
                .margin({ bottom: 1 })
            }, (result: string, index?: number) => index?.toString() ?? '')
          }

          Button('Test 2: JSInjector Validation')
            .onClick(() => this.runJsInjectorTests())
            .width('100%')
            .backgroundColor('#D9007DFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: '#4DFFFFFF' })
            .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            .margin({ top: 8, bottom: 4 })

          Text('Script Hash Valid: ' + this.scriptHashValid)
            .fontSize(12)
            .fontColor(this.scriptHashValid ? Color.Green : Color.Red)
            .width('100%')

          Button('Test 3: RequestInterceptor')
            .onClick(() => this.runRequestInterceptorTests())
            .width('100%')
            .backgroundColor('#D9007DFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: '#4DFFFFFF' })
            .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            .margin({ top: 8, bottom: 4 })

          Button('Test 4: TimeoutController (quick)')
            .onClick(() => {
              let tc = new TimeoutController(2000, 1)
              let retryCount = 0
              let timedOut = false
              tc.setOnRetry(() => {
                retryCount++
                this.addLog('[TIMEOUT_TEST] Retry #' + retryCount)
              })
              tc.setOnTimeout(() => {
                timedOut = true
                this.addLog('[TIMEOUT_TEST] Final timeout fired')
              })
              tc.start()
              this.addLog('[TIMEOUT_TEST] Started 2s timeout, maxRetries=1')
              setTimeout(() => {
                this.addLog('[TIMEOUT_TEST] After 5s: timedOut=' + timedOut + ', retries=' + retryCount + ' (expected: true, 1)')
              }, 5000)
            })
            .width('100%')
            .backgroundColor('#D9007DFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: '#4DFFFFFF' })
            .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            .margin({ top: 8, bottom: 4 })

          Divider().margin({ top: 8, bottom: 8 })

          Text('Log:')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(this.logMessages, (msg: string, index?: number) => {
            Text(msg)
              .fontSize(10)
              .fontColor(msg.indexOf('[ERROR]') !== -1 ? Color.Red :
                         msg.indexOf('[RESULT]') !== -1 ? Color.Green :
                         msg.indexOf('[PASS]') !== -1 ? Color.Green :
                         msg.indexOf('[FAIL]') !== -1 ? Color.Red : Color.Gray)
              .width('100%')
              .margin({ bottom: 1 })
          }, (msg: string, index?: number) => index?.toString() ?? '')
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background('#FFFFFF')
    .ignoreLayoutSafeArea()
    .padding(16)
  }
}
