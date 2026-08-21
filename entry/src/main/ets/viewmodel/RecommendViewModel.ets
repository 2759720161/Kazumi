import { RecommendCardModel } from '../models/RecommendCardModel'
import { AnimeItem } from '../models/AnimeItem'
import { HistoryRecord } from '../models/HistoryRecord'
import { BangumiApi, BangumiSearchProgressOptions } from '../core/api/BangumiApi'
import { HistoryStore } from '../store/HistoryStore'
import { RECOMMEND_GENRE_TAGS } from '../constants/RecommendTags'
import { Logger } from '../utils/Logger'
import { isHomePreloadEnabled } from '../utils/HomePreloadGate'

const logger = new Logger('RecommendViewModel')
const HOME_SECTION_PAGE_SIZE: number = 24

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
  private trendingNextOffset: number = HOME_SECTION_PAGE_SIZE
  private seasonalNextOffset: number = HOME_SECTION_PAGE_SIZE
  private highScoreNextOffset: number = HOME_SECTION_PAGE_SIZE
  private trendingRemainingFinished: boolean = false
  private seasonalRemainingFinished: boolean = false
  private highScoreRemainingFinished: boolean = false
  private backgroundPreloadEnabled: boolean = true
  private backgroundPreloadGeneration: number = 0

  setBackgroundPreloadEnabled(enabled: boolean): void {
    if (this.backgroundPreloadEnabled === enabled) {
      return
    }
    this.backgroundPreloadEnabled = enabled
    this.backgroundPreloadGeneration++
    logger.info('Home background preload %{public}s', enabled ? 'resumed' : 'paused')
  }

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

  async loadByTag(tag: string, onProgress?: (items: RecommendCardModel[]) => void,
    shouldContinue?: () => boolean): Promise<void> {
    if (tag === this.currentTag) {
      if (onProgress) {
        onProgress(this.copyList(this.tagTopicList))
      }
      return
    }
    this.currentTag = tag
    this.tagTopicList = []
    try {
      const options = new BangumiSearchProgressOptions()
      options.shouldContinue = shouldContinue
      options.onResults = (items: AnimeItem[]): void => {
        if ((shouldContinue && !shouldContinue()) || this.currentTag !== tag) {
          return
        }
        this.tagTopicList = this.buildRecommendModels(items)
        if (onProgress) {
          onProgress(this.copyList(this.tagTopicList))
        }
      }
      const results = await BangumiApi.searchAnimeProgressive('', [tag], 'rank', options)
      if ((shouldContinue && !shouldContinue()) || this.currentTag !== tag) {
        return
      }
      this.tagTopicList = this.buildRecommendModels(results)
      if (onProgress) {
        onProgress(this.copyList(this.tagTopicList))
      }
      logger.info('loadByTag: tag=%{public}s count=%{public}d', tag, this.tagTopicList.length)
    } catch (err) {
      logger.warn('loadByTag failed for %{public}s', tag)
    }
  }

  async loadRemainingTrending(onProgress?: (items: RecommendCardModel[]) => void,
    shouldContinue?: () => boolean): Promise<void> {
    await this.loadRemainingSection(
      this.trendingList,
      async (offset: number): Promise<AnimeItem[]> => BangumiApi.getTrendsList(offset),
      onProgress,
      shouldContinue,
      'trending',
      HOME_SECTION_PAGE_SIZE
    )
  }

  async loadRemainingHighScore(onProgress?: (items: RecommendCardModel[]) => void,
    shouldContinue?: () => boolean,
    maxItems: number = 0): Promise<void> {
    await this.loadRemainingSection(
      this.highScoreList,
      async (offset: number): Promise<AnimeItem[]> =>
        BangumiApi.searchHighScoreSubjects(HOME_SECTION_PAGE_SIZE, offset),
      onProgress,
      shouldContinue,
      'highScore',
      HOME_SECTION_PAGE_SIZE,
      maxItems
    )
  }

  async loadRemainingSeasonal(onProgress?: (items: RecommendCardModel[]) => void,
    shouldContinue?: () => boolean): Promise<void> {
    const range = BangumiApi.getCurrentSeasonRange()
    await this.loadRemainingSection(
      this.seasonalList,
      async (offset: number): Promise<AnimeItem[]> =>
        BangumiApi.searchSeasonalSubjects(range.start, range.end, HOME_SECTION_PAGE_SIZE, offset),
      onProgress,
      shouldContinue,
      'seasonal',
      HOME_SECTION_PAGE_SIZE
    )
  }

  async loadHomeTrending(): Promise<RecommendCardModel[]> {
    await this.loadTrending()
    return this.copyList(this.trendingList)
  }

  async loadHomeSeasonal(): Promise<RecommendCardModel[]> {
    this.seasonLabel = BangumiApi.getCurrentSeasonLabel()
    await this.loadSeasonal()
    return this.copyList(this.seasonalList)
  }

  async loadHomeHighScore(): Promise<RecommendCardModel[]> {
    await this.loadHighScore()
    return this.copyList(this.highScoreList)
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

    this.heroList = candidates
    return this.copyList(this.heroList)
  }

  async enrichHomeHeroList(): Promise<RecommendCardModel[]> {
    await this.enrichHeroList(this.heroList)
    return this.copyList(this.heroList)
  }

  private async loadTrending(): Promise<void> {
    this.trendingNextOffset = HOME_SECTION_PAGE_SIZE
    this.trendingRemainingFinished = false
    const results = await BangumiApi.getTrendsList(0, HOME_SECTION_PAGE_SIZE)
    // The server may return fewer items than requested. The next offset must
    // follow the actual response length, otherwise the missing tail is skipped.
    this.trendingNextOffset = results.length
    const models: RecommendCardModel[] = []
    for (let i = 0; i < results.length; i++) {
      models.push(RecommendCardModel.fromAnimeItem(results[i]))
    }
    this.trendingList = models
  }

  private async loadSeasonal(): Promise<void> {
    this.seasonalNextOffset = HOME_SECTION_PAGE_SIZE
    this.seasonalRemainingFinished = false
    const range = BangumiApi.getCurrentSeasonRange()
    const results = await BangumiApi.searchSeasonalSubjects(range.start, range.end, HOME_SECTION_PAGE_SIZE, 0)
    this.seasonalNextOffset = results.length
    const models: RecommendCardModel[] = []
    for (let i = 0; i < results.length; i++) {
      models.push(RecommendCardModel.fromAnimeItem(results[i]))
    }
    this.seasonalList = models
  }

  private async loadHighScore(): Promise<void> {
    this.highScoreNextOffset = HOME_SECTION_PAGE_SIZE
    this.highScoreRemainingFinished = false
    const results = await BangumiApi.searchHighScoreSubjects(HOME_SECTION_PAGE_SIZE, 0)
    this.highScoreNextOffset = results.length
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

  private copyList(items: RecommendCardModel[]): RecommendCardModel[] {
    const models: RecommendCardModel[] = []
    for (let i = 0; i < items.length; i++) {
      models.push(RecommendCardModel.copyOf(items[i]))
    }
    return models
  }

  private buildRecommendModels(items: AnimeItem[]): RecommendCardModel[] {
    const models: RecommendCardModel[] = []
    for (let i = 0; i < items.length; i++) {
      models.push(RecommendCardModel.fromAnimeItem(items[i]))
    }
    return models
  }

  private async loadRemainingSection(target: RecommendCardModel[],
    loader: (offset: number) => Promise<AnimeItem[]>,
    onProgress?: (items: RecommendCardModel[]) => void,
    shouldContinue?: () => boolean,
    sectionName: string = 'section',
    initialOffset: number = HOME_SECTION_PAGE_SIZE,
    maxItems: number = 0): Promise<void> {
    if (!this.canRunBackgroundPreload()) {
      return
    }
    if (this.isRemainingFinished(sectionName)) {
      return
    }

    if (maxItems > 0 && target.length >= maxItems) {
      return
    }

    let offset = this.getRemainingOffset(sectionName, initialOffset)
    let pageCount = 0
    const preloadGeneration = this.backgroundPreloadGeneration
    try {
      // Keep loading metadata until the source is exhausted. The old implementation
      // used this loop, which prevents the horizontal rail from depending on a second
      // edge gesture after every page. Images remain lazy-loaded by the card component.
      while (this.canRunBackgroundPreload(preloadGeneration) && (!shouldContinue || shouldContinue())) {
        const results = await loader(offset)
        if (!this.canRunBackgroundPreload(preloadGeneration) || (shouldContinue && !shouldContinue())) {
          return
        }

        const addedCount = this.appendUniqueModels(target, results, maxItems)
        if (addedCount > 0 && onProgress) {
          onProgress(this.copyList(target))
        }

        pageCount++
        logger.info('loadRemainingSection: section=%{public}s offset=%{public}d added=%{public}d count=%{public}d',
          sectionName, offset, addedCount, target.length)

        if (results.length === 0 || addedCount === 0) {
          this.markRemainingFinished(sectionName)
          break
        }

        // The automatic prefetch limit is only a temporary budget. Once the
        // user reaches the rail end, the next call can continue paging.
        if (maxItems > 0 && target.length >= maxItems) {
          break
        }

        // Use the actual response size. Some mirror endpoints return fewer items
        // than requested while still having more data at the next offset.
        offset += results.length
        this.setRemainingOffset(sectionName, offset)
      }
      logger.info('loadRemainingSection complete: section=%{public}s pages=%{public}d count=%{public}d',
        sectionName, pageCount, target.length)
    } catch (err) {
      logger.warn('loadRemainingSection failed for %{public}s', sectionName)
    }
  }

  private canRunBackgroundPreload(generation: number = this.backgroundPreloadGeneration): boolean {
    return this.backgroundPreloadEnabled &&
      generation === this.backgroundPreloadGeneration &&
      isHomePreloadEnabled()
  }

  private getRemainingOffset(sectionName: string, initialOffset: number): number {
    if (sectionName === 'trending') {
      return this.trendingNextOffset
    }
    if (sectionName === 'seasonal') {
      return this.seasonalNextOffset
    }
    if (sectionName === 'highScore') {
      return this.highScoreNextOffset
    }
    return initialOffset
  }

  private setRemainingOffset(sectionName: string, nextOffset: number): void {
    if (sectionName === 'trending') {
      this.trendingNextOffset = nextOffset
    } else if (sectionName === 'seasonal') {
      this.seasonalNextOffset = nextOffset
    } else if (sectionName === 'highScore') {
      this.highScoreNextOffset = nextOffset
    }
  }

  private isRemainingFinished(sectionName: string): boolean {
    if (sectionName === 'trending') {
      return this.trendingRemainingFinished
    }
    if (sectionName === 'seasonal') {
      return this.seasonalRemainingFinished
    }
    if (sectionName === 'highScore') {
      return this.highScoreRemainingFinished
    }
    return false
  }

  private markRemainingFinished(sectionName: string): void {
    if (sectionName === 'trending') {
      this.trendingRemainingFinished = true
    } else if (sectionName === 'seasonal') {
      this.seasonalRemainingFinished = true
    } else if (sectionName === 'highScore') {
      this.highScoreRemainingFinished = true
    }
  }

  private appendUniqueModels(target: RecommendCardModel[], items: AnimeItem[], maxItems: number = 0): number {
    const seenKeys: Set<string> = new Set()
    for (let i = 0; i < target.length; i++) {
      seenKeys.add(this.getRecommendModelKey(target[i]))
    }
    let addedCount = 0
    for (let i = 0; i < items.length; i++) {
      if (maxItems > 0 && target.length >= maxItems) {
        break
      }
      const model = RecommendCardModel.fromAnimeItem(items[i])
      const key = this.getRecommendModelKey(model)
      if (seenKeys.has(key)) {
        continue
      }
      seenKeys.add(key)
      target.push(model)
      addedCount++
    }
    return addedCount
  }

  private getRecommendModelKey(item: RecommendCardModel): string {
    if (item.bangumiId > 0) {
      return 'id:' + item.bangumiId.toString()
    }
    return 'title:' + item.title + ':' + item.originalTitle
  }
}
