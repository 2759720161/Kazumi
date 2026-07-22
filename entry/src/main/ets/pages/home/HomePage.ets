import { RecommendCardModel } from '../../models/RecommendCardModel'
import { RecommendViewModel } from '../../viewmodel/RecommendViewModel'
import { HeroBanner } from '../../components/recommend/HeroBanner'
import { PosterRailSection } from '../../components/recommend/PosterRailSection'
import { TagTopicSection } from '../../components/recommend/TagTopicSection'
import { LoadingOverlay } from '../../components/common/LoadingOverlay'
import { ErrorRetry } from '../../components/common/ErrorRetry'
import { Logger } from '../../utils/Logger'
import { RECOMMEND_GENRE_TAGS } from '../../constants/RecommendTags'
import { router } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitle,
  TitleBarContentOptions,
  HdsTabs
} from '@kit.UIDesignKit'
import {
  getEffectiveTopSafeHeight,
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle,
  buildTitleBarOptions,
  buildAdaptiveMaterialEffect,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import {
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  getBottomTabHideDistance,
  requestBottomTabAnimation,
  resolveBottomTabOffsetByDelta,
  resolveBottomTabSnapTarget
} from '../../utils/BottomTabAutoHide'

const logger = new Logger('HomePage')
const HOME_TITLE_TAG_BAR_HEIGHT: number = 44
const HOME_TITLE_ROW_HEIGHT: number = 72
const HOME_TITLE_TAG_LEFT_MARGIN: number = 16
const HOME_TITLE_MENU_RESERVED_WIDTH: number = 110
const HOME_TITLE_TAG_VISUAL_OFFSET_Y: number = -5
const HOME_STICKY_TAG_PIN_HYSTERESIS: number = 8
const HOME_TAG_SWITCH_PIN_GUARD_MS: number = 450
const HOME_STICKY_TAG_HEIGHT: number = 30

@Component
export struct HomePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State isLoading: boolean = true
  @State hasLoadError: boolean = false
  @State heroList: RecommendCardModel[] = []
  @State trendingList: RecommendCardModel[] = []
  @State seasonalList: RecommendCardModel[] = []
  @State highScoreList: RecommendCardModel[] = []
  @State tagTopicList: RecommendCardModel[] = []
  @State seasonLabel: string = ''
  @State tagLoading: boolean = false
  @State selectedTag: string = ''
  @State seasonalLoading: boolean = false
  @State highScoreLoading: boolean = false
  @State heroVersion: number = 0
  @State tagBarPinned: boolean = false

  private vm: RecommendViewModel = new RecommendViewModel()
  private scroller: Scroller = new Scroller()
  private loadToken: number = 0
  private tagSwitchInProgress: boolean = false
  private tagSwitchPinGuardUntil: number = 0
  private tagPinScrollThreshold: number = -1
  private tagRequestVersion: number = 0

  aboutToAppear(): void {
    this.loadRecommend()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.HomeNavigationContent()
      if (this.tagBarPinned) {
        this.StickyTitleTagBar()
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
          if (this.heroList.length === 0 && !this.shouldShowInitialSkeleton()) {
            Blank()
              .height(this.getHomeTopSpacerHeight())
              .width('100%')
          }

          if (this.shouldShowInitialSkeleton()) {
            this.InitialSkeletonContent()
          } else if (this.hasLoadError && this.heroList.length === 0 && this.trendingList.length === 0) {
            ErrorRetry({
              message: '无法加载推荐内容，请检查网络连接',
              onRetry: () => {
                this.loadRecommend()
              }
            })
          } else {
            if (this.heroList.length > 0) {
              HeroBanner({
                items: this.heroList,
                topInset: this.getHomeTopSpacerHeight(),
                version: this.heroVersion
              })
                .width('100%')
            }

            if (this.trendingList.length > 0) {
              PosterRailSection({
                title: '热门番组',
                subtitle: '近期讨论度最高',
                items: this.trendingList,
                showRank: false
              })
            }

            if (this.seasonalList.length > 0) {
              PosterRailSection({
                title: this.seasonLabel,
                subtitle: '正在放送',
                items: this.seasonalList,
                showRank: true
              })
            } else if (this.seasonalLoading) {
              this.PosterRailSkeleton(this.seasonLabel.length > 0 ? this.seasonLabel : '本季新番', '正在放送')
            }

            if (this.highScoreList.length > 0) {
              PosterRailSection({
                title: '高分佳作',
                subtitle: '评分人数充足的口碑作品',
                items: this.highScoreList,
                showRank: true
              })
            } else if (this.highScoreLoading) {
              this.PosterRailSkeleton('高分佳作', '评分人数充足的口碑作品')
            }

            TagTopicSection({
              items: this.tagTopicList,
              selectedTag: this.selectedTag,
              isLoading: this.tagLoading,
              tagBarPinned: this.tagBarPinned,
              onTagSelect: (tag: string) => {
                this.handleTagSelect(tag)
              },
              onTagBarAreaChange: (top: number, height: number) => {
                this.handleTagBarAreaChange(top, height)
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
      .id('homeScrollContainer')
      .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
        this.updateBottomTabOffset(yOffset)
        this.refreshTagBarPinnedState()
      })
      .onScrollStop(() => {
        this.snapBottomTabOffset()
        this.refreshTagBarPinnedState()
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(this.buildHomeTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  private async loadRecommend(): Promise<void> {
    const token = ++this.loadToken
    this.isLoading = true
    this.hasLoadError = false
    this.seasonalLoading = true
    this.highScoreLoading = true
    this.heroList = []
    this.trendingList = []
    this.seasonalList = []
    this.highScoreList = []
    this.heroVersion = 0
    this.seasonLabel = this.vm.seasonLabel.length > 0 ? this.vm.seasonLabel : '本季新番'
    try {
      let hero: RecommendCardModel[] = []
      let trending: RecommendCardModel[] = []

      try {
        trending = await this.vm.loadHomeTrending()
      } catch (err) {
        logger.warn('loadHomeTrending failed')
      }

      try {
        hero = await this.vm.buildHomeHeroFromTrending()
      } catch (err) {
        logger.warn('buildHomeHeroFromTrending failed')
      }

      if (token !== this.loadToken) {
        return
      }

      this.heroList = [...hero]
      this.trendingList = [...trending]
      this.heroVersion++
      this.hasLoadError = hero.length === 0 && trending.length === 0
      this.isLoading = false

      this.loadSeasonalSection(token)
      this.loadHighScoreSection(token)
      this.enrichHeroSection(token)
    } catch (err) {
      logger.error('loadRecommend failed: %{public}s', err instanceof Error ? err.message : String(err))
      this.hasLoadError = true
    } finally {
      if (token === this.loadToken) {
        this.isLoading = false
      }
    }
  }

  private shouldShowInitialSkeleton(): boolean {
    return this.isLoading && this.heroList.length === 0 && this.trendingList.length === 0
  }

  private async loadSeasonalSection(token: number): Promise<void> {
    try {
      const items = await this.vm.loadHomeSeasonal()
      if (token !== this.loadToken) {
        return
      }
      this.seasonalList = [...items]
      this.seasonLabel = this.vm.seasonLabel
    } catch (err) {
      logger.warn('loadHomeSeasonal failed')
    } finally {
      if (token === this.loadToken) {
        this.seasonalLoading = false
      }
    }
  }

  private async loadHighScoreSection(token: number): Promise<void> {
    try {
      const items = await this.vm.loadHomeHighScore()
      if (token !== this.loadToken) {
        return
      }
      this.highScoreList = [...items]
    } catch (err) {
      logger.warn('loadHomeHighScore failed')
    } finally {
      if (token === this.loadToken) {
        this.highScoreLoading = false
      }
    }
  }

  private async enrichHeroSection(token: number): Promise<void> {
    try {
      const items = await this.vm.enrichHomeHeroList()
      if (token !== this.loadToken) {
        return
      }
      this.heroList = [...items]
      this.heroVersion++
    } catch (err) {
      logger.warn('enrichHomeHeroList failed')
    }
  }

  @Builder
  private InitialSkeletonContent() {
    Column({ space: 20 }) {
      this.HeroSkeleton()
      this.PosterRailSkeleton('热门番组', '近期讨论度最高')
      this.PosterRailSkeleton(this.seasonLabel.length > 0 ? this.seasonLabel : '本季新番', '正在放送')
      this.PosterRailSkeleton('高分佳作', '评分人数充足的口碑作品')
    }
    .width('100%')
  }

  @Builder
  private HeroSkeleton() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [$r('app.color.card_background'), 0],
            [$r('app.color.page_background'), 1]
          ]
        })

      Row() {
        Column({ space: 10 }) {
          this.SkeletonBlock('76%', 28, 8)
          this.SkeletonBlock('92%', 16, 8)
          this.SkeletonBlock('64%', 16, 8)
          Row({ space: 8 }) {
            this.SkeletonBlock(58, 22, 11)
            this.SkeletonBlock(72, 22, 11)
          }
        }
        .layoutWeight(1)
        .padding({ left: 20, right: 10 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        Column() {
          this.SkeletonBlock(this.getSkeletonPosterWidth(), Math.round(this.getSkeletonPosterWidth() * 4 / 3), 12)
        }
        .margin({ right: 18 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getHomeTopSpacerHeight() + 24, bottom: 48 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.getHeroSkeletonHeight())
  }

  @Builder
  private PosterRailSkeleton(title: string, subtitle: string) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 2 }) {
          Text(title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 10 }) {
          ForEach([0, 1, 2, 3], (_: number, index?: number) => {
            Column({ space: 8 }) {
              this.SkeletonBlock(this.getRailSkeletonCardWidth(), Math.round(this.getRailSkeletonCardWidth() * 4 / 3), 12)
              this.SkeletonBlock('88%', 16, 8)
              this.SkeletonBlock('62%', 16, 8)
            }
            .width(this.getRailSkeletonCardWidth())
            .height(this.getRailSkeletonCardHeight())
            .alignItems(HorizontalAlign.Start)
          }, (_: number, index?: number) => 'home_rail_skeleton_' + title + '_' + (index ?? 0).toString())
        }
        .height(this.getRailSkeletonCardHeight())
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .width('100%')
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private SkeletonBlock(widthValue: string | number, heightValue: number, radiusValue: number) {
    Column()
      .width(widthValue)
      .height(heightValue)
      .borderRadius(radiusValue)
      .backgroundColor($r('app.color.skeleton_background'))
  }

  private async handleTagSelect(tag: string): Promise<void> {
    const requestVersion = ++this.tagRequestVersion
    if (this.tagBarPinned) {
      this.tagSwitchInProgress = true
      this.tagSwitchPinGuardUntil = Date.now() + HOME_TAG_SWITCH_PIN_GUARD_MS
    }
    this.selectedTag = tag

    if (tag.length === 0) {
      this.tagTopicList = []
      this.tagSwitchInProgress = false
      this.tagLoading = false
      this.tagSwitchPinGuardUntil = Date.now() + HOME_TAG_SWITCH_PIN_GUARD_MS
      return
    }

    this.tagLoading = true
    try {
      await this.vm.loadByTag(tag)
      if (requestVersion === this.tagRequestVersion && this.selectedTag === tag) {
        this.tagTopicList = this.vm.tagTopicList
      }
    } finally {
      if (requestVersion === this.tagRequestVersion) {
        this.tagLoading = false
        this.tagSwitchInProgress = false
        this.tagSwitchPinGuardUntil = Date.now() + HOME_TAG_SWITCH_PIN_GUARD_MS
      }
    }
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
      mainTitle: this.tagBarPinned ? '' : '首页'
    }
  }

  private buildHomeTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildHomeTitle(),
      menu: this.buildHomeMenu()
    }
  }

  private buildHomeTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('首页', this.hdsMaterialLevel)
    base.style = buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
    base.content = this.buildHomeTitleBarContent()
    return base
  }

  @Builder
  private StickyTitleTagBar() {
    Row() {
      Stack({ alignContent: Alignment.Start }) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(RECOMMEND_GENRE_TAGS, (tag: string, index?: number) => {
              this.StickyTagChip(tag)
            }, (tag: string, index?: number) => 'home_sticky_tag_' + tag)
          }
          .constraintSize({ minWidth: '100%' })
          .height('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 0, right: 12 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .fadingEdge(true)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height(HOME_TITLE_TAG_BAR_HEIGHT)
      }
      .width('100%')
      .height(HOME_TITLE_TAG_BAR_HEIGHT)
    }
    .width(this.getStickyTitleTagBarWidth())
    .height(HOME_TITLE_ROW_HEIGHT)
    .margin({ left: HOME_TITLE_TAG_LEFT_MARGIN, top: getEffectiveTopSafeHeight(this.topSafeHeight) })
    .alignItems(VerticalAlign.Center)
    .translate({ y: HOME_TITLE_TAG_VISUAL_OFFSET_Y })
    .zIndex(60)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private StickyTagChip(tag: string) {
    if (this.isHdsTabsEnabled && deviceInfo.distributionOSApiVersion >= 60100) {
      StickyHdsTagChip({
        tag: tag,
        selectedTag: this.selectedTag,
        isLoading: this.tagLoading,
        chipWidth: this.getStickyTagChipWidth(tag),
        hdsMaterialLevel: this.hdsMaterialLevel,
        onSelected: (nextTag: string) => {
          this.handleTagSelect(nextTag)
        }
      })
    } else {
      this.FallbackStickyTagChip(tag)
    }
  }

  @Builder
  private FallbackStickyTagChip(tag: string) {
    Row({ space: 5 }) {
      if (this.tagLoading && tag === this.selectedTag) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(Color.White)
      }

      Text(tag)
        .fontSize(13)
        .fontColor(tag === this.selectedTag ? Color.White : $r('app.color.text_primary'))
        .fontWeight(tag === this.selectedTag ? FontWeight.Medium : FontWeight.Normal)
    }
      .height(30)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(tag === this.selectedTag ? $r('app.color.accent_blue') : $r('app.color.tag_chip_bg'))
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onClick(() => {
        this.handleTagSelect(tag === this.selectedTag ? '' : tag)
      })
  }

  private getHomeTopSpacerHeight(): number {
    return getTopSpacerHeight(this.topSafeHeight)
  }

  private getHomeBottomSpacerHeight(): number {
    return getBottomSpacerHeight(this.bottomSafeHeight)
  }

  private getHeroSkeletonHeight(): number {
    if (this.screenWidthVp >= 840) {
      return 360 + this.getHomeTopSpacerHeight()
    } else if (this.screenWidthVp >= 600) {
      return 340 + this.getHomeTopSpacerHeight()
    }
    return 300 + this.getHomeTopSpacerHeight()
  }

  private getStickyTitleTagBarWidth(): number {
    const width = this.screenWidthVp > 0 ? this.screenWidthVp : 360
    return Math.max(150, width - HOME_TITLE_MENU_RESERVED_WIDTH - HOME_TITLE_TAG_LEFT_MARGIN)
  }

  private getStickyTagChipWidth(tag: string): number {
    return Math.max(58, tag.length * 15 + (this.tagLoading && tag === this.selectedTag ? 38 : 28))
  }

  private getSkeletonPosterWidth(): number {
    if (this.screenWidthVp >= 1200) {
      return 198
    } else if (this.screenWidthVp >= 840) {
      return 192
    } else if (this.screenWidthVp >= 600) {
      return 180
    }
    return 122
  }

  private getRailSkeletonCardWidth(): number {
    if (this.screenWidthVp >= 840) {
      return 156
    } else if (this.screenWidthVp >= 600) {
      return 132
    }
    return 112
  }

  private getRailSkeletonCardHeight(): number {
    return Math.round(this.getRailSkeletonCardWidth() * 4 / 3) + 44
  }

  private updateBottomTabOffset(deltaY: number): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const currentOffset = this.scroller.currentOffset()
    if (currentOffset.yOffset <= 0) {
      requestBottomTabAnimation(false)
      this.bottomTabOffset = 0
      return
    }
    const maxOffset = getBottomTabHideDistance(this.bottomSafeHeight)
    const nextOffset = resolveBottomTabOffsetByDelta(deltaY, this.bottomTabOffset, maxOffset)
    if (Math.abs(nextOffset - this.bottomTabOffset) >= 0.5) {
      this.bottomTabOffset = nextOffset
      requestBottomTabAnimation(resolveBottomTabSnapTarget(nextOffset, maxOffset) > 0)
    }
  }

  private snapBottomTabOffset(): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const maxOffset = getBottomTabHideDistance(this.bottomSafeHeight)
    const targetOffset = resolveBottomTabSnapTarget(this.bottomTabOffset, maxOffset)
    if (Math.abs(targetOffset - this.bottomTabOffset) < 0.5) {
      return
    }
    const shouldHide = targetOffset > 0
    requestBottomTabAnimation(shouldHide)
    if (!shouldHide) {
      this.bottomTabOffset = 0
    }
  }

  private handleTagBarAreaChange(top: number, _height: number): void {
    const pinLine = this.getHomeTopSpacerHeight()
    if (!this.tagBarPinned && top <= pinLine) {
      const offset = this.scroller.currentOffset()
      this.tagPinScrollThreshold = Math.max(0, offset.yOffset + top - pinLine)
      this.tagBarPinned = true
    }
  }

  private refreshTagBarPinnedState(): void {
    const offset = this.scroller.currentOffset()
    if (offset.yOffset <= 0 && this.tagBarPinned) {
      this.tagBarPinned = false
      this.tagPinScrollThreshold = -1
      return
    }
    if (!this.tagBarPinned || this.tagPinScrollThreshold < 0) {
      return
    }
    if (this.tagSwitchInProgress || Date.now() < this.tagSwitchPinGuardUntil) {
      return
    }
    if (offset.yOffset < this.tagPinScrollThreshold - HOME_STICKY_TAG_PIN_HYSTERESIS) {
      this.tagBarPinned = false
      this.tagPinScrollThreshold = -1
    }
  }
}

@Component
struct StickyHdsTagChip {
  @Prop tag: string = ''
  @Prop selectedTag: string = ''
  @Prop isLoading: boolean = false
  @Prop chipWidth: number = 64
  @Prop hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  onSelected?: (tag: string) => void

  build() {
    Column() {
      HdsTabs() {
        TabContent()
          .clip(false)
          .tabBar(this.contentBuilder())
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
      }
      .clip(false)
      .hitTestBehavior(HitTestMode.None)
      .align(Alignment.Center)
      .width(this.chipWidth)
      .height(HOME_STICKY_TAG_HEIGHT)
      .enabled(false)
      .barWidth(this.chipWidth)
      .barHeight(HOME_STICKY_TAG_HEIGHT)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .backgroundColor(Color.Transparent)
      .shadow(undefined)
      .barFloatingStyle({
        barWidth: {
          smallWidth: this.chipWidth,
          mediumWidth: this.chipWidth,
          largeWidth: this.chipWidth
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
    .clip(true)
    .borderRadius(HOME_STICKY_TAG_HEIGHT / 2)
    .width(this.chipWidth)
    .height(HOME_STICKY_TAG_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onClick(() => {
      this.onSelected?.(this.isSelected() ? '' : this.tag)
    })
  }

  @Builder
  private contentBuilder(): void {
    Row({ space: 5 }) {
      if (this.isLoading && this.isSelected()) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(Color.White)
      }

      Text(this.tag)
        .fontSize(13)
        .fontColor(this.isSelected() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .fontWeight(this.isSelected() ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
  }

  private isSelected(): boolean {
    return this.tag === this.selectedTag
  }
}
