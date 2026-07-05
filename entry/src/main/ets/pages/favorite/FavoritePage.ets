import { CollectController } from '../../controller/CollectController'
import { CollectedBangumi } from '../../models/CollectedBangumi'
import { CollectCard } from '../../components/collect/CollectCard'
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
  HdsNavigationMenuContentOptions
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle
} from '../../utils/HdsPageStyle'
import {
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  getBottomTabHideDistance,
  requestBottomTabAnimation,
  resolveBottomTabOffsetByDelta,
  resolveBottomTabSnapTarget
} from '../../utils/BottomTabAutoHide'

const logger = new Logger('FavoritePage')

@Component
export struct FavoritePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('currentTab') @Watch('onCurrentTabChanged') currentTab: number = 0
  @StorageLink('collectVersion') @Watch('onCollectVersionChanged') collectVersion: number = 0
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @State collectedList: CollectedBangumi[] = []
  @State visibleCollectedList: CollectedBangumi[] = []
  @State isEditMode: boolean = false
  @State isLoading: boolean = true
  @State showDeleteDialog: boolean = false
  @State deleteTargetAnimeId: string = ''
  @State deleteTargetName: string = ''
  @State showEditTipDialog: boolean = false
  private collectController: CollectController = new CollectController()
  private scroller: Scroller = new Scroller()

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
        Scroll(this.scroller) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
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
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildTitleBarOptions())
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

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
  CollectGrid(): void {
    if (this.visibleCollectedList.length === 0) {
      Column() {
        EmptyState({ message: '你的收藏还是空的' })
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
              onRemove: () => {
                this.requestDelete(item)
              }
            })
          }
        }, (item: CollectedBangumi) => `collect_${item.animeId}`)
      }
      .columnsTemplate(this.getGridColumnsTemplate())
      .columnsGap(8)
      .rowsGap(8)
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 6, bottom: 8 })
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

        Text('点击卡片可以取消收藏')
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
    this.visibleCollectedList = [...this.collectedList]
      .sort((a: CollectedBangumi, b: CollectedBangumi) => b.createdAt - a.createdAt)
    logger.info('Visible collectibles refreshed: count=%{public}d', this.visibleCollectedList.length)
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

  private requestDelete(item: CollectedBangumi): void {
    this.deleteTargetAnimeId = item.animeId
    this.deleteTargetName = item.animeName
    this.showDeleteDialog = true
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
