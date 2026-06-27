import { AnimeItem } from '../../models/AnimeItem'
import { AnimeCard } from '../../components/common/AnimeCard'
import { BangumiApi } from '../../core/api/BangumiApi'
import { SearchHistoryStore } from '../../store/SearchHistoryStore'
import { SearchHistory } from '../../models/SearchHistory'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsTabs,
  HdsTabsController,
  hdsMaterial
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle
} from '../../utils/HdsPageStyle'

const logger = new Logger('SearchPage')
const SEARCH_BAR_HEIGHT: number = 42
const SEARCH_BOTTOM_BAR_HEIGHT: number = 62
const SEARCH_BAR_HORIZONTAL_PADDING: number = 18
const SEARCH_RESULT_GAP: number = 10
const EXPLORE_KEYWORDS: string[] = [
  '葬送的芙莉莲', '擅长逃跑的殿下', '夏日重现', '孤独摇滚',
  '咒术回战', '间谍过家家', '辉夜大小姐', '跃动青春'
]

@Entry
@Component
export struct SearchPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true
  @State searchKeyword: string = ''
  @State submittedKeyword: string = ''
  @State searchResults: AnimeItem[] = []
  @State searchHistory: SearchHistory[] = []
  @State isSearching: boolean = false
  @State hasSearched: boolean = false
  @State searchGlowOpacity: number = 0
  @State searchGlowScale: number = 0.82
  @State searchGlowOffsetX: number = 0
  @State searchGlowOffsetY: number = 0

  private scroller: Scroller = new Scroller()
  private searchBarTabsController: HdsTabsController = new HdsTabsController()
  private searchHistoryStore: SearchHistoryStore = new SearchHistoryStore()

  aboutToAppear(): void {
    this.loadSearchHistory()
  }

  onPageShow(): void {
    this.loadSearchHistory()
  }

  build() {
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
  }

  @Builder
  private SearchContent() {
    Column() {
      Blank()
        .height(this.getSearchTopSpacerHeight())
        .width('100%')

      if (this.isSearching) {
        this.SearchLoadingView()
      } else if (this.searchResults.length > 0) {
        this.SearchResultHeader()
        this.SearchResultsView()
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
      if (this.isHdsTabsEnabled && deviceInfo.distributionOSApiVersion >= 60100) {
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
  private HdsSearchField() {
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
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      },
      miniBar: {
        miniBarBuilder: () => {
          this.SearchInputContent(true)
        },
        miniBarStyle: 1
      },
      lightColor: Color.Transparent
    })
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

        TextInput({ placeholder: '搜索动漫...', text: this.searchKeyword })
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
            this.searchKeyword = ''
            this.searchResults = []
            this.hasSearched = false
            this.submittedKeyword = ''
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
        .height(this.getBottomSpacerHeight())
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4 })
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
      Text('探索关键词')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(EXPLORE_KEYWORDS, (keyword: string) => {
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
        Text('输入番剧名称开始搜索')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text('搜索结果来自 Bangumi 元数据，可在详情页匹配播放源')
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
      Row() {
        LoadingProgress()
          .width(22)
          .height(22)
          .color($r('app.color.loading_color'))
        Text('正在搜索...')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 10 })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(96)
      .borderRadius(18)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4 })
  }

  @Builder
  private SearchResultHeader() {
    Column() {
      Text(`搜索“${this.submittedKeyword}”`)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(`${this.searchResults.length} 个相关条目`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
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
      }, (row: AnimeItem[], rowIndex?: number) => `search_row_${rowIndex}`)

      Blank()
        .height(this.getBottomSpacerHeight())
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
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
    return {
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
      style: buildImmersiveTitleBarStyle()
    }
  }

  private async doSearch(): Promise<void> {
    const trimmed = this.searchKeyword.trim()
    if (trimmed.length === 0) {
      return
    }
    this.isSearching = true
    this.hasSearched = true
    this.submittedKeyword = trimmed
    this.searchResults = []
    try {
      await this.searchHistoryStore.add(trimmed)
      this.searchHistory = await this.searchHistoryStore.getAll()
      const results = await BangumiApi.searchAnime(trimmed)
      this.searchResults = results
      logger.info('Search returned %{public}d results', results.length)
      this.scroller.scrollEdge(Edge.Top)
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

  private openDetail(item: AnimeItem): void {
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

  private getSearchTopSpacerHeight(): number {
    return getTopSpacerHeight(this.topSafeHeight) + SEARCH_BOTTOM_BAR_HEIGHT
  }

  private getBottomSpacerHeight(): number {
    return getBottomSpacerHeight(this.bottomSafeHeight)
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
}
