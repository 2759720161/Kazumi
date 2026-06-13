export class VideoSourceRequest {
  episodeUrl: string = ''
  ruleSourceId: number = -1
  useLegacyParser: boolean = false
  referer: string = ''
  userAgent: string = ''
  headers: Record<string, string> = {}
  antiCrawlerEnabled: boolean = false
  sniffTimeoutMs: number = 15000
  maxRetryCount: number = 2
}