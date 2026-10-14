import { CollectController } from '../../controller/CollectController'
import { CollectedBangumi } from '../../models/CollectedBangumi'
import { CollectType } from '../../models/CollectType'
import { CollectCard } from '../../components/collect/CollectCard'
import { CollectStatusMenu } from '../../components/collect/CollectStatusMenu'
import { EmptyState } from '../../components/common/EmptyState'
import { Logger } from '../../utils/Logger'
import { curves } from '@kit.ArkUI'
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
import { HistorySyncService } from '../../services/HistorySyncService'

const logger = new Logger('FavoritePage')
const COLLECT_CARD_GAP: number = 8
const COLLECT_STATUS_TYPES: number[] = [
  CollectType.watching,
  CollectType.planToWatch,
  CollectType.onHold,
  CollectType.watched,
  CollectType.abandoned
]
const COLLECT_STATUS_TAB_BAR_HEIGHT: number = 40
const COLLECT_STATUS_TAB_ITEM_GAP: number = 8
const COLLECT_STATUS_TAB_ITEM_MAX_WIDTH: number = 72
const COLLECT_STATUS_TAB_ITEM_MIN_WIDTH: number = 52

@Component
export struct FavoritePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('currentTab') @Watch('onCurrentTabChanged') currentTab: number = 0
  @StorageLink('collectVersion') @Watch('onCollectVersionChanged') collectVersion: number = 0
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State collectedList: CollectedBangumi[] = []
  @State visibleCollectedList: CollectedBangumi[] = []
  @State selectedCollectType: number = CollectType.watching
  @State isEditMode: boolean = false
  @State isLoading: boolean = true
  @State showDeleteDialog: boolean = false
  @State deleteTargetAnimeId: string = ''
  @State deleteTargetName: string = ''
  @State showEditTipDialog: boolean = false
  @State showCollectStatusSheet: boolean = false
  @State statusTargetAnimeId: string = ''
  @State statusTargetName: string = ''
  @State statusTargetType: number = CollectType.none
  private collectController: CollectController = new CollectController()
  private historySyncService: HistorySyncService = HistorySyncService.getInstance()
  private scroller: Scroller = new Scroller()
  private isAutoSyncing: boolean = false

  aboutToAppear(): void {
    this.loadCollectibles().then(() => {
      this.syncCollectIfAutoEnabled()
    }).catch((err: Error) => {
      logger.warn('Initial load collectibles failed: %{public}s', err.message)
    })
  }

  aboutToDisappear(): void {
    this.resetEditState()
  }

  private onCollectVersionChanged(): void {
    this.loadCollectibles()
  }

  private onCurrentTabChanged(): void {
    if (this.currentTab === 2) {
      this.loadCollectibles()
      this.syncCollectIfAutoEnabled()
      this.scroller.scrollEdge(Edge.Top)
    } else {
      this.resetEditState()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.scroller) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight) + COLLECT_STATUS_TAB_BAR_HEIGHT)
              .width('100%')

            if (this.isLoading) {
              Column() {
                LoadingProgress()
                  .width(48)
                  .height(48)
                  .color($r('app.color.loading_color'))
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else if (this.collectedList.length === 0) {
              Column() {
                EmptyState({ message: '你的收藏还是空的' })
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              this.CollectGrid()
            }

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
        }
        .width('100%')
        .height('100%')
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
              this.handleStatusSwipe(event.offsetX)
            })
        )
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      this.CollectStatusTabBar()

      if (this.showDeleteDialog) {
        this.DeleteConfirmDialog()
      }

      if (this.showEditTipDialog) {
        this.EditTipDialog()
      }

    }
    .width('100%')
    .height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.home_bg_top'), 0],
        [$r('app.color.page_background'), 0.35],
        [$r('app.color.page_background'), 1]
      ]
    })
    .bindSheet($$this.showCollectStatusSheet, this.CollectStatusSheetContent, {
      height: 410,
      showClose: false,
      dragBar: true,
      onDisappear: () => {
        this.showCollectStatusSheet = false
      }
    })
  }

  @Builder
  private CollectStatusTabBar(): void {
    Row({ space: COLLECT_STATUS_TAB_ITEM_GAP }) {
      ForEach(COLLECT_STATUS_TYPES, (collectType: number) => {
        Column() {
          CollectStatusTabItem({
            label: CollectType.getLabel(collectType),
            collectType: collectType,
            selectedType: this.selectedCollectType,
            tabWidth: this.getCollectStatusTabWidth(),
            onSelected: (selectedType: number) => {
              this.selectCollectType(selectedType)
            }
          })
        }
        .layoutWeight(1)
        .height(COLLECT_STATUS_TAB_BAR_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }, (collectType: number) => `collect_status_tab_${collectType}`)
    }
    .width('100%')
    .height(COLLECT_STATUS_TAB_BAR_HEIGHT)
    .padding({ left: 12, right: 12 })
    .margin({ top: getTopSpacerHeight(this.topSafeHeight) })
    .zIndex(30)
  }

  @Builder
  CollectGrid(): void {
    if (this.visibleCollectedList.length === 0) {
      Column() {
        EmptyState({ message: `${CollectType.getLabel(this.selectedCollectType)}列表为空` })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: 10 }) {
        ForEach(this.getCollectRows(), (row: CollectedBangumi[], rowIndex?: number) => {
          Row() {
            this.CollectGridSlot(row, 0)
            Blank()
              .width(COLLECT_CARD_GAP)
            this.CollectGridSlot(row, 1)
            if (this.getGridColumnCount() >= 3) {
              Blank()
                .width(COLLECT_CARD_GAP)
              this.CollectGridSlot(row, 2)
            }
            if (this.getGridColumnCount() >= 4) {
              Blank()
                .width(COLLECT_CARD_GAP)
              this.CollectGridSlot(row, 3)
            }
            if (this.getGridColumnCount() >= 5) {
              Blank()
                .width(COLLECT_CARD_GAP)
              this.CollectGridSlot(row, 4)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (_row: CollectedBangumi[], rowIndex?: number) => `collect_row_${rowIndex}`)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 8 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private CollectGridSlot(row: CollectedBangumi[], columnIndex: number): void {
    Column() {
      if (columnIndex < row.length) {
        CollectCard({
          collectedBangumi: row[columnIndex],
          isEditMode: this.isEditMode,
          onEditStatus: () => {
            this.requestStatusEdit(row[columnIndex])
          }
        })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DeleteConfirmDialog(): void {
    Column() {
      Column() {
        Text('取消收藏')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 24 })

        Text(`确定要取消收藏「${this.deleteTargetName}」吗？`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(26)
          .width('100%')
          .margin({ bottom: 26 })

        Row() {
          Text('取消')
            .layoutWeight(1)
            .height(52)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .clip(true)
            .onClick(() => {
              this.showDeleteDialog = false
            })

          Divider()
            .vertical(true)
            .height(34)
            .color($r('app.color.divider_color'))
            .margin({ left: 4, right: 4 })

          Text('删除')
            .layoutWeight(1)
            .height(52)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.status_error'))
            .textAlign(TextAlign.Center)
            .clip(true)
            .onClick(() => {
              this.confirmDelete()
            })
        }
        .width('100%')
        .height(52)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 20 })
      .borderRadius(34)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0x66000000)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20, bottom: 28 })
    .onClick(() => {
      this.showDeleteDialog = false
    })
  }

  @Builder
  EditTipDialog(): void {
    Column() {
      Column() {
        Text('编辑模式')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 12 })

        Text('点击卡片可以修改追番状态')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 20 })

        Button('确定')
          .width('100%')
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('sys.color.brand'))
          .fontColor(Color.White)
          .onClick(() => {
            this.showEditTipDialog = false
            AppStorage.setOrCreate('edit_tip_shown', true)
          })
      }
      .padding(24)
      .borderRadius(16)
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0x66000000)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  private refreshVisibleCollectedList(): void {
    this.visibleCollectedList = this.collectedList
      .filter((item: CollectedBangumi) => item.collectType === this.selectedCollectType)
      .sort((a: CollectedBangumi, b: CollectedBangumi) => b.createdAt - a.createdAt)
    logger.info('Visible collectibles refreshed: type=%{public}d count=%{public}d',
      this.selectedCollectType, this.visibleCollectedList.length)
  }

  private selectCollectType(collectType: number): void {
    const normalizedType = CollectType.normalize(collectType)
    if (normalizedType === CollectType.none || normalizedType === this.selectedCollectType) {
      return
    }
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion()
    }, () => {
      this.selectedCollectType = normalizedType
      this.refreshVisibleCollectedList()
    })
    this.scroller.scrollEdge(Edge.Top)
  }

  private handleStatusSwipe(offsetX: number): void {
    if (Math.abs(offsetX) < 30) {
      return
    }
    const currentIndex = COLLECT_STATUS_TYPES.indexOf(this.selectedCollectType)
    if (currentIndex < 0) {
      this.selectCollectType(CollectType.watching)
      return
    }
    const nextIndex = offsetX < 0 ? currentIndex + 1 : currentIndex - 1
    if (nextIndex >= 0 && nextIndex < COLLECT_STATUS_TYPES.length) {
      this.selectCollectType(COLLECT_STATUS_TYPES[nextIndex])
    }
  }

  private getCollectStatusTabWidth(): number {
    const availableWidth = this.screenWidthVp - 24
    const gapTotal = COLLECT_STATUS_TAB_ITEM_GAP * (COLLECT_STATUS_TYPES.length - 1)
    const fittedWidth = (availableWidth - gapTotal) / COLLECT_STATUS_TYPES.length
    return Math.max(COLLECT_STATUS_TAB_ITEM_MIN_WIDTH, Math.min(COLLECT_STATUS_TAB_ITEM_MAX_WIDTH, fittedWidth))
  }

  private getGridColumnCount(): number {
    if (this.screenWidthVp >= 840) return 5
    if (this.screenWidthVp >= 600) return 4
    return 3
  }

  private getCollectRows(): CollectedBangumi[][] {
    const rows: CollectedBangumi[][] = []
    const count = this.getGridColumnCount()
    for (let i = 0; i < this.visibleCollectedList.length; i += count) {
      rows.push(this.visibleCollectedList.slice(i, i + count))
    }
    return rows
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

  private async loadCollectibles(): Promise<void> {
    try {
      this.collectedList = await this.collectController.loadCollectibles()
      logger.info('Load collectibles: total=%{public}d', this.collectedList.length)
      this.refreshVisibleCollectedList()
    } catch (err) {
      logger.error('Load collectibles failed: %{public}s', JSON.stringify(err))
    } finally {
      this.isLoading = false
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Top)
      }, 50)
    }
  }

  private async syncCollectIfAutoEnabled(): Promise<void> {
    if (this.isAutoSyncing || this.currentTab !== 2) {
      return
    }
    this.isAutoSyncing = true
    try {
      const config = await this.historySyncService.getConfig()
      if (!config.enabled || !config.autoSync) {
        return
      }
      await this.historySyncService.syncNow()
      await this.loadCollectibles()
    } catch (err) {
      logger.warn('Auto sync collections failed: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isAutoSyncing = false
    }
  }

  private async confirmDelete(): Promise<void> {
    this.showDeleteDialog = false
    try {
      await this.collectController.deleteCollectByAnimeId(this.deleteTargetAnimeId)
      await this.loadCollectibles()
      this.exitEditMode()
      this.clearDeleteTarget()
    } catch (err) {
      logger.error('Delete favorite failed: %{public}s', JSON.stringify(err))
    }
  }

  @Builder
  private CollectStatusSheetContent(): void {
    CollectStatusMenu({
      currentType: this.statusTargetType,
      onSelect: (collectType: number) => {
        this.handleCollectStatusSelected(collectType)
      },
      onDismiss: () => {
        this.showCollectStatusSheet = false
      }
    })
      .padding({ bottom: this.bottomSafeHeight })
  }

  private requestStatusEdit(item: CollectedBangumi): void {
    this.statusTargetAnimeId = item.animeId
    this.statusTargetName = item.animeName
    this.statusTargetType = CollectType.normalize(item.collectType)
    this.showCollectStatusSheet = true
  }

  private async handleCollectStatusSelected(collectType: number): Promise<void> {
    const normalizedType = CollectType.normalize(collectType)
    this.showCollectStatusSheet = false
    if (normalizedType === this.statusTargetType || this.statusTargetAnimeId.length === 0) {
      return
    }
    if (normalizedType === CollectType.none) {
      this.deleteTargetAnimeId = this.statusTargetAnimeId
      this.deleteTargetName = this.statusTargetName
      this.showDeleteDialog = true
      return
    }
    try {
      await this.collectController.updateCollectType(this.statusTargetAnimeId, normalizedType)
      this.statusTargetType = normalizedType
      await this.loadCollectibles()
    } catch (err) {
      logger.error('Update favorite status failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private exitEditMode(): void {
    this.isEditMode = false
  }

  private clearDeleteTarget(): void {
    this.deleteTargetAnimeId = ''
    this.deleteTargetName = ''
  }

  private resetEditState(): void {
    this.exitEditMode()
    this.showEditTipDialog = false
    this.showDeleteDialog = false
    this.showCollectStatusSheet = false
    this.statusTargetAnimeId = ''
    this.statusTargetName = ''
    this.statusTargetType = CollectType.none
    this.clearDeleteTarget()
  }

  private buildEditIcon(): HdsNavigationIconOptions {
    return {
      icon: this.isEditMode ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.paintbrush'),
      label: 'edit',
      action: () => {
        this.isEditMode = !this.isEditMode
        if (this.isEditMode) {
          PersistentStorage.persistProp('edit_tip_shown', false)
          const shown = AppStorage.get<boolean>('edit_tip_shown') ?? false
          if (!shown) {
            this.showEditTipDialog = true
          }
        }
      }
    }
  }

  private buildMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: this.buildEditIcon()
      }]
    }
  }

  private buildTitle(): HdsNavigationTitle {
    return {
      mainTitle: '收藏',
      subTitle: this.isEditMode ? '编辑模式' : CollectType.getLabel(this.selectedCollectType)
    }
  }

  private buildTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildTitle(),
      menu: this.buildMenu()
    }
  }

  private buildTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
    if (style.originalStyle?.backgroundStyle) {
      style.originalStyle.backgroundStyle.maskExtraHeight = 0
    }
    if (style.scrollEffectStyle?.backgroundStyle) {
      style.scrollEffectStyle.backgroundStyle.maskExtraHeight = 0
    }
    return {
      style: style,
      content: this.buildTitleBarContent(),
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
  }
}

@Component
struct CollectStatusTabItem {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @Prop label: string = ''
  @Prop collectType: number = CollectType.watching
  @Prop selectedType: number = CollectType.watching
  @Prop tabWidth: number = COLLECT_STATUS_TAB_ITEM_MIN_WIDTH
  onSelected?: (collectType: number) => void

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
      .height(COLLECT_STATUS_TAB_BAR_HEIGHT)
      .enabled(false)
      .barWidth(this.tabWidth)
      .barHeight(COLLECT_STATUS_TAB_BAR_HEIGHT)
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
    .borderRadius(COLLECT_STATUS_TAB_BAR_HEIGHT / 2)
    .width(this.tabWidth)
    .height(COLLECT_STATUS_TAB_BAR_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
    .onClick(() => {
      this.onSelected?.(this.collectType)
    })
  }

  @Builder
  private tabBarContentBuilder(): void {
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
    .backgroundColor(Color.Transparent)
    .shadow(undefined)
    .hitTestBehavior(HitTestMode.Transparent)
    .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
  }

  private isSelected(): boolean {
    return this.selectedType === this.collectType
  }
}
