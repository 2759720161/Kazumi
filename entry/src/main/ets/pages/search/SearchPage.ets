import { AnimeItem } from '../../models/AnimeItem'
import { AnimeCard } from '../../components/common/AnimeCard'
import { BangumiApi, BangumiSearchProgressOptions } from '../../core/api/BangumiApi'
import { SearchHistoryStore } from '../../store/SearchHistoryStore'
import { SearchHistory } from '../../models/SearchHistory'
import { Logger } from '../../utils/Logger'
import { router, curves } from '@kit.ArkUI'
import { DetailNavigationParams, navigateToDetail } from '../../utils/DetailNavigation'
import { deviceInfo } from '@kit.BasicServicesKit'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsTabs,
  HdsTabsController
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle,
  buildAdaptiveMaterialEffect,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

const logger = new Logger('SearchPage')
const SEARCH_BAR_HEIGHT: number = 42
const SEARCH_BOTTOM_BAR_HEIGHT: number = 62
const SEARCH_TAB_LABELS: string[] = ['标题', '标签']
const SEARCH_TAB_BAR_HEIGHT: number = 40
const SEARCH_TAB_ITEM_WIDTH: number = 96
const SEARCH_BAR_HORIZONTAL_PADDING: number = 18
const SEARCH_RESULT_GAP: number = 10
const SEARCH_RESULT_TOP_GAP: number = 14
const EXPLORE_KEYWORDS: string[] = [
  '葬送的芙莉莲', '擅长逃跑的殿下', '夏日重现', '孤独摇滚',
  '咒术回战', '间谍过家家', '辉夜大小姐', '跃动青春'
]
const EXPLORE_TAGS: string[] = [
  '原创', '漫画改', '日常', '奇幻',
  '校园', '恋爱', '百合', '2024年4月'
]

class SearchQuery {
  id: number = -1
  keyword: string = ''
  tag: string = ''
  sort: string = 'heat'
}

@Entry
@Component
export struct SearchPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State searchKeyword: string = ''
  @State submittedKeyword: string = ''
  @State searchResults: AnimeItem[] = []
  @State searchHistory: SearchHistory[] = []
  @State isSearching: boolean = false
  @State isLoadingMoreSearchResults: boolean = false
  @State hasSearched: boolean = false
  @State searchGlowOpacity: number = 0
  @State searchGlowScale: number = 0.82
  @State searchGlowOffsetX: number = 0
  @State searchGlowOffsetY: number = 0
  @State selectedSearchTabIndex: number = 0

  private scroller: Scroller = new Scroller()
  private searchBarTabsController: HdsTabsController = new HdsTabsController()
  private searchHistoryStore: SearchHistoryStore = new SearchHistoryStore()
  private searchRequestSerial: number = 0
  private routeParamsApplied: boolean = false

  aboutToAppear(): void {
    this.applyRouteParams()
    this.loadSearchHistory()
  }

  onPageShow(): void {
    this.loadSearchHistory()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.scroller) {
          this.SearchContent()
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .clip(false)
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [$r('app.color.home_bg_top'), 0],
          [$r('app.color.page_background'), 0.34],
          [$r('app.color.page_background'), 1]
        ]
      })

      if (this.shouldShowSearchTabs()) {
        this.SearchTabBar()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private SearchContent() {
    Column() {
      Blank()
        .height(this.getSearchTopSpacerHeight())
        .width('100%')

      if (this.searchResults.length > 0) {
        this.SearchResultsView()
      } else if (this.isSearching) {
        this.SearchLoadingView()
      } else if (this.hasSearched) {
        this.SearchEmptyView()
      } else {
        this.SearchLandingView()
      }
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SearchBottomBar() {
    Row() {
      if (this.shouldUseHdsSearchField()) {
        this.HdsSearchField()
      } else {
        this.FallbackSearchField()
      }
    }
    .width('100%')
    .height(SEARCH_BOTTOM_BAR_HEIGHT)
    .padding({ left: SEARCH_BAR_HORIZONTAL_PADDING, right: SEARCH_BAR_HORIZONTAL_PADDING, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SearchTabBar() {
    Row({ space: 8 }) {
      ForEach(SEARCH_TAB_LABELS, (label: string, index?: number) => {
        SearchSegmentTabItem({
          label: label,
          index: index ?? 0,
          selectedIndex: this.selectedSearchTabIndex,
          tabWidth: SEARCH_TAB_ITEM_WIDTH,
          onSelected: (selectedIndex: number) => {
            this.selectSearchTab(selectedIndex)
          }
        })
      }, (label: string, index?: number) => `search_tab_${index}_${label}`)
    }
    .width('100%')
    .height(SEARCH_TAB_BAR_HEIGHT)
    .margin({ top: getTopSpacerHeight(this.topSafeHeight) + SEARCH_BOTTOM_BAR_HEIGHT })
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .zIndex(30)
  }

  @Builder
  private MiniBarPlaceholder() {
    Row()
      .width(this.getSearchBarWidth())
      .height(SEARCH_BAR_HEIGHT)
      .backgroundColor(Color.Transparent)
      .borderRadius(SEARCH_BAR_HEIGHT / 2)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private HdsSearchField() {
    Stack({ alignContent: Alignment.Center }) {
      this.HdsSearchFieldMaterial()
      this.SearchInputContent(true)
    }
    .width(this.getSearchBarWidth())
    .height(SEARCH_BAR_HEIGHT)
    .clip(false)
  }

  @Builder
  private HdsSearchFieldMaterial() {
    HdsTabs({ controller: this.searchBarTabsController }) {
      TabContent()
        .clip(false)
        .backgroundColor(Color.Transparent)
    }
    .width(this.getSearchBarWidth())
    .height(SEARCH_BAR_HEIGHT)
    .clip(false)
    .barWidth(this.getSearchBarWidth())
    .barHeight(SEARCH_BAR_HEIGHT)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .backgroundColor(Color.Transparent)
    .vertical(false)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.getSearchBarWidth(),
        mediumWidth: this.getSearchBarWidth(),
        largeWidth: this.getSearchBarWidth()
      },
      gradientMask: {
        maskColor: Color.Transparent
      },
      barBottomMargin: 0,
      barSideMargin: 0,
      systemMaterialEffect: buildAdaptiveMaterialEffect(this.hdsMaterialLevel),
      miniBar: {
        miniBarBuilder: (): void => {
          this.MiniBarPlaceholder()
        },
        miniBarStyle: 1
      },
      lightColor: Color.Transparent
    })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private FallbackSearchField() {
    Stack({ alignContent: Alignment.Center }) {
      this.SearchInputContent(false)
    }
    .width('100%')
    .height(SEARCH_BAR_HEIGHT)
    .backgroundColor($r('app.color.surface_button_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.border_light') })
    .borderRadius(SEARCH_BAR_HEIGHT / 2)
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
  }

  @Builder
  private SearchInputContent(enableGlow: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (enableGlow) {
        Circle()
          .width(this.getSearchGlowBoxSize())
          .height(this.getSearchGlowBoxSize())
          .radialGradient({
            center: ['50%', '50%'],
            radius: '50%',
            colors: this.getSearchGlowGradientColors()
          })
          .opacity(this.clampOpacity(this.searchGlowOpacity))
          .scale({ x: this.searchGlowScale, y: this.searchGlowScale })
          .offset({ x: this.searchGlowOffsetX, y: this.searchGlowOffsetY })
          .blendMode(BlendMode.SCREEN)
          .hitTestBehavior(HitTestMode.None)
      }

      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
          .margin({ left: 14, right: 4 })

        TextInput({ placeholder: this.getSearchPlaceholder(), text: this.searchKeyword })
          .layoutWeight(1)
          .height(SEARCH_BAR_HEIGHT)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 4, right: 4 })
          .onChange((value: string) => {
            this.searchKeyword = value
          })
          .onSubmit(() => {
            this.doSearch()
          })

        if (this.searchKeyword.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(38)
          .height(SEARCH_BAR_HEIGHT)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.searchRequestSerial += 1
            this.searchKeyword = ''
            this.searchResults = []
            this.isSearching = false
            this.isLoadingMoreSearchResults = false
            this.hasSearched = false
            this.submittedKeyword = ''
            this.selectedSearchTabIndex = 0
          })
        }
      }
      .width('100%')
      .height('100%')
      .borderRadius(SEARCH_BAR_HEIGHT / 2)
      .clip(true)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
    }
    .width('100%')
    .height('100%')
    .clip(false)
    .borderRadius(SEARCH_BAR_HEIGHT / 2)
    .onTouch((event: TouchEvent) => {
      if (enableGlow) {
        this.handleSearchGlowTouch(event)
      }
    })
  }

  @Builder
  private SearchLandingView() {
    Column() {
      this.SearchHistorySection()
      this.ExploreKeywordSection()
      Blank()
        .height(this.isLoadingMoreSearchResults ? 12 : this.getBottomSpacerHeight())
        .width('100%')

      if (this.isLoadingMoreSearchResults) {
        this.SearchLoadingMoreView()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4 })
  }

  @Builder
  private SearchLoadingMoreView() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color($r('app.color.accent_blue'))
      Text('正在继续加载更多结果')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: this.getBottomSpacerHeight() })
  }

  @Builder
  private SearchHistorySection() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.searchHistory.length > 0) {
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.clearSearchHistory()
            })
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.searchHistory.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchHistory, (item: SearchHistory) => {
            this.KeywordChip(item.keyword, `history_${item.id}`)
          }, (item: SearchHistory) => `hist_${item.id}_${item.keyword}`)
        }
        .width('100%')
      } else {
        this.SearchTipCard()
      }
    }
    .width('100%')
    .margin({ bottom: 26 })
  }

  @Builder
  private ExploreKeywordSection() {
    Column() {
      Text(this.selectedSearchTabIndex === 1 ? '探索标签' : '探索关键词')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.getExploreKeywords(), (keyword: string) => {
          this.KeywordChip(keyword, `explore_${keyword}`)
        }, (keyword: string) => `explore_${keyword}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private KeywordChip(keyword: string, key: string) {
    Text(keyword)
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .backgroundColor($r('app.color.surface_button_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
      .borderRadius(18)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .margin({ right: 9, bottom: 10 })
      .onClick(() => {
        this.searchKeyword = keyword
        this.doSearch()
      })
  }

  @Builder
  private SearchTipCard() {
    Row() {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(22)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ right: 12 })

      Column() {
        Text(this.selectedSearchTabIndex === 1 ? '输入标签开始搜索' : '输入番剧名称开始搜索')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.selectedSearchTabIndex === 1 ?
          '可输入百合、原创、漫画改等 Bangumi 标签' :
          '搜索结果来自 Bangumi 元数据，可在详情页匹配播放源')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .borderRadius(18)
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
  }

  @Builder
  private SearchLoadingView() {
    Column() {
      LoadingProgress()
        .width(42)
        .height(42)
        .color($r('app.color.accent_blue'))
      Text(this.selectedSearchTabIndex === 1 ? '正在搜索标签' : '正在搜索标题')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text(this.selectedSearchTabIndex === 1 ? '正在匹配相关 Bangumi 标签条目' : '正在从 Bangumi 元数据检索条目')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .width('100%')
    .height(220)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 32, right: 32, top: SEARCH_RESULT_TOP_GAP })
  }

  @Builder
  private SearchResultsView() {
    Column() {
      ForEach(this.getSearchResultRows(), (row: AnimeItem[], rowIndex?: number) => {
        Row() {
          this.SearchResultSlot(row, 0)
          Blank()
            .width(SEARCH_RESULT_GAP)
          this.SearchResultSlot(row, 1)
          if (this.getResultColumnsCount() >= 3) {
            Blank()
              .width(SEARCH_RESULT_GAP)
            this.SearchResultSlot(row, 2)
          }
          if (this.getResultColumnsCount() >= 4) {
            Blank()
              .width(SEARCH_RESULT_GAP)
            this.SearchResultSlot(row, 3)
          }
        }
        .width('100%')
        .margin({ bottom: SEARCH_RESULT_GAP })
      }, (row: AnimeItem[], rowIndex?: number) => this.getSearchResultRowKey(row, rowIndex ?? 0))

      Blank()
        .height(this.getBottomSpacerHeight())
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: SEARCH_RESULT_TOP_GAP, bottom: 8 })
  }

  @Builder
  private SearchResultSlot(row: AnimeItem[], columnIndex: number) {
    Column() {
      if (columnIndex < row.length) {
        this.SearchResultCard(row[columnIndex])
      }
    }
    .layoutWeight(1)
  }

  @Builder
  private SearchResultCard(item: AnimeItem) {
    AnimeCard({
      name: item.name,
      cover: item.cover,
      coverFallback: item.coverFallback,
      bangumiCover: item.bangumiCover,
      sourceName: item.sourceName,
      sharedCoverId: this.getSharedCoverId(item),
      onCardClick: () => {
        this.openDetail(item)
      }
    })
    .width('100%')
  }

  @Builder
  private SearchEmptyView() {
    Column() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(34)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ bottom: 12 })
      Text('未找到相关动漫')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('换个中文名、日文名或更短的关键词试试')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 52 })
    .alignItems(HorizontalAlign.Center)
  }

  private buildTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options: HdsNavigationTitleBarOptions = {
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
        }
      },
      style: buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
    }
    if (options.style?.originalStyle?.backgroundStyle) {
      options.style.originalStyle.backgroundStyle.maskExtraHeight = this.shouldShowSearchTabs() ? SEARCH_TAB_BAR_HEIGHT : 0
    }
    if (options.style?.scrollEffectStyle?.backgroundStyle) {
      options.style.scrollEffectStyle.backgroundStyle.maskExtraHeight = this.shouldShowSearchTabs() ? SEARCH_TAB_BAR_HEIGHT : 0
    }
    return options
  }

  private async doSearch(searchMode: number = this.selectedSearchTabIndex): Promise<void> {
    const trimmed = this.searchKeyword.trim()
    if (trimmed.length === 0) {
      return
    }
    const requestSerial = this.searchRequestSerial + 1
    this.searchRequestSerial = requestSerial
    this.isSearching = true
    this.isLoadingMoreSearchResults = false
    this.hasSearched = true
    this.submittedKeyword = trimmed
    this.searchResults = []
    try {
      await this.searchHistoryStore.add(trimmed)
      this.searchHistory = await this.searchHistoryStore.getAll()
      const query = this.parseSearchQuery(trimmed)
      let results: AnimeItem[] = []
      if (query.id > 0) {
        const item = await BangumiApi.getSubject(query.id)
        results = item !== null ? [item] : []
      } else {
        const explicitTags: string[] = query.tag.length > 0 ? [query.tag] : []
        const tags: string[] = searchMode === 1 && explicitTags.length === 0 ?
          [query.keyword] : explicitTags
        const keyword = tags.length > 0 ? '' : query.keyword
        let hasShownProgressResults = false
        logger.info('Search request mode=%{public}s keyword=%{public}s tags=%{public}s',
          searchMode === 1 ? 'tag' : 'title', keyword.length > 0 ? keyword : '<empty>', tags.join(','))
        const progressOptions = new BangumiSearchProgressOptions()
        progressOptions.shouldContinue = (): boolean => {
          return requestSerial === this.searchRequestSerial
        }
        progressOptions.onResults = (items: AnimeItem[]): void => {
          if (requestSerial !== this.searchRequestSerial) {
            return
          }
          this.searchResults = items
          this.isSearching = false
          this.isLoadingMoreSearchResults = true
          if (!hasShownProgressResults) {
            hasShownProgressResults = true
            this.scroller.scrollEdge(Edge.Top)
          }
        }
        results = await BangumiApi.searchAnimeProgressive(keyword, tags, query.sort, progressOptions)
        if (results.length > 0 && !hasShownProgressResults) {
          this.scroller.scrollEdge(Edge.Top)
        }
      }
      if (requestSerial !== this.searchRequestSerial) {
        logger.info('Ignore stale search response serial=%{public}d current=%{public}d',
          requestSerial, this.searchRequestSerial)
        return
      }
      this.searchResults = results
      this.isLoadingMoreSearchResults = false
      logger.info('Search returned %{public}d results', this.searchResults.length)
      if (results.length > 0 && query.id > 0) {
        this.scroller.scrollEdge(Edge.Top)
      }
    } catch (err) {
      if (requestSerial !== this.searchRequestSerial) {
        return
      }
      logger.error('Search failed')
    } finally {
      if (requestSerial === this.searchRequestSerial) {
        this.isSearching = false
        this.isLoadingMoreSearchResults = false
      }
    }
  }

  private parseSearchQuery(input: string): SearchQuery {
    const result = new SearchQuery()
    let keyword = input.trim()
    const idMatch = keyword.match(/(?:^|\s)id:(\d+)(?=\s|$)/i)
    if (idMatch !== null && idMatch.length > 1) {
      result.id = Number(idMatch[1])
      keyword = keyword.replace(/(?:^|\s)id:\d+(?=\s|$)/i, ' ')
    }

    const tagMatch = keyword.match(/(?:^|\s)tag:(\S+)(?=\s|$)/i)
    if (tagMatch !== null && tagMatch.length > 1) {
      result.tag = tagMatch[1]
      keyword = keyword.replace(/(?:^|\s)tag:\S+(?=\s|$)/i, ' ')
    }

    const sortMatch = keyword.match(/(?:^|\s)sort:([\w-]+)(?=\s|$)/i)
    if (sortMatch !== null && sortMatch.length > 1) {
      result.sort = this.normalizeSearchSort(sortMatch[1])
      keyword = keyword.replace(/(?:^|\s)sort:[\w-]+(?=\s|$)/i, ' ')
    }

    result.keyword = keyword.replace(/\s+/g, ' ').trim()
    return result
  }

  private normalizeSearchSort(sort: string): string {
    const value = sort.trim().toLowerCase()
    if (value === 'rank' || value === 'match' || value === 'score') {
      return value
    }
    return 'heat'
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      this.searchHistory = await this.searchHistoryStore.getAll()
    } catch (err) {
      logger.warn('Load search history failed')
    }
  }

  private applyRouteParams(): void {
    if (this.routeParamsApplied) {
      return
    }
    this.routeParamsApplied = true
    const params = router.getParams() as Record<string, Object> | null | undefined
    if (params === null || params === undefined) {
      return
    }

    let initialKeyword: string = ''
    let initialSearchMode: number = -1
    if (params['tag'] !== undefined) {
      initialKeyword = params['tag'] as string
      initialSearchMode = 1
    } else if (params['keyword'] !== undefined) {
      initialKeyword = params['keyword'] as string
    }
    if (params['searchMode'] !== undefined) {
      initialSearchMode = params['searchMode'] as number
    }

    const trimmed = initialKeyword.trim()
    if (trimmed.length === 0) {
      return
    }
    this.selectedSearchTabIndex = initialSearchMode === 1 ? 1 : 0
    this.searchKeyword = trimmed
    this.doSearch(this.selectedSearchTabIndex)
  }

  private async clearSearchHistory(): Promise<void> {
    try {
      await this.searchHistoryStore.clearAll()
      this.searchHistory = []
    } catch (err) {
      logger.warn('Clear search history failed')
    }
  }

  private openDetail(item: AnimeItem): void {
    const params = new DetailNavigationParams()
    params.animeName = item.name
    params.animeCover = item.cover
    params.animeCoverFallback = item.coverFallback
    params.animeBangumiCover = item.bangumiCover
    params.animeDesc = item.desc
    params.animeOriginalName = item.originalName
    params.animeAirDate = item.airDate
    params.animeRatingScore = item.ratingScore
    params.animeRank = item.rank
    params.animeTags = JSON.stringify(item.tags)
    params.animeVotes = item.votes
    params.animeVotesCount = JSON.stringify(item.votesCount)
    params.animeAirWeekday = item.airWeekday
    params.animeEps = item.eps
    params.animeUrl = item.url
    params.sourceName = item.sourceName
    params.sourceId = item.sourceId
    params.bangumiId = item.bangumiId
    params.sharedCoverId = this.getSharedCoverId(item)
    params.transitionCover = item.getGridCover()
    navigateToDetail(params)
  }

  private getSearchTopSpacerHeight(): number {
    return getTopSpacerHeight(this.topSafeHeight) + this.getSearchTopControlsHeight()
  }

  private getSharedCoverId(item: AnimeItem): string {
    const subjectId = item.bangumiId > 0 ? item.bangumiId.toString() : item.name
    return 'search-cover-' + subjectId
  }

  private getBottomSpacerHeight(): number {
    return getBottomSpacerHeight(this.bottomSafeHeight)
  }

  private shouldUseHdsSearchField(): boolean {
    return this.isHdsTabsEnabled && deviceInfo.distributionOSApiVersion >= 60100
  }

  private getSearchTopControlsHeight(): number {
    return SEARCH_BOTTOM_BAR_HEIGHT + (this.shouldShowSearchTabs() ? SEARCH_TAB_BAR_HEIGHT : 0)
  }

  private shouldShowSearchTabs(): boolean {
    return this.hasSearched || this.isSearching
  }

  private getSearchPlaceholder(): string {
    return this.selectedSearchTabIndex === 1 ? '搜索标签...' : '搜索动漫...'
  }

  private getExploreKeywords(): string[] {
    return this.selectedSearchTabIndex === 1 ? EXPLORE_TAGS : EXPLORE_KEYWORDS
  }

  private selectSearchTab(selectedIndex: number): void {
    if (selectedIndex === this.selectedSearchTabIndex) {
      return
    }
    this.getUIContext().animateTo({
      duration: 220,
      curve: curves.springMotion()
    }, () => {
      this.selectedSearchTabIndex = selectedIndex
    })
    this.scroller.scrollEdge(Edge.Top)
    if (this.searchKeyword.trim().length > 0) {
      this.doSearch(selectedIndex)
    }
  }

  private getSearchBarWidth(): number {
    const rawWidth = this.screenWidthVp > 0 ?
      this.screenWidthVp - SEARCH_BAR_HORIZONTAL_PADDING * 2 : 324
    return Math.max(220, rawWidth)
  }

  private getSearchGlowBoxSize(): number {
    return Math.max(SEARCH_BAR_HEIGHT * 3.8, 160)
  }

  private getSearchGlowGradientColors(): [ResourceColor, number][] {
    return [
      ['#FFFFFFFF', 0.0],
      ['#E6FFFFFF', 0.20],
      ['#80FFFFFF', 0.42],
      ['#26FFFFFF', 0.64],
      ['#08FFFFFF', 0.84],
      ['#00FFFFFF', 0.96],
      ['#00FFFFFF', 1.0]
    ]
  }

  private clampOpacity(value: number): number {
    return Math.max(0, Math.min(1, value))
  }

  private updateSearchGlowPosition(touch: TouchObject): void {
    this.searchGlowOffsetX = touch.x - this.getSearchBarWidth() / 2
    this.searchGlowOffsetY = touch.y - SEARCH_BAR_HEIGHT / 2
  }

  private handleSearchGlowTouch(event: TouchEvent): void {
    if (!event.touches || event.touches.length === 0) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
          this.searchGlowScale = 1.18
          this.searchGlowOpacity = 0
        })
      }
      return
    }

    const touch = event.touches[0]
    if (event.type === TouchType.Down) {
      this.updateSearchGlowPosition(touch)
      this.searchGlowScale = 0.82
      this.searchGlowOpacity = 0.04
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.searchGlowScale = 1.06
        this.searchGlowOpacity = 0.46
      })
    } else if (event.type === TouchType.Move) {
      this.updateSearchGlowPosition(touch)
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.updateSearchGlowPosition(touch)
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.searchGlowScale = 1.2
        this.searchGlowOpacity = 0
      })
    }
  }

  private getResultColumnsCount(): number {
    if (this.screenWidthVp >= 900) {
      return 4
    }
    if (this.screenWidthVp >= 600) {
      return 3
    }
    return 2
  }

  private getSearchResultRows(): AnimeItem[][] {
    const rows: AnimeItem[][] = []
    const count = this.getResultColumnsCount()
    for (let i = 0; i < this.searchResults.length; i += count) {
      rows.push(this.searchResults.slice(i, i + count))
    }
    return rows
  }

  private getSearchResultRowKey(row: AnimeItem[], rowIndex: number): string {
    const parts: string[] = []
    for (let i = 0; i < row.length; i++) {
      parts.push(this.getSearchResultItemKey(row[i]))
    }
    return `search_row_${rowIndex}_${row.length}_${parts.join('_')}`
  }

  private getSearchResultItemKey(item: AnimeItem): string {
    if (item.bangumiId > 0) {
      return `id_${item.bangumiId}`
    }
    return `name_${item.name}_${item.originalName}_${item.airDate}`
  }
}

@Component
struct SearchSegmentTabItem {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @Prop label: string = ''
  @Prop index: number = 0
  @Prop selectedIndex: number = 0
  @Prop tabWidth: number = SEARCH_TAB_ITEM_WIDTH
  onSelected?: (index: number) => void

  build() {
    Column() {
      HdsTabs() {
        TabContent()
          .clip(false)
          .tabBar(this.tabBarContentBuilder())
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
      }
      .clip(false)
      .hitTestBehavior(HitTestMode.None)
      .align(Alignment.Center)
      .height(SEARCH_TAB_BAR_HEIGHT)
      .barWidth(this.tabWidth)
      .barHeight(SEARCH_TAB_BAR_HEIGHT)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .backgroundColor(Color.Transparent)
      .shadow(undefined)
      .barFloatingStyle({
        barWidth: {
          smallWidth: this.tabWidth,
          mediumWidth: this.tabWidth,
          largeWidth: this.tabWidth
        },
        gradientMask: {
          maskColor: Color.Transparent
        },
        barBottomMargin: 0,
        barSideMargin: 0,
        systemMaterialEffect: buildAdaptiveMaterialEffect(this.hdsMaterialLevel),
        lightColor: Color.Transparent
      })
    }
    .backgroundColor(Color.Transparent)
    .clip(false)
    .width(this.tabWidth)
    .height(SEARCH_TAB_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
  }

  @Builder
  tabBarContentBuilder(): void {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.label)
        .fontSize(14)
        .fontWeight(this.isSelected() ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.isSelected() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .onClick(() => {
      this.selectTab()
    })
  }

  private selectTab(): void {
    this.onSelected?.(this.index)
  }

  private isSelected(): boolean {
    return this.selectedIndex === this.index
  }
}
