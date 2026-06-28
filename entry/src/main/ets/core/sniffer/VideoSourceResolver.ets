import { webview } from '@kit.ArkWeb'
import { VideoSniffer } from './VideoSniffer'
import { SnifferResult } from './SnifferResult'
import { VideoSourceRequest } from './VideoSourceRequest'
import { VideoSourceResult } from './VideoSourceResult'
import { ResolveErrorCode } from './ResolveErrorCode'
import { ResolveLogEvent } from './ResolveLogEvent'
import { CapturedRequestContext } from './CapturedRequestContext'
import { PlaybackOptions } from '../player/IPlayerEngine'
import { RuleSource } from '../../models/RuleSource'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { HttpClient } from '../../network/HttpClient'
import { Logger } from '../../utils/Logger'

const logger = new Logger('VideoSourceResolver')

const DEFAULT_PLAYER_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'

export class VideoSourceResolver {
  private sniffer: VideoSniffer = new VideoSniffer()
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private webController: webview.WebviewController | null = null
  private sessionId: number = 0
  private activeSessionId: number = 0
  private isResolving: boolean = false
  private currentRetryCount: number = 0
  private resolveStartTime: number = 0
  private logListeners: ((event: ResolveLogEvent) => void)[] = []

  setWebController(controller: webview.WebviewController): void {
    this.webController = controller
    this.sniffer.setWebController(controller)
  }

  addLogListener(listener: (event: ResolveLogEvent) => void): void {
    this.logListeners.push(listener)
  }

  removeLogListener(listener: (event: ResolveLogEvent) => void): void {
    const idx = this.logListeners.indexOf(listener)
    if (idx >= 0) {
      this.logListeners.splice(idx, 1)
    }
  }

  private emitLog(requestId: number, phase: string, detail: string): void {
    const event: ResolveLogEvent = {
      requestId: requestId,
      phase: phase,
      ts: Date.now(),
      detail: detail
    }
    for (let i = 0; i < this.logListeners.length; i++) {
      this.logListeners[i](event)
    }
  }

  async resolve(request: VideoSourceRequest): Promise<VideoSourceResult> {
    const mySession = ++this.sessionId
    this.activeSessionId = mySession
    this.isResolving = true
    this.resolveStartTime = Date.now()
    this.currentRetryCount = 0

    this.emitLog(mySession, 'start', 'episodeUrl=' + request.episodeUrl.substring(0, 80))

    if (this.sniffer.getIsSniffing()) {
      this.sniffer.cancel()
    }

    let ruleSource: RuleSource | null = null
    if (request.ruleSourceId >= 0) {
      ruleSource = await this.ruleStore.getById(request.ruleSourceId)
    }

    if (this.activeSessionId !== mySession) {
      this.isResolving = false
      return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
    }

    let useLegacy = request.useLegacyParser
    if (ruleSource !== null) {
      useLegacy = ruleSource.useLegacyParser
    }

    this.sniffer.setSniffStrategy(useLegacy)
    this.sniffer.setTimeout(request.sniffTimeoutMs, request.maxRetryCount)

    const sniffUrl = await this.normalizeSniffUrlForRule(request.episodeUrl, ruleSource)
    if (this.activeSessionId !== mySession) {
      this.isResolving = false
      return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
    }

    const direct7sefunResult = this.tryBuild7sefunDirectResult(sniffUrl, ruleSource)
    if (direct7sefunResult !== null) {
      this.isResolving = false
      return direct7sefunResult
    }

    this.emitLog(mySession, 'loadUrl', sniffUrl.substring(0, 100))

    let result = await this.doSniff(sniffUrl, request.maxRetryCount, mySession)

    if (this.activeSessionId !== mySession) {
      this.isResolving = false
      return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
    }

    if (result.isPlayable() && ruleSource !== null) {
      result = this.applyRuleSourceToResult(result, ruleSource)
    }

    this.emitLog(mySession, result.isPlayable() ? 'finish' : 'error',
      result.isPlayable() ? 'url=' + result.videoUrl.substring(0, 80) : result.errorMessage)

    this.isResolving = false
    return result
  }

  private async normalizeSniffUrlForRule(url: string, ruleSource: RuleSource | null): Promise<string> {
    if (ruleSource === null || ruleSource.name.toLowerCase() !== '7sefun') {
      return url
    }

    const playerUrl = await this.extract7sefunPlayerUrl(url)
    if (playerUrl.length === 0) {
      return url
    }

    logger.info('7sefun decoded player url: %{public}s', playerUrl.substring(0, 100))
    return playerUrl
  }

  private tryBuild7sefunDirectResult(url: string, ruleSource: RuleSource | null): VideoSourceResult | null {
    if (ruleSource === null || ruleSource.name.toLowerCase() !== '7sefun') {
      return null
    }
    const type = SnifferResult.detectType(url)
    if (type !== 'm3u8' && type !== 'mp4' && type !== 'flv' && type !== 'ts') {
      return null
    }
    const elapsed = Date.now() - this.resolveStartTime
    logger.info('7sefun direct media url resolved without WebView sniffing: %{public}s',
      url.substring(0, 100))
    const candidate = new SnifferResult(url, type, 'unknown', '7sefun_player_config')
    return VideoSourceResult.success(url, type, [candidate], elapsed)
  }

  private async extract7sefunPlayerUrl(url: string): Promise<string> {
    try {
      const client = new HttpClient()
      const response = await client.get(url, {
        'User-Agent': DEFAULT_PLAYER_USER_AGENT,
        'Referer': 'https://www.7sefun.top/',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      })
      if (!response.isSuccessful || response.body.length === 0) {
        logger.warn('7sefun player page fetch failed: status=%{public}d', response.statusCode)
        return ''
      }

      const match = response.body.match(/var\s+player_aaaa\s*=\s*\{[\s\S]*?"url"\s*:\s*"([^"]+)"/)
      if (match === null || match.length < 2) {
        logger.warn('7sefun player config not found')
        return ''
      }

      const decoded = this.decode7sefunPlayerUrl(match[1])
      if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
        return decoded.replace(/\\\//g, '/')
      }
    } catch (err) {
      logger.warn('7sefun player url extraction failed: %{public}s',
        err instanceof Error ? err.message : String(err))
    }
    return ''
  }

  private decode7sefunPlayerUrl(encoded: string): string {
    const percentEncoded = this.decodeBase64Ascii(encoded)
    try {
      return decodeURIComponent(percentEncoded)
    } catch (_) {
      return percentEncoded
    }
  }

  private decodeBase64Ascii(encoded: string): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let buffer = 0
    let bitCount = 0
    let output = ''

    for (let i = 0; i < encoded.length; i++) {
      const ch = encoded.charAt(i)
      if (ch === '=') {
        break
      }
      const value = alphabet.indexOf(ch)
      if (value < 0) {
        continue
      }
      buffer = (buffer << 6) | value
      bitCount += 6
      if (bitCount >= 8) {
        bitCount -= 8
        output += String.fromCharCode((buffer >> bitCount) & 0xff)
      }
    }

    return output
  }

  private doSniff(url: string, maxRetry: number, mySession: number): Promise<VideoSourceResult> {
    return new Promise<VideoSourceResult>((resolve) => {
      this.sniffer.setResultCallback((result: SnifferResult) => {
        if (this.activeSessionId !== mySession) {
          return
        }
        logger.info('Sniffed: %{public}s [%{public}s/%{public}s] from %{public}s',
          result.url.substring(0, 80), result.type, result.quality, result.source)
        this.emitLog(mySession, 'candidate', result.type + ' ' + result.url.substring(0, 80))
      })

      this.sniffer.setCompleteCallback((results: SnifferResult[]) => {
        if (this.activeSessionId !== mySession) {
          return
        }
        const elapsed = Date.now() - this.resolveStartTime
        const bestResult = this.selectBestResult(results)
        if (bestResult !== null) {
          resolve(VideoSourceResult.success(bestResult.url, bestResult.type, results, elapsed))
        } else if (results.length > 0) {
          resolve(VideoSourceResult.success(results[0].url, results[0].type, results, elapsed))
        } else {
          resolve(VideoSourceResult.fail('未嗅探到视频流地址', this.currentRetryCount, elapsed))
        }
      })

      this.sniffer.setErrorCallback((error: string) => {
        if (this.activeSessionId !== mySession) {
          return
        }
        const elapsed = Date.now() - this.resolveStartTime
        logger.warn('Sniff error: %{public}s', error)
        if (this.currentRetryCount < maxRetry) {
          this.currentRetryCount++
          let delayMs = this.currentRetryCount * 2000
          setTimeout(() => {
            if (this.activeSessionId !== mySession) {
              return
            }
            this.sniffer.sniff(url)
          }, delayMs)
        } else {
          resolve(VideoSourceResult.fail(error, this.currentRetryCount, elapsed))
        }
      })

      this.sniffer.setStatusCallback((status: string) => {
        if (this.activeSessionId !== mySession) {
          return
        }
        if (status === 'timeout') {
          const elapsed = Date.now() - this.resolveStartTime
          if (this.currentRetryCount < maxRetry) {
            this.currentRetryCount++
            let delayMs = this.currentRetryCount * 2000
            logger.info('Sniff timeout, retry %{public}d/%{public}d after %{public}dms',
              this.currentRetryCount, maxRetry, delayMs)
            setTimeout(() => {
              if (this.activeSessionId !== mySession) {
                return
              }
              this.sniffer.sniff(url)
            }, delayMs)
          } else {
            resolve(VideoSourceResult.timeout(this.currentRetryCount, elapsed))
          }
        }
      })

      this.sniffer.sniff(url)
    })
  }

  private selectBestResult(results: SnifferResult[]): SnifferResult | null {
    let best: SnifferResult | null = null
    for (let i = 0; i < results.length; i++) {
      const r = results[i]
      if (r.type === 'm3u8' || r.type === 'mp4') {
        if (best === null) {
          best = r
        } else if (r.type === 'm3u8' && best.type === 'mp4') {
          best = r
        } else if (this.isWeakWrapperCandidate(best) && !this.isWeakWrapperCandidate(r)) {
          best = r
        } else if (r.type === 'm3u8' && best.type === 'm3u8' &&
          best.quality === 'unknown' && r.quality !== 'unknown') {
          best = r
        }
      }
    }
    return best
  }

  private isWeakWrapperCandidate(result: SnifferResult): boolean {
    const lowerUrl = result.url.toLowerCase()
    return lowerUrl.indexOf('/m3u8/?url=') !== -1 ||
      lowerUrl.indexOf('/m3u8?url=') !== -1 ||
      lowerUrl.indexOf('player.moedot.net/player/') !== -1 ||
      lowerUrl.indexOf('://jx.') !== -1 ||
      lowerUrl.indexOf('//jx.') !== -1
  }

  private applyRuleSourceToResult(result: VideoSourceResult, rule: RuleSource): VideoSourceResult {
    if (rule.antiCrawlerConfig.enabled && rule.antiCrawlerConfig.captchaType > 0) {
      logger.info('Rule source has anti-crawler config: captchaType=%{public}d', rule.antiCrawlerConfig.captchaType)
    }
    return result
  }

  handleInterceptedRequest(url: string): void {
    if (this.isResolving && this.sniffer.getIsSniffing()) {
      logger.debug('handleInterceptedRequest: %{public}s', url.substring(0, 100))
      let type = SnifferResult.detectType(url)
      this.sniffer.handleInterceptedUrl(url, type, 'request_intercept')
    }
  }

  onWebViewPageBegin(): void {
    if (this.isResolving) {
      logger.debug('onWebViewPageBegin')
      this.sniffer.onPageBegin()
    }
  }

  onWebViewPageEnd(): void {
    if (this.isResolving) {
      logger.debug('onWebViewPageEnd')
      this.sniffer.onPageEnd()
    }
  }

  handleJsBridgeMessage(message: string): void {
    if (this.isResolving) {
      logger.debug('handleJsBridgeMessage: %{public}s', message.substring(0, 120))
      this.sniffer.handleJsBridgeMessage(message)
    }
  }

  buildPlaybackOptions(result: VideoSourceResult, request: VideoSourceRequest): PlaybackOptions {
    const options = new PlaybackOptions()
    options.url = result.videoUrl
    options.startPositionMs = 0

    if (request.referer.length > 0) {
      options.referer = request.referer
    }
    if (request.userAgent.length > 0) {
      options.userAgent = request.userAgent
    }

    let headerKeys = Object.keys(request.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      let key = headerKeys[i]
      options.headers[key] = request.headers[key]
    }

    if (options.referer.length === 0 || options.userAgent.length === 0) {
      let capturedContext: CapturedRequestContext | null = null
      for (let i = 0; i < result.candidates.length; i++) {
        const candidate = result.candidates[i]
        if (candidate.url === result.videoUrl && candidate.context !== null) {
          capturedContext = candidate.context
          break
        }
      }
      if (capturedContext !== null) {
        if (options.referer.length === 0 && capturedContext.referer.length > 0) {
          options.referer = capturedContext.referer
        }
        if (options.userAgent.length === 0 && capturedContext.userAgent.length > 0) {
          options.userAgent = capturedContext.userAgent
        }
        let ctxHeaderKeys = Object.keys(capturedContext.headers)
        for (let i = 0; i < ctxHeaderKeys.length; i++) {
          let key = ctxHeaderKeys[i]
          options.headers[key] = capturedContext.headers[key]
        }
      }
    }

    return options
  }

  async buildPlaybackOptionsWithRule(result: VideoSourceResult, request: VideoSourceRequest): Promise<PlaybackOptions> {
    const options = this.buildPlaybackOptions(result, request)

    if (request.ruleSourceId >= 0) {
      const rule = await this.ruleStore.getById(request.ruleSourceId)
      if (rule !== null) {
        if (options.referer.length === 0 && rule.referer.length > 0) {
          options.referer = rule.referer
        }
        if (options.userAgent.length === 0 && rule.userAgent.length > 0) {
          options.userAgent = rule.userAgent
        }
        if (rule.name.toLowerCase() === '7sefun') {
          options.referer = this.build7sefunPlaybackReferer(result.videoUrl, request.episodeUrl)
          if (options.userAgent.length === 0) {
            options.userAgent = DEFAULT_PLAYER_USER_AGENT
          }
          if (options.referer.length > 0) {
            options.headers['Referer'] = options.referer
          }
          options.headers['Accept'] = '*/*'
          options.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8'
          logger.info('7sefun playback headers: referer=%{public}s, url=%{public}s',
            options.referer.length > 0 ? options.referer : '<empty>',
            result.videoUrl.substring(0, 80))
        }
      }
    }
    if (options.userAgent.length === 0) {
      options.userAgent = DEFAULT_PLAYER_USER_AGENT
    }

    return options
  }

  private build7sefunPlaybackReferer(videoUrl: string, episodeUrl: string): string {
    const lowerUrl = videoUrl.toLowerCase()
    if (lowerUrl.indexOf('groupvideo.photo.qq.com') !== -1) {
      return ''
    }
    if (lowerUrl.indexOf('lmm85.com') !== -1) {
      return 'https://www.lmm85.com/'
    }
    if (episodeUrl.length > 0) {
      return episodeUrl
    }
    return 'https://www.7sefun.top/'
  }

  cancel(): void {
    this.activeSessionId = ++this.sessionId
    this.isResolving = false
    this.sniffer.cancel()
  }

  getIsResolving(): boolean {
    return this.isResolving
  }
}
