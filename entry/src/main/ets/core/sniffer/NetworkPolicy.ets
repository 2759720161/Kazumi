export class NetworkPolicy {
  static readonly DEFAULT_SNIFF_TIMEOUT_MS: number = 15000
  static readonly DEFAULT_MAX_RETRY: number = 2
  static readonly RETRY_BASE_DELAY_MS: number = 2000
  static readonly RETRY_MAX_DELAY_MS: number = 8000
  static readonly COLLECT_WINDOW_MS: number = 1000
  static readonly FALLBACK_WAIT_MS: number = 1000
  static readonly WEAK_CANDIDATE_DELAY_MS: number = 1200
  static readonly MEDIA_POLL_INTERVAL_MS: number = 500
  static readonly MEDIA_POLL_MAX_COUNT: number = 30
  static readonly HOOK_INSTALL_INTERVAL_MS: number = 250
  static readonly HOOK_INSTALL_MAX_COUNT: number = 40

  sniffTimeoutMs: number = NetworkPolicy.DEFAULT_SNIFF_TIMEOUT_MS
  maxRetry: number = NetworkPolicy.DEFAULT_MAX_RETRY

  calculateRetryDelay(retryCount: number): number {
    let delay = NetworkPolicy.RETRY_BASE_DELAY_MS
    for (let i = 0; i < retryCount; i++) {
      delay = delay * 2
    }
    if (delay > NetworkPolicy.RETRY_MAX_DELAY_MS) {
      delay = NetworkPolicy.RETRY_MAX_DELAY_MS
    }
    return delay
  }
}
