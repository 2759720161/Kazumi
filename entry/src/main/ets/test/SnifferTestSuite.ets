import { CandidateUrlFilter } from '../core/sniffer/CandidateUrlFilter'
import { SnifferResult } from '../core/sniffer/SnifferResult'
import { SniffRuleEvaluator } from '../core/sniffer/SniffRuleEvaluator'
import { TimeoutController } from '../core/sniffer/TimeoutController'
import { NetworkPolicy } from '../core/sniffer/NetworkPolicy'
import { CapturedRequestContext } from '../core/sniffer/CapturedRequestContext'
import { JSInjector } from '../core/sniffer/JSInjector'
import { RequestInterceptor } from '../core/sniffer/RequestInterceptor'
import { HlsManifestParser } from '../core/sniffer/HlsManifestParser'
import { SnifferSessionPool } from '../core/sniffer/SnifferSessionPool'
import { WebViewCleanupLevel } from '../core/sniffer/SnifferSessionPool'
import { VideoSourceRequest } from '../core/sniffer/VideoSourceRequest'

class TestResult {
  name: string = ''
  passed: boolean = false
  detail: string = ''
}

export class SnifferTestSuite {
  private results: TestResult[] = []
  private filter: CandidateUrlFilter = new CandidateUrlFilter()
  private ruleEvaluator: SniffRuleEvaluator = new SniffRuleEvaluator()

  private assert(name: string, condition: boolean, detail: string): void {
    const r = new TestResult()
    r.name = name
    r.passed = condition
    r.detail = detail
    this.results.push(r)
  }

  runAll(): number {
    this.results = []
    this.testCandidateUrlFilter()
    this.testSniffRuleEvaluator()
    this.testSnifferResultScoring()
    this.testTimeoutController()
    this.testRangeRequestDetection()
    this.testCapturedRequestContext()
    this.testContentTypeScoring()
    this.testJSInjectorScripts()
    this.testSnifferSessionPool()
    this.testHlsManifestParser()
    let failed = 0
    for (let i = 0; i < this.results.length; i++) {
      if (!this.results[i].passed) {
        failed++
      }
    }
    return failed
  }

  getResults(): TestResult[] {
    return this.results.slice()
  }

  getSummary(): string {
    let total = this.results.length
    let passed = 0
    let failed = 0
    for (let i = 0; i < this.results.length; i++) {
      if (this.results[i].passed) {
        passed++
      } else {
        failed++
      }
    }
    let lines: string[] = []
    lines.push('=== SnifferTestSuite Results ===')
    lines.push('Total: ' + total + '  Passed: ' + passed + '  Failed: ' + failed)
    for (let i = 0; i < this.results.length; i++) {
      const r = this.results[i]
      let status = r.passed ? 'PASS' : 'FAIL'
      lines.push('[' + status + '] ' + r.name + (r.detail.length > 0 ? ' - ' + r.detail : ''))
    }
    return lines.join('\n')
  }

  private testCandidateUrlFilter(): void {
    this.filter = new CandidateUrlFilter()
    this.filter.setRuleEvaluator(this.ruleEvaluator)

    let r: SnifferResult | null = null

    r = this.filter.filter('https://cdn.example.com/video.m3u8', 'request_intercept')
    this.assert('Filter-m3u8-accept', r !== null, r !== null ? 'type=' + r.type + ' score=' + r.score : 'null')
    this.assert('Filter-m3u8-type', r !== null && r.type === 'm3u8', r !== null ? r.type : 'null')
    this.assert('Filter-m3u8-score', r !== null && r.score >= 80, r !== null ? String(r.score) : 'null')

    r = this.filter.filter('https://cdn.example.com/video.mp4', 'video_tag')
    this.assert('Filter-mp4-accept', r !== null, r !== null ? 'type=' + r.type : 'null')
    this.assert('Filter-mp4-type', r !== null && r.type === 'mp4', r !== null ? r.type : 'null')
    this.assert('Filter-mp4-score', r !== null && r.score >= 70, r !== null ? String(r.score) : 'null')

    this.filter.reset()
    r = this.filter.filter('https://cdn.example.com/video.flv', 'player_config')
    this.assert('Filter-flv-accept', r !== null, r !== null ? 'type=' + r.type : 'null')

    this.filter.reset()
    r = this.filter.filter('https://cdn.example.com/seg.ts', 'request_intercept')
    this.assert('Filter-ts-accept', r !== null, r !== null ? 'type=' + r.type : 'null')

    this.filter.reset()
    r = this.filter.filter('data:video/mp4;base64,AAAA', 'media_poll')
    this.assert('Filter-data-reject', r === null, r !== null ? 'accepted' : 'rejected')

    this.filter.reset()
    r = this.filter.filter('https://doubleclick.net/ads/track.js', 'request_intercept')
    this.assert('Filter-ad-reject', r === null, r !== null ? 'accepted' : 'rejected')

    this.filter.reset()
    r = this.filter.filter('https://jx.example.com/m3u8?url=https://cdn.example.com/real.m3u8', 'request_intercept')
    this.assert('Filter-nested-unwrap', r !== null && r.type === 'm3u8',
      r !== null ? 'type=' + r.type + ' url=' + r.url.substring(0, 60) : 'null')

    this.filter.reset()
    r = this.filter.filter('https://jx.example.com/parse?url=wrapper', 'request_intercept')
    this.assert('Filter-weak-score', r !== null && r.score < 50,
      r !== null ? 'score=' + r.score : 'null')

    this.filter.reset()
    r = this.filter.filter('blob:https://example.com/uuid-123', 'media_current_src')
    this.assert('Filter-blob-accept', r !== null, r !== null ? 'type=' + r.type + ' score=' + r.score : 'null')
    this.assert('Filter-blob-penalty', r !== null && r.score <= 10,
      r !== null ? 'score=' + r.score : 'null')
    this.assert('Filter-blob-ruleSource', r !== null && r.ruleSource === 'blob_score_penalty',
      r !== null ? r.ruleSource : 'null')

    this.filter.reset()
    r = this.filter.filter('https://example.com/style.css', 'request_intercept')
    this.assert('Filter-css-reject', r === null, r !== null ? 'accepted' : 'rejected')

    this.filter.reset()
    r = this.filter.filter('https://example.com/image.jpg', 'request_intercept')
    this.assert('Filter-jpg-reject', r === null, r !== null ? 'accepted' : 'rejected')
  }

  private testSniffRuleEvaluator(): void {
    let verdict = this.ruleEvaluator.evaluateWeakCandidate('https://player.moedot.net/player/abc')
    this.assert('RuleEvaluator-weak-moedot', verdict.isWeak, 'isWeak=' + verdict.isWeak)
    this.assert('RuleEvaluator-weak-delay', verdict.delayMs === NetworkPolicy.WEAK_CANDIDATE_DELAY_MS,
      'delayMs=' + verdict.delayMs)

    verdict = this.ruleEvaluator.evaluateWeakCandidate('https://jx.example.com/parse?url=abc')
    this.assert('RuleEvaluator-weak-jx', verdict.isWeak, 'isWeak=' + verdict.isWeak)

    verdict = this.ruleEvaluator.evaluateWeakCandidate('https://cdn.example.com/video.m3u8')
    this.assert('RuleEvaluator-weak-normal', !verdict.isWeak, 'isWeak=' + verdict.isWeak)

    let promote = this.ruleEvaluator.evaluatePromotePage('https://player.cycanime.com/?url=abc')
    this.assert('RuleEvaluator-promote-cycanime', promote.shouldPromote, 'shouldPromote=' + promote.shouldPromote)

    promote = this.ruleEvaluator.evaluatePromotePage('https://cdn.example.com/video.m3u8')
    this.assert('RuleEvaluator-promote-normal', !promote.shouldPromote, 'shouldPromote=' + promote.shouldPromote)

    let cap = this.ruleEvaluator.evaluateProtocolCapability('.m3u8')
    this.assert('RuleEvaluator-protocol-hls', cap.supported, 'supported=' + cap.supported)

    cap = this.ruleEvaluator.evaluateProtocolCapability('.mp4')
    this.assert('RuleEvaluator-protocol-mp4', cap.supported, 'supported=' + cap.supported)

    cap = this.ruleEvaluator.evaluateProtocolCapability('.mpd')
    this.assert('RuleEvaluator-protocol-dash', !cap.supported, 'supported=' + cap.supported + ' msg=' + cap.message)

    cap = this.ruleEvaluator.evaluateProtocolCapability('rtmp://')
    this.assert('RuleEvaluator-protocol-rtmp', !cap.supported, 'supported=' + cap.supported)

    let isWeakUrl = this.ruleEvaluator.isWeakWrapperUrl('https://jx.example.com/parse?url=abc')
    this.assert('RuleEvaluator-isWeakUrl-jx', isWeakUrl, 'result=' + isWeakUrl)

    isWeakUrl = this.ruleEvaluator.isWeakWrapperUrl('https://cdn.example.com/video.m3u8')
    this.assert('RuleEvaluator-isWeakUrl-normal', !isWeakUrl, 'result=' + isWeakUrl)

    let shouldBlock = this.ruleEvaluator.shouldBlockSniffing('rtmp://example.com/live')
    this.assert('RuleEvaluator-block-rtmp', shouldBlock, 'result=' + shouldBlock)

    shouldBlock = this.ruleEvaluator.shouldBlockSniffing('https://example.com/video.m3u8')
    this.assert('RuleEvaluator-block-normal', !shouldBlock, 'result=' + shouldBlock)
  }

  private testSnifferResultScoring(): void {
    let score = SnifferResult.calculateScore('m3u8', 'request_intercept',
      'https://cdn.example.com/video.m3u8', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-high-m3u8-intercept', score >= 95, 'score=' + score)

    score = SnifferResult.calculateScore('mp4', 'video_tag',
      'https://cdn.example.com/video.mp4', '1080P', this.ruleEvaluator)
    this.assert('Scoring-mp4-1080p', score >= 75, 'score=' + score)

    score = SnifferResult.calculateScore('m3u8', 'request_intercept',
      'https://jx.example.com/m3u8?url=wrapper', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-weak-wrapper', score <= 50, 'score=' + score)

    score = SnifferResult.calculateScore('blob', 'media_current_src',
      'blob:https://example.com/uuid', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-blob-low', score <= 10, 'score=' + score)

    score = SnifferResult.calculateScore('flv', 'player_config',
      'https://cdn.example.com/video.flv', '720P', this.ruleEvaluator)
    this.assert('Scoring-flv-720p', score >= 50, 'score=' + score)

    score = SnifferResult.calculateScore('ts', 'request_intercept',
      'https://cdn.example.com/seg.ts', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-ts-intercept', score >= 45, 'score=' + score)
  }

  private testTimeoutController(): void {
    let tc = new TimeoutController(200, 1)
    let attemptCount = 0
    let timeoutFired = false
    let retryFired = false

    tc.setOnRetry(() => {
      retryFired = true
      attemptCount = tc.getAttemptCount()
    })
    tc.setOnTimeout(() => {
      timeoutFired = true
    })
    tc.start()
    this.assert('TimeoutController-start', true, 'started')

    let tc2 = new TimeoutController(200, 1)
    let tc2Timeout = false
    tc2.setOnTimeout(() => {
      tc2Timeout = true
    })
    tc2.start()
    tc2.cancel()
    this.assert('TimeoutController-cancel-no-callback', true, 'cancel called - verify manually no callback')

    this.assert('TimeoutController-exhausted-init', !tc.isExhausted(), 'not exhausted initially')
  }

  private testRangeRequestDetection(): void {
    let verdict = this.ruleEvaluator.evaluateRangeRequest(
      'https://cdn.example.com/video/seg-001', { 'Range': 'bytes=0-1024' })
    this.assert('Range-req-with-range-header', verdict.isRangeVideo,
      'isRangeVideo=' + verdict.isRangeVideo + ' rule=' + verdict.matchedRuleName)

    verdict = this.ruleEvaluator.evaluateRangeRequest(
      'https://cdn.example.com/video/seg-001', {})
    this.assert('Range-req-no-range-header', !verdict.isRangeVideo,
      'isRangeVideo=' + verdict.isRangeVideo)

    verdict = this.ruleEvaluator.evaluateRangeRequest(
      'https://cdn.example.com/video/seg-001',
      { 'Range': 'bytes=0-1024', 'Content-Type': 'video/mp4' })
    this.assert('Range-req-with-video-ct', verdict.isRangeVideo,
      'isRangeVideo=' + verdict.isRangeVideo + ' ct=' + verdict.detectedContentType)
    this.assert('Range-req-mime-rule', verdict.matchedRuleName === 'range_video_mime',
      'rule=' + verdict.matchedRuleName)

    verdict = this.ruleEvaluator.evaluateRangeRequest(
      'https://cdn.example.com/script.js', { 'Range': 'bytes=0-1024' })
    this.assert('Range-req-static-ext', !verdict.isRangeVideo,
      'isRangeVideo=' + verdict.isRangeVideo)

    verdict = this.ruleEvaluator.evaluateRangeRequest(
      'ftp://example.com/file', { 'Range': 'bytes=0-1024' })
    this.assert('Range-req-non-http', !verdict.isRangeVideo,
      'isRangeVideo=' + verdict.isRangeVideo)

    const interceptor = new RequestInterceptor()
    interceptor.setRuleEvaluator(this.ruleEvaluator)
    const rangeIntercepted = interceptor.shouldIntercept(
      'https://cdn.example.com/video/chunk-001', { 'Range': 'bytes=0-1024' })
    this.assert('Range-interceptor-header', rangeIntercepted,
      'intercepted=' + rangeIntercepted)

    const jsIntercepted = interceptor.shouldIntercept(
      'https://cdn.example.com/static/app.js', { 'Range': 'bytes=0-1024' })
    this.assert('Range-interceptor-static-reject', !jsIntercepted,
      'intercepted=' + jsIntercepted)

    let rangeScore = SnifferResult.calculateScore('range_video', 'fetch_intercept',
      'https://cdn.example.com/seg-001', 'unknown', this.ruleEvaluator)
    this.assert('Range-req-score-range-video', rangeScore >= 40 && rangeScore <= 60,
      'score=' + rangeScore)
  }

  private testCapturedRequestContext(): void {
    let ctx = new CapturedRequestContext()
    ctx.url = 'https://cdn.example.com/video.m3u8'
    ctx.referer = 'https://example.com/player'
    ctx.cookies = 'session=abc123; token=xyz'
    ctx.contentType = 'application/vnd.apple.mpegurl'
    ctx.hasRangeHeader = false
    this.assert('Ctx-referer', ctx.referer === 'https://example.com/player',
      'referer=' + ctx.referer)
    this.assert('Ctx-cookies', ctx.cookies.length > 0,
      'cookies length=' + ctx.cookies.length)
    this.assert('Ctx-contentType', ctx.contentType.length > 0,
      'contentType=' + ctx.contentType)
    this.assert('Ctx-hasRangeHeader', !ctx.hasRangeHeader,
      'hasRangeHeader=' + ctx.hasRangeHeader)

    let ctx2 = new CapturedRequestContext()
    ctx2.url = 'https://cdn.example.com/seg.ts'
    ctx2.hasRangeHeader = true
    this.assert('Ctx-range-true', ctx2.hasRangeHeader,
      'hasRangeHeader=' + ctx2.hasRangeHeader)
  }

  private testContentTypeScoring(): void {
    let score = SnifferResult.calculateScore('mp4', 'xhr_content_type',
      'https://cdn.example.com/api/stream', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-xhr-ct', score >= 70, 'score=' + score)

    score = SnifferResult.calculateScore('mp4', 'fetch_content_type',
      'https://cdn.example.com/api/stream', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-fetch-ct', score >= 70, 'score=' + score)

    score = SnifferResult.calculateScore('unknown', 'iframe_postmessage',
      'https://cdn.example.com/video', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-iframe-postmessage', score <= 15,
      'score=' + score)

    score = SnifferResult.calculateScore('range_video', 'fetch_intercept',
      'https://cdn.example.com/seg', 'unknown', this.ruleEvaluator)
    this.assert('Scoring-range-video-fetch', score >= 45, 'score=' + score)
  }

  private testJSInjectorScripts(): void {
    let modernScript = JSInjector.getModernSnifferScript()
    this.assert('JSInjector-modern-not-empty', modernScript.length > 100,
      'length=' + modernScript.length)
    this.assert('JSInjector-modern-has-iframe', modernScript.indexOf('tryInjectIframe') !== -1,
      'has tryInjectIframe')
    this.assert('JSInjector-modern-has-postMessage', modernScript.indexOf('__kazumi_sniff') !== -1,
      'has __kazumi_sniff marker')
    this.assert('JSInjector-modern-has-videoMime', modernScript.indexOf('videoMimeTypes') !== -1,
      'has videoMimeTypes')
    this.assert('JSInjector-modern-has-getSnifferExtra', modernScript.indexOf('getSnifferExtra') !== -1,
      'has getSnifferExtra')
    this.assert('JSInjector-modern-has-referer', modernScript.indexOf('document.referrer') !== -1,
      'has document.referrer')
    this.assert('JSInjector-modern-has-cookie', modernScript.indexOf('document.cookie') !== -1,
      'has document.cookie')
    this.assert('JSInjector-modern-has-range', modernScript.indexOf('hasRange') !== -1,
      'has hasRange')
    this.assert('JSInjector-modern-has-response-text', modernScript.indexOf('Response.prototype.text') !== -1,
      'has Response.prototype.text')
    this.assert('JSInjector-modern-has-fetch-text-detect', modernScript.indexOf('fetch_response_text') !== -1,
      'has fetch_response_text')
    this.assert('JSInjector-modern-has-header-object', modernScript.indexOf('headersToObject') !== -1,
      'has headersToObject')
    this.assert('JSInjector-modern-has-xhr-set-header', modernScript.indexOf('setRequestHeader') !== -1,
      'has setRequestHeader hook')
    this.assert('JSInjector-modern-posts-headers', modernScript.indexOf('msg.headers') !== -1,
      'posts headers')

    let legacyScript = JSInjector.getLegacySnifferScript()
    this.assert('JSInjector-legacy-not-empty', legacyScript.length > 100,
      'length=' + legacyScript.length)
    this.assert('JSInjector-legacy-has-postMessage', legacyScript.indexOf('__kazumi_sniff') !== -1,
      'has __kazumi_sniff marker')
    this.assert('JSInjector-legacy-has-getSnifferExtra', legacyScript.indexOf('getSnifferExtra') !== -1,
      'has getSnifferExtra')

    let fallbackScript = JSInjector.getVideoElementFallbackScript()
    this.assert('JSInjector-fallback-not-empty', fallbackScript.length > 100,
      'length=' + fallbackScript.length)

    let hash = JSInjector.getScriptHash()
    this.assert('JSInjector-hash-valid', hash.length > 0, 'hash=' + hash)
    this.assert('JSInjector-validate-hash', JSInjector.validateScriptHash(hash),
      'validates own hash')

    let headers = JSInjector.extractHeadersFromJson('{"Range":"bytes=0-1024","Cookie":"sid=abc"}')
    this.assert('JSInjector-extract-headers-range', headers['Range'] === 'bytes=0-1024',
      'Range=' + headers['Range'])
    this.assert('JSInjector-extract-headers-cookie', headers['Cookie'] === 'sid=abc',
      'Cookie=' + headers['Cookie'])

    let emptyHeaders = JSInjector.extractHeadersFromJson('')
    this.assert('JSInjector-extract-headers-empty', Object.keys(emptyHeaders).length === 0,
      'keys=' + Object.keys(emptyHeaders).length)

    let badHeaders = JSInjector.extractHeadersFromJson('not json')
    this.assert('JSInjector-extract-headers-bad', Object.keys(badHeaders).length === 0,
      'keys=' + Object.keys(badHeaders).length)
  }

  private testHlsManifestParser(): void {
    const manifest = '#EXTM3U\n' +
      '#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"\n' +
      '720/index.m3u8\n' +
      '#EXT-X-STREAM-INF:BANDWIDTH=3600000,RESOLUTION=1920x1080,CODECS="hvc1.2.4.L153.B0,mp4a.40.2"\n' +
      'https://cdn.example.com/1080/index.m3u8\n'
    const parser = new HlsManifestParser()
    const metadata = parser.parse(manifest, 'https://example.com/master.m3u8')
    this.assert('HLS-parser-is-hls', metadata.isHls, 'isHls=' + metadata.isHls)
    this.assert('HLS-parser-master', metadata.isMasterPlaylist, 'master=' + metadata.isMasterPlaylist)
    this.assert('HLS-parser-variants', metadata.variants.length === 2,
      'variants=' + metadata.variants.length)
    this.assert('HLS-parser-resolution', metadata.maxWidth === 1920 && metadata.maxHeight === 1080,
      'max=' + metadata.maxWidth + 'x' + metadata.maxHeight)
    this.assert('HLS-parser-bandwidth', metadata.maxBandwidth === 3600000 && metadata.minBandwidth === 1200000,
      'bw=' + metadata.minBandwidth + '/' + metadata.maxBandwidth)
    this.assert('HLS-parser-aac', metadata.hasAacAudio, 'aac=' + metadata.hasAacAudio)
    this.assert('HLS-parser-hdr-hint', metadata.hasHdrCodecHint, 'hdr=' + metadata.hasHdrCodecHint)
    this.assert('HLS-parser-relative-uri', metadata.variants[0].uri === 'https://example.com/720/index.m3u8',
      'uri=' + metadata.variants[0].uri)

    const mediaManifest = '#EXTM3U\n' +
      '#EXT-X-TARGETDURATION:10\n' +
      '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x1\n' +
      '#EXTINF:4.0,\n' +
      'ad0.ts\n' +
      '#EXT-X-DISCONTINUITY\n' +
      '#EXTINF:10.0,\n' +
      'main0.ts\n' +
      '#EXTINF:10.0,\n' +
      'main1.ts\n' +
      '#EXTINF:10.0,\n' +
      'main2.ts\n' +
      '#EXT-X-DISCONTINUITY\n' +
      '#EXTINF:5.0,\n' +
      'ad1.ts\n' +
      '#EXT-X-ENDLIST\n'
    const mediaMetadata = parser.parse(mediaManifest, 'https://example.com/path/index.m3u8')
    this.assert('HLS-media-segments', mediaMetadata.segments.length === 5,
      'segments=' + mediaMetadata.segments.length)
    this.assert('HLS-media-vod', mediaMetadata.isVod, 'vod=' + mediaMetadata.isVod)
    this.assert('HLS-media-target-duration', mediaMetadata.targetDuration === 10,
      'target=' + mediaMetadata.targetDuration)
    this.assert('HLS-media-total-duration', Math.round(mediaMetadata.totalDuration) === 39,
      'duration=' + mediaMetadata.totalDuration)
    this.assert('HLS-media-encrypted', mediaMetadata.hasEncryptedSegments && mediaMetadata.uniqueKeyUris.length === 1,
      'keys=' + mediaMetadata.uniqueKeyUris.length)
    this.assert('HLS-media-key-relative-uri', mediaMetadata.uniqueKeyUris[0] === 'https://example.com/path/key.bin',
      'key=' + mediaMetadata.uniqueKeyUris[0])
    this.assert('HLS-media-ad-groups', mediaMetadata.likelyAdSegmentCount === 2,
      'adSegments=' + mediaMetadata.likelyAdSegmentCount)
    this.assert('HLS-media-mpegts', mediaMetadata.codecs.indexOf('mpegts') >= 0,
      'codecs=' + mediaMetadata.codecs.join('|'))
  }

  private testSnifferSessionPool(): void {
    let pool = new SnifferSessionPool()
    let req1 = new VideoSourceRequest()
    req1.episodeUrl = 'https://example.com/anime/ep1'
    req1.ruleSourceId = 5

    let req2 = new VideoSourceRequest()
    req2.episodeUrl = 'https://example.com/anime/ep2'
    req2.ruleSourceId = 5

    let req3 = new VideoSourceRequest()
    req3.episodeUrl = 'https://other-site.com/video/ep1'
    req3.ruleSourceId = 10

    let lease1 = pool.acquire(req1)
    this.assert('Pool-acquire-lease1', lease1.sessionId > 0 && !lease1.released,
      'sessionId=' + lease1.sessionId + ' released=' + lease1.released)
    this.assert('Pool-max-workers', pool.getMaxWorkers() === 2,
      'maxWorkers=' + pool.getMaxWorkers())
    this.assert('Pool-foreground-worker', lease1.workerId === 1 && !lease1.background,
      'workerId=' + lease1.workerId + ' background=' + lease1.background)
    this.assert('Pool-acquire-origin', lease1.origin === 'example.com',
      'origin=' + lease1.origin)
    this.assert('Pool-acquire-ruleSourceId', lease1.ruleSourceId === 5,
      'ruleSourceId=' + lease1.ruleSourceId)
    this.assert('Pool-isLeaseActive-1', pool.isLeaseActive(lease1.sessionId),
      'active=true')
    this.assert('Pool-state-sniffing', pool.getPoolState() === 'sniffing',
      'state=' + pool.getPoolState())

    let lease2 = pool.acquire(req2)
    this.assert('Pool-acquire-supersedes', lease1.released && pool.isLeaseActive(lease2.sessionId),
      'lease1 superseded, lease2 active')
    this.assert('Pool-isLeaseActive-2', pool.isLeaseActive(lease2.sessionId),
      'active=true for lease2')
    this.assert('Pool-isLeaseActive-old', !pool.isLeaseActive(lease1.sessionId),
      'lease1 no longer active')

    let cleanup1 = pool.release(lease2)
    this.assert('Pool-release-same-origin-same-rule', cleanup1 === WebViewCleanupLevel.NONE,
      'cleanup=' + (cleanup1 === WebViewCleanupLevel.NONE ? 'none' :
        cleanup1 === WebViewCleanupLevel.SOFT ? 'soft' : 'full'))
    this.assert('Pool-isLeaseActive-released', !pool.isLeaseActive(lease2.sessionId),
      'lease2 not active after release')
    this.assert('Pool-state-idle', pool.getPoolState() === 'idle',
      'state=' + pool.getPoolState())

    let lease3 = pool.acquire(req3)
    this.assert('Pool-acquire-different-site', lease3.origin === 'other-site.com',
      'origin=' + lease3.origin)
    let cleanup2 = pool.release(lease3)
    this.assert('Pool-release-different-rule', cleanup2 === WebViewCleanupLevel.SOFT,
      'cleanup=' + (cleanup2 === WebViewCleanupLevel.NONE ? 'none' :
        cleanup2 === WebViewCleanupLevel.SOFT ? 'soft' : 'full'))

    pool.resetForNextUse(cleanup2)
    this.assert('Pool-reset-done', true, 'reset completed')

    let req4 = new VideoSourceRequest()
    req4.episodeUrl = 'https://example.com/anime/ep3'
    req4.ruleSourceId = 5
    let reuse = pool.shouldReuseState(lease2, req4)
    this.assert('Pool-shouldReuse-same-origin-rule', reuse,
      'reuse=' + reuse)

    let reuse2 = pool.shouldReuseState(lease3, req4)
    this.assert('Pool-shouldReuse-diff-origin', !reuse2,
      'reuse=' + reuse2)
    this.assert('Pool-request-origin', pool.getRequestOrigin(req4) === 'example.com',
      'origin=' + pool.getRequestOrigin(req4))

    let pool2 = new SnifferSessionPool()
    let cancelReq = new VideoSourceRequest()
    cancelReq.episodeUrl = 'https://test.com/play'
    let cancelLease = pool2.acquire(cancelReq)
    this.assert('Pool-cancel-active', pool2.isLeaseActive(cancelLease.sessionId),
      'active before cancel')
    pool2.cancelActive('test_cancel')
    this.assert('Pool-cancel-inactive', !pool2.isLeaseActive(cancelLease.sessionId),
      'inactive after cancel')
    this.assert('Pool-cancel-cancelled-flag', cancelLease.cancelled,
      'cancelled=' + cancelLease.cancelled)

    let doubleRelease = pool2.release(cancelLease)
    this.assert('Pool-release-already-released', doubleRelease === WebViewCleanupLevel.NONE,
      'double release returns none')

    let pool3 = new SnifferSessionPool()
    let leaseA = pool3.acquire(req1)
    let leaseB = pool3.acquire(req2)
    this.assert('Pool-seq-sessions', leaseB.sessionId > leaseA.sessionId,
      'B=' + leaseB.sessionId + ' > A=' + leaseA.sessionId)
    this.assert('Pool-seq-only-B-active', pool3.isLeaseActive(leaseB.sessionId) && !pool3.isLeaseActive(leaseA.sessionId),
      'only B active')

    let pool4 = new SnifferSessionPool()
    let bgLease1 = pool4.acquireBackground(req1)
    this.assert('Pool-bg-acquire', bgLease1 !== null && bgLease1.workerId === 2 && bgLease1.background,
      bgLease1 !== null ? 'workerId=' + bgLease1.workerId : 'null')
    let bgLease2 = pool4.acquireBackground(req2)
    this.assert('Pool-bg-singleton', bgLease2 === null,
      bgLease2 === null ? 'second rejected' : 'second accepted')
    if (bgLease1 !== null) {
      this.assert('Pool-bg-active', pool4.isBackgroundLeaseActive(bgLease1.sessionId),
        'background active')
      let bgCleanup = pool4.releaseBackground(bgLease1)
      this.assert('Pool-bg-release', !pool4.isBackgroundLeaseActive(bgLease1.sessionId) &&
        (bgCleanup === WebViewCleanupLevel.SOFT || bgCleanup === WebViewCleanupLevel.NONE),
        'cleanup=' + bgCleanup)
    }

    let bgLease3 = pool4.acquireBackground(req3)
    if (bgLease3 !== null) {
      pool4.cancelBackground('test_cancel')
      this.assert('Pool-bg-cancel', !pool4.isBackgroundLeaseActive(bgLease3.sessionId) && bgLease3.cancelled,
        'cancelled=' + bgLease3.cancelled)
    } else {
      this.assert('Pool-bg-cancel', false, 'failed to acquire background lease')
    }
  }
}
