import { RecommendCardModel } from '../models/RecommendCardModel'
import { AnimeItem } from '../models/AnimeItem'
import { HistoryRecord } from '../models/HistoryRecord'
import { BangumiApi } from '../core/api/BangumiApi'
import { HistoryStore } from '../store/HistoryStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('RecommendViewModel')

const GENRE_TAGS: string[] = [
  '日常', '原创', '校园', '搞笑', '奇幻',
  '百合', '恋爱', '悬疑', '热血', '后宫',
  '机战', '轻改', '偶像', '治愈', '异世界'
]

export class RecommendViewModel {
  heroList: RecommendCardModel[] = []
  trendingList: RecommendCardModel[] = []
  seasonalList: RecommendCardModel[] = []
  highScoreList: RecommendCardModel[] = []
  tagTopicList: RecommendCardModel[] = []
  continueWatching: HistoryRecord[] = []
  isLoading: boolean = false
  isInitialLoaded: boolean = false
  currentTag: string = ''
  seasonLabel: string = ''

  private historyStore: HistoryStore = new HistoryStore()

  async load(): Promise<void> {
    if (this.isLoading) {
      return
    }
    this.isLoading = true
    this.seasonLabel = BangumiApi.getCurrentSeasonLabel()

    try {
      const results = await Promise.all([
        this.loadTrending(),
        this.loadSeasonal(),
        this.loadHighScore(),
        this.loadContinueWatching()
      ])

      this.buildHeroList()
      this.isInitialLoaded = true
      logger.info('RecommendViewModel load complete: hero=%{public}d trending=%{public}d seasonal=%{public}d highScore=%{public}d history=%{public}d',
        this.heroList.length, this.trendingList.length, this.seasonalList.length,
        this.highScoreList.length, this.continueWatching.length)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('RecommendViewModel load failed: %{public}s', msg)
    } finally {
      this.isLoading = false
    }
  }

  async loadByTag(tag: string): Promise<void> {
    if (tag === this.currentTag) {
      return
    }
    this.currentTag = tag
    this.tagTopicList = []
    try {
      const results = await BangumiApi.searchByTagWithSort(tag, 'rank', 24, 0)
      const models: RecommendCardModel[] = []
      for (let i = 0; i < results.length; i++) {
        models.push(RecommendCardModel.fromAnimeItem(results[i]))
      }
      this.tagTopicList = models
      logger.info('loadByTag: tag=%{public}s count=%{public}d', tag, this.tagTopicList.length)
    } catch (err) {
      logger.warn('loadByTag failed for %{public}s', tag)
    }
  }

  async loadMoreTrending(): Promise<void> {
    try {
      const results = await BangumiApi.getTrendsList(this.trendingList.length)
      for (let i = 0; i < results.length; i++) {
        this.trendingList.push(RecommendCardModel.fromAnimeItem(results[i]))
      }
    } catch (err) {
      logger.warn('loadMoreTrending failed')
    }
  }

  async loadMoreHighScore(): Promise<void> {
    try {
      const results = await BangumiApi.searchHighScoreSubjects(24, this.highScoreList.length)
      for (let i = 0; i < results.length; i++) {
        this.highScoreList.push(RecommendCardModel.fromAnimeItem(results[i]))
      }
    } catch (err) {
      logger.warn('loadMoreHighScore failed')
    }
  }

  async loadMoreSeasonal(): Promise<void> {
    try {
      const range = BangumiApi.getCurrentSeasonRange()
      const results = await BangumiApi.searchSeasonalSubjects(range.start, range.end, 24, this.seasonalList.length)
      for (let i = 0; i < results.length; i++) {
        this.seasonalList.push(RecommendCardModel.fromAnimeItem(results[i]))
      }
    } catch (err) {
      logger.warn('loadMoreSeasonal failed')
    }
  }

  private async loadTrending(): Promise<void> {
    const results = await BangumiApi.getTrendsList(0)
    const models: RecommendCardModel[] = []
    for (let i = 0; i < results.length; i++) {
      models.push(RecommendCardModel.fromAnimeItem(results[i]))
    }
    this.trendingList = models
  }

  private async loadSeasonal(): Promise<void> {
    const range = BangumiApi.getCurrentSeasonRange()
    const results = await BangumiApi.searchSeasonalSubjects(range.start, range.end, 24, 0)
    const models: RecommendCardModel[] = []
    for (let i = 0; i < results.length; i++) {
      models.push(RecommendCardModel.fromAnimeItem(results[i]))
    }
    this.seasonalList = models
  }

  private async loadHighScore(): Promise<void> {
    const results = await BangumiApi.searchHighScoreSubjects(24, 0)
    const models: RecommendCardModel[] = []
    for (let i = 0; i < results.length; i++) {
      models.push(RecommendCardModel.fromAnimeItem(results[i]))
    }
    this.highScoreList = models
  }

  private async loadContinueWatching(): Promise<void> {
    try {
      this.continueWatching = await this.historyStore.getAll()
    } catch (err) {
      this.continueWatching = []
    }
  }

  async refreshContinueWatching(): Promise<void> {
    try {
      this.continueWatching = await this.historyStore.getAll()
    } catch (err) {
      this.continueWatching = []
    }
  }

  private buildHeroList(): void {
    const candidates: RecommendCardModel[] = []
    const usedIds: Set<number> = new Set()
    const heroLimit = 5

    const addFromList = (list: RecommendCardModel[], maxCount: number): void => {
      let added = 0
      for (let i = 0; i < list.length && candidates.length < heroLimit && added < maxCount; i++) {
        const item = list[i]
        if (!usedIds.has(item.id) && item.backdrop.length > 0) {
          usedIds.add(item.id)
          candidates.push(item)
          added++
        }
      }
    }

    addFromList(this.trendingList, 3)
    addFromList(this.highScoreList, 2)

    this.heroList = candidates
  }
}
