import { router, curves } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
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
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LOCAL_VIDEO_HISTORY_VERSION_KEY } from '../../store/LocalVideoHistoryChangeSignal'
import { UserDownloadFolder, UserFolderEntry } from '../../services/UserDownloadFolder'
import { Logger } from '../../utils/Logger'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
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

const logger = new Logger('LocalPage')
const LOCAL_TAB_LABELS: string[] = ['下载视频', '历史记录']
const LOCAL_TAB_BAR_HEIGHT: number = 40
const LOCAL_TAB_ITEM_WIDTH: number = 136

@Component
export struct LocalPage {
  @Prop @Watch('onActiveChanged') isActive: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onLocalHistoryVersionChanged') localHistoryVersion: number = 0
  @StorageLink('appRdbReady') @Watch('onRdbReadyChanged') appRdbReady: boolean = false
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @State localHistory: LocalVideoRecord[] = []
  @State ownFolderVideos: LocalVideoRecord[] = []
  @State rootFolderEntries: UserFolderEntry[] = []
  @State rootFolderRenderVersion: number = 0
  @State ownFolderScanned: boolean = false
  @State ownFolderScanFailed: boolean = false
  @State ownFolderScanning: boolean = false
  @State ownFolderCoverRenderVersion: number = 0
  @State selectedLocalTabIndex: number = 0
  @State showDeleteSheet: boolean = false
  @State isBatchDeleteSheet: boolean = false
  @State pendingDeleteId: number = -1
  @State pendingDeleteFileName: string = ''
  @State isEditMode: boolean = false
  @State selectedIds: number[] = []
  @State historyActionMenuId: number = -1
  private scroller: Scroller = new Scroller()
  private localVideoHistoryStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private hasScannedOwnDownloadFolder: boolean = false
  private isGeneratingCovers: boolean = false
  private isGeneratingOwnFolderCovers: boolean = false
  private pendingOwnFolderCoverGeneration: boolean = false
  private pendingOwnFolderRescan: boolean = false
  private isCleaningMissingHistory: boolean = false

  aboutToAppear(): void {
    if (this.appRdbReady) {
      this.loadLocalHistory()
    } else {
      logger.info('本地播放记录等待RDB初始化')
    }
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded()
    }
  }

  onBackPress(): boolean {
    if (this.historyActionMenuId >= 0) {
      this.historyActionMenuId = -1
      return true
    }
    if (this.showDeleteSheet) {
      this.closeDeleteDialog()
      return true
    }
    if (this.isEditMode) {
      this.exitEditMode()
      return true
    }
    return false
  }

  onPageShow(): void {
    if (this.appRdbReady) {
      this.loadLocalHistory()
    } else {
      logger.info('本地播放记录等待RDB初始化')
    }
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded(true)
    }
  }

  onRdbReadyChanged(): void {
    logger.info('Local page RDB ready changed: %{public}s', String(this.appRdbReady))
    if (!this.appRdbReady) {
      return
    }
    this.refreshLocalHistoryBindings()
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded(true)
    }
  }

  onLocalHistoryVersionChanged(): void {
    if (this.appRdbReady) {
      this.refreshLocalHistoryBindings()
    }
  }

  onActiveChanged(): void {
    logger.info('Local page active changed: %{public}s', String(this.isActive))
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded(true)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight) + LOCAL_TAB_BAR_HEIGHT)
              .width('100%')

            if (this.selectedLocalTabIndex === 0) {
              this.OwnFolderSection()
            } else {
              this.RecentSection()
              if (this.localHistory.length > 0) {

              }
            }

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ left: 12, right: 12 })
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
              if (Math.abs(event.offsetX) < 30) {
                return
              }
              if (event.offsetX < 0 && this.selectedLocalTabIndex < LOCAL_TAB_LABELS.length - 1) {
                this.getUIContext().animateTo({
                  duration: 220,
                  curve: curves.springMotion()
                }, () => {
                  this.selectedLocalTabIndex += 1
                })
                this.scroller.scrollToIndex(0)
              } else if (event.offsetX > 0 && this.selectedLocalTabIndex > 0) {
                this.getUIContext().animateTo({
                  duration: 220,
                  curve: curves.springMotion()
                }, () => {
                  this.selectedLocalTabIndex -= 1
                })
                this.scroller.scrollToIndex(0)
              }
            })
        )
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildLocalTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      this.LocalTabBar()

      if (this.showDeleteSheet) {
        this.DeleteConfirmDialog()
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
  private LocalTabBar(): void {
    Column() {
      Row({ space: 8 }) {
        ForEach(LOCAL_TAB_LABELS, (label: string, index?: number) => {
          Column() {
            LocalSegmentTabItem({
              label: label,
              index: index ?? 0,
              selectedIndex: this.selectedLocalTabIndex,
              tabWidth: LOCAL_TAB_ITEM_WIDTH,
              onSelected: (selectedIndex: number) => {
                this.getUIContext().animateTo({
                  duration: 220,
      curve: curves.springMotion()
                }, () => {
                  this.selectedLocalTabIndex = selectedIndex
                })
                this.scroller.scrollToIndex(0)
                if (this.isEditMode) {
                  this.exitEditMode()
                }
              }
            })
          }
          .width(LOCAL_TAB_ITEM_WIDTH)
        }, (label: string, index?: number) => `local_tab_${index}_${label}`)
      }
      .width('100%')
      .height(LOCAL_TAB_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 12, right: 12 })
      }
    .width('100%')
    .height(LOCAL_TAB_BAR_HEIGHT)
    .margin({ top: getTopSpacerHeight(this.topSafeHeight) })
    .zIndex(30)
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

  @Builder
  private LocalHeroSection(): void {
    Column() {
      if (this.localHistory.length > 0) {
        Row() {
          Column() {
            Text('继续播放')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(this.localHistory[0].fileName)
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
            Text(this.buildProgressText(this.localHistory[0]) + ' · ' + this.buildProgressPercentText(this.localHistory[0]))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Stack() {
            if (this.localHistory[0].coverUri.length > 0) {
              Image(this.localHistory[0].coverUri)
                .draggable(false)
                .width(96)
                .height(60)
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
              Rect()
                .width(96)
                .height(60)
                .radius(10)
                .fill('#33000000')
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(24)
                .fontColor([$r('app.color.text_on_primary')])
            } else {
              Circle()
                .width(54)
                .height(54)
                .fill($r('app.color.accent_blue'))
                .opacity(0.18)
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(26)
                .fontColor([$r('app.color.accent_blue')])
            }
          }
          .width(96)
          .height(60)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.localHistory[0].durationMs > 0) {
          Progress({
            value: Math.min(this.localHistory[0].positionMs, this.localHistory[0].durationMs),
            total: this.localHistory[0].durationMs,
            type: ProgressType.Linear
          })
            .height(4)
            .color($r('app.color.accent_blue'))
            .backgroundColor($r('app.color.button_ghost_bg'))
            .margin({ top: 16 })
        }

        if (this.localHistory[0].danmakuFileName.length > 0) {
          Row() {
            this.TagPill(this.buildDanmakuText(this.localHistory[0]), true)
          }
          .width('100%')
          .margin({ top: 12 })
        }

        Button('继续播放')
          .width('100%')
          .height(40)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(12)
          .margin({ top: 16 })
          .onClick(() => {
            this.openHistoryRecord(this.localHistory[0])
          })
      } else {
        Stack() {
          Circle()
            .width(64)
            .height(64)
            .fill($r('app.color.accent_blue'))
            .opacity(0.14)
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(36)
            .fontColor([$r('app.color.accent_blue')])
        }
        .width(72)
        .height(72)
        .margin({ bottom: 12 })

        Text('下载视频')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('在线播放页面下载的视频会自动归档到这里')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(20)
          .margin({ top: 8, bottom: 16 })

      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 22, bottom: 22 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.localHistory.length > 0) {
        this.openHistoryRecord(this.localHistory[0])
      }
    })
  }

  @Builder
  private OwnFolderSection(): void {
    Column() {
      if (this.rootFolderEntries.length > 0) {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.rootFolderEntries, (entry: UserFolderEntry) => {
              this.OwnFolderDirectoryCard(entry)
            }, (entry: UserFolderEntry) => 'own_anime_folder_' + entry.relativePath + '_' + entry.coverUri + '_' +
              this.rootFolderRenderVersion)
          }
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Top)
          .constraintSize({ minWidth: '100%' })
          .padding({ right: 24 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
        .width('100%')
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.folder_badge_plus'))
            .fontSize(92)
            .fontColor([$r('app.color.accent_blue')])
            .margin({ bottom: 22 })

          Text(this.buildOwnFolderEmptyTitle())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          Text(this.buildOwnFolderEmptySubtitle())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .lineHeight(24)
            .margin({ top: 18 })
          Text(this.buildOwnFolderDanmakuHint())
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .textAlign(TextAlign.Center)
            .lineHeight(21)
            .margin({ top: 14 })
        }
        .width('100%')
        .height(420)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 28, right: 28 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private OwnFolderDirectoryCard(entry: UserFolderEntry): void {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(entry.coverUri.length > 0 ? entry.coverUri : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width(132)
          .height(176)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .opacity(entry.coverUri.length > 0 ? 1 : 0.82)
        if (entry.coverUri.length === 0) {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(34)
            .fontColor([$r('app.color.accent_blue')])
            .margin({ right: 12, bottom: 12 })
        } else {
          Rect()
            .width(36)
            .height(36)
            .radius(18)
            .fill('#88000000')
            .margin({ right: 10, bottom: 10 })
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(20)
            .fontColor([$r('app.color.text_on_primary')])
            .margin({ right: 18, bottom: 18 })
        }
      }
      .width(132)
      .height(176)
      .clip(true)
      .backgroundColor($r('app.color.button_ghost_bg'))
      .borderRadius(12)

      Text(entry.name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(132)
      Text(this.buildFolderEntryStatus(entry))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(132)
    }
    .width(132)
    .onClick(() => this.openOwnFolderDirectory(entry))
  }

  @Builder
  private OwnFolderVideoCard(record: LocalVideoRecord): void {
    Row({ space: 12 }) {
      Stack() {
        Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width(124)
          .height(78)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .opacity(record.coverUri.length > 0 ? 1 : 0.82)
        Rect()
          .width(124)
          .height(78)
          .radius(12)
          .fill('#33000000')
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(25)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(124)
      .height(78)

      Column() {
        Text(record.fileName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Blank()
          .layoutWeight(1)
        Row() {
          Text(this.formatFileSize(record.fileSize))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          this.TagPill(this.buildDanmakuStatusText(record), record.danmakuFileName.length > 0)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(78)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
        .margin({ top: 31 })
    }
    .width('100%')
    .height(104)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.openOwnFolderVideo(record)
    })
  }

  @Builder
  private RecentSection(): void {
    Column() {
      if (this.localHistory.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(92)
            .fontColor([$r('app.color.accent_blue')])
            .margin({ bottom: 22 })

          Text('还没有下载视频播放记录')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          Text('播放过的下载视频会显示在这里')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .lineHeight(24)
            .margin({ top: 18 })
          Text('下载视频的播放进度、封面和弹幕绑定\n会在播放后自动保存')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .textAlign(TextAlign.Center)
            .lineHeight(21)
            .margin({ top: 14 })
        }
        .width('100%')
        .height(420)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 28, right: 28 })
      } else {
        Column({ space: 0 }) {
          ForEach(this.localHistory, (record: LocalVideoRecord) => {
            this.HistoryCard(record)
          }, (record: LocalVideoRecord) => 'local_history_' + record.id + '_' + record.fileKey)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private HistoryCard(record: LocalVideoRecord): void {
    Column() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
            .draggable(false)
            .width(112)
            .height(63)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(record.coverUri.length > 0 ? 1 : 0.82)
          if (record.durationMs > 0) {
            Progress({
              value: Math.min(record.positionMs, record.durationMs),
              total: record.durationMs,
              type: ProgressType.Linear
            })
              .width(96)
              .height(3)
              .color($r('app.color.accent_blue'))
              .backgroundColor('#66000000')
              .margin({ left: 8, bottom: 7 })
          }
        }
        .width(112)
        .height(63)

        Column() {
          Text(record.fileName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.buildProgressText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
          Text(this.formatLastPlayedAt(record.lastPlayedAt))
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .height(72)
        .alignItems(HorizontalAlign.Start)

        if (this.isEditMode) {
          SymbolGlyph(this.selectedIds.indexOf(record.id) >= 0 ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(22)
            .fontColor([this.selectedIds.indexOf(record.id) >= 0 ? $r('app.color.accent_blue') : $r('sys.color.icon_secondary')])
            .width(28)
        }
      }
      .width('100%')
      .height(88)
      .alignItems(VerticalAlign.Center)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 1 })
            .onAction(() => {
              if (this.isEditMode) {
                this.toggleSelect(record.id)
              } else {
                this.openHistoryRecord(record)
              }
            }),
          LongPressGesture({ duration: 500 })
            .onAction(() => {
              if (!this.isEditMode) {
                this.historyActionMenuId = record.id
              }
            })
        )
      )
      .bindMenu(this.historyActionMenuId === record.id, this.HistoryActionMenuContent, {
        placement: Placement.Bottom,
        showInSubWindow: false,
        onDisappear: () => {
          if (this.historyActionMenuId === record.id) {
            this.historyActionMenuId = -1
          }
        }
      })

      Divider()
        .color($r('app.color.divider_color'))
        .margin({ left: 124 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TagPill(text: string, highlighted: boolean): void {
    Text(text)
      .fontSize(11)
      .fontColor(highlighted ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(8)
      .backgroundColor(highlighted ? $r('app.color.button_ghost_bg') : Color.Transparent)
  }

  @Builder
  private DeleteConfirmDialog(): void {
    Column() {
      Column() {
        Text('是否删除此视频？')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 24 })

        Text(this.isBatchDeleteSheet ?
          `确定要删除这 ${this.selectedIds.length} 条观看记录吗？` : '确定要删除这条观看记录吗？')
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
            .onClick(() => {
              this.closeDeleteDialog()
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
            .onClick(() => {
              if (this.isBatchDeleteSheet) {
                this.confirmBatchDelete()
              } else {
                const id = this.pendingDeleteId
                this.closeDeleteDialog()
                this.deleteHistoryRecord(id)
              }
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
      this.closeDeleteDialog()
    })
  }

  private closeDeleteDialog(): void {
    this.showDeleteSheet = false
    this.pendingDeleteId = -1
    this.pendingDeleteFileName = ''
  }

  private async openOwnFolderVideo(record: LocalVideoRecord): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        const authorized = await LocalFilePicker.authorizeExistingUri(context, record.fileUri)
        if (!authorized) {
          logger.warn('本地目录视频授权失败: %{public}s', record.fileName)
          return
        }
      } catch (err) {
        logger.warn('本地目录视频授权异常: %{public}s', err instanceof Error ? err.message : String(err))
        return
      }
    }
    const latestRecord = await this.resolveLatestOwnFolderRecord(record)
    const playbackQueue = await this.buildPlaybackQueueForRecord(latestRecord)
    const queueIndex = this.findPlaybackQueueIndex(playbackQueue, latestRecord.fileUri)
    router.pushUrl({
      url: 'pages/player/LocalPlayerPage',
      params: {
        videoUri: latestRecord.fileUri,
        videoFileName: latestRecord.fileName,
        videoFileSize: latestRecord.fileSize,
        historyPositionMs: latestRecord.positionMs,
        danmakuUri: latestRecord.danmakuUri,
        danmakuFileName: latestRecord.danmakuFileName,
        danmakuOffsetMs: latestRecord.danmakuOffsetMs,
        danmakuFormat: latestRecord.danmakuFormat,
        danmakuCount: latestRecord.danmakuCount,
        drmScheme: latestRecord.drmScheme,
        drmPluginName: latestRecord.drmPluginName,
        drmOfflineKeyId: latestRecord.drmOfflineKeyId,
        playlistJson: JSON.stringify(playbackQueue),
        queueIndex: queueIndex
      }
    })
  }

  private async openHistoryRecord(record: LocalVideoRecord): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        const authorized = await LocalFilePicker.authorizeExistingUri(context, record.fileUri)
        if (!authorized) {
          logger.warn('历史视频授权失败: %{public}s', record.fileName)
          return
        }
      } catch (err) {
        logger.warn('历史视频授权异常: %{public}s', err instanceof Error ? err.message : String(err))
        return
      }
    }
    const playbackQueue = await this.buildPlaybackQueueForRecord(record)
    const queueIndex = this.findPlaybackQueueIndex(playbackQueue, record.fileUri)
    router.pushUrl({
      url: 'pages/player/LocalPlayerPage',
      params: {
        videoUri: record.fileUri,
        videoFileName: record.fileName,
        videoFileSize: record.fileSize,
        historyPositionMs: record.positionMs,
        danmakuUri: record.danmakuUri,
        danmakuFileName: record.danmakuFileName,
        danmakuOffsetMs: record.danmakuOffsetMs,
        danmakuFormat: record.danmakuFormat,
        danmakuCount: record.danmakuCount,
        drmScheme: record.drmScheme,
        drmPluginName: record.drmPluginName,
        drmOfflineKeyId: record.drmOfflineKeyId,
        playlistJson: JSON.stringify(playbackQueue),
        queueIndex: queueIndex
      }
    })
  }

  private async buildPlaybackQueueForRecord(record: LocalVideoRecord): Promise<LocalVideoRecord[]> {
    const fallback: LocalVideoRecord[] = [record]
    const context = getContext(this) as common.UIAbilityContext
    const scanned = await UserDownloadFolder.scanOwnVideoFiles(context)
    if (scanned === null || scanned.length === 0) {
      return fallback
    }
    const historyRecords = await this.loadLocalHistoryForMerge()
    const mergedRecords = this.mergeOwnFolderHistoryBindings(scanned, historyRecords)
    const parentPath = this.getParentPath(record.fileUri)
    if (parentPath.length === 0) {
      return fallback
    }
    const queue: LocalVideoRecord[] = []
    for (let i = 0; i < mergedRecords.length; i++) {
      const candidate = mergedRecords[i]
      if (this.getParentPath(candidate.fileUri) === parentPath) {
        queue.push(candidate)
      }
    }
    if (queue.length === 0) {
      return fallback
    }
    queue.sort((first: LocalVideoRecord, second: LocalVideoRecord): number => {
      return UserDownloadFolder.compareVideoNames(first.fileName, second.fileName)
    })
    return queue
  }

  private findPlaybackQueueIndex(queue: LocalVideoRecord[], fileUri: string): number {
    for (let i = 0; i < queue.length; i++) {
      if (queue[i].fileUri === fileUri) {
        return i
      }
    }
    return 0
  }

  private getParentPath(path: string): string {
    const normalized = path.replace(/\\/g, '/')
    const slashIndex = normalized.lastIndexOf('/')
    return slashIndex > 0 ? normalized.substring(0, slashIndex) : ''
  }

  private async loadLocalHistory(): Promise<void> {
    if (!this.appRdbReady) {
      logger.info('跳过加载本地播放记录，RDB尚未初始化')
      return
    }
    try {
      const records = await this.localVideoHistoryStore.getAll()
      this.localHistory = await this.removeMissingHistoryRecords(records)
      this.ensureMissingCovers()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('加载本地播放记录失败: %{public}s', msg)
      if (msg.indexOf('RdbStore not initialized') < 0) {
        this.localHistory = []
      }
    }
  }

  private async refreshLocalHistoryBindings(): Promise<void> {
    await this.loadLocalHistory()
    if (this.ownFolderVideos.length > 0) {
      this.ownFolderVideos = this.mergeOwnFolderHistoryBindings(this.ownFolderVideos, this.localHistory)
      this.ensureOwnFolderCovers()
    }
  }

  private async ensureMissingCovers(): Promise<void> {
    if (this.isGeneratingCovers || this.localHistory.length === 0) {
      return
    }
    this.isGeneratingCovers = true
    try {
      const maxGenerateCount = this.localHistory.length
      for (let i = 0; i < maxGenerateCount; i++) {
        const record = this.localHistory[i]
        if (record.coverUri.length > 0 || record.fileUri.length === 0 || record.fileKey.length === 0) {
          continue
        }
        if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
          logger.warn('跳过本地视频封面生成，文件暂不可读: %{public}s', record.fileName)
          continue
        }
        logger.info('开始生成本地视频封面: %{public}s', record.fileName)
        const coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(record.fileUri, record.fileName, record.fileSize)
        if (coverUri.length > 0) {
          await this.localVideoHistoryStore.updateCoverUri(record.fileKey, coverUri)
          this.localHistory[i].coverUri = coverUri
          this.localHistory = this.localHistory.slice()
          logger.info('本地视频封面已更新: %{public}s', record.fileName)
        }
      }
    } catch (err) {
      logger.warn('生成本地视频封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingCovers = false
    }
  }

  private async scanOwnDownloadFolderIfNeeded(force: boolean = false): Promise<void> {
    if (this.hasScannedOwnDownloadFolder && !force) {
      return
    }
    if (this.ownFolderScanning) {
      this.pendingOwnFolderRescan = this.pendingOwnFolderRescan || force
      return
    }
    this.ownFolderScanning = true
    this.ownFolderScanFailed = false
    try {
      logger.info('开始读取用户Download包名目录')
      const context = getContext(this) as common.UIAbilityContext
      const records = await UserDownloadFolder.scanOwnVideoFiles(context)
      if (records === null) {
        this.ownFolderScanFailed = true
        this.ownFolderScanned = true
        logger.warn('读取用户Download包名目录失败，目录暂不可访问')
        return
      }
      this.hasScannedOwnDownloadFolder = true
      const historyRecords = await this.loadLocalHistoryForMerge()
      this.ownFolderVideos = this.mergeOwnFolderHistoryBindings(records, historyRecords)
      const rootEntries = await UserDownloadFolder.listOwnDirectory(context)
      this.rootFolderEntries = rootEntries === null ? [] : rootEntries.filter((entry: UserFolderEntry): boolean => {
        return entry.isDirectory
      })
      this.rootFolderRenderVersion++
      this.ownFolderScanned = true
      this.ownFolderScanFailed = false
      logger.info('读取用户Download包名目录完成: %{public}d', records.length)
      this.ensureOwnFolderCovers()
    } catch (err) {
      this.ownFolderScanFailed = true
      this.ownFolderScanned = true
      logger.warn('读取用户Download包名目录失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.ownFolderScanning = false
      if (this.pendingOwnFolderRescan) {
        this.pendingOwnFolderRescan = false
        this.scanOwnDownloadFolderIfNeeded(true)
      }
    }
  }

  private rescanOwnDownloadFolder(): void {
    this.hasScannedOwnDownloadFolder = false
    this.scanOwnDownloadFolderIfNeeded()
  }

  private async ensureOwnFolderCovers(): Promise<void> {
    if (this.isGeneratingOwnFolderCovers || this.ownFolderVideos.length === 0) {
      if (this.isGeneratingOwnFolderCovers) {
        this.pendingOwnFolderCoverGeneration = true
      }
      return
    }
    this.isGeneratingOwnFolderCovers = true
    this.pendingOwnFolderCoverGeneration = false
    try {
      const maxGenerateCount = this.ownFolderVideos.length
      for (let i = 0; i < maxGenerateCount; i++) {
        if (i >= this.ownFolderVideos.length) {
          break
        }
        const record = this.ownFolderVideos[i]
        if (record.coverUri.length > 0 || record.fileUri.length === 0) {
          continue
        }
        if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
          logger.warn('跳过本地目录视频封面生成，文件暂不可读: %{public}s', record.fileName)
          continue
        }
        logger.info('开始生成本地目录视频封面: %{public}s', record.fileName)
        const coverUri = await LocalVideoThumbnailStore.getInstance()
          .ensureThumbnail(record.fileUri, record.fileName, record.fileSize)
        if (coverUri.length === 0) {
          continue
        }
        const currentIndex = this.findOwnFolderVideoIndex(record.fileUri, record.fileSize)
        if (currentIndex < 0) {
          continue
        }
        this.ownFolderVideos[currentIndex].coverUri = coverUri
        this.ownFolderVideos = this.ownFolderVideos.slice()
        this.ownFolderCoverRenderVersion++
        const fileKey = this.buildLocalFileKey(record)
        if (this.appRdbReady && fileKey.length > 0) {
          await this.localVideoHistoryStore.updateCoverUri(fileKey, coverUri)
        }
        logger.info('本地目录视频封面已更新: %{public}s', record.fileName)
      }
    } catch (err) {
      logger.warn('生成本地目录视频封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingOwnFolderCovers = false
      if (this.pendingOwnFolderCoverGeneration) {
        this.ensureOwnFolderCovers()
      }
    }
  }

  private findOwnFolderVideoIndex(fileUri: string, fileSize: number): number {
    for (let i = 0; i < this.ownFolderVideos.length; i++) {
      const record = this.ownFolderVideos[i]
      if (record.fileUri === fileUri && record.fileSize === fileSize) {
        return i
      }
    }
    return -1
  }

  private async loadLocalHistoryForMerge(): Promise<LocalVideoRecord[]> {
    if (!this.appRdbReady) {
      logger.info('本地目录暂不合并历史，RDB尚未初始化')
      return []
    }
    try {
      const records = await this.localVideoHistoryStore.getAll()
      return await this.removeMissingHistoryRecords(records)
    } catch (err) {
      logger.warn('读取本地历史用于目录合并失败: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  private async removeMissingHistoryRecords(records: LocalVideoRecord[]): Promise<LocalVideoRecord[]> {
    if (records.length === 0 || this.isCleaningMissingHistory) {
      return records
    }
    this.isCleaningMissingHistory = true
    const availableRecords: LocalVideoRecord[] = []
    const missingIds: number[] = []
    const missingRecords: LocalVideoRecord[] = []
    try {
      for (let i = 0; i < records.length; i++) {
        const record = records[i]
        if (record.fileUri.length > 0 && await LocalFilePicker.ensureReadableUri(record.fileUri)) {
          availableRecords.push(record)
        } else {
          missingIds.push(record.id)
          missingRecords.push(record)
        }
      }

      if (missingIds.length > 0) {
        try {
          await this.localVideoHistoryStore.deleteByIds(missingIds)
          for (let i = 0; i < missingRecords.length; i++) {
            await LocalFilePicker.revokeUriPermission(missingRecords[i].fileUri)
            if (missingRecords[i].danmakuUri.length > 0) {
              await LocalFilePicker.revokeUriPermission(missingRecords[i].danmakuUri)
            }
            logger.info('视频文件已删除，自动清理历史记录: %{public}s', missingRecords[i].fileName)
          }
        } catch (err) {
          logger.warn('自动清理已删除视频历史记录失败: %{public}s',
            err instanceof Error ? err.message : String(err))
        }
      }
      return availableRecords
    } finally {
      this.isCleaningMissingHistory = false
    }
  }

  private mergeOwnFolderHistoryBindings(records: LocalVideoRecord[], historyRecords: LocalVideoRecord[]): LocalVideoRecord[] {
    const historyMap: Map<string, LocalVideoRecord> = new Map()
    for (let i = 0; i < historyRecords.length; i++) {
      historyMap.set(this.buildLocalFileKey(historyRecords[i]), historyRecords[i])
    }
    for (let j = 0; j < records.length; j++) {
      const historyRecord = historyMap.get(this.buildLocalFileKey(records[j]))
      if (historyRecord === undefined) {
        continue
      }
      records[j].fileKey = historyRecord.fileKey
      records[j].coverUri = historyRecord.coverUri
      records[j].durationMs = historyRecord.durationMs
      records[j].positionMs = historyRecord.positionMs
      if (historyRecord.danmakuFileName.length > 0 && historyRecord.danmakuUri.length > 0) {
        records[j].danmakuFileName = historyRecord.danmakuFileName
        records[j].danmakuUri = historyRecord.danmakuUri
        records[j].danmakuOffsetMs = historyRecord.danmakuOffsetMs
        records[j].danmakuFormat = historyRecord.danmakuFormat
        records[j].danmakuCount = historyRecord.danmakuCount
      }
    }
    return records
  }

  private async resolveLatestOwnFolderRecord(record: LocalVideoRecord): Promise<LocalVideoRecord> {
    const historyRecord = await this.localVideoHistoryStore.getByFileKey(this.buildLocalFileKey(record))
    if (historyRecord === null) {
      return record
    }
    const merged = new LocalVideoRecord()
    merged.fileKey = historyRecord.fileKey
    merged.fileUri = record.fileUri
    merged.fileName = record.fileName
    merged.fileSize = record.fileSize
    merged.coverUri = historyRecord.coverUri
    merged.durationMs = historyRecord.durationMs
    merged.positionMs = historyRecord.positionMs
    merged.lastPlayedAt = historyRecord.lastPlayedAt
    merged.drmScheme = historyRecord.drmScheme.length > 0 ? historyRecord.drmScheme : record.drmScheme
    merged.drmPluginName = historyRecord.drmPluginName.length > 0 ? historyRecord.drmPluginName : record.drmPluginName
    merged.drmOfflineKeyId = historyRecord.drmOfflineKeyId.length > 0 ?
      historyRecord.drmOfflineKeyId : record.drmOfflineKeyId
    if (historyRecord.danmakuFileName.length > 0 && historyRecord.danmakuUri.length > 0) {
      merged.danmakuFileName = historyRecord.danmakuFileName
      merged.danmakuUri = historyRecord.danmakuUri
      merged.danmakuOffsetMs = historyRecord.danmakuOffsetMs
      merged.danmakuFormat = historyRecord.danmakuFormat
      merged.danmakuCount = historyRecord.danmakuCount
    } else {
      merged.danmakuFileName = record.danmakuFileName
      merged.danmakuUri = record.danmakuUri
      merged.danmakuOffsetMs = record.danmakuOffsetMs
      merged.danmakuFormat = record.danmakuFormat
      merged.danmakuCount = record.danmakuCount
    }
    logger.info('打开本地目录视频使用最新历史: name=%{public}s position=%{public}d',
      merged.fileName, merged.positionMs)
    return merged
  }

  private buildLocalFileKey(record: LocalVideoRecord): string {
    if (record.fileKey.length > 0) {
      return record.fileKey
    }
    return record.fileUri + '|' + record.fileSize + '|' + record.fileName
  }

  private async deleteHistoryRecord(id: number): Promise<void> {
    if (id < 0) {
      return
    }
    try {
      const record = this.findHistoryRecordById(id)
      if (record !== null) {
        await LocalFilePicker.revokeUriPermission(record.fileUri)
        if (record.danmakuUri.length > 0) {
          await LocalFilePicker.revokeUriPermission(record.danmakuUri)
        }
      }
      await this.localVideoHistoryStore.deleteById(id)
      await this.loadLocalHistory()
    } catch (err) {
      logger.warn('删除本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private askDeleteRecord(record: LocalVideoRecord): void {
    this.pendingDeleteId = record.id
    this.pendingDeleteFileName = record.fileName
    this.isBatchDeleteSheet = false
    this.showDeleteSheet = true
  }

  @Builder
  private HistoryActionMenuContent(): void {
    Menu() {
      MenuItem({ content: '删除' })
        .onClick(() => {
          const record = this.findHistoryRecordById(this.historyActionMenuId)
          this.historyActionMenuId = -1
          if (record !== null) {
            this.askDeleteRecord(record)
          }
        })
      MenuItem({ content: '多选' })
        .onClick(() => {
          const record = this.findHistoryRecordById(this.historyActionMenuId)
          this.historyActionMenuId = -1
          if (record !== null) {
            this.isEditMode = true
            this.selectedIds = [record.id]
          }
        })
    }
    .width(120)
    .radius(16)
  }

  private toggleSelect(id: number): void {
    const idx: number = this.selectedIds.indexOf(id)
    if (idx >= 0) {
      const newIds: number[] = []
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (this.selectedIds[i] !== id) {
          newIds.push(this.selectedIds[i])
        }
      }
      this.selectedIds = newIds
    } else {
      this.selectedIds = [...this.selectedIds, id]
    }
  }

  private handleSelectAllOrExit(): void {
    if (this.selectedIds.length === this.localHistory.length) {
      this.selectedIds = []
      return
    }
    const allIds: number[] = []
    for (let i = 0; i < this.localHistory.length; i++) {
      allIds.push(this.localHistory[i].id)
    }
    this.selectedIds = allIds
  }

  private exitEditMode(): void {
    this.isEditMode = false
    this.selectedIds = []
  }

  private async confirmBatchDelete(): Promise<void> {
    this.showDeleteSheet = false
    const idsToDelete: number[] = [...this.selectedIds]
    if (idsToDelete.length === 0) {
      return
    }
    const shouldExit: boolean = idsToDelete.length >= this.localHistory.length
    const removedRecords: LocalVideoRecord[] = []
    for (let i = 0; i < idsToDelete.length; i++) {
      const record = this.findHistoryRecordById(idsToDelete[i])
      if (record !== null) {
        removedRecords.push(record)
      }
    }
    const nextHistory: LocalVideoRecord[] = []
    for (let i = 0; i < this.localHistory.length; i++) {
      if (idsToDelete.indexOf(this.localHistory[i].id) < 0) {
        nextHistory.push(this.localHistory[i])
      }
    }
    this.localHistory = nextHistory
    this.selectedIds = []
    if (shouldExit) {
      this.exitEditMode()
    }
    try {
      for (let i = 0; i < removedRecords.length; i++) {
        await LocalFilePicker.revokeUriPermission(removedRecords[i].fileUri)
        if (removedRecords[i].danmakuUri.length > 0) {
          await LocalFilePicker.revokeUriPermission(removedRecords[i].danmakuUri)
        }
      }
      await this.localVideoHistoryStore.deleteByIds(idsToDelete)
    } catch (err) {
      logger.warn('批量删除本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      await this.loadLocalHistory()
    }
  }

  private findHistoryRecordById(id: number): LocalVideoRecord | null {
    for (let i = 0; i < this.localHistory.length; i++) {
      if (this.localHistory[i].id === id) {
        return this.localHistory[i]
      }
    }
    return null
  }

  private buildRefreshLocalDirectoryIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.arrow_counterclockwise'),
      label: 'refresh local directory',
      action: () => {
        this.rescanOwnDownloadFolder()
      }
    }
  }

  private buildDownloadManagerIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.arrow_down_circle'),
      label: 'downloads',
      action: () => {
        router.pushUrl({ url: 'pages/download/DownloadPage' })
      }
    }
  }

  private buildLocalTitle(): HdsNavigationTitle {
    if (this.isEditMode) {
      return {
        mainTitle: '已选择' + String(this.selectedIds.length) + '项',
        subTitle: ''
      }
    }
    return {
      mainTitle: '下载视频'
    }
  }

  private buildLocalMenu(): HdsNavigationMenuContentOptions {
    if (this.selectedLocalTabIndex === 1 && this.localHistory.length > 0) {
      if (this.isEditMode) {
        const cancelIcon: HdsNavigationIconOptions = {
          icon: $r('sys.symbol.xmark'),
          label: 'cancel',
          action: () => {
            this.exitEditMode()
          }
        }
        const trashIcon: HdsNavigationIconOptions = {
          icon: $r('sys.symbol.trash'),
          label: 'delete',
          action: () => {
            if (this.selectedIds.length > 0) {
              this.isBatchDeleteSheet = true
              this.showDeleteSheet = true
            }
          }
        }
        const selectAllIcon: HdsNavigationIconOptions = {
          icon: $r('sys.symbol.checkmark_square_on_square'),
          label: 'selectAll',
          action: () => {
            this.handleSelectAllOrExit()
          }
        }
        return {
          value: [{ content: cancelIcon }, { content: trashIcon }, { content: selectAllIcon }]
        }
      }
      const editIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.square_and_pencil'),
        label: 'edit',
        action: () => {
          this.isEditMode = true
        }
      }
      return {
        value: [{ content: editIcon }, { content: this.buildDownloadManagerIcon() },
          { content: this.buildRefreshLocalDirectoryIcon() }]
      }
    }
    return {
      value: [{ content: this.buildDownloadManagerIcon() }, { content: this.buildRefreshLocalDirectoryIcon() }]
    }
  }

  private buildLocalTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildLocalTitle(),
      menu: this.buildLocalMenu()
    }
  }

  private buildLocalTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('下载视频', this.hdsMaterialLevel)
    base.content = this.buildLocalTitleBarContent()
    if (base.style?.originalStyle?.backgroundStyle) {
      base.style.originalStyle.backgroundStyle.maskExtraHeight = LOCAL_TAB_BAR_HEIGHT
    }
    if (base.style?.scrollEffectStyle?.backgroundStyle) {
      base.style.scrollEffectStyle.backgroundStyle.maskExtraHeight = LOCAL_TAB_BAR_HEIGHT
    }
    return base
  }

  private buildProgressText(record: LocalVideoRecord): string {
    if (record.durationMs <= 0) {
      return this.formatTime(record.positionMs)
    }
    return this.formatTime(record.positionMs) + ' / ' + this.formatTime(record.durationMs)
  }

  private buildProgressPercentText(record: LocalVideoRecord): string {
    if (record.durationMs <= 0) {
      return '0%'
    }
    const percent = Math.max(0, Math.min(99, Math.floor(record.positionMs * 100 / record.durationMs)))
    return percent + '%'
  }

  private buildOwnFolderStatusText(): string {
    if (this.ownFolderScanning) {
      return '读取中'
    }
    if (this.ownFolderScanFailed) {
      return '暂不可访问'
    }
    if (!this.ownFolderScanned) {
      return '未读取'
    }
    return this.rootFolderEntries.length + ' 部番剧'
  }

  private buildFolderEntryStatus(entry: UserFolderEntry): string {
    const parts: string[] = []
    if (entry.childVideoCount > 0) {
      parts.push(String(entry.childVideoCount) + ' 个视频')
    }
    if (entry.childDirectoryCount > 0) {
      parts.push(String(entry.childDirectoryCount) + ' 个文件夹')
    }
    return parts.length > 0 ? parts.join(' · ') : '空文件夹'
  }

  private openOwnFolderDirectory(entry: UserFolderEntry): void {
    router.pushUrl({
      url: 'pages/local/FolderPage',
      params: { relativePath: entry.relativePath }
    }).catch((err: Object): void => {
      logger.warn('打开番剧文件夹失败: %{public}s', err instanceof Error ? err.message : String(err))
    })
  }

  private buildOwnFolderEmptyTitle(): string {
    if (this.ownFolderScanning) {
      return '正在读取'
    }
    if (this.ownFolderScanFailed) {
      return '目录暂不可访问'
    }
    return '暂无下载视频'
  }

  private buildOwnFolderEmptySubtitle(): string {
    if (this.ownFolderScanning) {
      return '正在读取本地目录'
    }
    if (this.ownFolderScanFailed) {
      return '请确认系统已授权或通过刷新重新激活目录'
    }
    return '从在线播放页面点击下载后，视频会按番剧自动归档\n下载完成后返回本页即可播放'
  }

  private buildOwnFolderDanmakuHint(): string {
    if (this.ownFolderScanning || this.ownFolderScanFailed) {
      return ''
    }
    return '下载的视频、弹幕和封面会自动绑定\n支持离线播放与播放历史记录'
  }

  private formatFileSize(size: number): string {
    if (size <= 0) {
      return '未知大小'
    }
    const mb = size / 1024 / 1024
    if (mb < 1024) {
      return mb.toFixed(mb >= 100 ? 0 : 1) + ' MB'
    }
    const gb = mb / 1024
    return gb.toFixed(gb >= 100 ? 0 : 1) + ' GB'
  }

  private buildDanmakuText(record: LocalVideoRecord): string {
    let text = record.danmakuFormat.length > 0 ? record.danmakuFormat : '弹幕'
    if (record.danmakuCount > 0) {
      text += ' · ' + record.danmakuCount + ' 条'
    }
    if (record.danmakuOffsetMs !== 0) {
      text += ' · ' + this.formatOffset(record.danmakuOffsetMs)
    }
    text += ' · ' + record.danmakuFileName
    return text
  }

  private buildDanmakuStatusText(record: LocalVideoRecord): string {
    if (record.danmakuFileName.length > 0) {
      if (record.danmakuCount > 0) {
        return '已匹配弹幕 · ' + record.danmakuCount + ' 条'
      }
      return '已匹配弹幕'
    }
    return '未匹配弹幕'
  }

  private formatLastPlayedAt(timestamp: number): string {
    if (timestamp <= 0) {
      return '--'
    }
    const date = new Date(timestamp)
    const now = new Date()
    const dateDay = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
    const nowDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const diffDays = Math.floor((nowDay - dateDay) / 86400000)
    const time = this.pad2(date.getHours()) + ':' + this.pad2(date.getMinutes())
    if (diffDays === 0) {
      return '今天 ' + time
    }
    if (diffDays === 1) {
      return '昨天 ' + time
    }
    return this.pad2(date.getMonth() + 1) + '-' + this.pad2(date.getDate())
  }

  private formatOffset(ms: number): string {
    if (ms === 0) {
      return '0s'
    }
    const sign = ms > 0 ? '+' : ''
    const absMs = Math.abs(ms)
    if (absMs >= 1000) {
      const seconds = absMs / 1000
      return sign + (seconds % 1 === 0 ? seconds.toFixed(0) : seconds.toFixed(1)) + 's'
    }
    return sign + absMs + 'ms'
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    if (hours > 0) {
      return hours + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
    }
    return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
  }

  private pad2(value: number): string {
    return value < 10 ? '0' + value : String(value)
  }
}

@Component
struct LocalSegmentTabItem {
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @Prop label: string = ''
  @Prop index: number = 0
  @Prop selectedIndex: number = 0
  @Prop tabWidth: number = LOCAL_TAB_ITEM_WIDTH
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
      .height(LOCAL_TAB_BAR_HEIGHT)
      .barWidth(this.tabWidth)
      .barHeight(LOCAL_TAB_BAR_HEIGHT)
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
    .height(LOCAL_TAB_BAR_HEIGHT)
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
