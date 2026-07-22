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
    if (this.isAudioRequest(url, headers)) {
      return false
    }
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
    if (this.urlFilter.isVideoUrl(url)) {
      return true
    }
    return this.detectTypeFromContentType(url, headers).length > 0
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
    let lowerUrl = url.toLowerCase()
    if (this.isAudioRequest(lowerUrl, headers)) {
      return 'unknown'
    }
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
    const contentTypeResult = this.detectTypeFromContentType(url, headers)
    if (contentTypeResult.length > 0) {
      return contentTypeResult
    }
    if (this.ruleEvaluator.evaluateRangeRequest(url, headers).isRangeVideo) {
      return 'range_video'
    }
    if (this.urlFilter.isVideoUrl(url)) {
      return 'mp4'
    }
    return 'unknown'
  }

  private detectTypeFromContentType(url: string, headers: Record<string, string>): string {
    const contentType = this.getHeaderIgnoreCase(headers, 'content-type').toLowerCase()
    if (contentType.length === 0 || !this.isHttpUrl(url) || this.isClearlyNonMediaUrl(url)) {
      return ''
    }
    if (contentType.indexOf('audio/') === 0 || this.urlFilter.isAudioUrl(url)) {
      return ''
    }
    if (contentType.indexOf('mpegurl') !== -1) {
      return 'm3u8'
    }
    if (contentType.indexOf('video/mp2t') !== -1) {
      return 'ts'
    }
    if (contentType.indexOf('video/flv') !== -1 || contentType.indexOf('video/x-flv') !== -1) {
      return 'flv'
    }
    if (contentType.indexOf('video/mp4') !== -1) {
      return 'mp4'
    }
    if (contentType.indexOf('video/') !== -1) {
      return 'mp4'
    }
    if (contentType.indexOf('application/octet-stream') !== -1 && this.urlFilter.isVideoUrl(url)) {
      const detected = this.detectType(url, {})
      return detected === 'unknown' ? 'mp4' : detected
    }
    return ''
  }

  private isAudioRequest(url: string, headers: Record<string, string>): boolean {
    if (this.urlFilter.isAudioUrl(url)) {
      return true
    }
    const contentType = this.getHeaderIgnoreCase(headers, 'content-type').toLowerCase()
    if (contentType.indexOf('audio/') === 0) {
      return true
    }
    const fetchDestination = this.getHeaderIgnoreCase(headers, 'sec-fetch-dest').toLowerCase()
    return fetchDestination === 'audio'
  }

  private getHeaderIgnoreCase(headers: Record<string, string>, name: string): string {
    const keys = Object.keys(headers)
    const target = name.toLowerCase()
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === target) {
        return headers[keys[i]]
      }
    }
    return ''
  }

  private isHttpUrl(url: string): boolean {
    const lowerUrl = url.toLowerCase()
    return lowerUrl.startsWith('http://') || lowerUrl.startsWith('https://')
  }

  private isClearlyNonMediaUrl(url: string): boolean {
    const cleanUrl = url.toLowerCase().split('?')[0].split('#')[0]
    const nonMediaExtensions: string[] = [
      '.js', '.css', '.html', '.htm', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg',
      '.ico', '.woff', '.woff2', '.ttf', '.otf', '.json', '.xml', '.txt', '.key'
    ]
    for (let i = 0; i < nonMediaExtensions.length; i++) {
      if (cleanUrl.endsWith(nonMediaExtensions[i])) {
        return true
      }
    }
    return false
  }

  getInterceptedUrls(): string[] {
    return this.interceptedUrls.slice()
  }

  reset(): void {
    this.interceptedUrls = []
  }
}
