import { VideoSourceRequest } from './VideoSourceRequest'
import { Logger } from '../../utils/Logger'

const logger = new Logger('SessionPool')

export class SnifferLease {
  sessionId: number = 0
  workerId: number = 0
  ruleSourceId: number = -1
  origin: string = ''
  createdAt: number = 0
  released: boolean = false
  cancelled: boolean = false
  background: boolean = false
}

export enum WebViewCleanupLevel {
  NONE = 0,
  SOFT = 1,
  FULL = 2
}

export class SnifferSessionPool {
  private readonly foregroundWorkerId: number = 1
  private readonly backgroundWorkerId: number = 2
  private readonly maxWorkers: number = 2
  private nextSessionId: number = 1
  private activeLease: SnifferLease | null = null
  private backgroundLease: SnifferLease | null = null
  private previousLease: SnifferLease | null = null
  private poolState: string = 'idle'

  acquire(request: VideoSourceRequest): SnifferLease {
    if (this.activeLease !== null && !this.activeLease.released) {
      logger.warn('cancel_stale: sessionId=%{public}d workerId=%{public}d reason=foreground_superseded',
        this.activeLease.sessionId, this.activeLease.workerId)
      this.cancelActive('superseded')
    }

    const lease = new SnifferLease()
    lease.sessionId = this.nextSessionId++
    lease.workerId = this.foregroundWorkerId
    lease.ruleSourceId = request.ruleSourceId
    lease.origin = this.extractOrigin(request.episodeUrl)
    lease.createdAt = Date.now()
    lease.released = false
    lease.cancelled = false
    lease.background = false

    this.previousLease = this.activeLease
    this.activeLease = lease
    this.poolState = (this.backgroundLease !== null && !this.backgroundLease.released) ? 'concurrent' : 'sniffing'

    logger.info('acquire: sessionId=%{public}d origin=%{public}s ruleSourceId=%{public}d',
      lease.sessionId, lease.origin, lease.ruleSourceId)

    if (this.backgroundLease !== null && !this.backgroundLease.released) {
      logger.info('concurrent_mode: foreground=%{public}d alongside background=%{public}d',
        lease.sessionId, this.backgroundLease.sessionId)
    }

    return lease
  }

  acquireBackground(request: VideoSourceRequest): SnifferLease | null {
    if (this.backgroundLease !== null && !this.backgroundLease.released) {
      logger.warn('prepare_next_reject: background lease already active sessionId=%{public}d',
        this.backgroundLease.sessionId)
      return null
    }

    const lease = new SnifferLease()
    lease.sessionId = this.nextSessionId++
    lease.workerId = this.backgroundWorkerId
    lease.ruleSourceId = request.ruleSourceId
    lease.origin = this.extractOrigin(request.episodeUrl)
    lease.createdAt = Date.now()
    lease.released = false
    lease.cancelled = false
    lease.background = true

    this.backgroundLease = lease
    logger.info('prepare_next_acquire: sessionId=%{public}d workerId=%{public}d origin=%{public}s ruleSourceId=%{public}d',
      lease.sessionId, lease.workerId, lease.origin, lease.ruleSourceId)
    return lease
  }

  release(lease: SnifferLease): WebViewCleanupLevel {
    if (lease.released) {
      logger.debug('release: already released sessionId=%{public}d', lease.sessionId)
      return WebViewCleanupLevel.NONE
    }

    lease.released = true
    if (!lease.background) {
      this.poolState = (this.backgroundLease !== null && !this.backgroundLease.released) ? 'preparing' : 'idle'
    }

    const cleanupLevel = this.determineCleanupLevel(lease)

    logger.info('release: sessionId=%{public}d cleanup=%{public}s',
      lease.sessionId,
      cleanupLevel === WebViewCleanupLevel.NONE ? 'none' :
      cleanupLevel === WebViewCleanupLevel.SOFT ? 'soft' : 'full')

    return cleanupLevel
  }

  releaseBackground(lease: SnifferLease): WebViewCleanupLevel {
    if (!lease.background) {
      return this.release(lease)
    }
    if (lease.released) {
      logger.debug('releaseBackground: already released sessionId=%{public}d', lease.sessionId)
      return WebViewCleanupLevel.NONE
    }
    lease.released = true
    const cleanupLevel = this.determineCleanupLevel(lease)
    if (this.backgroundLease !== null && this.backgroundLease.sessionId === lease.sessionId) {
      this.backgroundLease = null
    }
    logger.info('prepare_next_release: sessionId=%{public}d cleanup=%{public}s',
      lease.sessionId,
      cleanupLevel === WebViewCleanupLevel.NONE ? 'reuse_state' :
      cleanupLevel === WebViewCleanupLevel.SOFT ? 'soft_reset' : 'full_reset')
    return cleanupLevel
  }

  cancelActive(reason: string): void {
    if (this.activeLease === null || this.activeLease.released) {
      return
    }

    this.activeLease.cancelled = true
    this.activeLease.released = true
    this.poolState = 'idle'

    logger.info('cancelActive: sessionId=%{public}d reason=%{public}s',
      this.activeLease.sessionId, reason)
  }

  cancelBackground(reason: string): void {
    if (this.backgroundLease === null || this.backgroundLease.released) {
      return
    }
    this.backgroundLease.cancelled = true
    this.backgroundLease.released = true
    logger.info('prepare_next_cancel: sessionId=%{public}d reason=%{public}s',
      this.backgroundLease.sessionId, reason)
    this.backgroundLease = null
  }

  isLeaseActive(sessionId: number): boolean {
    if (this.activeLease === null) {
      return false
    }
    return this.activeLease.sessionId === sessionId &&
      !this.activeLease.released &&
      !this.activeLease.cancelled
  }

  getActiveLease(): SnifferLease | null {
    return this.activeLease
  }

  getActiveSessionId(): number {
    if (this.activeLease === null) {
      return 0
    }
    return this.activeLease.sessionId
  }

  isBackgroundLeaseActive(sessionId: number): boolean {
    if (this.backgroundLease === null) {
      return false
    }
    return this.backgroundLease.sessionId === sessionId &&
      !this.backgroundLease.released &&
      !this.backgroundLease.cancelled
  }

  hasActiveBackgroundLease(): boolean {
    return this.backgroundLease !== null && !this.backgroundLease.released && !this.backgroundLease.cancelled
  }

  getMaxWorkers(): number {
    return this.maxWorkers
  }

  getRequestOrigin(request: VideoSourceRequest): string {
    return this.extractOrigin(request.episodeUrl)
  }

  shouldReuseState(prevLease: SnifferLease | null, nextRequest: VideoSourceRequest): boolean {
    if (prevLease === null) {
      return false
    }
    if (prevLease.cancelled) {
      return false
    }
    const nextOrigin = this.extractOrigin(nextRequest.episodeUrl)
    if (prevLease.origin.length === 0 || nextOrigin.length === 0) {
      return false
    }
    if (prevLease.ruleSourceId !== nextRequest.ruleSourceId) {
      return false
    }
    return prevLease.origin === nextOrigin
  }

  resetForNextUse(cleanupLevel: WebViewCleanupLevel): void {
    if (cleanupLevel === WebViewCleanupLevel.NONE) {
      logger.info('reuse_state: same origin and rule source; keeping cookies/localStorage')
      return
    }

    this.previousLease = null

    if (cleanupLevel === WebViewCleanupLevel.FULL) {
      if (this.activeLease !== null) {
        this.activeLease = null
      }
      logger.info('full_reset: cleanup completed')
    } else {
      logger.info('soft_reset: cross origin or rule change; loaded about:blank, cookies/localStorage kept')
    }
  }

  getPoolState(): string {
    return this.poolState
  }

  getConcurrencyState(): string {
    const fg = this.activeLease !== null && !this.activeLease.released ? 'fg=active' : 'fg=idle'
    const bg = this.backgroundLease !== null && !this.backgroundLease.released ? 'bg=active' : 'bg=idle'
    return fg + ' ' + bg
  }

  private determineCleanupLevel(lease: SnifferLease): WebViewCleanupLevel {
    if (lease.cancelled) {
      return WebViewCleanupLevel.FULL
    }

    if (this.previousLease !== null) {
      const sameRuleSource = this.previousLease.ruleSourceId === lease.ruleSourceId
      const sameOrigin = this.previousLease.origin === lease.origin

      if (sameRuleSource && sameOrigin) {
        return WebViewCleanupLevel.NONE
      }

      if (sameRuleSource) {
        return WebViewCleanupLevel.SOFT
      }
    }

    return WebViewCleanupLevel.SOFT
  }

  private extractOrigin(url: string): string {
    if (url.length === 0) {
      return ''
    }
    let startIdx = 0
    if (url.indexOf('https://') === 0) {
      startIdx = 8
    } else if (url.indexOf('http://') === 0) {
      startIdx = 7
    } else {
      return ''
    }
    let slashIdx = url.indexOf('/', startIdx)
    if (slashIdx < 0) {
      slashIdx = url.indexOf('?', startIdx)
    }
    if (slashIdx < 0) {
      slashIdx = url.length
    }
    return url.substring(startIdx, slashIdx).toLowerCase()
  }
}
