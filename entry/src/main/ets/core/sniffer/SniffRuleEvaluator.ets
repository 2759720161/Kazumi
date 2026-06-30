import { SniffRule, WeakCandidateVerdict, PromotePageVerdict, FilterVerdict, ProtocolCapability, ScoringModifier } from './SniffRule'
import { NetworkPolicy } from './NetworkPolicy'

export class SniffRuleEvaluator {
  private rules: SniffRule[] = []

  constructor() {
    this.initializeBuiltinRules()
  }

  private initializeBuiltinRules(): void {
    const builtin: SniffRule[] = [
      {
        name: 'm3u8_wrapper', category: 'weak_candidate', ruleType: 'url_pattern',
        patterns: ['/m3u8/?url=', '/m3u8?url='],
        action: 'delay', actionParams: { 'delayMs': String(NetworkPolicy.WEAK_CANDIDATE_DELAY_MS) },
        priority: 10, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'moedot_wrapper', category: 'weak_candidate', ruleType: 'domain_match',
        patterns: ['player.moedot.net/player/'],
        action: 'delay', actionParams: { 'delayMs': String(NetworkPolicy.WEAK_CANDIDATE_DELAY_MS) },
        priority: 10, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'jx_prefix', category: 'weak_candidate', ruleType: 'domain_match',
        patterns: ['://jx.', '//jx.'],
        action: 'delay', actionParams: { 'delayMs': String(NetworkPolicy.WEAK_CANDIDATE_DELAY_MS) },
        priority: 10, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'cycanime_promote', category: 'promote_page', ruleType: 'domain_match',
        patterns: ['player.cycanime.com/?url='],
        action: 'promote', actionParams: {},
        priority: 20, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'ad_domain_reject', category: 'filter', ruleType: 'domain_match',
        patterns: ['doubleclick.net', 'googleadservices.com', 'googlesyndication.com',
          'adnxs.com', 'adsrvr.org', 'pagead2.googlesyndication.com'],
        action: 'reject', actionParams: { 'reason': 'ad_domain' },
        priority: 30, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'blob_score_penalty', category: 'scoring', ruleType: 'url_pattern',
        patterns: ['blob:'],
        action: 'score_penalty', actionParams: { 'scoreDelta': '-40' },
        priority: 5, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'protocol_hls', category: 'protocol', ruleType: 'extension_match',
        patterns: ['.m3u8'],
        action: 'mark_supported', actionParams: {},
        priority: 0, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'protocol_mp4', category: 'protocol', ruleType: 'extension_match',
        patterns: ['.mp4'],
        action: 'mark_supported', actionParams: {},
        priority: 0, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'protocol_flv', category: 'protocol', ruleType: 'extension_match',
        patterns: ['.flv'],
        action: 'mark_supported', actionParams: {},
        priority: 0, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'protocol_ts', category: 'protocol', ruleType: 'extension_match',
        patterns: ['.ts'],
        action: 'mark_supported', actionParams: {},
        priority: 0, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'protocol_dash', category: 'protocol', ruleType: 'extension_match',
        patterns: ['.mpd'],
        action: 'mark_unsupported', actionParams: { 'message': 'DASH not natively supported' },
        priority: 0, enabled: true, sourceTag: 'builtin'
      },
      {
        name: 'protocol_rtmp', category: 'protocol', ruleType: 'url_pattern',
        patterns: ['rtmp://'],
        action: 'mark_unsupported', actionParams: { 'message': 'RTMP not supported' },
        priority: 0, enabled: true, sourceTag: 'builtin'
      }
    ]
    this.rules = builtin
  }

  getRules(): SniffRule[] {
    return this.rules.slice()
  }

  getRulesByCategory(category: string): SniffRule[] {
    const result: SniffRule[] = []
    for (let i = 0; i < this.rules.length; i++) {
      if (this.rules[i].enabled && this.rules[i].category === category) {
        result.push(this.rules[i])
      }
    }
    result.sort((a, b) => b.priority - a.priority)
    return result
  }

  evaluateWeakCandidate(url: string): WeakCandidateVerdict {
    const verdict = new WeakCandidateVerdict()
    const rules = this.getRulesByCategory('weak_candidate')
    const lowerUrl = url.toLowerCase()
    for (let i = 0; i < rules.length; i++) {
      if (this.matchRule(rules[i], lowerUrl)) {
        verdict.isWeak = true
        verdict.matchedRuleName = rules[i].name
        const delayStr = rules[i].actionParams['delayMs']
        if (delayStr !== undefined && delayStr.length > 0) {
          verdict.delayMs = parseInt(delayStr, 10)
          if (isNaN(verdict.delayMs)) {
            verdict.delayMs = NetworkPolicy.WEAK_CANDIDATE_DELAY_MS
          }
        } else {
          verdict.delayMs = NetworkPolicy.WEAK_CANDIDATE_DELAY_MS
        }
        return verdict
      }
    }
    return verdict
  }

  evaluatePromotePage(url: string): PromotePageVerdict {
    const verdict = new PromotePageVerdict()
    const rules = this.getRulesByCategory('promote_page')
    const lowerUrl = url.toLowerCase()
    for (let i = 0; i < rules.length; i++) {
      if (this.matchRule(rules[i], lowerUrl)) {
        verdict.shouldPromote = true
        verdict.matchedRuleName = rules[i].name
        return verdict
      }
    }
    return verdict
  }

  evaluateUrlFilter(url: string, _type: string): FilterVerdict {
    const verdict = new FilterVerdict()
    const rules = this.getRulesByCategory('filter')
    const lowerUrl = url.toLowerCase()
    for (let i = 0; i < rules.length; i++) {
      if (this.matchRule(rules[i], lowerUrl)) {
        verdict.shouldReject = rules[i].action === 'reject'
        verdict.rejectReason = rules[i].actionParams['reason'] || ''
        verdict.matchedRuleName = rules[i].name
        return verdict
      }
    }
    return verdict
  }

  evaluateProtocolCapability(extension: string): ProtocolCapability {
    const cap = new ProtocolCapability()
    const rules = this.getRulesByCategory('protocol')
    const lowerExt = extension.toLowerCase()
    for (let i = 0; i < rules.length; i++) {
      if (this.matchRule(rules[i], lowerExt)) {
        cap.protocol = extension
        if (rules[i].action === 'mark_supported') {
          cap.supported = true
          cap.message = ''
        } else if (rules[i].action === 'mark_unsupported') {
          cap.supported = false
          cap.message = rules[i].actionParams['message'] || 'Not supported'
        }
        return cap
      }
    }
    cap.protocol = extension
    cap.supported = false
    cap.message = 'Unknown protocol'
    return cap
  }

  getScoringModifiers(url: string, _type: string): ScoringModifier[] {
    const modifiers: ScoringModifier[] = []
    const rules = this.getRulesByCategory('scoring')
    const lowerUrl = url.toLowerCase()
    for (let i = 0; i < rules.length; i++) {
      if (this.matchRule(rules[i], lowerUrl)) {
        const deltaStr = rules[i].actionParams['scoreDelta']
        if (deltaStr !== undefined && deltaStr.length > 0) {
          const delta = parseInt(deltaStr, 10)
          if (!isNaN(delta)) {
            const mod = new ScoringModifier()
            mod.ruleName = rules[i].name
            mod.scoreDelta = delta
            modifiers.push(mod)
          }
        }
      }
    }
    return modifiers
  }

  isWeakWrapperUrl(url: string): boolean {
    const rules = this.getRulesByCategory('weak_candidate')
    const lowerUrl = url.toLowerCase()
    for (let i = 0; i < rules.length; i++) {
      if (this.matchRule(rules[i], lowerUrl)) {
        return true
      }
    }
    return false
  }

  shouldBlockSniffing(url: string): boolean {
    const lowerUrl = url.toLowerCase()
    if (lowerUrl.indexOf('rtmp://') !== -1) {
      return true
    }
    return false
  }

  private matchRule(rule: SniffRule, lowerTarget: string): boolean {
    for (let i = 0; i < rule.patterns.length; i++) {
      const pattern = rule.patterns[i].toLowerCase()
      if (rule.ruleType === 'extension_match') {
        const cleanTarget = lowerTarget.split('?')[0].split('#')[0]
        if (cleanTarget.endsWith(pattern)) {
          return true
        }
      } else {
        if (lowerTarget.indexOf(pattern) !== -1) {
          return true
        }
      }
    }
    return false
  }
}
