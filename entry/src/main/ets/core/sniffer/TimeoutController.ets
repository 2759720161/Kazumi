import { NetworkPolicy } from './NetworkPolicy'

export class TimeoutController {
  private timeoutMs: number = NetworkPolicy.DEFAULT_SNIFF_TIMEOUT_MS
  private maxRetries: number = NetworkPolicy.DEFAULT_MAX_RETRY
  private attemptCount: number = 0
  private timerId: number = -1
  private onTimeout: (() => void) | null = null
  private onRetry: (() => void) | null = null

  constructor(timeoutMs: number, maxRetries: number) {
    this.timeoutMs = timeoutMs
    this.maxRetries = maxRetries
  }

  setOnTimeout(callback: () => void): void {
    this.onTimeout = callback
  }

  setOnRetry(callback: () => void): void {
    this.onRetry = callback
  }

  start(): void {
    this.clearTimer()
    this.attemptCount = 0
    this.scheduleTimeout()
  }

  private scheduleTimeout(): void {
    this.clearTimer()
    this.timerId = setTimeout(() => {
      this.attemptCount++
      if (this.attemptCount <= this.maxRetries && this.onRetry) {
        this.onRetry()
        this.scheduleTimeout()
      } else {
        if (this.onTimeout) {
          this.onTimeout()
        }
      }
    }, this.timeoutMs) as number
  }

  restart(): void {
    this.attemptCount = 0
    this.scheduleTimeout()
  }

  cancel(): void {
    this.clearTimer()
  }

  private clearTimer(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
  }

  getAttemptCount(): number {
    return this.attemptCount
  }

  isExhausted(): boolean {
    return this.attemptCount > this.maxRetries
  }
}
