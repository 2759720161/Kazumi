import { AnimeItem } from '../../models/AnimeItem'
import { BangumiApi } from '../../core/api/BangumiApi'
import { AnimeSeason, YearQuarterItem, QuarterItem } from '../../core/utils/AnimeSeason'
import { TimelineAnimeCard } from '../../components/timeline/TimelineAnimeCard'
import { TIMELINE_WEEKDAY_LABELS } from '../../components/timeline/TimelineWeekdayHdsTabs'
import { LoadingOverlay } from '../../components/common/LoadingOverlay'
import { EmptyState } from '../../components/common/EmptyState'
import { ErrorRetry } from '../../components/common/ErrorRetry'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitle,
  TitleBarStyleOptions,
  TitleBarContentOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsTabs,
  hdsMaterial
} from '@kit.UIDesignKit'
import {
  MINI_TITLE_BAR_CONTENT_HEIGHT,
  getEffectiveTopSafeHeight,
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle
} from '../../utils/HdsPageStyle'

const logger = new Logger('TimelinePage')
const WEEKDAY_TAB_COUNT: number = 7
const WEEKDAY_TAB_BAR_HEIGHT: number = 40
const WEEKDAY_TAB_ITEM_GAP: number = 8
const WEEKDAY_TAB_ITEM_MAX_WIDTH: number = 72
const WEEKDAY_TAB_ITEM_MIN_WIDTH: number = 52

const WEEKDAY_FULL_NAMES: string[] = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日']

const SEASON_SIDEBAR_MAX_WIDTH: number = 360
const SEASON_SIDEBAR_SLIDE_IN_DURATION: number = 250
const SEASON_SIDEBAR_SLIDE_OUT_DURATION: number = 200

@Component
export struct TimelinePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State selectedWeekdayIndex: number = 0
  @State seasonString: string = ''
  @State calendar: AnimeItem[][] = []
  @State isLoading: boolean = false
  @State isError: boolean = false
  @State hasLoaded: boolean = false
  @State showSeasonSideBar: boolean = false
  @State selectedYear: number = 0
  @State selectedQuarter: number = 0
  @State isViewingCurrentSeason: boolean = true
  private contentScroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.selectedYear = new Date().getFullYear()
    this.selectedQuarter = AnimeSeason.getSeasonQuarter()
    this.seasonString = AnimeSeason.getSeasonString()
    this.selectedWeekdayIndex = AnimeSeason.getCurrentWeekdayIndex()
    if (!this.hasLoaded) {
      this.loadCalendar()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.contentScroller) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight) + WEEKDAY_TAB_BAR_HEIGHT)
              .width('100%')

            if (this.isLoading && this.calendar.length === 0) {
              LoadingOverlay({ message: '时间表加载中...' })
            } else if (this.isError) {
              ErrorRetry({
                message: 'Bangumi 时间表加载失败',
                onRetry: () => {
                  this.retryLoad()
                }
              })
            } else if (this.getAnimeListForWeekday(this.selectedWeekdayIndex).length === 0) {
              EmptyState({ message: `${TIMELINE_WEEKDAY_LABELS[this.selectedWeekdayIndex]}暂无放送条目` })
            } else {
              this.AnimeListContent()
            }

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
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
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildTimelineTitleBarOptions())
      .bindToScrollable([this.contentScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (!this.isLoading && !this.isError && this.getAnimeListForWeekday(this.selectedWeekdayIndex).length > 0) {
        this.WeekdayTabBar()
      }

      if (this.showSeasonSideBar) {
        this.SeasonSideBarOverlay()
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
  private AnimeListContent(): void {
    Column() {
      ForEach(this.getAnimeListForWeekday(this.selectedWeekdayIndex), (item: AnimeItem, index?: number) => {
        TimelineAnimeCard({ animeItem: item })
          .margin({ bottom: 8 })
      }, (item: AnimeItem, index?: number) => `tl_${this.selectedWeekdayIndex}_${index}_${item.name}`)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  @Builder
  private WeekdayTabBar(): void {
    Column() {
      Row() {
        ForEach(this.getVisibleWeekdayIndices(), (weekdayIndex: number) => {
          Column() {
            WeekdayTabItem({
              label: TIMELINE_WEEKDAY_LABELS[weekdayIndex],
              index: weekdayIndex,
              selectedIndex: this.selectedWeekdayIndex,
              tabWidth: WEEKDAY_TAB_ITEM_MAX_WIDTH,
              onSelected: (selectedIndex: number) => {
                this.getUIContext().animateTo({
                  duration: 250,
                  curve: Curve.Friction
                }, () => {
                  this.selectedWeekdayIndex = selectedIndex
                })
              }
            })
          }
          .layoutWeight(1)
        }, (weekdayIndex: number) => `weekday_tab_${weekdayIndex}`)
      }
      .width('100%')
      .height(WEEKDAY_TAB_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('100%')
    .height(WEEKDAY_TAB_BAR_HEIGHT)
    .margin({ top: getTopSpacerHeight(this.topSafeHeight) })
    .zIndex(30)
  }

  @Builder
  SeasonSideBarOverlay(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .transition(TransitionEffect.OPACITY.animation({
          duration: SEASON_SIDEBAR_SLIDE_IN_DURATION,
          curve: Curve.EaseOut
        }))
        .onClick(() => {
          this.showSeasonSideBar = false
        })

      Column() {
        this.SeasonSideBarHeader()
        this.SeasonSideBarBody()
      }
      .width('82%')
      .constraintSize({ maxWidth: SEASON_SIDEBAR_MAX_WIDTH })
      .height('100%')
      .backgroundColor($r('app.color.page_background_media'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius({ topRight: 18, bottomRight: 18 })
      .border({ width: { right: 0.5 }, color: $r('app.color.border_panel') })
      .shadow({ radius: 24, color: $r('app.color.shadow_surface'), offsetX: 8 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: '-100%' }))
          .animation({
            duration: SEASON_SIDEBAR_SLIDE_IN_DURATION,
            curve: Curve.EaseOut
          }),
        TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: '-100%' }))
          .animation({
            duration: SEASON_SIDEBAR_SLIDE_OUT_DURATION,
            curve: Curve.EaseOut
          })
      ))
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.opacity(0.99).animation({
      duration: SEASON_SIDEBAR_SLIDE_IN_DURATION,
      curve: Curve.EaseOut
    }))
    .zIndex(40)
  }

  @Builder
  SeasonSideBarHeader(): void {
    Column() {
      Row() {
        Column() {
          Text('时间机器')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.button_ghost_bg'))
        .onClick(() => {
          this.showSeasonSideBar = false
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 20 })
      .margin({ top: getEffectiveTopSafeHeight(this.topSafeHeight) })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(getTopSpacerHeight(this.topSafeHeight))
  }

  @Builder
  SeasonSideBarBody(): void {
    Scroll() {
      Column() {
        this.CurrentSeasonPill()

        if (!this.isViewingCurrentSeason) {
          this.BackToCurrentSeasonButton()
        }

        ForEach(AnimeSeason.generateYearQuarterList(this.selectedYear, this.selectedQuarter),
          (item: YearQuarterItem) => {
            this.YearCard(item)
          }, (item: YearQuarterItem) => `year_${item.year}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
  }

  @Builder
  CurrentSeasonPill(): void {
    Row() {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(14)
        .fontColor([$r('app.color.accent_blue')])
      
      Text(AnimeSeason.getSeasonShortString(this.selectedYear, this.selectedQuarter))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent_blue'))
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.episode_item_selected_bg'))
    .borderRadius(8)
    .margin({ bottom: 12 })
  }

  @Builder
  BackToCurrentSeasonButton(): void {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
        .fontSize(14)
        .fontColor([$r('app.color.text_secondary')])
      
      Text('回到当前季度')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 6 })
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: 12 })
    .onClick(() => {
      const now = new Date()
      const currentYear = now.getFullYear()
      const currentQuarter = Math.floor(now.getMonth() / 3)
      this.onSeasonSelected(currentYear, currentQuarter)
    })
  }

  @Builder
  YearCard(item: YearQuarterItem): void {
    Column() {
      Row() {
        Text(`${item.year}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        
        Text('年')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 2 })
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row({ space: 8 }) {
        ForEach(item.quarters, (quarter: QuarterItem) => {
          this.QuarterChip(quarter, item.year)
        }, (quarter: QuarterItem) => `q_${item.year}_${quarter.quarterIndex}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor(item.isHighlighted ? $r('app.color.episode_item_selected_bg') : $r('app.color.card_background'))
    .margin({ bottom: 8 })
  }

  @Builder
  QuarterChip(quarter: QuarterItem, year: number): void {
    Column() {
      Text(quarter.seasonName)
        .fontSize(14)
        .fontWeight(quarter.isSelected ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(quarter.isSelected ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(quarter.isSelected ? $r('app.color.accent_blue') : $r('app.color.button_ghost_bg'))
    .onClick(() => {
      this.onSeasonSelected(year, quarter.quarterIndex)
    })
  }

  private openSeasonSideBar(): void {
    this.showSeasonSideBar = true
  }

  private buildSeasonIcon(): HdsNavigationIconOptions {
    return {
      icon: this.showSeasonSideBar ? $r('sys.symbol.xmark') : $r('sys.symbol.line_3_horizontal'),
      label: 'season',
      action: () => {
        if (this.showSeasonSideBar) {
          this.showSeasonSideBar = false
        } else {
          this.openSeasonSideBar()
        }
      }
    }
  }

  private buildTimelineTitle(): HdsNavigationTitle {
    return {
      mainTitle: this.seasonString,
      subTitle: WEEKDAY_FULL_NAMES[this.selectedWeekdayIndex]
    }
  }

  private buildTimelineTitleBarContent(): TitleBarContentOptions {
    return {
      backIcon: this.buildSeasonIcon(),
      title: this.buildTimelineTitle()
    }
  }

  private buildTimelineTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle()
    if (style.originalStyle?.backgroundStyle) {
      style.originalStyle.backgroundStyle.maskExtraHeight = 0
    }
    if (style.scrollEffectStyle?.backgroundStyle) {
      style.scrollEffectStyle.backgroundStyle.maskExtraHeight = 0
    }
    return {
      style: style,
      content: this.buildTimelineTitleBarContent(),
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
  }

  private getVisibleWeekdayCount(): number {
    if (this.screenWidthVp >= 600) {
      return 5
    }
    return 3
  }

  private getVisibleWeekdayIndices(): number[] {
    const count = this.getVisibleWeekdayCount()
    const result: number[] = []
    const selected = this.selectedWeekdayIndex
    
    if (count === 3) {
      if (selected === 0) {
        result.push(0, 1, 2)
      } else if (selected === 6) {
        result.push(4, 5, 6)
      } else {
        result.push(selected - 1, selected, selected + 1)
      }
    } else if (count === 5) {
      if (selected <= 1) {
        for (let i = 0; i < 5; i++) result.push(i)
      } else if (selected >= 5) {
        for (let i = 2; i < 7; i++) result.push(i)
      } else {
        for (let i = selected - 2; i <= selected + 2; i++) result.push(i)
      }
    } else {
      for (let i = 0; i < 7; i++) result.push(i)
    }
    
    return result
  }

  private getWeekdayTabWidth(): number {
    const count = this.getVisibleWeekdayCount()
    const availableWidth = this.screenWidthVp - 24
    const gapTotal = WEEKDAY_TAB_ITEM_GAP * (count - 1)
    const fittedWidth = (availableWidth - gapTotal) / count
    return Math.max(WEEKDAY_TAB_ITEM_MIN_WIDTH, Math.min(WEEKDAY_TAB_ITEM_MAX_WIDTH, fittedWidth))
  }

  private getAnimeListForWeekday(weekdayIndex: number): AnimeItem[] {
    if (this.calendar.length < WEEKDAY_TAB_COUNT) {
      return []
    }
    const apiIndex = weekdayIndex === 6 ? 0 : weekdayIndex + 1
    return this.calendar[apiIndex]
  }

  private async loadCalendar(): Promise<void> {
    this.isLoading = true
    this.isError = false
    try {
      const result = await BangumiApi.getCalendar()
      this.calendar = result
      this.hasLoaded = true
      logger.info('Calendar loaded: %{public}d days', result.filter((arr: AnimeItem[]) => arr.length > 0).length)
    } catch (_err) {
      this.isError = true
      logger.warn('Calendar load failed')
    } finally {
      this.isLoading = false
    }
  }

  private onSeasonSelected(year: number, quarter: number): void {
    if (year === this.selectedYear && quarter === this.selectedQuarter) {
      this.showSeasonSideBar = false
      return
    }

    this.showSeasonSideBar = false
    this.seasonString = '加载中'
    this.selectedYear = year
    this.selectedQuarter = quarter
    this.isViewingCurrentSeason = AnimeSeason.isCurrentSeason(year, quarter)
    this.selectedWeekdayIndex = AnimeSeason.getCurrentWeekdayIndex()
    this.loadCalendarBySeason(year, quarter)
  }

  private async loadCalendarBySeason(year: number, quarter: number): Promise<void> {
    this.isLoading = true
    this.isError = false
    try {
      let result: AnimeItem[][] = []
      if (AnimeSeason.isCurrentSeason(year, quarter)) {
        result = await BangumiApi.getCalendar()
      } else {
        const mirrorResult = await BangumiApi.fetchCalendarBySeason(
          AnimeSeason.getSeasonDateRange(year, quarter)[0],
          AnimeSeason.getSeasonDateRange(year, quarter)[1])
        const hasData = mirrorResult.some((arr: AnimeItem[]) => arr.length > 0)
        if (hasData) {
          result = mirrorResult
        } else {
          result = await BangumiApi.searchByAirDateRange(
            AnimeSeason.getSeasonDateRange(year, quarter)[0],
            AnimeSeason.getSeasonDateRange(year, quarter)[1])
        }
      }
      this.calendar = result
      this.seasonString = AnimeSeason.getSeasonString(new Date(year, quarter * 3, 1))
      this.hasLoaded = true
      logger.info('Season calendar loaded for %{public}d Q%{public}d', year, quarter)
    } catch (_err) {
      this.isError = true
      logger.warn('Season calendar load failed')
    } finally {
      this.isLoading = false
    }
  }

  private retryLoad(): void {
    if (this.isViewingCurrentSeason) {
      this.loadCalendar()
    } else {
      this.loadCalendarBySeason(this.selectedYear, this.selectedQuarter)
    }
  }
}

@Component
struct WeekdayTabItem {
  @Prop label: string = ''
  @Prop index: number = 0
  @Prop selectedIndex: number = 0
  @Prop tabWidth: number = 100
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
      .height(WEEKDAY_TAB_BAR_HEIGHT)
      .barWidth(this.tabWidth)
      .barHeight(WEEKDAY_TAB_BAR_HEIGHT)
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
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        },
        lightColor: Color.Transparent
      })
    }
    .backgroundColor(Color.Transparent)
    .clip(false)
    .width(this.tabWidth)
    .height(WEEKDAY_TAB_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
  }

  @Builder
  tabBarContentBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Text(this.label)
          .fontSize(14)
          .fontWeight(this.isSelected() ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.isSelected() ? '#E6000000' : '#99000000')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
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
