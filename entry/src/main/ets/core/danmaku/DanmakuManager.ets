import { PlayerState } from '../player/IPlayerEngine'
import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuApiService, DanmakuApiResponse } from './DanmakuApiService'
import { DanmakuTimeSync } from './DanmakuTimeSync'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { DanmakuRenderer } from './DanmakuRenderer'
import { DanmakuEpisodeResolver } from './DanmakuEpisodeResolver'
import { DandanCredentialStore } from './DandanCredentialStore'
import { DanmakuMappingStore, DanmakuMappingRecord } from './DanmakuMappingStore'
import { DanmakuPlaybackBindingStore, DanmakuPlaybackBinding } from './DanmakuPlaybackBindingStore'
import { EpisodeNumberExtractor } from './EpisodeNumberExtractor'
import { DanmakuStyleSettings } from './DanmakuStyleSettings'
import { DanmakuRuntimeStats } from './DanmakuRuntimeStats'
import { DanmakuCacheStore } from './DanmakuCacheStore'
import { DanmakuDeduplicator } from './DanmakuDeduplicator'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuManager')

const DANMAKU_PREFS_KEY_ENABLED = 'danmaku_enabled'
const DANMAKU_CACHE_MAX_EPISODES = 10

const DANMAKU_FAILURE_NO_CREDENTIALS = '未配置官方凭据'
const DANMAKU_FAILURE_PROXY_UNAVAILABLE = '反代不可用'
const DANMAKU_FAILURE_NO_SEARCH_RESULT = '搜索无结果'
const DANMAKU_FAILURE_EPISODE_INDEX_OUT_OF_RANGE = '分集索引越界'
const DANMAKU_FAILURE_EMPTY_COMMENTS = 'comment为空'
const DANMAKU_FAILURE_BGM_ID_PATH_FAILED = 'Bangumi ID主路径失败'

class DanmakuLoadRequest {
  animeName: string = ''
  episodeIndex: number = 0
  bangumiId: number = 0
  episodeTitle: string = ''
  episodeKey: string = ''
  sourceId: number = -1
  episodeUrl: string = ''

  constructor(animeName: string, episodeIndex: number, bangumiId: number,
    episodeTitle: string, episodeKey: string, sourceId: number, episodeUrl: string) {
    this.animeName = animeName
    this.episodeIndex = episodeIndex
    this.bangumiId = bangumiId
    this.episodeTitle = episodeTitle
    this.episodeKey = episodeKey
    this.sourceId = sourceId
    this.episodeUrl = episodeUrl
  }
}

export class DanmakuManager {
  private apiService: DanmakuApiService = new DanmakuApiService()
  private episodeResolver: DanmakuEpisodeResolver = new DanmakuEpisodeResolver()
  private mappingStore: DanmakuMappingStore = DanmakuMappingStore.getInstance()
  private bindingStore: DanmakuPlaybackBindingStore = DanmakuPlaybackBindingStore.getInstance()
  private persistentCache: DanmakuCacheStore = DanmakuCacheStore.getInstance()
  private timeSync: DanmakuTimeSync | null = null
  private trackAllocator: DanmakuTrackAllocator | null = null
  private renderer: DanmakuRenderer | null = null
  private danmakuCache: Map<string, DanmakuItem[]> = new Map()
  private refreshingEpisodeIds: Set<number> = new Set()
  private isDanmakuEnabled: boolean = true
  private isLoading: boolean = false
  private currentEpisodeKey: string = ''
  private failureReason: string = ''
  private pendingLoadRequest: DanmakuLoadRequest | null = null
  private initialized: boolean = false
  private pendingCanvasContext: CanvasRenderingContext2D | null = null
  private pendingCanvasWidth: number = 0
  private pendingCanvasHeight: number = 0
  private stats: DanmakuRuntimeStats = new DanmakuRuntimeStats()
  private currentSettings: DanmakuStyleSettings = DanmakuStyleSettings.getDefault()
  private currentRawDanmaku: DanmakuItem[] = []
  private lastPlayerState: PlayerState | null = null

  async init(): Promise<void> {
    await DandanCredentialStore.getInstance().init()

    if (!this.initialized || this.trackAllocator === null || this.renderer === null || this.timeSync === null) {
      this.trackAllocator = new DanmakuTrackAllocator()
      this.renderer = new DanmakuRenderer(this.trackAllocator, this.stats)
      this.timeSync = new DanmakuTimeSync(this.trackAllocator, this.renderer, this.stats)
      this.initialized = true
    }

    this.currentSettings = await DanmakuStyleSettings.load()
    this.renderer.setStyle(this.currentSettings)
    this.timeSync.setSettings(this.currentSettings)
    this.bindPendingCanvasIfReady()

    try {
      const prefs = PreferencesStore.getInstance()
      this.isDanmakuEnabled = await prefs.getBoolean(DANMAKU_PREFS_KEY_ENABLED, true)
    } catch (_err) {
      this.isDanmakuEnabled = true
    }

    logger.info('DanmakuManager初始化完成, 弹幕开关=%{public}s', String(this.isDanmakuEnabled))
  }

  onPlayerStateUpdate(state: PlayerState): void {
    this.lastPlayerState = state
    if (!this.isDanmakuEnabled) {
      if (this.timeSync !== null) {
        this.timeSync.syncPlayerSnapshot(state)
      }
      return
    }
    if (this.timeSync !== null) {
      this.timeSync.onPlayerStateUpdate(state)
    }
  }

  sendLocalDanmaku(content: string, positionMs: number, type: number = 0, color: string = '#FFB74D'): boolean {
    const trimmed = content.trim()
    if (!this.isDanmakuEnabled || trimmed.length === 0 || this.timeSync === null) {
      return false
    }
    const safePosition = Math.max(0, positionMs)
    const item = new DanmakuItem(trimmed, safePosition, color, this.currentSettings.fontSize, type, 'Local')
    this.insertCurrentRawDanmaku(item)
    const shown = this.timeSync.addLocalDanmaku(item)
    logger.info('本地弹幕发送: shown=%{public}s, position=%{public}d, type=%{public}d',
      String(shown), safePosition, type)
    return shown
  }

  async loadDanmakuByEpisodeId(episodeId: number, animeId: number, animeTitle: string, episodeTitle: string): Promise<boolean> {
    if (episodeId <= 0) {
      return false
    }
    try {
      const cachedItems = await this.persistentCache.get(episodeId)
      if (cachedItems !== null && cachedItems.length > 0) {
        this.clearCurrentDanmaku()
        this.onDanmakuLoaded(cachedItems)
        this.stats.currentEpisodeId = episodeId
        this.stats.currentAnimeId = animeId
        this.stats.matchSource = 'manual-cache'
        this.stats.loadedCount = cachedItems.length
        this.failureReason = ''
        this.refreshEpisodeCache(episodeId)
        logger.info('手动弹幕缓存加载成功: episodeId=%{public}d, count=%{public}d', episodeId, cachedItems.length)
        return true
      }

      const response: DanmakuApiResponse = await this.apiService.fetchDanmaku(episodeId)
      if (response.success && response.items.length > 0) {
        await this.persistentCache.put(episodeId, response.items)
        this.clearCurrentDanmaku()
        this.onDanmakuLoaded(response.items)
        this.stats.currentEpisodeId = episodeId
        this.stats.currentAnimeId = animeId
        this.stats.matchSource = 'manual'
        this.stats.loadedCount = response.items.length
        this.failureReason = ''
        logger.info('手动弹幕加载成功: episodeId=%{public}d, count=%{public}d', episodeId, response.items.length)
        return true
      }
      logger.warn('手动弹幕加载失败: episodeId=%{public}d, success=%{public}s, items=%{public}d',
        episodeId, String(response.success), response.items.length)
      return false
    } catch (_err) {
      logger.warn('手动弹幕加载异常: episodeId=%{public}d', episodeId)
      return false
    }
  }

  async saveManualMapping(bangumiId: number, episodeNo: number, animeName: string,
    animeId: number, episodeId: number, animeTitle: string, episodeTitle: string,
    sourceId: number = -1, episodeUrl: string = ''): Promise<void> {
    const record: DanmakuMappingRecord = new DanmakuMappingRecord()
    record.animeId = animeId
    record.episodeId = episodeId
    record.animeTitle = animeTitle
    record.episodeTitle = episodeTitle
    await this.mappingStore.saveMapping(bangumiId, episodeNo, animeName, record)
    const binding: DanmakuPlaybackBinding = new DanmakuPlaybackBinding()
    binding.episodeId = episodeId
    binding.animeId = animeId
    binding.animeTitle = animeTitle
    binding.episodeTitle = episodeTitle
    this.bindingStore.saveBinding(bangumiId, episodeNo, animeName, binding, sourceId, episodeUrl).catch((_err: Error) => {})
  }

  async loadDanmakuForEpisode(animeName: string, episodeIndex: number,
    bangumiId: number = 0, episodeTitle: string = '',
    sourceId: number = -1, episodeUrl: string = ''): Promise<void> {
    if (!this.isDanmakuEnabled || animeName.length === 0) {
      return
    }

    this.failureReason = ''

    const episodeKey = `${animeName}_${bangumiId}_${episodeIndex}`
    if (this.currentEpisodeKey.length > 0 && this.currentEpisodeKey !== episodeKey) {
      this.clearCurrentDanmaku()
    }
    this.currentEpisodeKey = episodeKey

    const cached = this.danmakuCache.get(episodeKey)
    if (cached !== undefined && cached !== null) {
      logger.info('使用缓存的弹幕数据, key=%{public}s, count=%{public}d',
        episodeKey, cached.length)
      this.onDanmakuLoaded(cached)
      return
    }

    if (this.isLoading) {
      this.pendingLoadRequest = new DanmakuLoadRequest(animeName, episodeIndex, bangumiId, episodeTitle, episodeKey, sourceId, episodeUrl)
      logger.info('弹幕加载进行中，已排队最新请求: key=%{public}s', episodeKey)
      return
    }
    this.isLoading = true

    const episodeNo = episodeTitle.length > 0
      ? EpisodeNumberExtractor.extractEpisodeNumber(episodeTitle, episodeIndex)
      : episodeIndex

    logger.info('弹幕加载: animeName=%{public}s, bangumiId=%{public}d, episodeTitle=%{public}s, episodeNo=%{public}d',
      animeName, bangumiId, episodeTitle, episodeNo)

    try {
      if (episodeNo <= 0) {
        this.failureReason = DANMAKU_FAILURE_EPISODE_INDEX_OUT_OF_RANGE
        this.stats.matchSource = 'none'
        logger.warn('弹幕加载失败: %{public}s', this.failureReason)
        return
      }

      const manualMapping: DanmakuMappingRecord | null = await this.mappingStore.lookupMapping(bangumiId, episodeNo, animeName)
      if (manualMapping !== null && manualMapping.episodeId > 0) {
        logger.info('发现手动映射: episodeId=%{public}d, animeId=%{public}d', manualMapping.episodeId, manualMapping.animeId)
        const manualSuccess: boolean = await this.loadDanmakuByEpisodeId(
          manualMapping.episodeId, manualMapping.animeId, manualMapping.animeTitle, manualMapping.episodeTitle)
        if (manualSuccess) {
          const binding: DanmakuPlaybackBinding = new DanmakuPlaybackBinding()
          binding.episodeId = manualMapping.episodeId
          binding.animeId = manualMapping.animeId
          binding.animeTitle = manualMapping.animeTitle
          binding.episodeTitle = manualMapping.episodeTitle
          this.bindingStore.saveBinding(bangumiId, episodeNo, animeName, binding, sourceId, episodeUrl).catch((_err: Error) => {})
          return
        }
        logger.warn('手动映射加载失败，降级到自动匹配')
      }

      const binding: DanmakuPlaybackBinding | null = await this.bindingStore.lookupBinding(bangumiId, episodeNo, animeName, sourceId, episodeUrl)
      if (binding !== null && binding.episodeId > 0) {
        logger.info('发现播放绑定: episodeId=%{public}d, animeId=%{public}d', binding.episodeId, binding.animeId)
        const bindingCached = await this.persistentCache.get(binding.episodeId, sourceId, episodeUrl)
        if (bindingCached !== null && bindingCached.length > 0) {
          this.clearCurrentDanmaku()
          this.onDanmakuLoaded(bindingCached)
          this.stats.currentEpisodeId = binding.episodeId
          this.stats.currentAnimeId = binding.animeId
          this.stats.matchSource = 'binding-cache'
          this.stats.loadedCount = bindingCached.length
          this.failureReason = ''
          logger.info('播放绑定缓存加载成功: episodeId=%{public}d, count=%{public}d', binding.episodeId, bindingCached.length)
          return
        }
        logger.info('播放绑定存在但缓存为空，继续自动匹配')
      }

      const adjustedIndex = episodeNo - 1
      logger.info('episodeNo: received=%{public}d, converted=0-based=%{public}d',
        episodeNo, adjustedIndex)
      const episodeId = await this.episodeResolver.resolveEpisodeId(animeName, adjustedIndex, bangumiId)
      if (episodeId <= 0) {
        const hasCredentials = DandanCredentialStore.getInstance().hasCredentials()
        if (!hasCredentials) {
          this.failureReason = DANMAKU_FAILURE_NO_CREDENTIALS
        } else if (bangumiId > 0) {
          this.failureReason = DANMAKU_FAILURE_BGM_ID_PATH_FAILED
        } else {
          this.failureReason = DANMAKU_FAILURE_NO_SEARCH_RESULT
        }
        this.stats.matchSource = 'none'
        logger.warn('弹幕加载失败: %{public}s', this.failureReason)
        return
      }

      logger.info('解析到episodeId=%{public}d, 开始加载弹幕', episodeId)
      const persistentCached = await this.persistentCache.get(episodeId, sourceId, episodeUrl)
      if (persistentCached !== null && persistentCached.length > 0) {
        this.failureReason = ''
        this.stats.currentEpisodeId = episodeId
        this.stats.currentAnimeId = 0
        this.stats.matchSource = bangumiId > 0 ? 'bangumi-cache' : 'search-cache'
        this.stats.loadedCount = persistentCached.length
        this.cacheDanmaku(episodeKey, persistentCached)
        if (episodeKey === this.currentEpisodeKey) {
          this.onDanmakuLoaded(persistentCached)
        }
        this.refreshEpisodeCache(episodeId)
        this.saveAutoMatchBinding(bangumiId, episodeNo, animeName, episodeId, 0, sourceId, episodeUrl)
        return
      }

      const response: DanmakuApiResponse = await this.apiService.fetchDanmaku(episodeId)
      if (response.success) {
        if (response.items.length === 0) {
          this.failureReason = DANMAKU_FAILURE_EMPTY_COMMENTS
          this.stats.matchSource = 'none'
          logger.warn('弹幕加载失败: %{public}s', this.failureReason)
          return
        }
        logger.info('弹幕加载成功, episodeId=%{public}d, count=%{public}d',
          episodeId, response.items.length)
        this.failureReason = ''
        this.stats.currentEpisodeId = episodeId
        this.stats.currentAnimeId = 0
        if (bangumiId > 0) {
          this.stats.matchSource = 'bangumi'
        } else {
          this.stats.matchSource = 'search'
        }
        await this.persistentCache.put(episodeId, response.items, sourceId, episodeUrl)
        this.cacheDanmaku(episodeKey, response.items)
        if (episodeKey === this.currentEpisodeKey) {
          this.onDanmakuLoaded(response.items)
        }
        this.saveAutoMatchBinding(bangumiId, episodeNo, animeName, episodeId, 0, sourceId, episodeUrl)
      } else {
        this.failureReason = DANMAKU_FAILURE_PROXY_UNAVAILABLE
        logger.warn('弹幕加载失败: %{public}s', this.failureReason)
      }
    } catch (err) {
      this.failureReason = DANMAKU_FAILURE_PROXY_UNAVAILABLE
      logger.error('弹幕加载异常: %{public}s',
        err instanceof Error ? err.message : String(err))
    } finally {
      this.isLoading = false
      await this.consumePendingLoadRequest(episodeKey)
    }
  }

  toggleDanmaku(): boolean {
    this.isDanmakuEnabled = !this.isDanmakuEnabled
    try {
      const prefs = PreferencesStore.getInstance()
      prefs.setBoolean(DANMAKU_PREFS_KEY_ENABLED, this.isDanmakuEnabled)
    } catch (_err) {
    }

    if (!this.isDanmakuEnabled) {
      this.suspendDisplay()
    } else {
      if (this.timeSync !== null) {
        if (this.lastPlayerState !== null) {
          this.timeSync.syncPlayerSnapshot(this.lastPlayerState)
        }
        if (this.currentRawDanmaku.length > 0) {
          this.applyCurrentDanmakuData()
        }
        if (this.lastPlayerState !== null) {
          this.timeSync.onPlayerStateUpdate(this.lastPlayerState)
        }
      }
    }
    logger.info('弹幕开关切换: %{public}s', String(this.isDanmakuEnabled))
    return this.isDanmakuEnabled
  }

  getIsDanmakuEnabled(): boolean {
    return this.isDanmakuEnabled
  }

  getFailureReason(): string {
    return this.failureReason
  }

  getIsLoading(): boolean {
    return this.isLoading
  }

  hasDanmakuData(): boolean {
    return this.failureReason.length === 0 && this.currentRawDanmaku.length > 0
  }

  getRenderer(): DanmakuRenderer | null {
    return this.renderer
  }

  getDiscardCount(): number {
    if (this.trackAllocator !== null) {
      return this.trackAllocator.getDiscardCount()
    }
    return 0
  }

  getCurrentManualMapping(bangumiId: number, episodeNo: number, animeName: string): Promise<DanmakuMappingRecord | null> {
    return this.mappingStore.lookupMapping(bangumiId, episodeNo, animeName)
  }

  async clearManualMapping(bangumiId: number, episodeNo: number, animeName: string): Promise<boolean> {
    return await this.mappingStore.clearMapping(bangumiId, episodeNo, animeName)
  }

  async reloadSettings(): Promise<void> {
    const previousSettings = this.currentSettings
    this.currentSettings = await DanmakuStyleSettings.load()
    if (this.renderer !== null) {
      this.renderer.setStyle(this.currentSettings)
    }
    if (this.timeSync !== null) {
      this.timeSync.setSettings(this.currentSettings)
      if (this.currentRawDanmaku.length > 0 && previousSettings.deduplication !== this.currentSettings.deduplication) {
        this.applyCurrentDanmakuData()
      } else {
        this.timeSync.applySettingsToActiveDanmaku()
      }
    }
    logger.info('弹幕设置已热更新: color=%{public}s, hideColor=%{public}s, dedup=%{public}s',
      String(this.currentSettings.useSourceColor), String(this.currentSettings.hideColor),
      String(this.currentSettings.deduplication))
  }

  onCanvasReady(context: CanvasRenderingContext2D, width: number, height: number): void {
    logger.info('弹幕Canvas ready: width=%{public}d, height=%{public}d', width, height)
    this.pendingCanvasContext = context
    this.pendingCanvasWidth = width
    this.pendingCanvasHeight = height
    this.bindPendingCanvasIfReady()
  }

  onCanvasSizeChanged(width: number, height: number): void {
    logger.info('弹幕Canvas size changed: width=%{public}d, height=%{public}d', width, height)
    this.pendingCanvasWidth = width
    this.pendingCanvasHeight = height
    if (this.trackAllocator !== null) {
      this.trackAllocator.updateCanvasSize(width, height)
    }
    if (this.renderer !== null) {
      this.renderer.updateCanvasSize(width, height)
    }
    if (this.timeSync !== null) {
      this.timeSync.resyncAfterResize()
      this.timeSync.recoverAfterCanvasReady()
    }
  }

  release(): void {
    this.stopRendering()
    if (this.timeSync !== null) {
      this.timeSync.reset()
      this.timeSync = null
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.reset()
      this.trackAllocator = null
    }
    if (this.renderer !== null) {
      this.renderer.release()
      this.renderer = null
    }
    this.episodeResolver.reset()
    this.danmakuCache.clear()
    this.currentEpisodeKey = ''
    this.isLoading = false
    this.pendingLoadRequest = null
    this.initialized = false
    this.pendingCanvasContext = null
    this.pendingCanvasWidth = 0
    this.pendingCanvasHeight = 0
    this.refreshingEpisodeIds.clear()
    this.stats.resetForEpisode()
    this.currentRawDanmaku = []
    logger.info('DanmakuManager已释放')
  }

  private onDanmakuLoaded(items: DanmakuItem[]): void {
    this.currentRawDanmaku = items
    this.applyCurrentDanmakuData()
  }

  private insertCurrentRawDanmaku(item: DanmakuItem): void {
    let insertIndex = 0
    while (insertIndex < this.currentRawDanmaku.length && this.currentRawDanmaku[insertIndex].timeMs <= item.timeMs) {
      insertIndex++
    }
    this.currentRawDanmaku.splice(insertIndex, 0, item)
  }

  private applyCurrentDanmakuData(): void {
    if (this.timeSync !== null) {
      if (this.renderer !== null) {
        this.renderer.clearAll()
      }
      if (this.trackAllocator !== null) {
        this.trackAllocator.reset()
      }
      const playbackItems = this.currentSettings.deduplication
        ? DanmakuDeduplicator.mergeDuplicateDanmakus(this.currentRawDanmaku)
        : this.currentRawDanmaku
      if (this.currentSettings.deduplication && playbackItems.length !== this.currentRawDanmaku.length) {
        logger.info('弹幕去重完成: %{public}d -> %{public}d', this.currentRawDanmaku.length, playbackItems.length)
      }
      this.timeSync.setDanmakuData(playbackItems)
    }
  }

  private clearCurrentDanmaku(): void {
    if (this.timeSync !== null) {
      this.timeSync.reset()
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.reset()
    }
    if (this.renderer !== null) {
      this.renderer.clearAll()
    }
  }

  private stopRendering(): void {
    if (this.timeSync !== null) {
      this.timeSync.reset()
    }
    if (this.renderer !== null) {
      this.renderer.stopRendering()
      this.renderer.clearAll()
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.reset()
    }
  }

  private suspendDisplay(): void {
    if (this.timeSync !== null) {
      this.timeSync.suspendDisplay()
      return
    }
    if (this.renderer !== null) {
      this.renderer.stopRendering()
      this.renderer.clearAll()
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.reset()
    }
  }

  private cacheDanmaku(episodeKey: string, items: DanmakuItem[]): void {
    if (this.danmakuCache.size >= DANMAKU_CACHE_MAX_EPISODES) {
      const firstKey: string = this.danmakuCache.keys().next().value as string
      if (firstKey !== undefined) {
        this.danmakuCache.delete(firstKey)
      }
    }
    this.danmakuCache.set(episodeKey, items)
  }

  private refreshEpisodeCache(episodeId: number): void {
    if (episodeId <= 0 || this.refreshingEpisodeIds.has(episodeId)) {
      return
    }
    this.refreshingEpisodeIds.add(episodeId)
    this.apiService.fetchDanmaku(episodeId).then(async (response: DanmakuApiResponse) => {
      if (response.success && response.items.length > 0) {
        await this.persistentCache.put(episodeId, response.items)
      }
    }).catch((err: Error) => {
      logger.warn('后台刷新弹幕缓存失败: episodeId=%{public}d, err=%{public}s',
        episodeId, err instanceof Error ? err.message : String(err))
    }).finally(() => {
      this.refreshingEpisodeIds.delete(episodeId)
    })
  }

  private async consumePendingLoadRequest(finishedEpisodeKey: string): Promise<void> {
    const pending = this.pendingLoadRequest
    if (pending === null) {
      return
    }
    this.pendingLoadRequest = null
    if (pending.episodeKey === finishedEpisodeKey) {
      return
    }
    logger.info('执行排队的弹幕加载: key=%{public}s', pending.episodeKey)
    await this.loadDanmakuForEpisode(pending.animeName, pending.episodeIndex, pending.bangumiId, pending.episodeTitle, pending.sourceId, pending.episodeUrl)
  }

  private saveAutoMatchBinding(bangumiId: number, episodeNo: number, animeName: string,
    episodeId: number, animeId: number, sourceId: number = -1, episodeUrl: string = ''): void {
    const binding: DanmakuPlaybackBinding = new DanmakuPlaybackBinding()
    binding.episodeId = episodeId
    binding.animeId = animeId
    binding.animeTitle = ''
    binding.episodeTitle = ''
    this.bindingStore.saveBinding(bangumiId, episodeNo, animeName, binding, sourceId, episodeUrl).catch((_err: Error) => {})
  }

  private bindPendingCanvasIfReady(): void {
    if (this.pendingCanvasContext === null || this.pendingCanvasWidth <= 0 || this.pendingCanvasHeight <= 0) {
      return
    }
    if (this.trackAllocator !== null) {
      this.trackAllocator.updateCanvasSize(this.pendingCanvasWidth, this.pendingCanvasHeight)
    }
    if (this.renderer !== null) {
      this.renderer.setCanvasContext(this.pendingCanvasContext, this.pendingCanvasWidth, this.pendingCanvasHeight)
    }
    if (this.timeSync !== null) {
      this.timeSync.recoverAfterCanvasReady()
    }
  }
}
