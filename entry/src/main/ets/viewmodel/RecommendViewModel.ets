import { RecommendCardModel } from '../models/RecommendCardModel'
import { AnimeItem } from '../models/AnimeItem'
import { HistoryRecord } from '../models/HistoryRecord'
import { BangumiApi } from '../core/api/BangumiApi'
import { HistoryStore } from '../store/HistoryStore'
import { RECOMMEND_GENRE_TAGS } from '../constants/RecommendTags'
import { Logger } from '../utils/Logger'

const logger = new Logger('RecommendViewModel')

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

      await this.buildHeroList()
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

  async loadHomeTrending(): Promise<RecommendCardModel[]> {
    await this.loadTrending()
    return [...this.trendingList]
  }

  async loadHomeSeasonal(): Promise<RecommendCardModel[]> {
    this.seasonLabel = BangumiApi.getCurrentSeasonLabel()
    await this.loadSeasonal()
    return [...this.seasonalList]
  }

  async loadHomeHighScore(): Promise<RecommendCardModel[]> {
    await this.loadHighScore()
    return [...this.highScoreList]
  }

  async buildHomeHeroFromTrending(): Promise<RecommendCardModel[]> {
    const candidates: RecommendCardModel[] = []
    const usedIds: Set<number> = new Set()
    const heroLimit = 5

    for (let i = 0; i < this.trendingList.length && candidates.length < heroLimit; i++) {
      const item = this.trendingList[i]
      if (!usedIds.has(item.id) && item.backdrop.length > 0) {
        usedIds.add(item.id)
        candidates.push(item)
      }
    }

    await this.enrichHeroList(candidates)
    this.heroList = candidates
    return [...this.heroList]
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

  private async buildHeroList(): Promise<void> {
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

    await this.enrichHeroList(candidates)
    this.heroList = candidates
  }

  private async enrichHeroList(items: RecommendCardModel[]): Promise<void> {
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (!this.shouldFetchHeroDetail(item)) {
        continue
      }

      try {
        const detail = await BangumiApi.getSubject(item.bangumiId)
        if (detail !== null) {
          this.applyHeroDetail(item, RecommendCardModel.fromAnimeItem(detail))
        }
      } catch (err) {
        logger.warn('enrichHeroList failed for %{public}d', item.bangumiId)
      }
    }
  }

  private shouldFetchHeroDetail(item: RecommendCardModel): boolean {
    if (item.bangumiId <= 0) {
      return false
    }
    return item.summary.length === 0 ||
      item.score <= 0 ||
      item.rank <= 0 ||
      item.tags.length === 0 ||
      item.eps <= 0 ||
      item.date.length === 0
  }

  private applyHeroDetail(target: RecommendCardModel, detail: RecommendCardModel): void {
    if (target.title.length === 0 && detail.title.length > 0) target.title = detail.title
    if (target.originalTitle.length === 0 && detail.originalTitle.length > 0) target.originalTitle = detail.originalTitle
    if (target.cover.length === 0 && detail.cover.length > 0) target.cover = detail.cover
    if (target.coverLarge.length === 0 && detail.coverLarge.length > 0) target.coverLarge = detail.coverLarge
    if (target.backdrop.length === 0 && detail.getHeroBackdrop().length > 0) target.backdrop = detail.getHeroBackdrop()
    if (target.summary.length === 0 && detail.summary.length > 0) target.summary = detail.summary
    if (target.score <= 0 && detail.score > 0) target.score = detail.score
    if (target.rank <= 0 && detail.rank > 0) target.rank = detail.rank
    if (target.votes <= 0 && detail.votes > 0) target.votes = detail.votes
    if (target.date.length === 0 && detail.date.length > 0) target.date = detail.date
    if (target.year.length === 0 && detail.year.length > 0) target.year = detail.year
    if (target.platform.length === 0 && detail.platform.length > 0) target.platform = detail.platform
    if (target.tags.length === 0 && detail.tags.length > 0) target.tags = [...detail.tags]
    if (target.eps <= 0 && detail.eps > 0) target.eps = detail.eps
    if (target.coverFallback.length === 0 && detail.coverFallback.length > 0) target.coverFallback = detail.coverFallback
    if (target.coverCommon.length === 0 && detail.coverCommon.length > 0) target.coverCommon = detail.coverCommon
    if (target.coverMedium.length === 0 && detail.coverMedium.length > 0) target.coverMedium = detail.coverMedium
    if (target.bangumiCover.length === 0 && detail.bangumiCover.length > 0) target.bangumiCover = detail.bangumiCover
    if (target.aliases.length === 0 && detail.aliases.length > 0) target.aliases = [...detail.aliases]
    if (target.airWeekday <= 0 && detail.airWeekday > 0) target.airWeekday = detail.airWeekday
    if (target.votesCount.length === 0 && detail.votesCount.length > 0) target.votesCount = [...detail.votesCount]
  }
}
