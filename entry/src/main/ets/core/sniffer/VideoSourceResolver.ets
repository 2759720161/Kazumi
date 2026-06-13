import { webview } from '@kit.ArkWeb'
import { VideoSniffer } from './VideoSniffer'
import { SnifferResult } from './SnifferResult'
import { VideoSourceRequest } from './VideoSourceRequest'
import { VideoSourceResult } from './VideoSourceResult'
import { PlaybackOptions } from '../player/IPlayerEngine'
import { RuleSource, AntiCrawlerConfig } from '../../models/RuleSource'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('VideoSourceResolver')

const DEFAULT_PLAYER_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'

export class VideoSourceResolver {
  private sniffer: VideoSniffer = new VideoSniffer()
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private webController: webview.WebviewController | null = null
  private isResolving: boolean = false
  private currentRetryCount: number = 0
  private resolveStartTime: number = 0

  setWebController(controller: webview.WebviewController): void {
    this.webController = controller
    this.sniffer.setWebController(controller)
  }

  async resolve(request: VideoSourceRequest): Promise<VideoSourceResult> {
    if (this.isResolving) {
      return VideoSourceResult.fail('正在嗅探中，请勿重复调用', 0, 0)
    }

    this.isResolving = true
    this.resolveStartTime = Date.now()
    this.currentRetryCount = 0

    let ruleSource: RuleSource | null = null
    if (request.ruleSourceId >= 0) {
      ruleSource = await this.ruleStore.getById(request.ruleSourceId)
    }

    let useLegacy = request.useLegacyParser
    if (ruleSource !== null) {
      useLegacy = ruleSource.useLegacyParser
    }

    this.sniffer.setSniffStrategy(useLegacy)
    this.sniffer.setTimeout(request.sniffTimeoutMs, request.maxRetryCount)

    let result = await this.doSniff(request.episodeUrl, request.maxRetryCount)

    if (result.isPlayable() && ruleSource !== null) {
      result = this.applyRuleSourceToResult(result, ruleSource)
    }

    this.isResolving = false
    return result
  }

  private doSniff(url: string, maxRetry: number): Promise<VideoSourceResult> {
    return new Promise<VideoSourceResult>((resolve) => {
      this.sniffer.setResultCallback((result: SnifferResult) => {
        logger.info('Sniffed: %{public}s [%{public}s/%{public}s] from %{public}s',
          result.url.substring(0, 80), result.type, result.quality, result.source)
      })

      this.sniffer.setCompleteCallback((results: SnifferResult[]) => {
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
        const elapsed = Date.now() - this.resolveStartTime
        logger.warn('Sniff error: %{public}s', error)
        if (this.currentRetryCount < maxRetry) {
          this.currentRetryCount++
          let delayMs = this.currentRetryCount * 2000
          setTimeout(() => {
            this.sniffer.sniff(url)
          }, delayMs)
        } else {
          resolve(VideoSourceResult.fail(error, this.currentRetryCount, elapsed))
        }
      })

      this.sniffer.setStatusCallback((status: string) => {
        if (status === 'timeout') {
          const elapsed = Date.now() - this.resolveStartTime
          if (this.currentRetryCount < maxRetry) {
            this.currentRetryCount++
            let delayMs = this.currentRetryCount * 2000
            logger.info('Sniff timeout, retry %{public}d/%{public}d after %{public}dms',
              this.currentRetryCount, maxRetry, delayMs)
            setTimeout(() => {
              this.sniffer.sniff(url)
            }, delayMs)
          } else {
            resolve(VideoSourceResult.timeout(this.currentRetryCount, elapsed))
          }
        } else if (status === 'found') {
          // onComplete will handle this
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
      let type = SnifferResult.detectType(url)
      this.sniffer.handleInterceptedUrl(url, type, 'request_intercept')
    }
  }

  onWebViewPageEnd(): void {
    if (this.isResolving) {
      this.sniffer.onPageEnd()
    }
  }

  handleJsBridgeMessage(message: string): void {
    if (this.isResolving) {
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
      }
    }
    if (options.userAgent.length === 0) {
      options.userAgent = DEFAULT_PLAYER_USER_AGENT
    }

    return options
  }

  cancel(): void {
    this.isResolving = false
    this.sniffer.cancel()
  }

  getIsResolving(): boolean {
    return this.isResolving
  }
}
