export class CapturedRequestContext {
  url: string = ''
  referer: string = ''
  userAgent: string = ''
  headers: Record<string, string> = {}
  cookies: string = ''
  contentType: string = ''
  hasRangeHeader: boolean = false
}
