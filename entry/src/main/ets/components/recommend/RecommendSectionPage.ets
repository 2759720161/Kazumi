import { BangumiApi } from '../../core/api/BangumiApi'
import { AnimeItem } from '../../models/AnimeItem'
import { RecommendCardModel } from '../../models/RecommendCardModel'
import { Logger } from '../../utils/Logger'
import { RecommendCard } from './RecommendCard'
import { ErrorRetry } from '../common/ErrorRetry'
import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import { RecommendSectionCache, RecommendSectionType } from '../../utils/RecommendSectionCache'

const logger = new Logger('RecommendSectionPage')
const SECTION_PAGE_SIZE: number = 24
const SECTION_RENDER_BATCH: number = 24
const SECTION_CARD_GAP: number = 10

@Component
export struct RecommendSectionPage {
  @Prop sectionType: RecommendSectionType = RecommendSectionType.TRENDING
  @Prop title: string = ''
  @Prop showRank: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State items: RecommendCardModel[] = []
  @State isLoading: boolean = true
  @State isLoadingMore: boolean = false
  @State loadError: boolean = false
  @State hasMore: boolean = true
  @State isPageActive: boolean = true
  // Keep the render window small when the cache already contains many items.
  @State renderedItemCount: number = SECTION_RENDER_BATCH
  private nextOffset: number = 0
  private requestVersion: number = 0
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.isPageActive = true
    this.isLoadingMore = false
    const cachedItems = RecommendSectionCache.get(this.sectionType)
    if (cachedItems.length === 0) {
      // Let the navigation render its first frame before starting the request.
      setTimeout(() => {
        if (this.isPageActive) {
          this.loadInitial()
        }
      }, 0)
      return
    }
    this.requestVersion++
    this.items = cachedItems
    this.renderedItemCount = Math.min(SECTION_RENDER_BATCH, cachedItems.length)
    this.nextOffset = cachedItems.length
    this.isLoading = false
    this.loadError = false
    this.hasMore = true
    const version = this.requestVersion
    setTimeout(() => {
      if (this.isPageActive && version === this.requestVersion) {
        // Reveal cached metadata in small batches so a large home preload does
        // not make the first page build hundreds of GridItems at once.
        this.revealCachedItems(version)
        this.loadRemainingPages(version, cachedItems.length)
      }
    }, 0)
  }

  aboutToDisappear(): void {
    this.isPageActive = false
    this.isLoadingMore = false
    this.requestVersion++
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')
            .hitTestBehavior(HitTestMode.None)

          if (this.isLoading) {
            this.SkeletonGrid()
          } else if (this.loadError && this.items.length === 0) {
            Column() {
              ErrorRetry({
                message: '暂时无法加载番组内容',
                onRetry: () => {
                  this.loadInitial()
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.items.length === 0) {
            Text('暂无番组内容')
              .fontSize(14)
              .fontColor($r('app.color.text_hint'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 48, bottom: 48 })
          } else {
            this.PosterGrid()
          }

          if (this.isLoadingMore) {
            Row() {
              LoadingProgress()
                .width(22)
                .height(22)
                .color($r('app.color.accent_blue'))
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)
          }

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .clip(false)
      .onScrollEdge((side: Edge) => {
        if (side === Edge.Bottom) {
          this.expandRenderedWindow()
        }
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions(this.title, this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.home_bg_top'), 0],
        [$r('app.color.page_background'), 0.35],
        [$r('app.color.page_background'), 1]
      ]
    })
  }

  @Builder
  private PosterGrid(): void {
    Grid() {
      ForEach(this.getRenderedItems(), (item: RecommendCardModel, index?: number) => {
        GridItem() {
          RecommendCard({
            item: item,
            showRank: this.showRank,
            cardWidth: this.getCardWidth(),
            sharedCoverIdPrefix: this.sectionType,
            loadEnabled: this.isPageActive,
            pauseWhenHomeInactive: false
          })
        }
        .height(this.getCardHeight())
      }, (item: RecommendCardModel, index?: number) =>
        'section_item_' + this.getItemKey(item) + '_' + (index ?? 0).toString())
    }
    .width('100%')
    .columnsTemplate(this.getGridColumns())
    .columnsGap(SECTION_CARD_GAP)
    .rowsGap(SECTION_CARD_GAP)
    .scrollBar(BarState.Off)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private SkeletonGrid(): void {
    Grid() {
      ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
        GridItem() {
          Column({ space: 8 }) {
            Column()
              .width('100%')
              .height(this.getPosterHeight())
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
            Column()
              .width('78%')
              .height(14)
              .borderRadius(7)
              .backgroundColor($r('app.color.card_background'))
          }
          .width('100%')
          .height(this.getCardHeight())
          .alignItems(HorizontalAlign.Start)
        }
      }, (index: number) => 'section_skeleton_' + index.toString())
    }
    .width('100%')
    .columnsTemplate(this.getGridColumns())
    .columnsGap(SECTION_CARD_GAP)
    .rowsGap(SECTION_CARD_GAP)
    .scrollBar(BarState.Off)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  private async loadInitial(): Promise<void> {
    const version = ++this.requestVersion
    this.isLoading = true
    this.isLoadingMore = false
    this.loadError = false
    this.hasMore = true
    this.nextOffset = 0
    this.items = []
    this.renderedItemCount = SECTION_RENDER_BATCH
    try {
      const results = await this.fetchItems(0)
      if (version !== this.requestVersion) {
        return
      }
      this.items = this.buildModels(results)
      RecommendSectionCache.set(this.sectionType, this.items)
      this.nextOffset = results.length
      // The mirror may cap a request for 24 items to 20 items. A short but
      // non-empty page is still a valid page, so do not treat it as EOF.
      this.hasMore = results.length > 0
      this.renderedItemCount = Math.min(SECTION_RENDER_BATCH, this.items.length)
      this.isLoading = false
      if (results.length > 0 && this.hasMore) {
        await this.loadRemainingPages(version, results.length)
      }
    } catch (err) {
      if (version === this.requestVersion) {
        this.loadError = true
        logger.warn('Initial section load failed: %{public}s', err instanceof Error ? err.message : String(err))
      }
    } finally {
      if (version === this.requestVersion) {
        this.isLoading = false
        this.isLoadingMore = false
      }
    }
  }

  private async loadRemainingPages(version: number, startOffset: number): Promise<void> {
    if (this.isLoadingMore || !this.hasMore || !this.isPageActive || version !== this.requestVersion) {
      return
    }
    this.isLoadingMore = true
    let offset = startOffset
    let merged = this.items.slice()
    try {
      while (this.isPageActive && version === this.requestVersion && this.hasMore) {
        const results = await this.fetchItems(offset)
        if (!this.isPageActive || version !== this.requestVersion) {
          return
        }
        if (results.length === 0) {
          this.hasMore = false
          break
        }

        const nextItems = this.appendUnique(merged, results)
        if (nextItems.length === merged.length) {
          this.hasMore = false
          break
        }
        const addedCount = nextItems.length - merged.length
        merged = nextItems
        this.items = merged.slice()
        RecommendSectionCache.set(this.sectionType, this.items)
        offset += results.length
        this.nextOffset = offset
        // Do not compare with SECTION_PAGE_SIZE here. Bangumi mirrors can
        // return fewer items than requested while still having more pages.
        // Empty or duplicate pages are handled above as the end condition.
        this.hasMore = results.length > 0
        // Publish each batch immediately. The first batch is intentionally
        // capped, while later batches become renderable as soon as metadata
        // arrives, matching the progressive category-topic experience.
        this.renderedItemCount = Math.min(
          this.items.length,
          this.renderedItemCount + Math.max(addedCount, 1)
        )
        logger.info('section batch: type=%{public}s offset=%{public}d returned=%{public}d total=%{public}d rendered=%{public}d',
          this.sectionType,
          (offset - results.length),
          results.length,
          this.items.length,
          this.renderedItemCount)
        // Yield between pages so Grid layout and image decoding do not block
        // the next frame or interrupt a continuous user scroll.
        await this.yieldToUi()
      }
    } catch (err) {
      logger.warn('Load more section failed: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      if (version === this.requestVersion) {
        this.isLoadingMore = false
      }
    }
  }

  private async yieldToUi(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 0)
    })
  }

  private async revealCachedItems(version: number): Promise<void> {
    while (this.isPageActive && version === this.requestVersion &&
      this.renderedItemCount < this.items.length) {
      this.renderedItemCount = Math.min(
        this.items.length,
        this.renderedItemCount + SECTION_RENDER_BATCH
      )
      await this.yieldToUi()
    }
  }

  private async fetchItems(offset: number): Promise<AnimeItem[]> {
    if (this.sectionType === RecommendSectionType.SEASONAL) {
      const range = BangumiApi.getCurrentSeasonRange()
      return BangumiApi.searchSeasonalSubjects(range.start, range.end, SECTION_PAGE_SIZE, offset)
    }
    if (this.sectionType === RecommendSectionType.HIGH_SCORE) {
      return BangumiApi.searchHighScoreSubjects(SECTION_PAGE_SIZE, offset)
    }
    return BangumiApi.getTrendsList(offset, SECTION_PAGE_SIZE)
  }

  private buildModels(items: AnimeItem[]): RecommendCardModel[] {
    const result: RecommendCardModel[] = []
    for (let i = 0; i < items.length; i++) {
      result.push(RecommendCardModel.fromAnimeItem(items[i]))
    }
    return result
  }

  private appendUnique(current: RecommendCardModel[], incoming: AnimeItem[]): RecommendCardModel[] {
    const result: RecommendCardModel[] = []
    const seen: Set<string> = new Set()
    for (let i = 0; i < current.length; i++) {
      result.push(current[i])
      seen.add(this.getItemKey(current[i]))
    }
    for (let i = 0; i < incoming.length; i++) {
      const model = RecommendCardModel.fromAnimeItem(incoming[i])
      const key = this.getItemKey(model)
      if (!seen.has(key)) {
        seen.add(key)
        result.push(model)
      }
    }
    return result
  }

  private getItemKey(item: RecommendCardModel): string {
    const subjectId = item.bangumiId > 0 ? item.bangumiId : item.id
    return subjectId > 0 ? 'id:' + subjectId.toString() : 'title:' + item.title
  }

  private getRenderedItems(): RecommendCardModel[] {
    const result: RecommendCardModel[] = []
    const count = Math.min(this.items.length, this.renderedItemCount)
    for (let i = 0; i < count; i++) {
      result.push(this.items[i])
    }
    return result
  }

  private expandRenderedWindow(): void {
    if (this.renderedItemCount >= this.items.length) {
      return
    }
    this.renderedItemCount = Math.min(
      this.items.length,
      this.renderedItemCount + SECTION_RENDER_BATCH
    )
  }

  private getColumnCount(): number {
    if (this.screenWidthVp >= 840) {
      return 5
    }
    if (this.screenWidthVp >= 600) {
      return 4
    }
    return 3
  }

  private getGridColumns(): string {
    if (this.screenWidthVp >= 840) {
      return '1fr 1fr 1fr 1fr 1fr'
    }
    if (this.screenWidthVp >= 600) {
      return '1fr 1fr 1fr 1fr'
    }
    return '1fr 1fr 1fr'
  }

  private getCardWidth(columnCount: number = this.getColumnCount()): number {
    const availableWidth = Math.max(0, this.screenWidthVp - 32 - SECTION_CARD_GAP * (columnCount - 1))
    return Math.floor(availableWidth / columnCount)
  }

  private getPosterHeight(): number {
    return Math.round(this.getCardWidth() * 4 / 3)
  }

  private getCardHeight(): number {
    return this.getPosterHeight() + 44
  }
}
