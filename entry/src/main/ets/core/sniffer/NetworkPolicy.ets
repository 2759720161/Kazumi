export class NetworkPolicy {
  static readonly DEFAULT_PLAYER_USER_AGENT: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'
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

  private static readonly USER_AGENTS: string[] = [
    NetworkPolicy.DEFAULT_PLAYER_USER_AGENT,
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Edg/137.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:139.0) Gecko/20100101 Firefox/139.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36'
  ]

  static getRandomUA(): string {
    const count = NetworkPolicy.USER_AGENTS.length
    if (count === 0) {
      return NetworkPolicy.DEFAULT_PLAYER_USER_AGENT
    }
    const index = Math.floor(Math.random() * count)
    return NetworkPolicy.USER_AGENTS[index]
  }

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
