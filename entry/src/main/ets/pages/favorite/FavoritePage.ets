import { CollectController } from '../../controller/CollectController'
import { CollectedBangumi } from '../../models/CollectedBangumi'
import { CollectType } from '../../models/CollectType'
import { CollectCard } from '../../components/collect/CollectCard'
import { CollectStatusMenu } from '../../components/collect/CollectStatusMenu'
import { EmptyState } from '../../components/common/EmptyState'
import { Logger } from '../../utils/Logger'
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
import { LengthMetrics } from '@kit.ArkUI'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle
} from '../../utils/HdsPageStyle'

const logger = new Logger('FavoritePage')
const COLLECT_TAB_LABELS: string[] = ['在看', '想看', '搁置', '看过', '抛弃']
const COLLECT_TAB_BAR_HEIGHT: number = 40
const COLLECT_TAB_BAR_SECTION_GAP: number = 6
const COLLECT_TAB_BAR_HORIZONTAL_PADDING: number = 8
const COLLECT_TAB_ITEM_GAP: number = 8
const COLLECT_TAB_ITEM_MAX_WIDTH: number = 84
const COLLECT_TAB_ITEM_MIN_WIDTH: number = 52

@Component
export struct FavoritePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('currentTab') @Watch('onCurrentTabChanged') currentTab: number = 0
  @StorageLink('collectVersion') @Watch('onCollectVersionChanged') collectVersion: number = 0
  @State collectedList: CollectedBangumi[] = []
  @State visibleCollectedList: CollectedBangumi[] = []
  @State isEditMode: boolean = false
  @State isLoading: boolean = true
  @State currentTabIndex: number = 0
  @State showDeleteDialog: boolean = false
  @State deleteTargetAnimeId: string = ''
  @State deleteTargetName: string = ''
  @State showStatusMenu: boolean = false
  @State statusMenuTarget: CollectedBangumi | null = null
  @State showEditTipDialog: boolean = false
  private collectController: CollectController = new CollectController()

  aboutToAppear(): void {
    this.loadCollectibles()
  }

  private onCollectVersionChanged(): void {
    this.loadCollectibles()
  }

  private onCurrentTabChanged(): void {
    if (this.currentTab === 2) {
      this.loadCollectibles()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll() {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight) + COLLECT_TAB_BAR_HEIGHT)
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
                EmptyState({ message: '你的片库还是空的' })
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
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .bindSheet($$this.showStatusMenu, this.StatusMenuSheetContent, {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        radius: LengthMetrics.vp(24),
        backgroundColor: $r('app.color.page_background'),
        onDisappear: () => {
          this.showStatusMenu = false
        }
      })

      if (!this.isLoading && this.collectedList.length > 0) {
        this.CollectTabBar()
      }

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
  }

  @Builder
  StatusMenuSheetContent() {
    if (this.statusMenuTarget !== null) {
      CollectStatusMenu({
        currentType: this.statusMenuTarget!.collectType,
        isVisible: $showStatusMenu,
        onSelect: (type: number) => {
          this.onStatusMenuSelect(type)
        }
      })
    }
  }

  @Builder
  CollectTabBar(): void {
    Column() {
      Scroll() {
        Row({ space: COLLECT_TAB_ITEM_GAP }) {
          ForEach(COLLECT_TAB_LABELS, (label: string, index?: number) => {
            CollectTabItem({
              label: label,
              index: index ?? 0,
              tabWidth: this.getCollectTabWidth(),
              selectedIndex: this.currentTabIndex,
              onSelected: (selectedIndex: number) => {
                logger.info('Collect tab selected: %{public}d', selectedIndex)
                this.currentTabIndex = selectedIndex
                this.refreshVisibleCollectedList()
              }
            })
          }, (label: string, index?: number) => `collect_tab_${index}`)
        }
        .height(COLLECT_TAB_BAR_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({
          left: COLLECT_TAB_BAR_HORIZONTAL_PADDING,
          right: COLLECT_TAB_BAR_HORIZONTAL_PADDING
        })
      }
      .width('100%')
      .height(COLLECT_TAB_BAR_HEIGHT)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .clip(false)
    }
    .width('100%')
    .height(COLLECT_TAB_BAR_HEIGHT)
    .margin({ top: getTopSpacerHeight(this.topSafeHeight) })
    .zIndex(30)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  CollectGrid(): void {
    if (this.visibleCollectedList.length === 0) {
      Column() {
        EmptyState({ message: `${COLLECT_TAB_LABELS[this.currentTabIndex]}列表为空` })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Grid() {
        ForEach(this.visibleCollectedList, (item: CollectedBangumi) => {
          GridItem() {
            CollectCard({
              collectedBangumi: item,
              isEditMode: this.isEditMode,
              onStatusChange: (type: number) => {
                this.onCardStatusChange(item, type)
              }
            })
          }
        }, (item: CollectedBangumi) => `collect_${item.animeId}_${item.collectType}`)
      }
      .columnsTemplate(this.getGridColumnsTemplate())
      .columnsGap(8)
      .rowsGap(8)
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: COLLECT_TAB_BAR_SECTION_GAP, bottom: 8 })
    }
  }

  @Builder
  DeleteConfirmDialog(): void {
    Column() {
      Column() {
        Text('取消收藏')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 12 })

        Text(`确定要取消收藏「${this.deleteTargetName}」吗？`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 20 })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface_button_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .onClick(() => {
              this.showDeleteDialog = false
            })

          Button('删除')
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.status_error'))
            .fontColor($r('app.color.text_on_primary'))
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmDelete()
            })
        }
        .width('100%')
      }
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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

        Text('点击卡片可以修改收藏状态或取消收藏')
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

  private getCollectedByType(collectType: number): CollectedBangumi[] {
    return this.collectedList
      .filter((item: CollectedBangumi) => item.collectType === collectType)
      .sort((a: CollectedBangumi, b: CollectedBangumi) => b.createdAt - a.createdAt)
  }

  private refreshVisibleCollectedList(): void {
    const collectType = this.currentTabIndex + 1
    this.visibleCollectedList = this.getCollectedByType(collectType)
    logger.info('Visible collectibles refreshed: tab=%{public}d type=%{public}d count=%{public}d',
      this.currentTabIndex, collectType, this.visibleCollectedList.length)
  }

  private getGridColumnCount(): number {
    if (this.screenWidthVp >= 840) return 5
    if (this.screenWidthVp >= 600) return 4
    return 3
  }

  private getGridColumnsTemplate(): string {
    const count = this.getGridColumnCount()
    const fraction = '1fr '
    return fraction.repeat(count).trim()
  }

  private getCollectTabWidth(): number {
    const availableWidth = this.screenWidthVp
      - COLLECT_TAB_BAR_HORIZONTAL_PADDING * 2
      - COLLECT_TAB_ITEM_GAP * (COLLECT_TAB_LABELS.length - 1)
    const fittedWidth = availableWidth / COLLECT_TAB_LABELS.length
    return Math.max(COLLECT_TAB_ITEM_MIN_WIDTH, Math.min(COLLECT_TAB_ITEM_MAX_WIDTH, fittedWidth))
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
    }
  }

  private async confirmDelete(): Promise<void> {
    this.showDeleteDialog = false
    try {
      await this.collectController.deleteCollectByAnimeId(this.deleteTargetAnimeId)
      await this.loadCollectibles()
    } catch (err) {
      logger.error('Delete favorite failed: %{public}s', JSON.stringify(err))
    }
  }

  private onCardStatusChange(item: CollectedBangumi, currentType: number): void {
    this.statusMenuTarget = item
    this.showStatusMenu = true
  }

  private async onStatusMenuSelect(type: number): Promise<void> {
    if (this.statusMenuTarget === null) return

    if (type === CollectType.none) {
      this.deleteTargetAnimeId = this.statusMenuTarget!.animeId
      this.deleteTargetName = this.statusMenuTarget!.animeName
      this.showStatusMenu = false
      this.showDeleteDialog = true
      return
    }

    try {
      await this.collectController.updateCollectType(this.statusMenuTarget!.animeId, type)
      this.showStatusMenu = false
      await this.loadCollectibles()
    } catch (err) {
      logger.error('Update collect type failed: %{public}s', JSON.stringify(err))
    }
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
      mainTitle: '片库',
      subTitle: this.isEditMode ? '编辑模式' : ''
    }
  }

  private buildTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildTitle(),
      menu: this.buildMenu()
    }
  }

  private buildTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle()
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
struct CollectTabItem {
  @Prop label: string = ''
  @Prop index: number = 0
  @Prop tabWidth: number = COLLECT_TAB_ITEM_MAX_WIDTH
  @Prop selectedIndex: number = 0
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
      .height(COLLECT_TAB_BAR_HEIGHT)
      .barWidth(this.tabWidth)
      .barHeight(COLLECT_TAB_BAR_HEIGHT)
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
    .height(COLLECT_TAB_BAR_HEIGHT)
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
