import { webview } from '@kit.ArkWeb'
import { SnifferResult } from './SnifferResult'
import { RequestInterceptor } from './RequestInterceptor'
import { JSInjector } from './JSInjector'
import { CandidateUrlFilter } from './CandidateUrlFilter'
import { TimeoutController } from './TimeoutController'

export class VideoSniffer {
  private requestInterceptor: RequestInterceptor = new RequestInterceptor()
  private urlFilter: CandidateUrlFilter = new CandidateUrlFilter()
  private timeoutController: TimeoutController = new TimeoutController(15000, 2)
  private results: SnifferResult[] = []
  private isSniffing: boolean = false
  private webController: webview.WebviewController | null = null
  private onResult: ((result: SnifferResult) => void) | null = null
  private onComplete: ((results: SnifferResult[]) => void) | null = null
  private onError: ((error: string) => void) | null = null
  private onStatusChange: ((status: string) => void) | null = null
  private useLegacyParser: boolean = false
  private delayedFinishTimer: number = -1
  private readonly weakCandidateDelayMs: number = 1200

  setResultCallback(callback: (result: SnifferResult) => void): void {
    this.onResult = callback
  }

  setCompleteCallback(callback: (results: SnifferResult[]) => void): void {
    this.onComplete = callback
  }

  setErrorCallback(callback: (error: string) => void): void {
    this.onError = callback
  }

  setStatusCallback(callback: (status: string) => void): void {
    this.onStatusChange = callback
  }

  setWebController(controller: webview.WebviewController): void {
    this.webController = controller
  }

  setSniffStrategy(useLegacy: boolean): void {
    this.useLegacyParser = useLegacy
  }

  setTimeout(timeoutMs: number, maxRetry: number): void {
    this.timeoutController = new TimeoutController(timeoutMs, maxRetry)
  }

  sniff(url: string): void {
    if (this.isSniffing) {
      return
    }
    this.isSniffing = true
    this.results = []
    this.clearDelayedFinish()
    this.requestInterceptor.reset()
    this.urlFilter.reset()

    if (this.onStatusChange) {
      this.onStatusChange('loading')
    }

    this.requestInterceptor.setOnIntercept((interceptedUrl: string, type: string) => {
      this.handleInterceptedUrl(interceptedUrl, type, 'request_intercept')
    })

    this.timeoutController.setOnRetry(() => {
      if (this.onStatusChange) {
        this.onStatusChange('retrying (attempt ' + this.timeoutController.getAttemptCount() + ')')
      }
    })

    this.timeoutController.setOnTimeout(() => {
      this.stopAndClearWebView()
      this.finishSniffing('timeout')
    })

    this.timeoutController.start()

    if (this.webController) {
      try {
        this.webController.loadUrl(url)
      } catch (e) {
        if (this.onError) {
          this.onError('Failed to load URL: ' + e)
        }
        this.cancel()
      }
    }
  }

  onPageEnd(): void {
    if (!this.webController) {
      return
    }
    let script = JSInjector.getSnifferScript(this.useLegacyParser)
    try {
      this.webController.runJavaScript(script, (err, result) => {
        if (err) {
          return
        }
      })
    } catch (e) {
    }
  }

  handleInterceptedUrl(url: string, type: string, source: string): void {
    let result = this.urlFilter.filter(url, source)
    this.recordResult(result)
  }

  handleJsBridgeMessage(message: string): void {
    try {
      let data = JSON.parse(message) as Record<string, string>
      let url = data['url'] || ''
      let type = data['type'] || ''
      let source = data['source'] || ''
      if (url) {
        let result = this.urlFilter.filter(url, source)
        this.recordResult(result)
      }
    } catch (e) {
    }
  }

  private recordResult(result: SnifferResult | null): void {
    if (result === null || !this.isSniffing) {
      return
    }
    this.results.push(result)
    if (this.onResult) {
      this.onResult(result)
    }
    if (result.type !== 'm3u8' && result.type !== 'mp4') {
      return
    }
    if (this.isWeakWrapperCandidate(result)) {
      this.scheduleDelayedFinish()
      return
    }
    this.finishSniffing('found')
  }

  private isWeakWrapperCandidate(result: SnifferResult): boolean {
    const lowerUrl = result.url.toLowerCase()
    return lowerUrl.indexOf('/m3u8/?url=') !== -1 ||
      lowerUrl.indexOf('/m3u8?url=') !== -1 ||
      lowerUrl.indexOf('://jx.') !== -1 ||
      lowerUrl.indexOf('//jx.') !== -1
  }

  private scheduleDelayedFinish(): void {
    if (this.delayedFinishTimer >= 0) {
      return
    }
    this.delayedFinishTimer = setTimeout(() => {
      this.delayedFinishTimer = -1
      if (this.isSniffing) {
        this.finishSniffing('found')
      }
    }, this.weakCandidateDelayMs)
  }

  private clearDelayedFinish(): void {
    if (this.delayedFinishTimer >= 0) {
      clearTimeout(this.delayedFinishTimer)
      this.delayedFinishTimer = -1
    }
  }

  private finishSniffing(reason: string): void {
    this.clearDelayedFinish()
    this.isSniffing = false
    this.timeoutController.cancel()
    if (reason === 'found') {
      this.stopAndClearWebView()
    }
    if (this.onStatusChange) {
      this.onStatusChange(reason === 'found' ? 'found' : (reason === 'timeout' ? 'timeout' : 'done'))
    }
    if (this.onComplete) {
      this.onComplete(this.results)
    }
  }

  cancel(): void {
    this.isSniffing = false
    this.clearDelayedFinish()
    this.timeoutController.cancel()
    this.stopAndClearWebView()
    if (this.onStatusChange) {
      this.onStatusChange('cancelled')
    }
  }

  private stopAndClearWebView(): void {
    if (this.webController) {
      try {
        this.webController.loadUrl('about:blank')
      } catch (e) {
      }
      try {
        this.webController.stop()
      } catch (e) {
      }
    }
  }

  getResults(): SnifferResult[] {
    return this.results.slice()
  }

  getIsSniffing(): boolean {
    return this.isSniffing
  }
}
