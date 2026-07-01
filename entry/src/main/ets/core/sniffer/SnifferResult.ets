import { CapturedRequestContext } from './CapturedRequestContext'
import { SniffRuleEvaluator } from './SniffRuleEvaluator'

const TYPE_BASE_SCORES: Record<string, number> = {
  'm3u8': 80, 'mp4': 70, 'flv': 50, 'ts': 30, 'range_video': 45, 'blob': 15, 'unknown': 10
}

const SOURCE_SCORE_DELTAS: Record<string, number> = {
  'request_intercept': 15, 'hls_load_source': 15, 'video_tag': 10,
  'player_config': 10, 'media_current_src': 8, 'mui_player_ctor': 5,
  'media_poll': 5, 'iframe_scan': -5, 'iframe_postmessage': -3,
  'video_src_setter': 10, 'initial_media_scan': 3, 'mutation_observer': 3,
  'xhr_intercept': 8, 'fetch_intercept': 8, 'xhr_content_type': 12,
  'fetch_content_type': 12, 'xhr_content_detect': 10,
  'video_content_type': 12, 'range_request': 5
}

const QUALITY_SCORE_DELTAS: Record<string, number> = {
  '1080P': 5, '720P': 3
}

export class SnifferResult {
  url: string = ''
  type: string = ''
  quality: string = ''
  source: string = ''
  timestamp: number = 0
  context: CapturedRequestContext | null = null
  ruleSource: string = ''
  score: number = 0

  constructor(url: string, type: string, quality: string, source: string) {
    this.url = url
    this.type = type
    this.quality = quality
    this.source = source
    this.timestamp = Date.now()
  }

  static detectType(url: string): string {
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
    if (lowerUrl.indexOf('.mknvideo') !== -1) {
      return 'mp4'
    }
    if (lowerUrl.indexOf('.ts') !== -1) {
      return 'ts'
    }
    if (SnifferResult.isLikelyExtensionlessMp4Url(lowerUrl)) {
      return 'mp4'
    }
    return 'unknown'
  }

  private static isLikelyExtensionlessMp4Url(lowerUrl: string): boolean {
    const mediaHints: string[] = [
      '://v16', '://v26', '://v3', '://v6', '://v9',
      '://lf', '://lf2', '://lf3', '://lf6', '://lf9', '://lf20',
      '://vkc', '://vkce', '://fev', '://febo',
      '/video/tos/',
      'videocdn', 'video-cdn', 'mcdn', 'bytecdntp',
      'bytetos.com', 'csp-sign', 'tos-cn-v-',
      'play.mknacg.top:9009/d/', 'tjdownload.pan.wo.cn', 'pan.wo.cn/openapi/download',
      '/openapi/download?fid=',
      '/videos/', '/videoplayback', '/videoplay',
      'cdnvideo', 'cdn-video', 'hlsvideo',
      'streaming', 'liveld'
    ]
    const nonMediaDomains: string[] = [
      'byteimg.com',
      'pstatp.com',
      'douyinpic.com',
      'snssdk.com'
    ]
    const nonMediaExtensions: string[] = [
      '.js', '.css', '.html', '.htm', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg',
      '.ico', '.woff', '.woff2', '.ttf', '.otf', '.json'
    ]
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      return false
    }
    for (let i = 0; i < nonMediaDomains.length; i++) {
      if (lowerUrl.indexOf(nonMediaDomains[i]) !== -1) {
        return false
      }
    }
    const cleanUrl = lowerUrl.split('?')[0].split('#')[0]
    for (let i = 0; i < nonMediaExtensions.length; i++) {
      if (cleanUrl.endsWith(nonMediaExtensions[i])) {
        return false
      }
    }
    for (let i = 0; i < mediaHints.length; i++) {
      if (lowerUrl.indexOf(mediaHints[i]) !== -1) {
        return true
      }
    }
    return false
  }

  toString(): string {
    return `[${this.type}] ${this.url} (${this.quality}) score=${this.score} from ${this.source}`
  }

  static calculateScore(type: string, source: string, url: string, quality: string,
    ruleEvaluator: SniffRuleEvaluator): number {
    let score = TYPE_BASE_SCORES[type] || 10

    const sourceDelta = SOURCE_SCORE_DELTAS[source]
    if (sourceDelta !== undefined) {
      score += sourceDelta
    }

    if (quality.length > 0) {
      const qualityDelta = QUALITY_SCORE_DELTAS[quality]
      if (qualityDelta !== undefined) {
        score += qualityDelta
      }
    }

    if (type === 'm3u8' || type === 'mp4' || type === 'flv' || type === 'ts' || type === 'range_video') {
      if (!ruleEvaluator.isWeakWrapperUrl(url)) {
        score += 10
      }
    }

    if (ruleEvaluator.isWeakWrapperUrl(url)) {
      score -= 30
    }

    const modifiers = ruleEvaluator.getScoringModifiers(url, type)
    for (let i = 0; i < modifiers.length; i++) {
      score += modifiers[i].scoreDelta
    }

    return score
  }
}
