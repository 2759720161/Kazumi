import { AnimeItem } from '../../models/AnimeItem'
import { BangumiApi } from '../../core/api/BangumiApi'
import { AnimeSeason, YearQuarterItem, QuarterItem } from '../../core/utils/AnimeSeason'
import { TimelineAnimeCard } from '../../components/timeline/TimelineAnimeCard'
import { TIMELINE_WEEKDAY_LABELS } from '../../components/timeline/TimelineWeekdayHdsTabs'
import { ErrorRetry } from '../../components/common/ErrorRetry'
import { Logger } from '../../utils/Logger'
import { router, curves } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitle,
  TitleBarStyleOptions,
  TitleBarContentOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsTabs
} from '@kit.UIDesignKit'
import {
  MINI_TITLE_BAR_CONTENT_HEIGHT,
  getEffectiveTopSafeHeight,
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle,
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
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
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
  @State weekdayTabWindowStart: number = 0
  private contentScroller: Scroller = new Scroller()
  private weekdayTabScroller: Scroller = new Scroller()
  private enrichingWeekdayKeys: string[] = []
  private enrichedWeekdayKeys: string[] = []

  aboutToAppear(): void {
    this.selectedYear = new Date().getFullYear()
    this.selectedQuarter = AnimeSeason.getSeasonQuarter()
    this.seasonString = AnimeSeason.getSeasonString()
    this.selectedWeekdayIndex = AnimeSeason.getCurrentWeekdayIndex()
    this.weekdayTabWindowStart = this.resolveWeekdayTabWindowStart(this.selectedWeekdayIndex)
    if (!this.hasLoaded) {
      this.loadCalendar()
    }
  }

  onPageShow(): void {
    // The timeline page remains mounted while detail pages are pushed. Clone
    // the current items on return so cover fields enriched in the background
    // are propagated to recycled TimelineAnimeCard components immediately.
    if (this.calendar.length >= WEEKDAY_TAB_COUNT) {
      this.calendar = this.cloneCalendar(this.calendar)
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
              this.TimelineSkeletonList()
            } else if (this.isError) {
              ErrorRetry({
                message: 'Bangumi 时间表加载失败',
                onRetry: () => {
                  this.retryLoad()
                }
              })
            } else if (this.getAnimeListForWeekday(this.selectedWeekdayIndex).length === 0) {
              Column() {
                Text('这一天暂无放送条目')
                  .fontSize(16)
                  .fontColor($r('app.color.text_secondary'))
                Text('试试切换到其它星期')
                  .fontSize(14)
                  .fontColor($r('app.color.text_hint'))
                  .margin({ top: 4 })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              this.AnimeListContent()
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
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .clip(false)
        .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
          this.updateBottomTabOffset(yOffset)
        })
        .onScrollStop(() => {
          this.snapBottomTabOffset()
        })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 40 })
            .onActionEnd((event: GestureEvent) => {
              if (Math.abs(event.offsetX) < 30) {
                return
              }
              if (event.offsetX < 0 && this.selectedWeekdayIndex < WEEKDAY_TAB_COUNT - 1) {
                const nextIndex = this.selectedWeekdayIndex + 1
                const nextWindowStart = this.resolveWeekdayTabWindowStart(nextIndex)
                this.getUIContext().animateTo({
                  duration: 250,
                  curve: curves.springMotion()
                }, () => {
                  this.selectedWeekdayIndex = nextIndex
                  this.weekdayTabWindowStart = nextWindowStart
                })
                this.scrollWeekdayTabWindowToStart(nextWindowStart)
                this.contentScroller.scrollToIndex(0)
                this.enrichSelectedWeekdayInBackground(nextIndex)
              } else if (event.offsetX > 0 && this.selectedWeekdayIndex > 0) {
                const nextIndex = this.selectedWeekdayIndex - 1
                const nextWindowStart = this.resolveWeekdayTabWindowStart(nextIndex)
                this.getUIContext().animateTo({
                  duration: 250,
                  curve: curves.springMotion()
                }, () => {
                  this.selectedWeekdayIndex = nextIndex
                  this.weekdayTabWindowStart = nextWindowStart
                })
                this.scrollWeekdayTabWindowToStart(nextWindowStart)
                this.contentScroller.scrollToIndex(0)
                this.enrichSelectedWeekdayInBackground(nextIndex)
              }
            })
        )
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

      if (!this.isError) {
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
    Grid() {
      ForEach(this.getAnimeListForWeekday(this.selectedWeekdayIndex), (item: AnimeItem, index?: number) => {
        GridItem() {
          TimelineAnimeCard({ animeItem: item })
        }
      }, (item: AnimeItem, index?: number) =>
        // The calendar first renders lightweight subject records and enriches
        // them with cover URLs afterwards. Include the cover in the key so a
        // recycled GridItem is rebuilt when enrichment finishes.
        `tl_${this.selectedYear}_${this.selectedQuarter}_${this.selectedWeekdayIndex}_${index}_${item.bangumiId}_${item.name}_${item.getGridCover()}`)
    }
    .columnsTemplate(this.getTimelineCardColumns())
    .columnsGap(10)
    .rowsGap(10)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  private updateBottomTabOffset(deltaY: number): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const currentOffset = this.contentScroller.currentOffset()
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

  @Builder
  private TimelineSkeletonList(): void {
    Grid() {
      ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
        GridItem() {
          Row() {
            Column()
              .width(92)
              .height(132)
              .borderRadius(10)
              .backgroundColor($r('app.color.skeleton_background'))

            Column() {
              Column()
                .width('70%')
                .height(16)
                .borderRadius(4)
                .backgroundColor($r('app.color.skeleton_background'))
              Column()
                .width('50%')
                .height(14)
                .borderRadius(4)
                .margin({ top: 6 })
                .backgroundColor($r('app.color.skeleton_background'))
              Column()
                .width('85%')
                .height(14)
                .borderRadius(4)
                .margin({ top: 4 })
                .backgroundColor($r('app.color.skeleton_background'))
              Blank()
                .layoutWeight(1)
              Row() {
                Column()
                  .width(36)
                  .height(14)
                  .borderRadius(4)
                  .backgroundColor($r('app.color.skeleton_background'))
              }
            }
            .layoutWeight(1)
            .height(132)
            .margin({ left: 14 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 0.5, color: $r('app.color.card_specular_border') })
        }
      }, (index: number) => `tl_skeleton_${index}`)
    }
    .columnsTemplate(this.getTimelineCardColumns())
    .columnsGap(10)
    .rowsGap(10)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }

  @Builder
  private WeekdayTabBar(): void {
    Column() {
      Stack() {
        List({
          space: WEEKDAY_TAB_ITEM_GAP,
          initialIndex: this.weekdayTabWindowStart,
          scroller: this.weekdayTabScroller
        }) {
          ForEach(this.getAllWeekdayIndices(), (weekdayIndex: number) => {
            ListItem() {
              Column() {
                WeekdayTabItem({
                  label: TIMELINE_WEEKDAY_LABELS[weekdayIndex],
                  index: weekdayIndex,
                selectedIndex: this.selectedWeekdayIndex,
                tabWidth: WEEKDAY_TAB_ITEM_MAX_WIDTH,
                onSelected: (selectedIndex: number) => {
                  const nextWindowStart = this.resolveWeekdayTabWindowStart(selectedIndex)
                  this.getUIContext().animateTo({
                    duration: 250,
                    curve: curves.springMotion()
                  }, () => {
                      this.selectedWeekdayIndex = selectedIndex
                      this.weekdayTabWindowStart = nextWindowStart
                    })
                    this.scrollWeekdayTabWindowToStart(nextWindowStart)
                    this.contentScroller.scrollToIndex(0)
                    this.enrichSelectedWeekdayInBackground(selectedIndex)
                  }
                })
              }
              .clip(true)
              .backgroundColor(Color.Transparent)
              .borderRadius(WEEKDAY_TAB_BAR_HEIGHT / 2)
              .width('100%')
              .height(WEEKDAY_TAB_BAR_HEIGHT)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
            .clip(true)
            .backgroundColor(Color.Transparent)
            .borderRadius(WEEKDAY_TAB_BAR_HEIGHT / 2)
            .width(this.getWeekdayTabCellWidth())
            .height(WEEKDAY_TAB_BAR_HEIGHT)
          }, (weekdayIndex: number) => `weekday_tab_${weekdayIndex}`)
        }
        .clip(true)
        .backgroundColor(Color.Transparent)
        .width('100%')
        .height(WEEKDAY_TAB_BAR_HEIGHT)
        .padding({ left: 12, right: 12 })
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .alignListItem(ListItemAlign.Center)
      }
      .width('100%')
      .height(WEEKDAY_TAB_BAR_HEIGHT)
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
      .width(this.getSeasonSideBarWidth())
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
          Text('季度选择')
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
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
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

  private getSeasonSideBarWidth(): Length {
    if (this.screenWidthVp >= 900) {
      return 420
    }
    if (this.screenWidthVp >= 600) {
      return 360
    }
    return '82%'
  }

  private getVisibleWeekdayCount(): number {
    if (this.screenWidthVp >= 840) {
      return 7
    }
    if (this.screenWidthVp >= 600) {
      return 5
    }
    return 3
  }

  private getAllWeekdayIndices(): number[] {
    const result: number[] = []
    for (let i = 0; i < WEEKDAY_TAB_COUNT; i++) {
      result.push(i)
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

  private getWeekdayTabCellWidth(): number {
    const count = this.getVisibleWeekdayCount()
    const availableWidth = this.screenWidthVp - 24
    const gapTotal = WEEKDAY_TAB_ITEM_GAP * (count - 1)
    return Math.max(WEEKDAY_TAB_ITEM_MIN_WIDTH, (availableWidth - gapTotal) / count)
  }

  private handleWeekdayTabWindowSwipe(offsetX: number): void {
    if (Math.abs(offsetX) < 24) {
      return
    }
    const direction = offsetX < 0 ? 1 : -1
    const nextStart = this.clampWeekdayTabWindowStart(this.weekdayTabWindowStart + direction)
    if (nextStart === this.weekdayTabWindowStart) {
      return
    }
    this.weekdayTabWindowStart = nextStart
    this.scrollWeekdayTabWindowToStart(nextStart)
  }

  private scrollWeekdayTabWindowToStart(start: number): void {
    try {
      this.weekdayTabScroller.scrollToIndex(start, true, ScrollAlign.START)
    } catch (error) {
      logger.warn(`scroll weekday window failed: ${JSON.stringify(error)}`)
    }
  }

  private resolveWeekdayTabWindowStart(selectedIndex: number): number {
    const count = this.getVisibleWeekdayCount()
    const centeredStart = selectedIndex - Math.floor(count / 2)
    return this.clampWeekdayTabWindowStart(centeredStart)
  }

  private clampWeekdayTabWindowStart(start: number): number {
    const maxStart = Math.max(0, WEEKDAY_TAB_COUNT - this.getVisibleWeekdayCount())
    return Math.max(0, Math.min(maxStart, start))
  }

  private getTimelineCardColumns(): string {
    if (this.screenWidthVp >= 1200) {
      return '1fr 1fr 1fr'
    }
    if (this.screenWidthVp >= 600) {
      return '1fr 1fr'
    }
    return '1fr'
  }

  private getAnimeListForWeekday(weekdayIndex: number): AnimeItem[] {
    if (this.calendar.length < WEEKDAY_TAB_COUNT) {
      return []
    }
    return this.calendar[weekdayIndex]
  }

  private async loadCalendar(): Promise<void> {
    this.isLoading = true
    this.isError = false
    try {
      const result = await BangumiApi.getCalendar()
      this.calendar = result
      this.hasLoaded = true
      logger.info('Calendar loaded: %{public}d days', result.filter((arr: AnimeItem[]) => arr.length > 0).length)
      this.enrichSelectedWeekdayInBackground(this.selectedWeekdayIndex)
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
    this.enrichingWeekdayKeys = []
    this.enrichedWeekdayKeys = []
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
        if (BangumiApi.isCalendarResultUseful(mirrorResult)) {
          result = mirrorResult
        } else {
          const fallbackResult = await BangumiApi.searchByAirDateRange(
            AnimeSeason.getSeasonDateRange(year, quarter)[0],
            AnimeSeason.getSeasonDateRange(year, quarter)[1])
          if (BangumiApi.hasCalendarItems(fallbackResult)) {
            result = fallbackResult
          } else {
            result = mirrorResult
          }
        }
      }
      this.calendar = result
      this.seasonString = AnimeSeason.getSeasonString(new Date(year, quarter * 3, 1))
      this.hasLoaded = true
      logger.info('Season calendar loaded for %{public}d Q%{public}d', year, quarter)
      this.enrichSelectedWeekdayInBackground(this.selectedWeekdayIndex)
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

  private enrichSelectedWeekdayInBackground(weekdayIndex: number): void {
    if (this.calendar.length < WEEKDAY_TAB_COUNT) {
      return
    }
    const key = this.buildEnrichWeekdayKey(weekdayIndex)
    if (this.hasEnrichKey(this.enrichedWeekdayKeys, key) || this.hasEnrichKey(this.enrichingWeekdayKeys, key)) {
      return
    }
    this.addEnrichKey(this.enrichingWeekdayKeys, key)
    const targetCalendar = this.calendar
    const visibleDayItemCount = targetCalendar[weekdayIndex].length
    BangumiApi.enrichCalendarItemsForDay(targetCalendar, weekdayIndex, visibleDayItemCount, () => {
      if (this.buildEnrichWeekdayKey(this.selectedWeekdayIndex) !== key || this.calendar.length < WEEKDAY_TAB_COUNT) {
        return
      }
      this.calendar = this.cloneCalendar(targetCalendar)
    })
      .then(() => {
        this.removeEnrichKey(this.enrichingWeekdayKeys, key)
        this.addEnrichKey(this.enrichedWeekdayKeys, key)
        if (this.buildEnrichWeekdayKey(this.selectedWeekdayIndex) !== key || this.calendar.length < WEEKDAY_TAB_COUNT) {
          return
        }
        this.calendar = this.cloneCalendar(targetCalendar)
      })
      .catch((_err: Error) => {
        this.removeEnrichKey(this.enrichingWeekdayKeys, key)
        logger.warn('Visible weekday enrich failed')
      })
  }

  private buildEnrichWeekdayKey(weekdayIndex: number): string {
    return `${this.selectedYear}-${this.selectedQuarter}-${weekdayIndex}`
  }

  private hasEnrichKey(keys: string[], key: string): boolean {
    return keys.indexOf(key) >= 0
  }

  private addEnrichKey(keys: string[], key: string): void {
    if (!this.hasEnrichKey(keys, key)) {
      keys.push(key)
    }
  }

  private removeEnrichKey(keys: string[], key: string): void {
    const index = keys.indexOf(key)
    if (index >= 0) {
      keys.splice(index, 1)
    }
  }

  private cloneCalendar(source: AnimeItem[][]): AnimeItem[][] {
    const result: AnimeItem[][] = []
    for (let i = 0; i < source.length; i++) {
      // enrichCalendarItemsForDay mutates the existing AnimeItem instances.
      // Clone the items as well as the arrays so TimelineAnimeCard @Watch
      // receives a new prop object and replaces its initial placeholder.
      const clonedDay: AnimeItem[] = []
      for (let j = 0; j < source[i].length; j++) {
        clonedDay.push(AnimeItem.fromJSON(source[i][j].toJSON()))
      }
      result.push(clonedDay)
    }
    return result
  }
}

@Component
struct WeekdayTabItem {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
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
      .width(this.tabWidth)
      .height(WEEKDAY_TAB_BAR_HEIGHT)
      .enabled(false)
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
        systemMaterialEffect: buildAdaptiveMaterialEffect(this.hdsMaterialLevel),
        lightColor: Color.Transparent
      })
    }
    .backgroundColor(Color.Transparent)
    .clip(true)
    .borderRadius(WEEKDAY_TAB_BAR_HEIGHT / 2)
    .width(this.tabWidth)
    .height(WEEKDAY_TAB_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .onClick(() => {
      this.selectTab()
    })
  }

  @Builder
  tabBarContentBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
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
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .shadow(undefined)
    .hitTestBehavior(HitTestMode.Transparent)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
  }

  private selectTab(): void {
    this.onSelected?.(this.index)
  }

  private isSelected(): boolean {
    return this.selectedIndex === this.index
  }
}
