import { PlayerState } from '../player/IPlayerEngine'
import { DanmakuItem } from '../../models/DanmakuItem'
import { DanmakuApiService, DanmakuApiResponse } from './DanmakuApiService'
import { DanmakuTimeSync } from './DanmakuTimeSync'
import { DanmakuTrackAllocator } from './DanmakuTrackAllocator'
import { DanmakuRenderer } from './DanmakuRenderer'
import { DanmakuEpisodeResolver } from './DanmakuEpisodeResolver'
import { DandanCredentialStore } from './DandanCredentialStore'
import { EpisodeNumberExtractor } from './EpisodeNumberExtractor'
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

export class DanmakuManager {
  private apiService: DanmakuApiService = new DanmakuApiService()
  private episodeResolver: DanmakuEpisodeResolver = new DanmakuEpisodeResolver()
  private timeSync: DanmakuTimeSync | null = null
  private trackAllocator: DanmakuTrackAllocator | null = null
  private renderer: DanmakuRenderer | null = null
  private danmakuCache: Map<string, DanmakuItem[]> = new Map()
  private isDanmakuEnabled: boolean = true
  private isLoading: boolean = false
  private currentEpisodeKey: string = ''
  private failureReason: string = ''

  async init(): Promise<void> {
    await DandanCredentialStore.getInstance().init()

    this.trackAllocator = new DanmakuTrackAllocator()
    this.renderer = new DanmakuRenderer(this.trackAllocator)
    this.timeSync = new DanmakuTimeSync(this.trackAllocator, this.renderer)

    try {
      const prefs = PreferencesStore.getInstance()
      this.isDanmakuEnabled = await prefs.getBoolean(DANMAKU_PREFS_KEY_ENABLED, true)
    } catch (_err) {
      this.isDanmakuEnabled = true
    }

    logger.info('DanmakuManager初始化完成, 弹幕开关=%{public}s', String(this.isDanmakuEnabled))
  }

  onPlayerStateUpdate(state: PlayerState): void {
    if (!this.isDanmakuEnabled) {
      return
    }
    if (this.timeSync !== null) {
      this.timeSync.onPlayerStateUpdate(state)
    }
  }

  async loadDanmakuForEpisode(animeName: string, episodeIndex: number,
    bangumiId: number = 0, episodeTitle: string = ''): Promise<void> {
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
        logger.warn('弹幕加载失败: %{public}s', this.failureReason)
        return
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
        logger.warn('弹幕加载失败: %{public}s', this.failureReason)
        return
      }

      logger.info('解析到episodeId=%{public}d, 开始加载弹幕', episodeId)
      const response: DanmakuApiResponse = await this.apiService.fetchDanmaku(episodeId)
      if (response.success) {
        if (response.items.length === 0) {
          this.failureReason = DANMAKU_FAILURE_EMPTY_COMMENTS
          logger.warn('弹幕加载失败: %{public}s', this.failureReason)
          return
        }
        logger.info('弹幕加载成功, episodeId=%{public}d, count=%{public}d',
          episodeId, response.items.length)
        this.failureReason = ''
        this.cacheDanmaku(episodeKey, response.items)
        if (episodeKey === this.currentEpisodeKey) {
          this.onDanmakuLoaded(response.items)
        }
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
      this.stopRendering()
    } else if (this.currentEpisodeKey.length > 0) {
      const lastUnderscore = this.currentEpisodeKey.lastIndexOf('_')
      if (lastUnderscore > 0) {
        const episodeIndex = parseInt(this.currentEpisodeKey.substring(lastUnderscore + 1), 10)
        const animeName = this.currentEpisodeKey.substring(0, lastUnderscore)
        const secondUnderscore = animeName.lastIndexOf('_')
        const realAnimeName = secondUnderscore > 0 ? animeName.substring(0, secondUnderscore) : animeName
        if (realAnimeName.length > 0 && !isNaN(episodeIndex)) {
          logger.info('弹幕重新加载: bangumiId信息丢失，使用标题搜索路径')
          this.loadDanmakuForEpisode(realAnimeName, episodeIndex)
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

  getRenderer(): DanmakuRenderer | null {
    return this.renderer
  }

  getDiscardCount(): number {
    if (this.trackAllocator !== null) {
      return this.trackAllocator.getDiscardCount()
    }
    return 0
  }

  onCanvasReady(context: CanvasRenderingContext2D, width: number, height: number): void {
    if (this.trackAllocator !== null) {
      this.trackAllocator.updateCanvasSize(width, height)
    }
    if (this.renderer !== null) {
      this.renderer.setCanvasContext(context, width, height)
    }
  }

  onCanvasSizeChanged(width: number, height: number): void {
    if (this.trackAllocator !== null) {
      this.trackAllocator.updateCanvasSize(width, height)
    }
    if (this.renderer !== null) {
      this.renderer.updateCanvasSize(width, height)
    }
    if (this.timeSync !== null) {
      this.timeSync.resyncAfterResize()
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
    logger.info('DanmakuManager已释放')
  }

  private onDanmakuLoaded(items: DanmakuItem[]): void {
    if (this.timeSync !== null) {
      this.timeSync.setDanmakuData(items)
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

  private cacheDanmaku(episodeKey: string, items: DanmakuItem[]): void {
    if (this.danmakuCache.size >= DANMAKU_CACHE_MAX_EPISODES) {
      const firstKey: string = this.danmakuCache.keys().next().value as string
      if (firstKey !== undefined) {
        this.danmakuCache.delete(firstKey)
      }
    }
    this.danmakuCache.set(episodeKey, items)
  }
}
