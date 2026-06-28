export class CapturedRequestContext {
  url: string = ''
  referer: string = ''
  userAgent: string = ''
  headers: Record<string, string> = {}
}
