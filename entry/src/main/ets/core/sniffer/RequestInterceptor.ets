export class RequestInterceptor {
  private interceptedUrls: string[] = []
  private onIntercept: ((url: string, type: string) => void) | null = null

  setOnIntercept(callback: (url: string, type: string) => void): void {
    this.onIntercept = callback
  }

  shouldIntercept(url: string): boolean {
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
    return false
  }

  interceptRequest(url: string): boolean {
    if (this.shouldIntercept(url)) {
      this.interceptedUrls.push(url)
      if (this.onIntercept) {
        let type = this.detectType(url)
        this.onIntercept(url, type)
      }
      return true
    }
    return false
  }

  private detectType(url: string): string {
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
    return 'ts'
  }

  getInterceptedUrls(): string[] {
    return this.interceptedUrls.slice()
  }

  reset(): void {
    this.interceptedUrls = []
  }
}