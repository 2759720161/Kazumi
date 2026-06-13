import { Logger } from '../utils/Logger'

const logger = new Logger('SimpleCache')

interface CacheEntry {
  value: Object
  expireAt: number
}

export class SimpleCache {
  private cache: Map<string, CacheEntry> = new Map()
  private static instance: SimpleCache | null = null
  private hitCount: number = 0
  private missCount: number = 0

  private constructor() {}

  static getInstance(): SimpleCache {
    if (SimpleCache.instance === null) {
      SimpleCache.instance = new SimpleCache()
    }
    return SimpleCache.instance
  }

  get(key: string): Object | null {
    const entry = this.cache.get(key)
    if (entry === undefined || entry === null) {
      this.missCount++
      return null
    }
    if (Date.now() > entry.expireAt) {
      this.cache.delete(key)
      this.missCount++
      return null
    }
    this.hitCount++
    return entry.value
  }

  put(key: string, value: Object, ttlMs: number): void {
    const entry: CacheEntry = {
      value: value,
      expireAt: Date.now() + ttlMs
    }
    this.cache.set(key, entry)
  }

  remove(key: string): void {
    this.cache.delete(key)
  }

  clear(): void {
    this.cache.clear()
    this.hitCount = 0
    this.missCount = 0
  }

  evictExpired(): number {
    let evicted = 0
    const now = Date.now()
    this.cache.forEach((entry: CacheEntry, key: string) => {
      if (now > entry.expireAt) {
        this.cache.delete(key)
        evicted++
      }
    })
    return evicted
  }

  size(): number {
    return this.cache.size
  }

  getStats(): string {
    const total = this.hitCount + this.missCount
    const hitRate = total > 0 ? Math.round(this.hitCount / total * 100) : 0
    return `CacheStats{size=${this.cache.size}, hits=${this.hitCount}, misses=${this.missCount}, hitRate=${hitRate}%}`
  }

  logStats(): void {
    logger.info(this.getStats())
  }
}