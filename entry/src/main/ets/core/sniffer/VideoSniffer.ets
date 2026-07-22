import { webview } from '@kit.ArkWeb'
import { SnifferResult } from './SnifferResult'
import { CapturedRequestContext } from './CapturedRequestContext'
import { RequestInterceptor } from './RequestInterceptor'
import { JSInjector } from './JSInjector'
import { CandidateUrlFilter } from './CandidateUrlFilter'
import { TimeoutController } from './TimeoutController'
import { NetworkPolicy } from './NetworkPolicy'
import { SniffRuleEvaluator } from './SniffRuleEvaluator'
import { Logger } from '../../utils/Logger'

const logger = new Logger('VideoSniffer')

export class VideoSniffer {
  private requestInterceptor: RequestInterceptor = new RequestInterceptor()
  private urlFilter: CandidateUrlFilter = new CandidateUrlFilter()
  private timeoutController: TimeoutController = new TimeoutController(
    NetworkPolicy.DEFAULT_SNIFF_TIMEOUT_MS, NetworkPolicy.DEFAULT_MAX_RETRY)
  private ruleEvaluator: SniffRuleEvaluator = new SniffRuleEvaluator()
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
  private collectWindowTimer: number = -1
  private hasPlayableResult: boolean = false
  private fallbackExecuted: boolean = false
  private promotedPlayerPageUrls: Set<string> = new Set()
  private currentReferer: string = ''
  private userAgent: string = NetworkPolicy.DEFAULT_PLAYER_USER_AGENT
  private readonly weakCandidateDelayMs: number = NetworkPolicy.WEAK_CANDIDATE_DELAY_MS
  private readonly fallbackWaitMs: number = NetworkPolicy.FALLBACK_WAIT_MS

  setUserAgent(userAgent: string): void {
    this.userAgent = userAgent.length > 0 ? userAgent : NetworkPolicy.DEFAULT_PLAYER_USER_AGENT
  }

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

  setRuleEvaluator(evaluator: SniffRuleEvaluator): void {
    this.ruleEvaluator = evaluator
    this.urlFilter.setRuleEvaluator(evaluator)
    this.requestInterceptor.setRuleEvaluator(evaluator)
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
    this.clearCollectWindow()
    this.hasPlayableResult = false
    this.requestInterceptor.reset()
    this.urlFilter.reset()

    if (this.onStatusChange) {
      this.onStatusChange('loading')
    }

    this.requestInterceptor.setOnIntercept((interceptedUrl: string, type: string, headers: Record<string, string>) => {
      if (this.sniffSessionId !== mySession) {
        return
      }
      this.handleInterceptedUrlWithHeaders(interceptedUrl, type, 'request_intercept', headers)
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
        this.applyCustomUserAgent()
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
          logger.info('onPageBegin: script dispatched, waiting for ready handshake')
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
          logger.info('onPageEnd: script dispatched, waiting for ready handshake')
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
    this.handleInterceptedUrlWithHeaders(url, type, source, {})
  }

  handleInterceptedRequest(url: string, headers: Record<string, string>): void {
    if (!this.isSniffing) {
      return
    }
    this.promotePlayerPageIfNeeded(url)
    this.requestInterceptor.interceptRequest(url, headers)
  }

  private handleInterceptedUrlWithHeaders(url: string, type: string, source: string,
    headers: Record<string, string>): void {
    if (!this.isSniffing) {
      return
    }
    logger.debug('interceptUrl: [%{public}s] %{public}s from %{public}s', type, url.substring(0, 80), source)
    this.promotePlayerPageIfNeeded(url)
    let result = this.urlFilter.filter(url, source)
    const rangeVerdict = this.ruleEvaluator.evaluateRangeRequest(url, headers)
    if (result === null) {
      result = this.createHeaderDetectedResult(url, source, headers)
    }
    if (result !== null) {
      const ctx = new CapturedRequestContext()
      ctx.url = result.url
      ctx.referer = this.currentReferer
      ctx.headers = headers
      ctx.hasRangeHeader = rangeVerdict.isRangeVideo
      ctx.contentType = rangeVerdict.detectedContentType
      const referer = this.getHeaderIgnoreCase(headers, 'referer')
      if (referer.length > 0) {
        ctx.referer = referer
      }
      const cookie = this.getHeaderIgnoreCase(headers, 'cookie')
      if (cookie.length > 0) {
        ctx.cookies = cookie
      }
      const contentType = this.getHeaderIgnoreCase(headers, 'content-type')
      if (contentType.length > 0) {
        ctx.contentType = contentType
      }
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
      const event = data['event'] || ''
      if (event === 'sniffer_ready') {
        this.jsInjected = true
        logger.info('Sniffer script ready: mode=%{public}s', data['mode'] || 'unknown')
        return
      }
      let url = data['url'] || ''
      let type = data['type'] || ''
      let source = data['source'] || ''
      let referer = data['referer'] || ''
      let cookie = data['cookie'] || ''
      let contentType = data['contentType'] || ''
      const responseUrl = data['responseUrl'] || ''
      const responseStatus = data['responseStatus'] || ''
      let headers = JSInjector.extractHeadersFromJson(data['headers'] || '')
      let hasRange = data['hasRange'] === 'true'
      if (contentType.length > 0 && this.getHeaderIgnoreCase(headers, 'content-type').length === 0) {
        headers['Content-Type'] = contentType
      }
      if (this.getHeaderIgnoreCase(headers, 'range').length > 0) {
        hasRange = true
      }
      if (!url) {
        return
      }
      if (source === 'json_response') {
        logger.info('JSON media candidate: status=%{public}s response=%{public}s media=%{public}s',
          responseStatus.length > 0 ? responseStatus : 'unknown',
          responseUrl.length > 0 ? responseUrl.substring(0, 120) : 'unknown', url.substring(0, 120))
      }
      if (referer.length > 0) {
        this.currentReferer = referer
      }
      this.promotePlayerPageIfNeeded(url)
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
        type.indexOf('hls_load_source') !== -1
      if (isVideoElementSource) {
        result = this.urlFilter.filterVideoElementUrl(url, source)
      } else {
        result = this.urlFilter.filter(url, source)
      }
      if (hasRange && this.getHeaderIgnoreCase(headers, 'range').length === 0) {
        headers['Range'] = 'bytes=0-'
      }
      if (result === null) {
        result = this.createHeaderDetectedResult(url, source, headers)
      } else if (contentType.length > 0) {
        const detectedType = this.requestInterceptor.detectType(url, headers)
        if (detectedType !== 'unknown' && detectedType !== 'range_video' && detectedType !== result.type) {
          result.type = detectedType
          result.ruleSource = 'response_content_type'
          result.score = SnifferResult.calculateScore(detectedType, source, result.url, result.quality,
            this.ruleEvaluator)
        }
      }
      if (result !== null) {
        const ctx = new CapturedRequestContext()
        ctx.url = result.url
        ctx.referer = this.currentReferer
        if (referer.length > 0) {
          ctx.referer = referer
        }
        if (cookie.length > 0) {
          ctx.cookies = cookie
        }
        if (contentType.length > 0) {
          ctx.contentType = contentType
        }
        ctx.hasRangeHeader = hasRange
        let headerKeys = Object.keys(headers)
        for (let i = 0; i < headerKeys.length; i++) {
          const key = headerKeys[i]
          ctx.headers[key] = headers[key]
        }
        if (hasRange && this.getHeaderIgnoreCase(ctx.headers, 'range').length === 0) {
          ctx.headers['Range'] = 'bytes=0-'
        }
        if (referer.length > 0 && this.getHeaderIgnoreCase(ctx.headers, 'referer').length === 0) {
          ctx.headers['Referer'] = referer
        }
        if (cookie.length > 0 && this.getHeaderIgnoreCase(ctx.headers, 'cookie').length === 0) {
          ctx.headers['Cookie'] = cookie
        }
        if (contentType.length > 0 && this.getHeaderIgnoreCase(ctx.headers, 'content-type').length === 0) {
          ctx.headers['Content-Type'] = contentType
        }
        result.context = ctx
      }
      this.recordResult(result)
    } catch (e) {
      logger.warn('JSBridge parse error: %{public}s', String(e))
    }
  }

  private createHeaderDetectedResult(url: string, source: string,
    headers: Record<string, string>): SnifferResult | null {
    if (!this.requestInterceptor.shouldIntercept(url, headers)) {
      return null
    }
    const detectedType = this.requestInterceptor.detectType(url, headers)
    if (detectedType === 'unknown') {
      return null
    }
    const result = new SnifferResult(url, detectedType, 'unknown', source)
    const contentType = this.getHeaderIgnoreCase(headers, 'content-type')
    if (contentType.length > 0) {
      result.ruleSource = 'response_content_type'
    } else {
      const rangeVerdict = this.ruleEvaluator.evaluateRangeRequest(url, headers)
      result.ruleSource = rangeVerdict.matchedRuleName.length > 0 ? rangeVerdict.matchedRuleName : 'request_intercept'
    }
    result.score = SnifferResult.calculateScore(detectedType, source, url, 'unknown', this.ruleEvaluator)
    return result
  }

  private recordResult(result: SnifferResult | null): void {
    if (result === null || !this.isSniffing) {
      return
    }
    if (this.isIgnored7sefunCandidate(result.url)) {
      logger.info('recordResult: ignore 7sefun blocked candidate %{public}s from %{public}s',
        result.url.substring(0, 80), result.source)
      return
    }
    logger.info('recordResult: [%{public}s/%{public}s] score=%{public}d %{public}s from %{public}s',
      result.type, result.quality, result.score, result.url.substring(0, 80), result.source)
    this.results.push(result)
    if (this.onResult) {
      this.onResult(result)
    }
    if (result.type !== 'm3u8' && result.type !== 'mp4' && result.type !== 'flv' &&
      result.type !== 'ts' && result.type !== 'range_video') {
      return
    }
    if (result.type === 'range_video') {
      logger.info('recordResult: provisional range candidate, waiting for confirmed video resource')
      this.scheduleDelayedFinish(NetworkPolicy.RANGE_CANDIDATE_WAIT_MS)
      return
    }
    const weakVerdict = this.ruleEvaluator.evaluateWeakCandidate(result.url)
    if (weakVerdict.isWeak) {
      this.scheduleDelayedFinish(weakVerdict.delayMs)
      return
    }
    this.clearDelayedFinish()
    if (!this.hasPlayableResult) {
      this.hasPlayableResult = true
      this.startCollectWindow()
    }
  }

  private startCollectWindow(): void {
    if (this.collectWindowTimer >= 0) {
      return
    }
    this.collectWindowTimer = setTimeout(() => {
      this.collectWindowTimer = -1
      if (this.isSniffing) {
        this.finishSniffing('found')
      }
    }, NetworkPolicy.COLLECT_WINDOW_MS)
  }

  private clearCollectWindow(): void {
    if (this.collectWindowTimer >= 0) {
      clearTimeout(this.collectWindowTimer)
      this.collectWindowTimer = -1
    }
  }

  private isIgnored7sefunCandidate(url: string): boolean {
    const lowerReferer = this.currentReferer.toLowerCase()
    if (lowerReferer.indexOf('7sefun.top') === -1) {
      return false
    }
    const lowerUrl = url.toLowerCase()
    return lowerUrl.indexOf('jxdunrui.top') !== -1 || lowerUrl.indexOf('mao6.') !== -1
  }

  private promotePlayerPageIfNeeded(url: string): void {
    if (!this.webController || !this.isSniffing) {
      return
    }
    const verdict = this.ruleEvaluator.evaluatePromotePage(url)
    if (!verdict.shouldPromote) {
      return
    }
    if (this.promotedPlayerPageUrls.has(url)) {
      return
    }
    this.promotedPlayerPageUrls.add(url)
    this.currentReferer = url
    logger.info('Promoting player frame to main WebView for sniffing (rule=%{public}s): %{public}s',
      verdict.matchedRuleName, url.substring(0, 100))
    try {
      this.applyCustomUserAgent()
      this.webController.loadUrl(url)
    } catch (e) {
      logger.warn('Promote player page failed: %{public}s', String(e))
    }
  }

  private applyCustomUserAgent(): void {
    if (this.webController === null || this.userAgent.length === 0) {
      return
    }
    try {
      this.webController.setCustomUserAgent(this.userAgent)
    } catch (e) {
      logger.warn('Set WebView user agent failed: %{public}s', String(e))
    }
  }

  private scheduleDelayedFinish(delayMs: number): void {
    if (this.delayedFinishTimer >= 0) {
      return
    }
    this.delayedFinishTimer = setTimeout(() => {
      this.delayedFinishTimer = -1
      if (this.isSniffing) {
        this.finishSniffing('found')
      }
    }, delayMs > 0 ? delayMs : this.weakCandidateDelayMs)
  }

  private clearDelayedFinish(): void {
    if (this.delayedFinishTimer >= 0) {
      clearTimeout(this.delayedFinishTimer)
      this.delayedFinishTimer = -1
    }
  }

  private getHeaderIgnoreCase(headers: Record<string, string>, name: string): string {
    const keys = Object.keys(headers)
    const lowerName = name.toLowerCase()
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === lowerName) {
        return headers[keys[i]]
      }
    }
    return ''
  }

  private finishSniffing(reason: string): void {
    this.clearDelayedFinish()
    this.clearCollectWindow()
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
    this.clearCollectWindow()
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
    this.clearCollectWindow()
    this.hasPlayableResult = false
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
