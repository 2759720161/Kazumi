import { webview } from '@kit.ArkWeb'
import { SnifferResult } from './SnifferResult'
import { CapturedRequestContext } from './CapturedRequestContext'
import { RequestInterceptor } from './RequestInterceptor'
import { JSInjector } from './JSInjector'
import { CandidateUrlFilter } from './CandidateUrlFilter'
import { TimeoutController } from './TimeoutController'
import { Logger } from '../../utils/Logger'

const logger = new Logger('VideoSniffer')

export class VideoSniffer {
  private requestInterceptor: RequestInterceptor = new RequestInterceptor()
  private urlFilter: CandidateUrlFilter = new CandidateUrlFilter()
  private timeoutController: TimeoutController = new TimeoutController(15000, 2)
  private results: SnifferResult[] = []
  private sniffSessionId: number = 0
  private isSniffing: boolean = false
  private webController: webview.WebviewController | null = null
  private onResult: ((result: SnifferResult) => void) | null = null
  private onComplete: ((results: SnifferResult[]) => void) | null = null
  private onError: ((error: string) => void) | null = null
  private onStatusChange: ((status: string) => void) | null = null
  private useLegacyParser: boolean = false
  private jsInjected: boolean = false
  private delayedFinishTimer: number = -1
  private fallbackExecuted: boolean = false
  private promotedPlayerPageUrls: Set<string> = new Set()
  private currentReferer: string = ''
  private readonly weakCandidateDelayMs: number = 1200
  private readonly fallbackWaitMs: number = 1000

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
    const mySession = ++this.sniffSessionId
    this.isSniffing = true
    this.results = []
    this.jsInjected = false
    this.fallbackExecuted = false
    this.promotedPlayerPageUrls = new Set()
    this.currentReferer = url
    this.clearDelayedFinish()
    this.requestInterceptor.reset()
    this.urlFilter.reset()

    if (this.onStatusChange) {
      this.onStatusChange('loading')
    }

    this.requestInterceptor.setOnIntercept((interceptedUrl: string, type: string) => {
      if (this.sniffSessionId !== mySession) {
        return
      }
      this.handleInterceptedUrl(interceptedUrl, type, 'request_intercept')
    })

    this.timeoutController.setOnRetry(() => {
      if (this.sniffSessionId !== mySession) {
        return
      }
      if (this.onStatusChange) {
        this.onStatusChange('retrying (attempt ' + this.timeoutController.getAttemptCount() + ')')
      }
    })

    this.timeoutController.setOnTimeout(() => {
      if (this.sniffSessionId !== mySession) {
        return
      }
      if (!this.fallbackExecuted && this.isSniffing) {
        this.fallbackExecuted = true
        logger.info('Timeout: executing video element fallback before finalizing')
        this.executeVideoElementFallback()
        setTimeout(() => {
          if (this.sniffSessionId !== mySession) {
            return
          }
          if (this.isSniffing) {
            if (this.results.length === 0) {
              this.stopAndClearWebView()
              this.finishSniffing('timeout')
            }
          }
        }, this.fallbackWaitMs)
        return
      }
      this.stopAndClearWebView()
      this.finishSniffing('timeout')
    })

    this.timeoutController.start()

    if (this.webController) {
      try {
        this.webController.loadUrl(url)
      } catch (e) {
        if (this.sniffSessionId !== mySession) {
          return
        }
        if (this.onError) {
          this.onError('Failed to load URL: ' + e)
        }
        this.cancel()
      }
    }
  }

  onPageBegin(): void {
    if (!this.webController || !this.isSniffing) {
      return
    }
    logger.info('onPageBegin: injecting sniffer script')
    let script = JSInjector.getSnifferScript(this.useLegacyParser)
    try {
      this.webController.runJavaScript(script, (err, result) => {
        if (!this.isSniffing) {
          return
        }
        if (!err) {
          this.jsInjected = true
          logger.info('onPageBegin: script injected OK')
        } else {
          logger.warn('onPageBegin: script inject failed: %{public}s', String(err))
        }
      })
    } catch (e) {
      logger.warn('onPageBegin: runJavaScript exception: %{public}s', String(e))
    }
  }

  onPageEnd(): void {
    if (!this.webController || !this.isSniffing) {
      return
    }
    logger.info('onPageEnd fallback: injecting sniffer script')
    let script = JSInjector.getSnifferScript(this.useLegacyParser)
    try {
      this.webController.runJavaScript(script, (err, result) => {
        if (!this.isSniffing) {
          return
        }
        if (!err) {
          this.jsInjected = true
          logger.info('onPageEnd: script injected OK')
        }
      })
    } catch (e) {
    }
  }

  executeVideoElementFallback(): void {
    if (!this.webController || !this.isSniffing) {
      return
    }
    logger.info('Executing video element fallback scan')
    let script = JSInjector.getVideoElementFallbackScript()
    try {
      this.webController.runJavaScript(script, (err, result) => {
        if (!this.isSniffing) {
          return
        }
        if (err) {
          logger.warn('Fallback scan failed: %{public}s', String(err))
        } else {
          logger.info('Fallback scan completed, result: %{public}s', String(result))
        }
      })
    } catch (e) {
      logger.warn('Fallback exception: %{public}s', String(e))
    }
  }

  handleInterceptedUrl(url: string, type: string, source: string): void {
    if (!this.isSniffing) {
      return
    }
    logger.debug('interceptUrl: [%{public}s] %{public}s from %{public}s', type, url.substring(0, 80), source)
    this.promotePlayerPageIfNeeded(url)
    let result = this.urlFilter.filter(url, source)
    if (result !== null) {
      const ctx = new CapturedRequestContext()
      ctx.url = result.url
      ctx.referer = this.currentReferer
      result.context = ctx
    }
    this.recordResult(result)
  }

  handleJsBridgeMessage(message: string): void {
    if (!this.isSniffing) {
      return
    }
    try {
      logger.debug('JSBridge raw: %{public}s', message.substring(0, 120))
      let data = JSON.parse(message) as Record<string, string>
      let url = data['url'] || ''
      let type = data['type'] || ''
      let source = data['source'] || ''
      if (!url) {
        return
      }
      let result: SnifferResult | null = null
      let isVideoElementSource = source.indexOf('video_element') !== -1 ||
        source.indexOf('video_tag') !== -1 ||
        source.indexOf('video_src_setter') !== -1 ||
        source.indexOf('media_current_src') !== -1 ||
        source.indexOf('media_poll') !== -1 ||
        source.indexOf('mui_player_ctor') !== -1 ||
        source.indexOf('hls_load_source') !== -1 ||
        source.indexOf('player_config') !== -1 ||
        type.indexOf('player_config') !== -1 ||
        type.indexOf('hls_load_source') !== -1 ||
        type.indexOf('video') !== -1
      if (isVideoElementSource) {
        result = this.urlFilter.filterVideoElementUrl(url, source)
      } else {
        result = this.urlFilter.filter(url, source)
      }
      if (result !== null) {
        const ctx = new CapturedRequestContext()
        ctx.url = result.url
        ctx.referer = this.currentReferer
        result.context = ctx
      }
      this.recordResult(result)
    } catch (e) {
      logger.warn('JSBridge parse error: %{public}s', String(e))
    }
  }

  private recordResult(result: SnifferResult | null): void {
    if (result === null || !this.isSniffing) {
      return
    }
    logger.info('recordResult: [%{public}s/%{public}s] %{public}s from %{public}s',
      result.type, result.quality, result.url.substring(0, 80), result.source)
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
      lowerUrl.indexOf('player.moedot.net/player/') !== -1 ||
      lowerUrl.indexOf('://jx.') !== -1 ||
      lowerUrl.indexOf('//jx.') !== -1
  }

  private promotePlayerPageIfNeeded(url: string): void {
    if (!this.webController || !this.isSniffing) {
      return
    }
    const lowerUrl = url.toLowerCase()
    if (!this.isPromotablePlayerPage(lowerUrl)) {
      return
    }
    if (this.promotedPlayerPageUrls.has(url)) {
      return
    }
    this.promotedPlayerPageUrls.add(url)
    this.currentReferer = url
    logger.info('Promoting player frame to main WebView for sniffing: %{public}s', url.substring(0, 100))
    try {
      this.webController.loadUrl(url)
    } catch (e) {
      logger.warn('Promote player page failed: %{public}s', String(e))
    }
  }

  private isPromotablePlayerPage(lowerUrl: string): boolean {
    return lowerUrl.indexOf('://player.cycanime.com/') !== -1 &&
      lowerUrl.indexOf('?url=') !== -1
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
    this.sniffSessionId++
    this.isSniffing = false
    this.clearDelayedFinish()
    this.timeoutController.cancel()
    this.stopAndClearWebView()
    if (this.onStatusChange) {
      this.onStatusChange('cancelled')
    }
  }

  reset(): void {
    this.results = []
    this.promotedPlayerPageUrls = new Set()
    this.clearDelayedFinish()
    this.fallbackExecuted = false
    this.jsInjected = false
    this.requestInterceptor.reset()
    this.urlFilter.reset()
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
