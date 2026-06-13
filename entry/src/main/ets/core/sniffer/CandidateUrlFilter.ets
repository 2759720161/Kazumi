import { SnifferResult } from './SnifferResult'

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

const VIDEO_EXTENSIONS: string[] = ['.m3u8', '.mp4', '.flv', '.ts', '.m4v', '.webm']

const NON_MEDIA_EXTENSIONS: string[] = [
  '.js', '.css', '.html', '.htm', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg',
  '.ico', '.woff', '.woff2', '.ttf', '.otf', '.json'
]

const MEDIA_URL_HINTS: string[] = [
  '://v16', '://v26', '://v3', '://v6', '://v9',
  '/video/tos/',
  'videocdn', 'video-cdn', 'mcdn', 'bytecdntp'
]

export class CandidateUrlFilter {
  private seenUrls: Set<string> = new Set()

  isVideoUrl(url: string): boolean {
    let lowerUrl = url.toLowerCase()
    for (let i = 0; i < VIDEO_EXTENSIONS.length; i++) {
      if (lowerUrl.indexOf(VIDEO_EXTENSIONS[i]) !== -1) {
        return true
      }
    }
    if (lowerUrl.indexOf('m3u8') !== -1 || lowerUrl.indexOf('mp4') !== -1) {
      return true
    }
    return this.isLikelyExtensionlessMediaUrl(lowerUrl)
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
      return null
    }
    if (this.isAdUrl(url)) {
      return null
    }
    if (!this.isVideoUrl(url)) {
      return null
    }
    if (this.seenUrls.has(url)) {
      return null
    }
    this.seenUrls.add(url)
    let type = SnifferResult.detectType(url)
    if (type === 'unknown' && this.isLikelyExtensionlessMediaUrl(url.toLowerCase())) {
      type = 'mp4'
    }
    let quality = this.guessQuality(url)
    return new SnifferResult(url, type, quality, source)
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
