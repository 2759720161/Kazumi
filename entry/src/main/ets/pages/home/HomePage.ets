import { RecommendCardModel } from '../../models/RecommendCardModel'
import { HistoryRecord } from '../../models/HistoryRecord'
import { RecommendViewModel } from '../../viewmodel/RecommendViewModel'
import { HeroBanner } from '../../components/recommend/HeroBanner'
import { QuickAccessBar } from '../../components/recommend/QuickAccessBar'
import { PosterRailSection } from '../../components/recommend/PosterRailSection'
import { ContinueWatchingSection } from '../../components/recommend/ContinueWatchingSection'
import { TagTopicSection } from '../../components/recommend/TagTopicSection'
import { LoadingOverlay } from '../../components/common/LoadingOverlay'
import { ErrorRetry } from '../../components/common/ErrorRetry'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
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
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'

const logger = new Logger('HomePage')

@Component
export struct HomePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('currentTab') @Watch('onTabChanged') currentTab: number = 0
  @State scrollOffset: number = 0
  @State isLoading: boolean = true
  @State hasLoadError: boolean = false
  @State heroList: RecommendCardModel[] = []
  @State trendingList: RecommendCardModel[] = []
  @State seasonalList: RecommendCardModel[] = []
  @State highScoreList: RecommendCardModel[] = []
  @State tagTopicList: RecommendCardModel[] = []
  @State continueWatchingItems: HistoryRecord[] = []
  @State seasonLabel: string = ''

  private vm: RecommendViewModel = new RecommendViewModel()
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadRecommend()
  }

  private onTabChanged(): void {
    if (this.currentTab === 0 && !this.isLoading) {
      this.refreshHistory()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.HomeNavigationContent()

      if (this.scrollOffset > 800) {
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
        Column({ space: 20 }) {
          Blank()
            .height(this.getHomeTopSpacerHeight())
            .width('100%')

          if (this.isLoading && this.heroList.length === 0 && this.trendingList.length === 0) {
            LoadingOverlay({ message: '加载推荐内容...' })
          } else if (this.hasLoadError && this.heroList.length === 0 && this.trendingList.length === 0) {
            ErrorRetry({
              message: '无法加载推荐内容，请检查网络连接',
              onRetry: () => {
                this.loadRecommend()
              }
            })
          } else {
            if (this.heroList.length > 0) {
              HeroBanner({ items: this.heroList })
                .width('100%')
            }

            QuickAccessBar()
              .width('100%')
              .padding({ left: 16, right: 16 })

            if (this.continueWatchingItems.length > 0) {
              ContinueWatchingSection({ items: this.continueWatchingItems })
                .width('100%')
            }

            if (this.trendingList.length > 0) {
              PosterRailSection({
                title: '热门番组',
                subtitle: '近期讨论度最高',
                items: this.trendingList,
                showRank: false,
                showScore: true
              })
            }

            if (this.seasonalList.length > 0) {
              PosterRailSection({
                title: this.seasonLabel,
                subtitle: '正在放送',
                items: this.seasonalList,
                showRank: true,
                showScore: true
              })
            }

            if (this.highScoreList.length > 0) {
              PosterRailSection({
                title: '高分佳作',
                subtitle: '评分人数充足的口碑作品',
                items: this.highScoreList,
                showRank: true,
                showScore: true
              })
            }

            TagTopicSection({
              items: this.tagTopicList,
              onTagSelect: (tag: string) => {
                this.handleTagSelect(tag)
              }
            })
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
      .scrollBar(BarState.Off)
      .clip(false)
      .onScrollFrameBegin((offset: number) => {
        this.scrollOffset = this.scroller.currentOffset().yOffset
        return { offsetRemain: offset }
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

  private async loadRecommend(): Promise<void> {
    this.isLoading = true
    this.hasLoadError = false
    try {
      await this.vm.load()
      this.heroList = this.vm.heroList
      this.trendingList = this.vm.trendingList
      this.seasonalList = this.vm.seasonalList
      this.highScoreList = this.vm.highScoreList
      this.continueWatchingItems = this.vm.continueWatching
      this.seasonLabel = this.vm.seasonLabel

      const allEmpty = this.heroList.length === 0 &&
        this.trendingList.length === 0 &&
        this.seasonalList.length === 0 &&
        this.highScoreList.length === 0
      if (allEmpty) {
        this.hasLoadError = true
      }
    } catch (err) {
      logger.error('loadRecommend failed: %{public}s', err instanceof Error ? err.message : String(err))
      this.hasLoadError = true
    } finally {
      this.isLoading = false
    }
  }

  private async refreshHistory(): Promise<void> {
    try {
      await this.vm.refreshContinueWatching()
      this.continueWatchingItems = this.vm.continueWatching
    } catch (err) {
      logger.warn('refreshHistory failed')
    }
  }

  private async handleTagSelect(tag: string): Promise<void> {
    if (tag.length === 0) {
      this.tagTopicList = []
      return
    }
    await this.vm.loadByTag(tag)
    this.tagTopicList = this.vm.tagTopicList
  }

  private buildHomeSearchIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.magnifyingglass'),
      label: 'search',
      action: () => {
        router.pushUrl({ url: 'pages/search/SearchPage' })
      }
    }
  }

  private buildHomeHistoryIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.clock'),
      label: 'history',
      action: () => {
        router.pushUrl({ url: 'pages/history/HistoryPage' })
      }
    }
  }

  private buildHomeMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: this.buildHomeSearchIcon()
      }, {
        content: this.buildHomeHistoryIcon()
      }]
    }
  }

  private buildHomeTitle(): HdsNavigationTitle {
    return {
      mainTitle: 'Kazumi',
      subTitle: '推荐'
    }
  }

  private buildHomeTitleBarContent(): TitleBarContentOptions {
    return {
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

  private getHomeBottomSpacerHeight(): number {
    return getBottomSpacerHeight(this.bottomSafeHeight)
  }
}
