import { CandidateUrlFilter } from './CandidateUrlFilter'
import { SniffRuleEvaluator } from './SniffRuleEvaluator'

// 视频 MIME 类型关键词列表，用于 Content-Type 兜底识别
const VIDEO_CONTENT_TYPE_HINTS: string[] = [
  'video/',
  'mpegurl',
  'application/x-mpegurl',
  'application/vnd.apple.mpegurl',
  'application/octet-stream;',
  'video/mp2t',
  'video/mp4',
  'video/webm',
  'video/x-flv',
  'video/flv'
]

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

  /**
   * 判断请求是否应被拦截为视频候选。
   * 优先级：
   *   1. Range 视频请求（由规则引擎判定）
   *   2. URL 后缀/关键词匹配
   *   3. 响应头 Content-Type 兜底（覆盖无特征 CDN URL）
   */
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
    if (this.hasVideoContentType(headers)) {
      return true
    }
    return this.urlFilter.isVideoUrl(url)
  }

  /**
   * 判断 headers 中的 Content-Type 是否为视频类型。
   * 用于兜底识别：无论 URL 特征如何，只要响应是视频就拦截。
   */
  private hasVideoContentType(headers: Record<string, string>): boolean {
    let contentType = ''
    // 大小写不敏感地查找 content-type
    const keys = Object.keys(headers)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === 'content-type') {
        contentType = headers[keys[i]].toLowerCase()
        break
      }
    }
    if (contentType.length === 0) {
      return false
    }
    for (let i = 0; i < VIDEO_CONTENT_TYPE_HINTS.length; i++) {
      if (contentType.indexOf(VIDEO_CONTENT_TYPE_HINTS[i].toLowerCase()) !== -1) {
        return true
      }
    }
    return false
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
    // Content-Type 兜底：根据响应头推断类型
    if (this.hasVideoContentType(headers)) {
      let contentType = ''
      const keys = Object.keys(headers)
      for (let i = 0; i < keys.length; i++) {
        if (keys[i].toLowerCase() === 'content-type') {
          contentType = headers[keys[i]].toLowerCase()
          break
        }
      }
      if (contentType.indexOf('mpegurl') !== -1) {
        return 'm3u8'
      }
      if (contentType.indexOf('mp2t') !== -1) {
        return 'ts'
      }
      if (contentType.indexOf('flv') !== -1) {
        return 'flv'
      }
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
