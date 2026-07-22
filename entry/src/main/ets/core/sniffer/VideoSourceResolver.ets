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
import { NetworkPolicy } from './NetworkPolicy'
import { SnifferSessionPool } from './SnifferSessionPool'
import { SnifferLease, WebViewCleanupLevel } from './SnifferSessionPool'
import { Logger } from '../../utils/Logger'
import { HlsManifestParser } from './HlsManifestParser'
import { SniffRuleEvaluator } from './SniffRuleEvaluator'

const logger = new Logger('VideoSourceResolver')

const DEFAULT_PLAYER_USER_AGENT = NetworkPolicy.DEFAULT_PLAYER_USER_AGENT

export class VideoSourceResolver {
  private sniffer: VideoSniffer = new VideoSniffer()
  private backgroundSniffer: VideoSniffer = new VideoSniffer()
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private webController: webview.WebviewController | null = null
  private backgroundWebController: webview.WebviewController | null = null
  private sessionId: number = 0
  private activeSessionId: number = 0
  private activePrepareSessionId: number = 0
  private resolveEpoch: number = 0
  private isResolving: boolean = false
  private policy: NetworkPolicy = new NetworkPolicy()
  private hlsManifestParser: HlsManifestParser = new HlsManifestParser()
  private ruleEvaluator: SniffRuleEvaluator = new SniffRuleEvaluator()
  private resolveStartTime: number = 0
  private logListeners: ((event: ResolveLogEvent) => void)[] = []
  private sessionPool: SnifferSessionPool = new SnifferSessionPool()
  private currentLease: SnifferLease | null = null
  private backgroundLease: SnifferLease | null = null
  private isPreparingNext: boolean = false

  constructor() {
    this.sniffer.setRuleEvaluator(this.ruleEvaluator)
    this.backgroundSniffer.setRuleEvaluator(this.ruleEvaluator)
  }

  setWebController(controller: webview.WebviewController): void {
    this.setWorkerWebController(1, controller)
  }

  setWorkerWebController(workerId: number, controller: webview.WebviewController): void {
    if (workerId === 2) {
      this.backgroundWebController = controller
      this.backgroundSniffer.setWebController(controller)
      return
    }
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
    const myEpoch = this.resolveEpoch
    this.activeSessionId = mySession
    this.isResolving = true
    this.resolveStartTime = Date.now()

    if (this.isPreparingNext || this.backgroundLease !== null || this.backgroundSniffer.getIsSniffing()) {
      this.cancelBackgroundPreparation('foreground_resolve')
    }

    this.emitLog(mySession, 'start', 'episodeUrl=' + request.episodeUrl.substring(0, 80))

    if (this.sniffer.getIsSniffing()) {
      this.sniffer.cancel()
    }

    let ruleSource: RuleSource | null = null
    if (request.ruleSourceId >= 0) {
      ruleSource = await this.ruleStore.getById(request.ruleSourceId)
    }

    if (this.activeSessionId !== mySession || this.resolveEpoch !== myEpoch) {
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
    if (this.activeSessionId !== mySession || this.resolveEpoch !== myEpoch) {
      this.isResolving = false
      return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
    }

    const tvtfunResult = await this.tryResolveTvTFunApiResult(sniffUrl, ruleSource, request)
    if (this.activeSessionId !== mySession || this.resolveEpoch !== myEpoch) {
      this.isResolving = false
      return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
    }
    if (tvtfunResult !== null) {
      await this.attachStreamMetadata(tvtfunResult, request, mySession, myEpoch)
      this.isResolving = false
      return tvtfunResult
    }

    const direct7sefunResult = this.tryBuild7sefunDirectResult(sniffUrl, ruleSource)
    if (direct7sefunResult !== null) {
      await this.attachStreamMetadata(direct7sefunResult, request, mySession, myEpoch)
      this.isResolving = false
      return direct7sefunResult
    }

    const directResult = this.tryBuildDirectMediaResult(sniffUrl)
    if (directResult !== null) {
      await this.attachStreamMetadata(directResult, request, mySession, myEpoch)
      this.isResolving = false
      return directResult
    }

    this.currentLease = this.sessionPool.acquire(request)
    const lease = this.currentLease
    const leaseId = lease.sessionId

    try {
      this.emitLog(mySession, 'loadUrl', sniffUrl.substring(0, 100))

      let result = await this.doSniff(sniffUrl, request.maxRetryCount, mySession, myEpoch, lease,
        this.resolveStartTime)

      if (!this.sessionPool.isLeaseActive(leaseId)) {
        this.isResolving = false
        return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
      }

      this.releaseLease(lease)

      if (this.activeSessionId !== mySession || this.resolveEpoch !== myEpoch) {
        this.isResolving = false
        return VideoSourceResult.cancelled(Date.now() - this.resolveStartTime)
      }

      if (result.isPlayable() && ruleSource !== null) {
        result = this.applyRuleSourceToResult(result, ruleSource)
      }
      if (result.isPlayable()) {
        await this.attachStreamMetadata(result, request, mySession, myEpoch)
      }

      this.emitLog(mySession, result.isPlayable() ? 'finish' : 'error',
        result.isPlayable() ? 'url=' + result.videoUrl.substring(0, 80) : result.errorMessage)

      this.isResolving = false
      return result
    } finally {
      if (this.currentLease !== null && this.currentLease.sessionId === leaseId) {
        this.releaseLease(lease)
      }
    }
  }

  async prepareNext(request: VideoSourceRequest): Promise<VideoSourceResult> {
    if (this.backgroundSniffer.getIsSniffing()) {
      logger.info('prepareNext skipped: background sniffer busy')
      return VideoSourceResult.fail('预解析跳过：后台 worker 正忙', 0, 0)
    }
    if (this.sessionPool.hasActiveBackgroundLease()) {
      logger.info('prepareNext skipped: background lease active')
      return VideoSourceResult.fail('预解析跳过：已有后台任务', 0, 0)
    }

    const mySession = ++this.sessionId
    const myEpoch = this.resolveEpoch
    this.activePrepareSessionId = mySession
    this.isPreparingNext = true
    const prepareStartTime = Date.now()

    let ruleSource: RuleSource | null = null
    if (request.ruleSourceId >= 0) {
      ruleSource = await this.ruleStore.getById(request.ruleSourceId)
    }
    if (!this.isResolverSessionActive(mySession, myEpoch, 2)) {
      this.finishPrepareSession(mySession)
      return VideoSourceResult.cancelled(Date.now() - prepareStartTime)
    }

    let useLegacy = request.useLegacyParser
    if (ruleSource !== null) {
      useLegacy = ruleSource.useLegacyParser
    }
    this.backgroundSniffer.setSniffStrategy(useLegacy)
    this.backgroundSniffer.setTimeout(request.sniffTimeoutMs, request.maxRetryCount)

    const sniffUrl = await this.normalizeSniffUrlForRule(request.episodeUrl, ruleSource)
    const tvtfunResult = await this.tryResolveTvTFunApiResult(sniffUrl, ruleSource, request, prepareStartTime)
    if (tvtfunResult !== null) {
      await this.attachStreamMetadata(tvtfunResult, request, mySession, myEpoch, 2)
      this.emitLog(mySession, 'prepareNextDone', 'url=' + tvtfunResult.videoUrl.substring(0, 80))
      return tvtfunResult
    }
    const direct7sefunResult = this.tryBuild7sefunDirectResult(sniffUrl, ruleSource, prepareStartTime)
    if (direct7sefunResult !== null) {
      await this.attachStreamMetadata(direct7sefunResult, request, mySession, myEpoch, 2)
      this.finishPrepareSession(mySession)
      return direct7sefunResult
    }
    const directResult = this.tryBuildDirectMediaResult(sniffUrl, prepareStartTime)
    if (directResult !== null) {
      await this.attachStreamMetadata(directResult, request, mySession, myEpoch, 2)
      this.finishPrepareSession(mySession)
      return directResult
    }

    const lease = this.sessionPool.acquireBackground(request)
    if (lease === null) {
      this.finishPrepareSession(mySession)
      return VideoSourceResult.fail('预解析跳过：后台 worker 已占用', 0, Date.now() - prepareStartTime)
    }
    this.backgroundLease = lease
    const leaseId = lease.sessionId

    try {
      await this.delayMs(300)
      if (!this.sessionPool.isBackgroundLeaseActive(leaseId) ||
        !this.isResolverSessionActive(mySession, myEpoch, 2)) {
        return VideoSourceResult.cancelled(Date.now() - prepareStartTime)
      }

      this.emitLog(mySession, 'prepareNext', 'url=' + sniffUrl.substring(0, 100))
      let result = await this.doSniff(sniffUrl, request.maxRetryCount, mySession, myEpoch, lease,
        prepareStartTime)
      if (!this.sessionPool.isBackgroundLeaseActive(leaseId)) {
        return VideoSourceResult.cancelled(Date.now() - prepareStartTime)
      }
      this.releaseBackgroundLease(lease)

      if (result.isPlayable() && ruleSource !== null) {
        result = this.applyRuleSourceToResult(result, ruleSource)
      }
      if (result.isPlayable()) {
        await this.attachStreamMetadata(result, request, mySession, myEpoch, 2)
      }
      this.emitLog(mySession, result.isPlayable() ? 'prepareNextDone' : 'prepareNextError',
        result.isPlayable() ? 'url=' + result.videoUrl.substring(0, 80) : result.errorMessage)
      return result
    } finally {
      this.finishPrepareSession(mySession)
      if (this.backgroundLease !== null && this.backgroundLease.sessionId === leaseId) {
        this.releaseBackgroundLease(lease)
      }
    }
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
    if (this.shouldSniff7sefunOriginalPage(playerUrl)) {
      logger.info('7sefun player url requires original page sniffing: %{public}s',
        playerUrl.substring(0, 100))
      return url
    }
    return playerUrl
  }

  private tryBuild7sefunDirectResult(url: string, ruleSource: RuleSource | null,
    startTimeMs: number = this.resolveStartTime): VideoSourceResult | null {
    if (ruleSource === null || ruleSource.name.toLowerCase() !== '7sefun') {
      return null
    }
    const type = SnifferResult.detectType(url)
    if (type !== 'm3u8' && type !== 'mp4' && type !== 'flv' && type !== 'ts') {
      return null
    }
    if (this.shouldSniff7sefunOriginalPage(url)) {
      logger.info('7sefun direct media ignored, fallback to WebView sniffing: %{public}s',
        url.substring(0, 100))
      return null
    }
    const elapsed = Date.now() - startTimeMs
    logger.info('7sefun direct media url resolved without WebView sniffing: %{public}s',
      url.substring(0, 100))
    const candidate = new SnifferResult(url, type, 'unknown', '7sefun_player_config')
    candidate.score = 120
    return VideoSourceResult.success(url, type, [candidate], elapsed)
  }

  private async tryResolveTvTFunApiResult(url: string, ruleSource: RuleSource | null, request: VideoSourceRequest,
    startTimeMs: number = this.resolveStartTime): Promise<VideoSourceResult | null> {
    if (ruleSource === null || ruleSource.name.toLowerCase() !== 'tvtfun') {
      return null
    }
    if (url.indexOf('https://www.tvtfun.net/api/videos/resolve-play-url?') !== 0) {
      return null
    }
    try {
      const headers: Record<string, string> = {}
      headers['Accept'] = 'application/json,text/plain,*/*'
      headers['Accept-Encoding'] = 'identity'
      headers['Referer'] = request.episodeUrl.indexOf('/api/videos/resolve-play-url?') >= 0
        ? 'https://www.tvtfun.net/'
        : request.episodeUrl
      headers['User-Agent'] = request.userAgent.length > 0 ? request.userAgent : DEFAULT_PLAYER_USER_AGENT
      const client = new HttpClient()
      const response = await client.get(url, headers)
      if (!response.isSuccessful || response.body.length === 0) {
        logger.warn('TvTFun resolve-play-url failed: status=%{public}d body=%{public}s',
          response.statusCode, response.body.substring(0, Math.min(120, response.body.length)))
        return null
      }
      const parsed = JSON.parse(response.body) as Record<string, Object>
      const mediaUrl = this.extractTvTFunMediaUrl(parsed)
      if (mediaUrl.length === 0) {
        logger.warn('TvTFun resolve-play-url returned no media url')
        return null
      }
      const type = SnifferResult.detectType(mediaUrl)
      if (!this.isDirectPlayableType(type)) {
        logger.warn('TvTFun resolved url is not playable type=%{public}s url=%{public}s',
          type, mediaUrl.substring(0, 100))
        return null
      }
      const elapsed = Date.now() - startTimeMs
      logger.info('TvTFun API resolved media without WebView: %{public}s', mediaUrl.substring(0, 100))
      const candidate = new SnifferResult(mediaUrl, type, 'unknown', 'tvtfun_resolve_api')
      candidate.score = 150
      return VideoSourceResult.success(mediaUrl, type, [candidate], elapsed)
    } catch (err) {
      logger.warn('TvTFun resolve-play-url exception: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  private extractTvTFunMediaUrl(parsed: Record<string, Object>): string {
    const data = parsed['data']
    if (data === undefined || data === null || Array.isArray(data) || typeof data !== 'object') {
      return ''
    }
    const dataRecord = data as Record<string, Object>
    const rawUrl = dataRecord['url']
    if (typeof rawUrl !== 'string') {
      return ''
    }
    return rawUrl as string
  }

  private shouldSniff7sefunOriginalPage(url: string): boolean {
    const lowerUrl = url.toLowerCase()
    return lowerUrl.indexOf('jxdunrui.top') !== -1 || lowerUrl.indexOf('mao6.') !== -1
  }

  private tryBuildDirectMediaResult(url: string, startTimeMs: number = this.resolveStartTime): VideoSourceResult | null {
    const mediaUrl = this.extractDirectMediaUrl(url)
    if (mediaUrl.length === 0) {
      return null
    }
    const type = SnifferResult.detectType(mediaUrl)
    if (!this.isDirectPlayableType(type)) {
      return null
    }
    const elapsed = Date.now() - startTimeMs
    logger.info('direct media url resolved without WebView sniffing: %{public}s',
      mediaUrl.substring(0, 100))
    const candidate = new SnifferResult(mediaUrl, type, 'unknown', 'direct_url')
    candidate.score = 130
    return VideoSourceResult.success(mediaUrl, type, [candidate], elapsed)
  }

  private extractDirectMediaUrl(url: string): string {
    const decodedUrl = this.decodeUrlRepeated(url)
    if (this.isDirectPlayableUrl(decodedUrl)) {
      return decodedUrl
    }
    const rawQuery = this.extractQuery(url)
    const fromRawQuery = this.extractDirectMediaUrlFromQuery(rawQuery)
    if (fromRawQuery.length > 0) {
      return fromRawQuery
    }
    if (decodedUrl !== url) {
      return this.extractDirectMediaUrlFromQuery(this.extractQuery(decodedUrl))
    }
    return ''
  }

  private extractQuery(url: string): string {
    const queryIndex = url.indexOf('?')
    if (queryIndex < 0 || queryIndex === url.length - 1) {
      return ''
    }
    return url.substring(queryIndex + 1)
  }

  private extractDirectMediaUrlFromQuery(query: string): string {
    if (query.length === 0) {
      return ''
    }
    const params = query.split('&')
    const mediaKeys: string[] = ['url', 'play', 'src', 'video', 'videourl', 'file', 'm3u8', 'source']
    for (let i = 0; i < params.length; i++) {
      const pair = params[i]
      const eqIndex = pair.indexOf('=')
      if (eqIndex <= 0) {
        continue
      }
      const key = pair.substring(0, eqIndex).toLowerCase()
      if (mediaKeys.indexOf(key) < 0) {
        continue
      }
      const rawValue = pair.substring(eqIndex + 1)
      const value = this.decodeUrlRepeated(rawValue)
      const direct = this.findMediaUrlInValue(value)
      if (direct.length > 0) {
        return direct
      }
    }
    return ''
  }

  private findMediaUrlInValue(value: string): string {
    const candidates = value.split(',')
    for (let i = 0; i < candidates.length; i++) {
      const candidate = this.decodeUrlRepeated(candidates[i].trim())
      if (this.isDirectPlayableUrl(candidate)) {
        return candidate
      }
    }
    if (this.isDirectPlayableUrl(value)) {
      return value
    }
    return ''
  }

  private decodeUrlRepeated(value: string): string {
    let current = value
    for (let i = 0; i < 2; i++) {
      const replaced = current.replace(/\+/g, '%20')
      try {
        const decoded = decodeURIComponent(replaced)
        if (decoded === current || decoded === replaced) {
          current = decoded
          break
        }
        current = decoded
      } catch (_) {
        break
      }
    }
    return current
  }

  private isDirectPlayableUrl(url: string): boolean {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false
    }
    const cleanUrl = url.toLowerCase().split('?')[0].split('#')[0]
    return cleanUrl.indexOf('.m3u8') !== -1 || cleanUrl.indexOf('.mp4') !== -1 ||
      cleanUrl.indexOf('.flv') !== -1 || cleanUrl.indexOf('.ts') !== -1 ||
      cleanUrl.indexOf('.mknvideo') !== -1
  }

  private isDirectPlayableType(type: string): boolean {
    return type === 'm3u8' || type === 'mp4' || type === 'flv' || type === 'ts'
  }

  private async attachStreamMetadata(result: VideoSourceResult, request: VideoSourceRequest,
    mySession: number, myEpoch: number, workerId: number = 1): Promise<void> {
    if (result.videoType !== 'm3u8') {
      return
    }
    if (!this.isResolverSessionActive(mySession, myEpoch, workerId)) {
      return
    }
    const headers = this.buildMetadataProbeHeaders(result, request)
    try {
      const client = new HttpClient()
      const response = await client.get(result.videoUrl, headers)
      if (!this.isResolverSessionActive(mySession, myEpoch, workerId)) {
        return
      }
      if (!response.isSuccessful || response.body.length === 0) {
        this.emitLog(mySession, 'metadata', 'hls manifest fetch skipped status=' + String(response.statusCode))
        return
      }
      const metadata = this.hlsManifestParser.parse(response.body, result.videoUrl)
      result.streamMetadata = metadata
      this.emitLog(mySession, 'metadata', metadata.summary())
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.emitLog(mySession, 'metadata', 'hls manifest probe failed: ' + msg)
    }
  }

  private buildMetadataProbeHeaders(result: VideoSourceResult, request: VideoSourceRequest): Record<string, string> {
    const headers: Record<string, string> = {}
    const requestKeys = Object.keys(request.headers)
    for (let i = 0; i < requestKeys.length; i++) {
      headers[requestKeys[i]] = request.headers[requestKeys[i]]
    }
    if (request.referer.length > 0) {
      headers['Referer'] = request.referer
    }
    if (request.userAgent.length > 0) {
      headers['User-Agent'] = request.userAgent
    }

    let captured = this.findCapturedContext(result)
    if (captured !== null) {
      const ctxKeys = Object.keys(captured.headers)
      for (let i = 0; i < ctxKeys.length; i++) {
        if (headers[ctxKeys[i]] === undefined) {
          headers[ctxKeys[i]] = captured.headers[ctxKeys[i]]
        }
      }
      if (headers['Referer'] === undefined && captured.referer.length > 0) {
        headers['Referer'] = captured.referer
      }
      if (headers['Cookie'] === undefined && captured.cookies.length > 0) {
        headers['Cookie'] = captured.cookies
      }
      if (headers['User-Agent'] === undefined && captured.userAgent.length > 0) {
        headers['User-Agent'] = captured.userAgent
      }
    }
    if (headers['User-Agent'] === undefined) {
      headers['User-Agent'] = DEFAULT_PLAYER_USER_AGENT
    }
    headers['Accept'] = 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
    return headers
  }

  private findCapturedContext(result: VideoSourceResult): CapturedRequestContext | null {
    let bestContext: CapturedRequestContext | null = null
    let bestScore = -1
    for (let i = 0; i < result.candidates.length; i++) {
      const candidate = result.candidates[i]
      if (candidate.url !== result.videoUrl || candidate.context === null) {
        continue
      }
      const score = this.getContextScore(candidate.context)
      if (score > bestScore) {
        bestScore = score
        bestContext = candidate.context
      }
    }
    return bestContext
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
      return encodeURI(this.decodeUrlRepeated(percentEncoded))
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

  private releaseLease(lease: SnifferLease): void {
    const cleanupLevel = this.sessionPool.release(lease)
    this.applyWebViewCleanup(cleanupLevel, lease.workerId)
    this.sessionPool.resetForNextUse(cleanupLevel)
    const sniffer = this.getSnifferForLease(lease)
    if (sniffer.getIsSniffing()) {
      sniffer.cancel()
    } else {
      sniffer.reset()
    }
    if (this.currentLease !== null && this.currentLease.sessionId === lease.sessionId) {
      this.currentLease = null
    }
  }

  private releaseBackgroundLease(lease: SnifferLease): void {
    const cleanupLevel = this.sessionPool.releaseBackground(lease)
    this.applyWebViewCleanup(cleanupLevel, lease.workerId)
    this.sessionPool.resetForNextUse(cleanupLevel)
    const sniffer = this.getSnifferForLease(lease)
    if (sniffer.getIsSniffing()) {
      sniffer.cancel()
    } else {
      sniffer.reset()
    }
    if (this.backgroundLease !== null && this.backgroundLease.sessionId === lease.sessionId) {
      this.backgroundLease = null
    }
  }

  private cancelBackgroundPreparation(reason: string): void {
    if (this.backgroundLease === null && !this.isPreparingNext && !this.backgroundSniffer.getIsSniffing()) {
      return
    }
    const lease = this.backgroundLease
    this.activePrepareSessionId = 0
    this.isPreparingNext = false
    if (lease !== null) {
      this.sessionPool.cancelBackground(reason)
    }
    const cleanupLevel = reason === 'foreground_resolve' ? WebViewCleanupLevel.SOFT : WebViewCleanupLevel.FULL
    this.applyWebViewCleanup(cleanupLevel, lease === null ? 2 : lease.workerId)
    if (lease !== null) {
      this.sessionPool.resetForNextUse(cleanupLevel)
    }
    this.backgroundLease = null
    if (this.backgroundSniffer.getIsSniffing()) {
      this.backgroundSniffer.cancel()
    }
  }

  private isLeaseActiveById(sessionId: number): boolean {
    return this.sessionPool.isLeaseActive(sessionId) || this.sessionPool.isBackgroundLeaseActive(sessionId)
  }

  private isResolverSessionActive(sessionId: number, epoch: number, workerId: number): boolean {
    if (this.resolveEpoch !== epoch) {
      return false
    }
    if (workerId === 2) {
      return this.isPreparingNext && this.activePrepareSessionId === sessionId
    }
    return this.isResolving && this.activeSessionId === sessionId
  }

  private finishPrepareSession(sessionId: number): void {
    this.isPreparingNext = false
    if (this.activePrepareSessionId === sessionId) {
      this.activePrepareSessionId = 0
    }
  }

  private delayMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, ms)
    })
  }

  private getSnifferForLease(lease: SnifferLease): VideoSniffer {
    return lease.workerId === 2 ? this.backgroundSniffer : this.sniffer
  }

  private getSnifferForWorker(workerId: number): VideoSniffer {
    return workerId === 2 ? this.backgroundSniffer : this.sniffer
  }

  private doSniff(url: string, maxRetry: number, mySession: number, myEpoch: number,
    lease: SnifferLease, startTimeMs: number): Promise<VideoSourceResult> {
    return new Promise<VideoSourceResult>((resolve) => {
      const leaseId = lease.sessionId
      const workerId = lease.workerId
      const sniffer = this.getSnifferForLease(lease)
      let retryCount = 0
      let retryScheduled = false
      let settled = false
      const resolveOnce = (result: VideoSourceResult): void => {
        if (settled) {
          return
        }
        settled = true
        resolve(result)
      }
      const resolveCancelled = (): void => {
        resolveOnce(VideoSourceResult.cancelled(Date.now() - startTimeMs))
      }
      const isStillActive = (): boolean => {
        return this.isResolverSessionActive(mySession, myEpoch, workerId) &&
          this.isLeaseActiveById(leaseId)
      }

      sniffer.setResultCallback((result: SnifferResult) => {
        if (!isStillActive()) {
          resolveCancelled()
          return
        }
        logger.info('Sniffed: %{public}s [%{public}s/%{public}s] from %{public}s',
          result.url.substring(0, 80), result.type, result.quality, result.source)
        this.emitLog(mySession, 'candidate', result.type + ' ' + result.url.substring(0, 80))
      })

      sniffer.setCompleteCallback((results: SnifferResult[]) => {
        if (!isStillActive()) {
          resolveCancelled()
          return
        }
        if (retryScheduled) {
          logger.info('Sniff attempt completed during retry window, awaiting next attempt')
          return
        }
        const elapsed = Date.now() - startTimeMs
        const bestResult = this.selectBestResult(results)
        if (bestResult !== null) {
          const contextScore = this.getContextScore(bestResult.context)
          const headerCount = bestResult.context === null ? 0 : Object.keys(bestResult.context.headers).length
          logger.info('Selected sniff result: source=%{public}s score=%{public}d contextScore=%{public}d headers=%{public}d url=%{public}s',
            bestResult.source, bestResult.score, contextScore, headerCount, bestResult.url.substring(0, 120))
          resolveOnce(VideoSourceResult.success(bestResult.url, bestResult.type, results, elapsed))
        } else if (results.length > 0) {
          resolveOnce(VideoSourceResult.fail('未找到播放器支持的视频格式', retryCount, elapsed))
        } else {
          resolveOnce(VideoSourceResult.fail('未嗅探到视频流地址', retryCount, elapsed))
        }
      })

      sniffer.setErrorCallback((error: string) => {
        if (!isStillActive()) {
          resolveCancelled()
          return
        }
        const elapsed = Date.now() - startTimeMs
        logger.warn('Sniff error: %{public}s', error)
        if (retryCount < maxRetry) {
          retryCount++
          let delayMs = this.policy.calculateRetryDelay(retryCount)
          setTimeout(() => {
            if (!isStillActive()) {
              resolveCancelled()
              return
            }
            sniffer.sniff(url)
          }, delayMs)
        } else {
          resolveOnce(VideoSourceResult.fail(error, retryCount, elapsed))
        }
      })

      sniffer.setStatusCallback((status: string) => {
        if (!isStillActive()) {
          resolveCancelled()
          return
        }
        if (status === 'timeout') {
          const elapsed = Date.now() - startTimeMs
          if (retryCount < maxRetry) {
            retryCount++
            retryScheduled = true
            let delayMs = this.policy.calculateRetryDelay(retryCount)
            logger.info('Sniff timeout, retry %{public}d/%{public}d after %{public}dms',
              retryCount, maxRetry, delayMs)
            setTimeout(() => {
              retryScheduled = false
              if (!isStillActive()) {
                resolveCancelled()
                return
              }
              logger.info('Starting sniff retry %{public}d/%{public}d', retryCount, maxRetry)
              sniffer.sniff(url)
            }, delayMs)
          } else {
            resolveOnce(VideoSourceResult.timeout(retryCount, elapsed))
          }
        }
      })

      sniffer.sniff(url)
    })
  }

  private selectBestResult(results: SnifferResult[]): SnifferResult | null {
    let bestDirect: SnifferResult | null = null
    let bestWeak: SnifferResult | null = null
    for (let i = 0; i < results.length; i++) {
      const r = results[i]
      if (!this.isSupportedPlayableResult(r)) {
        continue
      }
      if (this.ruleEvaluator.isWeakWrapperUrl(r.url)) {
        if (bestWeak === null || this.isBetterPlayableResult(r, bestWeak)) {
          bestWeak = r
        }
      } else if (bestDirect === null || this.isBetterPlayableResult(r, bestDirect)) {
        bestDirect = r
      }
    }
    if (bestDirect !== null) {
      return bestDirect
    }
    if (bestWeak !== null) {
      return bestWeak
    }
    let fallback: SnifferResult | null = null
    for (let i = 0; i < results.length; i++) {
      const r = results[i]
      if ((r.type === 'blob' || r.type === 'unknown') && !this.isExplicitlyUnsupportedUrl(r.url)) {
        if (fallback === null || r.score > fallback.score) {
          fallback = r
        }
      }
    }
    return fallback
  }

  private isSupportedPlayableResult(result: SnifferResult): boolean {
    if (result.type === 'range_video') {
      return true
    }
    let protocol = ''
    if (result.type === 'm3u8') {
      protocol = '.m3u8'
    } else if (result.type === 'mp4') {
      protocol = '.mp4'
    } else if (result.type === 'flv') {
      protocol = '.flv'
    } else if (result.type === 'ts') {
      protocol = '.ts'
    } else {
      return false
    }
    return this.ruleEvaluator.evaluateProtocolCapability(protocol).supported
  }

  private isBetterPlayableResult(candidate: SnifferResult, current: SnifferResult): boolean {
    if (candidate.url === current.url) {
      const candidateContextScore = this.getContextScore(candidate.context)
      const currentContextScore = this.getContextScore(current.context)
      if (candidateContextScore !== currentContextScore) {
        return candidateContextScore > currentContextScore
      }
    }
    const candidatePriority = this.getProtocolPriority(candidate.type)
    const currentPriority = this.getProtocolPriority(current.type)
    if (candidatePriority !== currentPriority) {
      return candidatePriority > currentPriority
    }
    if (candidate.score !== current.score) {
      return candidate.score > current.score
    }
    return candidate.timestamp < current.timestamp
  }

  private getContextScore(context: CapturedRequestContext | null): number {
    if (context === null) {
      return 0
    }
    let score = Object.keys(context.headers).length * 2
    if (context.cookies.length > 0) {
      score += 8
    }
    if (context.referer.length > 0) {
      score += 4
    }
    if (context.userAgent.length > 0) {
      score += 2
    }
    if (context.hasRangeHeader) {
      score += 2
    }
    return score
  }

  private getProtocolPriority(type: string): number {
    if (type === 'm3u8') {
      return 500
    }
    if (type === 'mp4') {
      return 400
    }
    if (type === 'flv') {
      return 300
    }
    if (type === 'range_video') {
      return 200
    }
    if (type === 'ts') {
      return 100
    }
    return 0
  }

  private isExplicitlyUnsupportedUrl(url: string): boolean {
    const lowerUrl = url.toLowerCase().split('?')[0].split('#')[0]
    if (this.ruleEvaluator.shouldBlockSniffing(url)) {
      return true
    }
    return lowerUrl.endsWith('.mpd')
  }

  private applyRuleSourceToResult(result: VideoSourceResult, rule: RuleSource): VideoSourceResult {
    if (rule.antiCrawlerConfig.enabled && rule.antiCrawlerConfig.captchaType > 0) {
      logger.info('Rule source has anti-crawler config: captchaType=%{public}d', rule.antiCrawlerConfig.captchaType)
    }
    return result
  }

  handleInterceptedRequest(url: string, headers: Record<string, string> = {}, workerId: number = 1): void {
    if (workerId === 1) {
      if (!this.isResolving || this.currentLease === null ||
        !this.sessionPool.isLeaseActive(this.currentLease.sessionId)) {
        return
      }
    } else {
      if (!this.isPreparingNext || this.backgroundLease === null ||
        !this.sessionPool.isBackgroundLeaseActive(this.backgroundLease.sessionId)) {
        return
      }
    }
    logger.debug('handleInterceptedRequest worker=%{public}d: %{public}s', workerId, url.substring(0, 100))
    this.getSnifferForWorker(workerId).handleInterceptedRequest(url, headers)
  }

  onWebViewPageBegin(workerId: number = 1): void {
    if (workerId === 1) {
      if (!this.isResolving || this.currentLease === null ||
        !this.sessionPool.isLeaseActive(this.currentLease.sessionId)) {
        return
      }
    } else {
      if (!this.isPreparingNext || this.backgroundLease === null ||
        !this.sessionPool.isBackgroundLeaseActive(this.backgroundLease.sessionId)) {
        return
      }
    }
    logger.debug('onWebViewPageBegin worker=%{public}d', workerId)
    this.getSnifferForWorker(workerId).onPageBegin()
  }

  onWebViewPageEnd(workerId: number = 1): void {
    if (workerId === 1) {
      if (!this.isResolving || this.currentLease === null ||
        !this.sessionPool.isLeaseActive(this.currentLease.sessionId)) {
        return
      }
    } else {
      if (!this.isPreparingNext || this.backgroundLease === null ||
        !this.sessionPool.isBackgroundLeaseActive(this.backgroundLease.sessionId)) {
        return
      }
    }
    logger.debug('onWebViewPageEnd worker=%{public}d', workerId)
    this.getSnifferForWorker(workerId).onPageEnd()
  }

  handleJsBridgeMessage(message: string, workerId: number = 1): void {
    if (workerId === 1) {
      if (!this.isResolving || this.currentLease === null ||
        !this.sessionPool.isLeaseActive(this.currentLease.sessionId)) {
        return
      }
    } else {
      if (!this.isPreparingNext || this.backgroundLease === null ||
        !this.sessionPool.isBackgroundLeaseActive(this.backgroundLease.sessionId)) {
        return
      }
    }
    logger.debug('handleJsBridgeMessage worker=%{public}d: %{public}s', workerId, message.substring(0, 120))
    this.getSnifferForWorker(workerId).handleJsBridgeMessage(message)
  }

  buildPlaybackOptions(result: VideoSourceResult, request: VideoSourceRequest): PlaybackOptions {
    const options = new PlaybackOptions()
    options.url = result.videoUrl
    options.startPositionMs = 0
    options.streamMetadata = result.streamMetadata

    if (request.referer.length > 0) {
      options.referer = request.referer
    }
    if (request.userAgent.length > 0) {
      options.userAgent = request.userAgent
    }

    let headerKeys = Object.keys(request.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      let key = headerKeys[i]
      this.setPlaybackHttpHeader(options.headers, key, request.headers[key])
    }

    let capturedContext: CapturedRequestContext | null = this.findCapturedContext(result)
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
        this.setPlaybackHttpHeader(options.headers, key, capturedContext.headers[key])
      }
      if (capturedContext.cookies.length > 0) {
        let existingCookie = this.getPlaybackHttpHeader(options.headers, 'Cookie')
        if (existingCookie !== undefined && existingCookie.length > 0) {
          let merged = this.mergeCookieStrings(existingCookie, capturedContext.cookies)
          options.headers['Cookie'] = merged
        } else {
          options.headers['Cookie'] = capturedContext.cookies
        }
      }
    }

    return options
  }

  private setPlaybackHttpHeader(headers: Record<string, string>, key: string, value: string): void {
    const canonicalKey = this.canonicalPlaybackHttpHeader(key)
    if (canonicalKey.length === 0) {
      return
    }
    const safeValue = this.sanitizePlaybackHttpHeaderValue(value)
    if (safeValue.length === 0) {
      return
    }
    const existingKey = this.findPlaybackHttpHeaderKey(headers, canonicalKey)
    if (existingKey.length > 0) {
      return
    }
    headers[canonicalKey] = safeValue
  }

  private getPlaybackHttpHeader(headers: Record<string, string>, key: string): string {
    const existingKey = this.findPlaybackHttpHeaderKey(headers, key)
    if (existingKey.length === 0) {
      return ''
    }
    return headers[existingKey]
  }

  private findPlaybackHttpHeaderKey(headers: Record<string, string>, key: string): string {
    const target = key.toLowerCase()
    const keys = Object.keys(headers)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === target) {
        return keys[i]
      }
    }
    return ''
  }

  private removePlaybackHttpHeader(headers: Record<string, string>, key: string): Record<string, string> {
    const target = key.toLowerCase()
    const next: Record<string, string> = {}
    const keys = Object.keys(headers)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() !== target) {
        next[keys[i]] = headers[keys[i]]
      }
    }
    return next
  }

  private canonicalPlaybackHttpHeader(key: string): string {
    const lowerKey = key.trim().toLowerCase()
    switch (lowerKey) {
      case 'cookie':
        return 'Cookie'
      case 'origin':
        return 'Origin'
      case 'accept':
        return 'Accept'
      case 'referer':
      case 'referrer':
        return 'Referer'
      case 'user-agent':
        return 'User-Agent'
      default:
        return ''
    }
  }

  private sanitizePlaybackHttpHeaderValue(value: string): string {
    const trimmed = value.trim()
    if (trimmed.length === 0) {
      return ''
    }
    if (trimmed.indexOf('\r') >= 0 || trimmed.indexOf('\n') >= 0 || trimmed.indexOf(',') >= 0) {
      return ''
    }
    return trimmed
  }

  private mergeCookieStrings(existing: string, captured: string): string {
    let cookieMap: Map<string, string> = new Map()
    let parseCookies = (cookieStr: string) => {
      let pairs = cookieStr.split(';')
      for (let i = 0; i < pairs.length; i++) {
        let pair = pairs[i].trim()
        if (pair.length === 0) {
          continue
        }
        let eqIdx = pair.indexOf('=')
        if (eqIdx > 0) {
          let name = pair.substring(0, eqIdx).trim()
          let value = pair.substring(eqIdx + 1).trim()
          cookieMap.set(name, value)
        }
      }
    }
    parseCookies(existing)
    parseCookies(captured)
    let parts: string[] = []
    cookieMap.forEach((value: string, key: string) => {
      parts.push(key + '=' + value)
    })
    return parts.join('; ')
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
          const fallbackReferer = this.build7sefunPlaybackReferer(result.videoUrl, request.episodeUrl)
          if (this.shouldOverride7sefunReferer(result.videoUrl) || options.referer.length === 0) {
            options.referer = fallbackReferer
          }
          if (options.userAgent.length === 0) {
            options.userAgent = DEFAULT_PLAYER_USER_AGENT
          }
          const existingReferer = this.findPlaybackHttpHeaderKey(options.headers, 'Referer')
          if (options.referer.length > 0) {
            if (existingReferer.length === 0 || this.shouldOverride7sefunReferer(result.videoUrl)) {
              if (existingReferer.length > 0 && existingReferer !== 'Referer') {
                options.headers = this.removePlaybackHttpHeader(options.headers, existingReferer)
              }
              options.headers['Referer'] = options.referer
            }
          } else if (this.shouldOverride7sefunReferer(result.videoUrl) && existingReferer.length > 0) {
            options.headers = this.removePlaybackHttpHeader(options.headers, existingReferer)
          }
          if (options.userAgent.length > 0) {
            options.headers['User-Agent'] = options.userAgent
          }
          options.headers['Accept'] = '*/*'
          logger.info('7sefun playback headers: referer=%{public}s, url=%{public}s',
            options.referer.length > 0 ? options.referer : '<empty>',
            result.videoUrl.substring(0, 80))
        } else if (rule.name.toLowerCase() === 'tvtfun') {
          if (options.referer.length === 0) {
            options.referer = 'https://www.tvtfun.net/'
          }
          if (options.userAgent.length === 0) {
            options.userAgent = DEFAULT_PLAYER_USER_AGENT
          }
          options.headers['Referer'] = options.referer
          options.headers['User-Agent'] = options.userAgent
          options.headers['Accept'] = '*/*'
          logger.info('TvTFun playback headers applied: url=%{public}s', result.videoUrl.substring(0, 80))
        }
      }
    }
    if (options.userAgent.length === 0) {
      options.userAgent = DEFAULT_PLAYER_USER_AGENT
    }

    // groupvideo.photo.qq.com rejects the page Referer with HTTP 404 even though
    // the same signed media URL is playable without that header. Keep this
    // workaround scoped to that host so other rule sources retain their headers.
    this.clearRefererForGroupVideo(options, result.videoUrl)

    return options
  }

  private clearRefererForGroupVideo(options: PlaybackOptions, videoUrl: string): void {
    const lowerUrl = videoUrl.toLowerCase()
    const isGroupVideo = lowerUrl.startsWith('https://groupvideo.photo.qq.com/') ||
      lowerUrl.startsWith('http://groupvideo.photo.qq.com/')
    if (!isGroupVideo) {
      return
    }
    options.referer = ''
    const refererKey = this.findPlaybackHttpHeaderKey(options.headers, 'Referer')
    if (refererKey.length > 0) {
      options.headers = this.removePlaybackHttpHeader(options.headers, refererKey)
    }
    logger.info('Scoped playback workaround: cleared Referer for groupvideo media URL')
  }

  private shouldOverride7sefunReferer(videoUrl: string): boolean {
    const lowerUrl = videoUrl.toLowerCase()
    return lowerUrl.indexOf('groupvideo.photo.qq.com') !== -1 || lowerUrl.indexOf('lmm85.com') !== -1
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
    this.resolveEpoch++
    this.isResolving = false
    if (this.currentLease !== null) {
      this.sessionPool.cancelActive('user_cancel')
      const cleanupLevel = WebViewCleanupLevel.FULL
      this.applyWebViewCleanup(cleanupLevel, this.currentLease.workerId)
      this.sessionPool.resetForNextUse(cleanupLevel)
      this.currentLease = null
    }
    if (this.backgroundLease !== null) {
      this.cancelBackgroundPreparation('user_cancel')
    }
    this.sniffer.cancel()
  }

  private applyWebViewCleanup(cleanupLevel: WebViewCleanupLevel, workerId: number = 1): void {
    const controller = workerId === 2 ? this.backgroundWebController : this.webController
    if (controller === null) {
      return
    }
    if (cleanupLevel === WebViewCleanupLevel.NONE) {
      logger.debug('applyWebViewCleanup: no cleanup, reusing state worker=%{public}d', workerId)
      return
    }
    try {
      controller.loadUrl('about:blank')
    } catch (e) {
      logger.warn('applyWebViewCleanup loadUrl blank failed: %{public}s', String(e))
    }
    if (cleanupLevel === WebViewCleanupLevel.FULL) {
      try {
        controller.stop()
      } catch (e) {
      }
      try {
        webview.WebCookieManager.clearAllCookiesSync()
      } catch (e) {
      }
      logger.info('applyWebViewCleanup: full cleanup done worker=%{public}d (cleared cookies, stopped WebView)', workerId)
    } else {
      logger.info('applyWebViewCleanup: soft cleanup done worker=%{public}d (about:blank, cookies preserved)', workerId)
    }
  }

  getIsResolving(): boolean {
    return this.isResolving
  }

  getIsPreparingNext(): boolean {
    return this.isPreparingNext
  }
}
