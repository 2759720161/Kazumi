import { CandidateUrlFilter } from './CandidateUrlFilter'
import { SniffRuleEvaluator } from './SniffRuleEvaluator'

export class RequestInterceptor {
  private interceptedUrls: string[] = []
  private onIntercept: ((url: string, type: string, headers: Record<string, string>) => void) | null = null
  private urlFilter: CandidateUrlFilter = new CandidateUrlFilter()
  private ruleEvaluator: SniffRuleEvaluator = new SniffRuleEvaluator()

  setOnIntercept(callback: (url: string, type: string, headers: Record<string, string>) => void): void {
    this.onIntercept = callback
  }

  setRuleEvaluator(evaluator: SniffRuleEvaluator): void {
    this.ruleEvaluator = evaluator
    this.urlFilter.setRuleEvaluator(evaluator)
  }

  shouldIntercept(url: string, headers: Record<string, string> = {}): boolean {
    if (this.ruleEvaluator.evaluateRangeRequest(url, headers).isRangeVideo) {
      return true
    }
    let lowerUrl = url.toLowerCase()
    if (lowerUrl.indexOf('.m3u8') !== -1) {
      return true
    }
    if (lowerUrl.indexOf('.mp4') !== -1) {
      return true
    }
    if (lowerUrl.indexOf('.flv') !== -1) {
      return true
    }
    if (lowerUrl.indexOf('.ts') !== -1 && lowerUrl.indexOf('.ts/') === -1) {
      return true
    }
    return this.urlFilter.isVideoUrl(url)
  }

  interceptRequest(url: string, headers: Record<string, string> = {}): boolean {
    if (this.shouldIntercept(url, headers)) {
      if (this.interceptedUrls.indexOf(url) !== -1) {
        return false
      }
      this.interceptedUrls.push(url)
      if (this.onIntercept) {
        let type = this.detectType(url, headers)
        this.onIntercept(url, type, headers)
      }
      return true
    }
    return false
  }

  detectType(url: string, headers: Record<string, string> = {}): string {
    if (this.ruleEvaluator.evaluateRangeRequest(url, headers).isRangeVideo) {
      return 'range_video'
    }
    let lowerUrl = url.toLowerCase()
    if (lowerUrl.indexOf('.m3u8') !== -1 || lowerUrl.indexOf('m3u8') !== -1) {
      return 'm3u8'
    }
    if (lowerUrl.indexOf('.mp4') !== -1 || lowerUrl.indexOf('mp4') !== -1) {
      return 'mp4'
    }
    if (lowerUrl.indexOf('.flv') !== -1 || lowerUrl.indexOf('flv') !== -1) {
      return 'flv'
    }
    if (lowerUrl.indexOf('.ts') !== -1) {
      return 'ts'
    }
    if (this.urlFilter.isVideoUrl(url)) {
      return 'mp4'
    }
    return 'unknown'
  }

  getInterceptedUrls(): string[] {
    return this.interceptedUrls.slice()
  }

  reset(): void {
    this.interceptedUrls = []
  }
}
