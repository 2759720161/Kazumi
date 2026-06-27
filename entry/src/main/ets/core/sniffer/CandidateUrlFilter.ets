import { SnifferResult } from './SnifferResult'
import { Logger } from '../../utils/Logger'

const logger = new Logger('UrlFilter')

const AD_DOMAINS: string[] = [
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'adnxs.com',
  'adsrvr.org',
  'pagead2.googlesyndication.com',
  'analytics',
  'tracker',
  'pixel',
  'beacon'
]

const NON_MEDIA_DOMAINS: string[] = [
  'byteimg.com',
  'pstatp.com',
  'douyinpic.com',
  'snssdk.com'
]

const VIDEO_EXTENSIONS: string[] = ['.m3u8', '.mp4', '.flv', '.ts', '.m4v', '.webm', '.mknvideo']

const NON_MEDIA_EXTENSIONS: string[] = [
  '.js', '.css', '.html', '.htm', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg',
  '.ico', '.woff', '.woff2', '.ttf', '.otf', '.json'
]

const MEDIA_URL_HINTS: string[] = [
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
  'streaming', 'liveld',
  'cdn.vvvip'
]

export class CandidateUrlFilter {
  private seenUrls: Set<string> = new Set()

  isVideoUrl(url: string): boolean {
    let lowerUrl = url.toLowerCase()
    const cleanUrl = lowerUrl.split('?')[0].split('#')[0]
    for (let i = 0; i < NON_MEDIA_EXTENSIONS.length; i++) {
      if (cleanUrl.endsWith(NON_MEDIA_EXTENSIONS[i])) {
        return false
      }
    }
    for (let i = 0; i < VIDEO_EXTENSIONS.length; i++) {
      if (cleanUrl.indexOf(VIDEO_EXTENSIONS[i]) !== -1) {
        return true
      }
    }
    if (cleanUrl.indexOf('m3u8') !== -1 || cleanUrl.indexOf('mp4') !== -1) {
      return true
    }
    return this.isLikelyExtensionlessMediaUrl(lowerUrl)
  }

  isHttpVideoUrl(url: string): boolean {
    let lowerUrl = url.toLowerCase()
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      return false
    }
    if (lowerUrl.indexOf('blob:') !== -1) {
      return false
    }
    if (this.isAdUrl(url)) {
      return false
    }
    const cleanUrl = lowerUrl.split('?')[0].split('#')[0]
    for (let i = 0; i < NON_MEDIA_EXTENSIONS.length; i++) {
      if (cleanUrl.endsWith(NON_MEDIA_EXTENSIONS[i])) {
        return false
      }
    }
    return true
  }

  isAdUrl(url: string): boolean {
    let lowerUrl = url.toLowerCase()
    for (let i = 0; i < AD_DOMAINS.length; i++) {
      if (lowerUrl.indexOf(AD_DOMAINS[i]) !== -1) {
        return true
      }
    }
    return false
  }

  isDataOrBlobUrl(url: string): boolean {
    return url.indexOf('data:') === 0 || url.indexOf('blob:') === 0
  }

  filter(url: string, source: string): SnifferResult | null {
    if (this.isDataOrBlobUrl(url)) {
      logger.debug('filter REJECT blob/data: %{public}s', url.substring(0, 80))
      return null
    }
    const candidateUrl = this.extractNestedMediaUrl(url)
    if (candidateUrl !== url) {
      logger.info('filter UNWRAP nested media: %{public}s -> %{public}s',
        url.substring(0, 80), candidateUrl.substring(0, 80))
    }
    if (this.isAdUrl(candidateUrl)) {
      logger.debug('filter REJECT ad: %{public}s', candidateUrl.substring(0, 80))
      return null
    }
    if (!this.isVideoUrl(candidateUrl)) {
      logger.debug('filter REJECT not-video: %{public}s', candidateUrl.substring(0, 80))
      return null
    }
    if (this.seenUrls.has(candidateUrl)) {
      logger.debug('filter REJECT dup: %{public}s', candidateUrl.substring(0, 80))
      return null
    }
    this.seenUrls.add(candidateUrl)
    let type = SnifferResult.detectType(candidateUrl)
    if (type === 'unknown' && this.isLikelyExtensionlessMediaUrl(candidateUrl.toLowerCase())) {
      type = 'mp4'
    }
    let quality = this.guessQuality(candidateUrl)
    logger.info('filter ACCEPT [%{public}s] %{public}s from %{public}s', type, candidateUrl.substring(0, 80), source)
    return new SnifferResult(candidateUrl, type, quality, source)
  }

  filterVideoElementUrl(url: string, source: string): SnifferResult | null {
    const candidateUrl = this.extractNestedMediaUrl(url)
    if (candidateUrl !== url) {
      logger.info('videoElement UNWRAP nested media: %{public}s -> %{public}s',
        url.substring(0, 80), candidateUrl.substring(0, 80))
    }
    if (!this.isHttpVideoUrl(candidateUrl)) {
      logger.debug('videoElement REJECT not-http/ad: %{public}s', candidateUrl.substring(0, 80))
      return null
    }
    if (this.seenUrls.has(candidateUrl)) {
      logger.debug('videoElement REJECT dup: %{public}s', candidateUrl.substring(0, 80))
      return null
    }
    this.seenUrls.add(candidateUrl)
    let type = SnifferResult.detectType(candidateUrl)
    if (type === 'unknown') {
      type = 'mp4'
    }
    let quality = this.guessQuality(candidateUrl)
    logger.info('videoElement ACCEPT [%{public}s] %{public}s from %{public}s', type, candidateUrl.substring(0, 80), source)
    return new SnifferResult(candidateUrl, type, quality, source)
  }

  private extractNestedMediaUrl(url: string): string {
    const queryIndex = url.indexOf('?')
    if (queryIndex === -1) {
      return url
    }
    const query = url.substring(queryIndex + 1)
    const params = query.split('&')
    const keys: string[] = ['url=', 'play=', 'src=', 'video=', 'videourl=']
    for (let i = 0; i < params.length; i++) {
      const part = params[i]
      const lowerPart = part.toLowerCase()
      for (let j = 0; j < keys.length; j++) {
        if (lowerPart.startsWith(keys[j])) {
          const rawValue = part.substring(keys[j].length)
          const decoded = this.decodeUrlParam(rawValue)
          const nestedValues = decoded.split(',')
          for (let k = 0; k < nestedValues.length; k++) {
            const nestedValue = nestedValues[k].trim()
            if (this.isHttpVideoUrl(nestedValue) && this.isVideoUrl(nestedValue)) {
              return nestedValue
            }
          }
        }
      }
    }
    return url
  }

  private decodeUrlParam(value: string): string {
    let decoded = value.replace(/\+/g, '%20')
    for (let i = 0; i < 2; i++) {
      try {
        const next = decodeURIComponent(decoded)
        if (next === decoded) {
          break
        }
        decoded = next
      } catch (e) {
        break
      }
    }
    return decoded
  }

  private isLikelyExtensionlessMediaUrl(lowerUrl: string): boolean {
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      return false
    }
    for (let i = 0; i < NON_MEDIA_DOMAINS.length; i++) {
      if (lowerUrl.indexOf(NON_MEDIA_DOMAINS[i]) !== -1) {
        return false
      }
    }
    const cleanUrl = lowerUrl.split('?')[0].split('#')[0]
    for (let i = 0; i < NON_MEDIA_EXTENSIONS.length; i++) {
      if (cleanUrl.endsWith(NON_MEDIA_EXTENSIONS[i])) {
        return false
      }
    }
    for (let i = 0; i < MEDIA_URL_HINTS.length; i++) {
      if (lowerUrl.indexOf(MEDIA_URL_HINTS[i]) !== -1) {
        return true
      }
    }
    return false
  }

  private guessQuality(url: string): string {
    let lowerUrl = url.toLowerCase()
    if (lowerUrl.indexOf('1080') !== -1 || lowerUrl.indexOf('fhd') !== -1) {
      return '1080P'
    }
    if (lowerUrl.indexOf('720') !== -1 || lowerUrl.indexOf('hd') !== -1) {
      return '720P'
    }
    if (lowerUrl.indexOf('480') !== -1 || lowerUrl.indexOf('sd') !== -1) {
      return '480P'
    }
    if (lowerUrl.indexOf('360') !== -1) {
      return '360P'
    }
    return 'unknown'
  }

  reset(): void {
    this.seenUrls = new Set()
  }
}
