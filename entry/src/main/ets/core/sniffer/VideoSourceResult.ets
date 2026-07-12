import { SnifferResult } from './SnifferResult'
import { ResolveErrorCode } from './ResolveErrorCode'
import { StreamMetadata } from '../player/StreamMetadata'

export class VideoSourceResult {
  status: string = 'pending'
  videoUrl: string = ''
  videoType: string = ''
  candidates: SnifferResult[] = []
  errorMessage: string = ''
  retryCount: number = 0
  sniffDurationMs: number = 0
  errorCode: ResolveErrorCode | '' = ''
  retriable: boolean = false
  streamMetadata: StreamMetadata | null = null

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
    result.errorCode = ResolveErrorCode.NotFound
    result.retriable = true
    return result
  }

  static timeout(retryCount: number, durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'timeout'
    result.errorMessage = '嗅探超时'
    result.retryCount = retryCount
    result.sniffDurationMs = durationMs
    result.errorCode = ResolveErrorCode.Timeout
    result.retriable = true
    return result
  }

  static captcha(durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'captcha'
    result.errorMessage = '遇到验证码，需要人工处理'
    result.sniffDurationMs = durationMs
    result.errorCode = ResolveErrorCode.Captcha
    return result
  }

  static cancelled(durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'error'
    result.errorMessage = '嗅探已取消'
    result.sniffDurationMs = durationMs
    result.errorCode = ResolveErrorCode.Cancelled
    return result
  }

  static networkError(message: string, durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'error'
    result.errorMessage = message
    result.sniffDurationMs = durationMs
    result.errorCode = ResolveErrorCode.Network
    result.retriable = true
    return result
  }

  static wrapperOnly(candidates: SnifferResult[], durationMs: number): VideoSourceResult {
    const result = new VideoSourceResult()
    result.status = 'error'
    result.errorMessage = '仅找到嵌套播放器链接'
    result.candidates = candidates
    result.sniffDurationMs = durationMs
    result.errorCode = ResolveErrorCode.WrapperOnly
    result.retriable = true
    return result
  }

  isPlayable(): boolean {
    return this.status === 'success' && this.videoUrl.length > 0
  }
}
