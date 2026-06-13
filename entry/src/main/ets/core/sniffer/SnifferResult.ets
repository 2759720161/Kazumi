export class SnifferResult {
  url: string = ''
  type: string = ''
  quality: string = ''
  source: string = ''
  timestamp: number = 0

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
      '/video/tos/',
      'videocdn', 'video-cdn', 'mcdn', 'bytecdntp'
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
    return `[${this.type}] ${this.url} (${this.quality}) from ${this.source}`
  }
}
