import { AnimeItem } from '../../models/AnimeItem'
import { AnimeCard } from '../../components/common/AnimeCard'
import { LoadingOverlay } from '../../components/common/LoadingOverlay'
import { EmptyState } from '../../components/common/EmptyState'
import { BangumiApi } from '../../core/api/BangumiApi'
import { SearchHistoryStore } from '../../store/SearchHistoryStore'
import { SearchHistory } from '../../models/SearchHistory'
import { Logger } from '../../utils/Logger'
import { LengthMetrics, router } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitle,
  TitleBarContentOptions
} from '@kit.UIDesignKit'
import {
  DEFAULT_TOP_SAFE_HEIGHT,
  MINI_TITLE_BAR_CONTENT_HEIGHT,
  HDS_FLOATING_TAB_CONTENT_SPACER,
  getEffectiveTopSafeHeight as getEffectiveTopSafe,
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'

const logger = new Logger('HomePage')

const CATEGORY_MENU_WIDTH: number = 216
const CATEGORY_MENU_MAX_HEIGHT: number = 420
const CATEGORY_MENU_ANIMATION_DURATION: number = 150
const CATEGORY_MENU_DISAPPEAR_ANIMATION_DURATION: number = 120


const GENRE_TAGS: string[] = [
  '日常', '原创', '校园', '搞笑', '奇幻',
  '百合', '恋爱', '悬疑', '热血', '后宫',
  '机战', '轻改', '偶像', '治愈', '异世界'
]

const MENU_LABELS: string[] = ['热门', ...GENRE_TAGS]

@Component
export struct HomePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @State currentTag: string = '热门番组'
  @State trendList: AnimeItem[] = []
  @State bangumiList: AnimeItem[] = []
  @State isLoading: boolean = false
  @State isLoadingMore: boolean = false
  @State isTimeOut: boolean = false
  @State isSearching: boolean = false
  @State searchKeyword: string = ''
  @State searchResults: AnimeItem[] = []
  @State showSearchView: boolean = false
  @State scrollOffset: number = 0
  @State showCategoryMenu: boolean = false
  @State searchHistory: SearchHistory[] = []

  private scroller: Scroller = new Scroller()
  private searchScroller: Scroller = new Scroller()
  private canLoadMore: boolean = true
  private searchHistoryStore: SearchHistoryStore = new SearchHistoryStore()

  aboutToAppear(): void {

    this.loadTrends()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showSearchView) {
        HdsNavigation() {
          Scroll(this.searchScroller) {
            this.SearchView()
          }
          .width('100%')
          .height('100%')
          .edgeEffect(EdgeEffect.Spring)
          .clip(false)
        }
        .width('100%')
        .height('100%')
        .titleBar({
          enableComponentSafeArea: false,
          avoidLayoutSafeArea: true,
          content: {
            title: {
              mainTitle: '搜索'
            },
            bottomBuilder: {
              builder: (): void => {
                this.SearchBottomBar()
              }
            },
            menu: {
              value: [{
                content: {
                  icon: $r('sys.symbol.xmark'),
                  label: 'close',
                  action: () => {
                    this.showSearchView = false
                    this.isSearching = false
                    this.searchResults = []
                    this.searchKeyword = ''
                  }
                }
              }]
            }
          },
          style: buildImmersiveTitleBarStyle()
        })
        .bindToScrollable([this.searchScroller])
        .hideBackButton(true)
        .titleMode(HdsNavigationTitleMode.MINI)
        .backgroundColor(Color.Transparent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      } else {
        this.HomeNavigationContent()
      }

      if (!this.showSearchView && this.scrollOffset > 800) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
        .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
        .position({ x: '87%', y: '90%' })
        .onClick(() => {
          this.scroller.scrollEdge(Edge.Top)
        })
      }

      if (!this.showSearchView && this.showCategoryMenu) {
        this.CategoryMenuOverlay()
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
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
  private HomeNavigationContent() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(this.getHomeTopSpacerHeight())
            .width('100%')

          if (this.isLoading && this.currentList().length === 0) {
            LoadingOverlay({ message: '加载中...' })
          } else if (this.isTimeOut) {
            this.ErrorView()
          } else {
            Grid() {
              ForEach(this.currentList(), (item: AnimeItem, index?: number) => {
                GridItem() {
                  this.PopularCard(item)
                }
              }, (item: AnimeItem, index?: number) => `pop_${index}_${item.name}`)
            }
            .columnsTemplate(this.getGridColumns())
            .columnsGap(8)
            .rowsGap(8)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          }

          Blank()
            .height(this.getHomeBottomSpacerHeight())
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .clip(false)
      .onScrollFrameBegin((offset: number) => {
        this.scrollOffset = this.scroller.currentOffset().yOffset
        return { offsetRemain: offset }
      })
      .onReachEnd(() => {
        this.checkLoadMore()
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(this.buildHomeTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private SearchBottomBar() {
    Row() {
      TextInput({ placeholder: '搜索动漫...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor($r('app.color.surface_button_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_light') })
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.searchKeyword = value
        })
        .onSubmit(() => {
          this.doSearch()
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CategoryMenuOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .transition(TransitionEffect.OPACITY.animation({
          duration: CATEGORY_MENU_ANIMATION_DURATION,
          curve: Curve.EaseOut
        }))
        .onClick(() => {
          this.closeCategoryMenu()
        })

      Column() {
        Text('分类')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .height(36)
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Start)

        Scroll() {
          Column() {
            ForEach(MENU_LABELS, (label: string) => {
              this.CategoryMenuItem(label)
            }, (label: string) => `category_${label}`)
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 8 })
        }
        .width('100%')
        .height(CATEGORY_MENU_MAX_HEIGHT - 36)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width(CATEGORY_MENU_WIDTH)
      .height(CATEGORY_MENU_MAX_HEIGHT)
      .borderRadius(16)
      .backgroundColor($r('app.color.category_menu_surface'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
      .position({ x: 16, y: this.getHomeTopSpacerHeight() - 4 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96, centerX: 0, centerY: 0 }))
          .animation({
            duration: CATEGORY_MENU_ANIMATION_DURATION,
            curve: Curve.EaseOut
          }),
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.98, y: 0.98, centerX: 0, centerY: 0 }))
          .animation({
            duration: CATEGORY_MENU_DISAPPEAR_ANIMATION_DURATION,
            curve: Curve.EaseOut
          })
      ))
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.opacity(0.99).animation({
      duration: CATEGORY_MENU_ANIMATION_DURATION,
      curve: Curve.EaseOut
    }))
    .zIndex(30)
  }

  @Builder
  private CategoryMenuItem(label: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(this.isMenuSelected(label) ? $r('app.color.tab_icon_selected') : $r('app.color.text_primary'))
        .fontWeight(this.isMenuSelected(label) ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.isMenuSelected(label)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([$r('app.color.tab_icon_selected')])
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .backgroundColor(this.isMenuSelected(label) ? $r('app.color.category_menu_item_selected') : $r('app.color.color_transparent'))
    .margin({ bottom: 2 })
    .onClick(() => {
      this.selectTagFromMenu(this.tagFromMenuLabel(label))
    })
  }

  @Builder
  private PopularCard(item: AnimeItem) {
    Column() {
      Stack() {
        Image(item.getGridCover().length > 0 ? item.getGridCover() : $r('app.media.ic_placeholder'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 8, topRight: 8 })
          .alt($r('app.media.ic_placeholder'))
      }
      .width('100%')
      .height(140)
      .borderRadius({ topLeft: 8, topRight: 8 })

      Column() {
        Text(item.name)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .height(48)

      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .alignItems(HorizontalAlign.Start)
    }
    .borderRadius(8)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/detail/DetailPage',
        params: {
          animeName: item.name,
          animeCover: item.cover,
          animeCoverFallback: item.coverFallback,
          animeBangumiCover: item.bangumiCover,
          animeDesc: item.desc,
          animeOriginalName: item.originalName,
          animeAirDate: item.airDate,
          animeRatingScore: item.ratingScore,
          animeRank: item.rank,
          animeTags: JSON.stringify(item.tags),
          animeVotes: item.votes,
          animeVotesCount: JSON.stringify(item.votesCount),
          animeAirWeekday: item.airWeekday,
          animeEps: item.eps,
          animeUrl: item.url,
          sourceName: item.sourceName,
          sourceId: item.sourceId,
          bangumiId: item.bangumiId
        }
      })
    })
  }

  @Builder
  private SearchView() {
    Column() {
      Blank()
        .height(this.getSearchTopSpacerHeight())
        .width('100%')

      if (this.isSearching) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.loading_color'))
          Text('搜索中...')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }
        .padding(16)
      } else if (this.searchResults.length > 0) {
        Grid() {
          ForEach(this.searchResults, (item: AnimeItem, index?: number) => {
            GridItem() {
              AnimeCard({
                name: item.name,
                cover: item.cover,
                coverFallback: item.coverFallback,
                bangumiCover: item.bangumiCover,
                sourceName: item.sourceName,
                onCardClick: () => {
                  router.pushUrl({
                    url: 'pages/detail/DetailPage',
                    params: {
                      animeName: item.name,
                      animeCover: item.cover,
                      animeCoverFallback: item.coverFallback,
                      animeBangumiCover: item.bangumiCover,
                      animeDesc: item.desc,
                      animeOriginalName: item.originalName,
                      animeAirDate: item.airDate,
                      animeRatingScore: item.ratingScore,
                      animeRank: item.rank,
                      animeTags: JSON.stringify(item.tags),
                      animeVotes: item.votes,
                      animeVotesCount: JSON.stringify(item.votesCount),
                      animeAirWeekday: item.airWeekday,
                      animeEps: item.eps,
                      animeUrl: item.url,
                      sourceName: item.sourceName,
                      sourceId: item.sourceId,
                      bangumiId: item.bangumiId
                    }
                  })
                }
              })
            }
          }, (item: AnimeItem, index?: number) => `search_${index}_${item.name}`)

          GridItem() {
            Column()
              .height(this.getHomeBottomSpacerHeight())
              .hitTestBehavior(HitTestMode.None)
          }

          GridItem() {
            Column()
              .height(this.getHomeBottomSpacerHeight())
              .hitTestBehavior(HitTestMode.None)
          }

          GridItem() {
            Column()
              .height(this.getHomeBottomSpacerHeight())
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .layoutWeight(1)
      } else if (this.searchKeyword.trim().length > 0 && !this.isSearching) {
        EmptyState({ message: '未找到相关动漫' })
      } else {
        this.SearchHistoryView()
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }

  @Builder
  private SearchHistoryView() {
    Column() {
      if (this.searchHistory.length > 0) {
        Row() {
          Text('搜索历史')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.clearSearchHistory()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchHistory, (item: SearchHistory) => {
            Text(item.keyword)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_button_bg'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: $r('app.color.border_subtle') })
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.searchKeyword = item.keyword
                this.doSearch()
              })
          }, (item: SearchHistory) => `hist_${item.id}_${item.keyword}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      } else {
        EmptyState({ message: '输入关键词搜索动漫' })
      }
    }
    .width('100%')
  }

  @Builder
  private ErrorView() {
    Column() {
      Text('无法加载数据')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      Text('请检查网络连接或Bangumi服务状态')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 16 })

      Button('点击重试')
        .height(40)
        .padding({ left: 22, right: 22 })
        .borderRadius(20)
        .backgroundColor($r('app.color.button_primary_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .shadow({ radius: 14, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
        .onClick(() => {
          this.retryLoad()
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private currentList(): AnimeItem[] {
    return this.currentTag === '热门番组' ? this.trendList : this.bangumiList
  }

  private selectTag(tag: string): void {
    if (tag === this.currentTag) {
      return
    }
    this.currentTag = tag

    this.isTimeOut = false
    this.canLoadMore = true
    if (tag === '热门番组') {
      this.trendList = []
      this.loadTrends()
    } else {
      this.bangumiList = []
      this.loadByTag(true)
    }
  }

  private tagFromMenuLabel(label: string): string {
    return label === '热门' ? '热门番组' : label
  }

  private isMenuSelected(label: string): boolean {
    return this.currentTag === this.tagFromMenuLabel(label)
  }

  private selectTagFromMenu(tag: string): void {
    this.selectTag(tag)
    this.closeCategoryMenu()
    this.scroller.scrollEdge(Edge.Top)
  }

  private openCategoryMenu(): void {
    this.getUIContext().animateTo({
      duration: CATEGORY_MENU_ANIMATION_DURATION,
      curve: Curve.EaseOut
    }, () => {
      this.showCategoryMenu = true
    })
  }

  private closeCategoryMenu(): void {
    this.getUIContext().animateTo({
      duration: CATEGORY_MENU_DISAPPEAR_ANIMATION_DURATION,
      curve: Curve.EaseOut
    }, () => {
      this.showCategoryMenu = false
    })
  }

  private toggleCategoryMenu(): void {
    if (this.showCategoryMenu) {
      this.closeCategoryMenu()
    } else {
      this.openCategoryMenu()
    }
  }

  private async loadTrends(): Promise<void> {
    this.isLoading = true
    this.isTimeOut = false
    this.canLoadMore = true
    try {
      const results = await BangumiApi.getTrendsList(this.trendList.length)
      this.trendList = this.trendList.concat(results)
      this.isTimeOut = this.trendList.length === 0
      if (results.length < 24) {
        this.canLoadMore = false
      }
      logger.info('Trends total: %{public}d', this.trendList.length)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Load trends failed: %{public}s', msg)
      this.isTimeOut = this.trendList.length === 0
    } finally {
      this.isLoading = false
    }
  }

  private async loadByTag(isInit: boolean): Promise<void> {
    if (isInit) {
      this.isLoading = true
    } else {
      this.isLoadingMore = true
    }
    this.isTimeOut = false
    try {
      const offset = isInit ? 0 : this.bangumiList.length
      const results = await BangumiApi.getBangumiListByTag(this.currentTag, offset)
      if (isInit) {
        this.bangumiList = results
      } else {
        this.bangumiList = this.bangumiList.concat(results)
      }
      this.isTimeOut = this.bangumiList.length === 0
      if (results.length < 24) {
        this.canLoadMore = false
      }
      logger.info('Tag %{public}s total: %{public}d', this.currentTag, this.bangumiList.length)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Load by tag failed: %{public}s', msg)
      this.isTimeOut = this.bangumiList.length === 0
    } finally {
      this.isLoading = false
      this.isLoadingMore = false
    }
  }

  private checkLoadMore(): void {
    if (!this.canLoadMore || this.isLoadingMore || this.isLoading) {
      return
    }
    if (this.currentTag === '热门番组') {
      this.loadTrendsMore()
    } else {
      this.loadByTag(false)
    }
  }

  private async loadTrendsMore(): Promise<void> {
    this.isLoadingMore = true
    try {
      const results = await BangumiApi.getTrendsList(this.trendList.length)
      this.trendList = this.trendList.concat(results)
      if (results.length < 24) {
        this.canLoadMore = false
      }
    } catch (err) {
      logger.warn('Load more trends failed')
    } finally {
      this.isLoadingMore = false
    }
  }

  private async doSearch(): Promise<void> {
    const trimmed = this.searchKeyword.trim()
    if (trimmed.length === 0) {
      return
    }
    this.isSearching = true
    this.searchResults = []
    try {
      await this.searchHistoryStore.add(trimmed)
      let results = await BangumiApi.searchAnime(trimmed)
      this.searchResults = results
      logger.info('Search returned %{public}d results', results.length)
    } catch (err) {
      logger.error('Search failed')
    } finally {
      this.isSearching = false
    }
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      this.searchHistory = await this.searchHistoryStore.getAll()
    } catch (err) {
      logger.warn('Load search history failed')
    }
  }

  private async clearSearchHistory(): Promise<void> {
    try {
      await this.searchHistoryStore.clearAll()
      this.searchHistory = []
    } catch (err) {
      logger.warn('Clear search history failed')
    }
  }

  private retryLoad(): void {
    if (this.currentTag === '热门番组') {
      this.trendList = []
      this.loadTrends()
    } else {
      this.bangumiList = []
      this.loadByTag(true)
    }
  }



  private buildHomeSearchIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.magnifyingglass'),
      label: 'search',
      action: () => {
        this.showSearchView = true
        this.closeCategoryMenu()
        this.loadSearchHistory()
      }
    }
  }

  private buildHomeCategoryIcon(): HdsNavigationIconOptions {
    return {
      icon: this.showCategoryMenu ? $r('sys.symbol.xmark') : $r('sys.symbol.line_3_horizontal'),
      label: 'category',
      action: () => {
        this.toggleCategoryMenu()
      }
    }
  }

  private buildHomeMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: this.buildHomeSearchIcon()
      }]
    }
  }

  private buildHomeTitle(): HdsNavigationTitle {
    return {
      mainTitle: 'Kazumi',
      subTitle: this.currentTag
    }
  }

  private buildHomeTitleBarContent(): TitleBarContentOptions {
    return {
      backIcon: this.buildHomeCategoryIcon(),
      title: this.buildHomeTitle(),
      menu: this.buildHomeMenu()
    }
  }

  private buildHomeTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('Kazumi')
    base.style = buildImmersiveTitleBarStyle()
    base.content = this.buildHomeTitleBarContent()
    return base
  }

  private getHomeTopSpacerHeight(): number {
    return getTopSpacerHeight(this.topSafeHeight)
  }

  private getSearchTopSpacerHeight(): number {
    return getTopSpacerHeight(this.topSafeHeight) + 56
  }

  private getHomeBottomSpacerHeight(): number {
    return getBottomSpacerHeight(this.bottomSafeHeight)
  }

  private getEffectiveTopSafeHeight(): number {
    return getEffectiveTopSafe(this.topSafeHeight)
  }

  private getGridColumns(): string {
    if (this.screenWidthVp >= 840) {
      return '1fr 1fr 1fr 1fr 1fr'
    } else if (this.screenWidthVp >= 600) {
      return '1fr 1fr 1fr 1fr'
    }
    return '1fr 1fr 1fr'
  }

  private getGridColumnsCount(): number {
    if (this.screenWidthVp >= 840) {
      return 5
    } else if (this.screenWidthVp >= 600) {
      return 4
    }
    return 3
  }
}

