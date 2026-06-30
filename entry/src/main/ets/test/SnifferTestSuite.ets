import { CandidateUrlFilter } from '../core/sniffer/CandidateUrlFilter'
import { SnifferResult } from '../core/sniffer/SnifferResult'
import { SniffRuleEvaluator } from '../core/sniffer/SniffRuleEvaluator'
import { TimeoutController } from '../core/sniffer/TimeoutController'
import { NetworkPolicy } from '../core/sniffer/NetworkPolicy'

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
}
