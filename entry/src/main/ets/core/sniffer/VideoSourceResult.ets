import { SnifferResult } from './SnifferResult'

export class VideoSourceResult {
  status: string = 'pending'
  videoUrl: string = ''
  videoType: string = ''
  candidates: SnifferResult[] = []
  errorMessage: string = ''
  retryCount: number = 0
  sniffDurationMs: number = 0

  static success(url: string, type: string, candidates: SnifferResult[], durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'success'
    result.videoUrl = url
    result.videoType = type
    result.candidates = candidates
    result.sniffDurationMs = durationMs
    return result
  }

  static fail(message: string, retryCount: number, durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'error'
    result.errorMessage = message
    result.retryCount = retryCount
    result.sniffDurationMs = durationMs
    return result
  }

  static timeout(retryCount: number, durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'timeout'
    result.errorMessage = '嗅探超时'
    result.retryCount = retryCount
    result.sniffDurationMs = durationMs
    return result
  }

  static captcha(durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'captcha'
    result.errorMessage = '遇到验证码，需要人工处理'
    result.sniffDurationMs = durationMs
    return result
  }

  isPlayable(): boolean {
    return this.status === 'success' && this.videoUrl.length > 0
  }
}