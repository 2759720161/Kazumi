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
  HdsTabs,
  hdsMaterial
} from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { LOCAL_VIDEO_HISTORY_VERSION_KEY } from '../../store/LocalVideoHistoryChangeSignal'
import { UserDownloadFolder } from '../../services/UserDownloadFolder'
import { Logger } from '../../utils/Logger'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'
import {
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  getBottomTabHideDistance,
  requestBottomTabAnimation,
  resolveBottomTabOffsetByDelta,
  resolveBottomTabSnapTarget
} from '../../utils/BottomTabAutoHide'

const logger = new Logger('LocalPage')
const LOCAL_TAB_LABELS: string[] = ['本地目录', '历史记录']
const LOCAL_TAB_BAR_HEIGHT: number = 40
const LOCAL_TAB_ITEM_WIDTH: number = 128

@Component
export struct LocalPage {
  @Prop @Watch('onActiveChanged') isActive: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(LOCAL_VIDEO_HISTORY_VERSION_KEY) @Watch('onLocalHistoryVersionChanged') localHistoryVersion: number = 0
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @State localHistory: LocalVideoRecord[] = []
  @State ownFolderVideos: LocalVideoRecord[] = []
  @State ownFolderScanned: boolean = false
  @State ownFolderScanFailed: boolean = false
  @State ownFolderScanning: boolean = false
  @State selectedLocalTabIndex: number = 0
  @State showClearConfirm: boolean = false
  @State showDeleteConfirm: boolean = false
  @State pendingDeleteId: number = -1
  @State pendingDeleteFileName: string = ''
  private scroller: Scroller = new Scroller()
  private localVideoHistoryStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()
  private hasScannedOwnDownloadFolder: boolean = false
  private isGeneratingCovers: boolean = false
  private isGeneratingOwnFolderCovers: boolean = false

  aboutToAppear(): void {
    this.loadLocalHistory()
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded()
    }
  }

  onPageShow(): void {
    this.loadLocalHistory()
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded()
    }
  }

  onLocalHistoryVersionChanged(): void {
    this.refreshLocalHistoryBindings()
  }

  onActiveChanged(): void {
    logger.info('Local page active changed: %{public}s', String(this.isActive))
    if (this.isActive) {
      this.scanOwnDownloadFolderIfNeeded()
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
                this.LocalDataSection()
              }
            }

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .height('100%')
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
      }
      .width('100%')
      .height('100%')
      .titleBar(this.buildLocalTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .bindSheet($$this.showClearConfirm, this.ClearConfirmSheet, {
        height: 220,
        showClose: false,
        dragBar: false
      })
      .bindSheet($$this.showDeleteConfirm, this.DeleteConfirmSheet, {
        height: 230,
        showClose: false,
        dragBar: false
      })

      this.LocalTabBar()
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

        Text('本地播放')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('选择本地视频播放，可手动导入 XML / JSON / ASS 弹幕')
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
      if (this.ownFolderVideos.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.ownFolderVideos, (record: LocalVideoRecord) => {
            this.OwnFolderVideoCard(record)
          }, (record: LocalVideoRecord) => 'own_folder_' + record.fileUri + '_' + record.fileSize)
        }
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
  }

  @Builder
  private OwnFolderVideoCard(record: LocalVideoRecord): void {
    Row({ space: 12 }) {
      Stack() {
        Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
          .width(82)
          .height(58)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .opacity(record.coverUri.length > 0 ? 1 : 0.82)
      }
      .width(82)
      .height(58)

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
      .height(58)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
        .margin({ top: 21 })
    }
    .width('100%')
    .height(106)
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

          Text('还没有播放记录')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          Text('播放过的视频会显示在这里')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .lineHeight(24)
            .margin({ top: 18 })
          Text('本地视频的播放进度、封面和弹幕绑定\n会在播放后自动保存')
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
        Column({ space: 8 }) {
          ForEach(this.localHistory, (record: LocalVideoRecord) => {
            this.HistoryCard(record)
          }, (record: LocalVideoRecord) => 'local_history_' + record.id + '_' + record.fileKey)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private HistoryCard(record: LocalVideoRecord): void {
    Row({ space: 12 }) {
      Stack() {
        if (record.coverUri.length > 0) {
          Image(record.coverUri)
            .width(82)
            .height(58)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
        } else {
          Image($r('app.media.ic_placeholder'))
            .width(82)
            .height(58)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(0.82)
        }
      }
      .width(82)
      .height(58)

      Column() {
        Row() {
          Text(record.fileName)
            .layoutWeight(1)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_secondary')])
            .padding({ left: 8, right: 4, top: 4, bottom: 4 })
            .onClick(() => {
              this.askDeleteRecord(record)
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row() {
          Text(this.buildProgressText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.buildProgressPercentText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 4 })

        if (record.durationMs > 0) {
          Progress({
            value: Math.min(record.positionMs, record.durationMs),
            total: record.durationMs,
            type: ProgressType.Linear
          })
            .height(3)
            .color($r('app.color.accent_blue'))
            .backgroundColor($r('app.color.button_ghost_bg'))
            .margin({ top: 8 })
        }

        Row() {
          Row() {
            if (record.danmakuFileName.length > 0) {
              this.HistoryDanmakuPill(this.buildDanmakuText(record), true)
            } else {
              this.HistoryDanmakuPill('未匹配弹幕', false)
            }
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })

          Text('上次播放 ' + this.formatLastPlayedAt(record.lastPlayedAt))
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Clip })
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .height(82)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(106)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.openHistoryRecord(record)
    })
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
  private HistoryDanmakuPill(text: string, highlighted: boolean): void {
    Text(text)
      .fontSize(11)
      .fontColor(highlighted ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(8)
      .backgroundColor(highlighted ? $r('app.color.button_ghost_bg') : Color.Transparent)
  }

  @Builder
  private LocalDataSection(): void {
    Column() {
      Text('本地数据')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Row() {
        Text('清空播放记录')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Blank()
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(17)
          .fontColor([$r('app.color.status_error')])
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 12 })
      .borderRadius(10)
      .backgroundColor($r('app.color.button_ghost_bg'))
      .margin({ top: 10 })
      .onClick(() => {
        this.showClearConfirm = true
      })
      Text('不会删除本地视频文件')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  private DeleteConfirmSheet(): void {
    Column() {
      Text('删除这条播放记录？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 22, bottom: 8 })
      Text(this.pendingDeleteFileName.length > 0 ? this.pendingDeleteFileName : '不会删除本地视频文件。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 22 })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .borderRadius(12)
          .onClick(() => {
            this.showDeleteConfirm = false
            this.pendingDeleteId = -1
            this.pendingDeleteFileName = ''
          })
        Button('删除')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.status_error'))
          .borderRadius(12)
          .onClick(() => {
            const id = this.pendingDeleteId
            this.showDeleteConfirm = false
            this.pendingDeleteId = -1
            this.pendingDeleteFileName = ''
            this.deleteHistoryRecord(id)
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
  }

  @Builder
  private ClearConfirmSheet(): void {
    Column() {
      Text('清空播放记录？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 22, bottom: 8 })
      Text('这不会删除本地视频文件。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 22 })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .borderRadius(12)
          .onClick(() => {
            this.showClearConfirm = false
          })
        Button('清空')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.status_error'))
          .borderRadius(12)
          .onClick(() => {
            this.showClearConfirm = false
            this.clearAllHistory()
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
  }

  private async openOwnFolderVideo(record: LocalVideoRecord): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      logger.warn('本地目录视频不可读: %{public}s', record.fileName)
      return
    }
    const latestRecord = await this.resolveLatestOwnFolderRecord(record)
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
        danmakuCount: latestRecord.danmakuCount
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
        danmakuCount: record.danmakuCount
      }
    })
  }

  private async loadLocalHistory(): Promise<void> {
    try {
      this.localHistory = await this.localVideoHistoryStore.getAll()
      this.ensureMissingCovers()
    } catch (err) {
      logger.warn('加载本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.localHistory = []
    }
  }

  private async refreshLocalHistoryBindings(): Promise<void> {
    await this.loadLocalHistory()
    if (this.ownFolderVideos.length > 0) {
      this.ownFolderVideos = this.mergeOwnFolderHistoryBindings(this.ownFolderVideos, this.localHistory)
    }
  }

  private async ensureMissingCovers(): Promise<void> {
    if (this.isGeneratingCovers || this.localHistory.length === 0) {
      return
    }
    this.isGeneratingCovers = true
    try {
      const maxGenerateCount = Math.min(this.localHistory.length, 12)
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

  private async scanOwnDownloadFolderIfNeeded(): Promise<void> {
    if (this.hasScannedOwnDownloadFolder) {
      return
    }
    if (this.ownFolderScanning) {
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
      this.ownFolderVideos = this.mergeOwnFolderHistoryBindings(records, await this.localVideoHistoryStore.getAll())
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
    }
  }

  private rescanOwnDownloadFolder(): void {
    this.hasScannedOwnDownloadFolder = false
    this.scanOwnDownloadFolderIfNeeded()
  }

  private async ensureOwnFolderCovers(): Promise<void> {
    if (this.isGeneratingOwnFolderCovers || this.ownFolderVideos.length === 0) {
      return
    }
    this.isGeneratingOwnFolderCovers = true
    try {
      const maxGenerateCount = Math.min(this.ownFolderVideos.length, 24)
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
        logger.info('本地目录视频封面已更新: %{public}s', record.fileName)
      }
    } catch (err) {
      logger.warn('生成本地目录视频封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isGeneratingOwnFolderCovers = false
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

  private async clearAllHistory(): Promise<void> {
    try {
      for (let i = 0; i < this.localHistory.length; i++) {
        await LocalFilePicker.revokeUriPermission(this.localHistory[i].fileUri)
        if (this.localHistory[i].danmakuUri.length > 0) {
          await LocalFilePicker.revokeUriPermission(this.localHistory[i].danmakuUri)
        }
      }
      await this.localVideoHistoryStore.clearAll()
      this.localHistory = []
    } catch (err) {
      logger.warn('清空本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private askDeleteRecord(record: LocalVideoRecord): void {
    this.pendingDeleteId = record.id
    this.pendingDeleteFileName = record.fileName
    this.showDeleteConfirm = true
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

  private buildLocalTitle(): HdsNavigationTitle {
    return {
      mainTitle: '本地视频'
    }
  }

  private buildLocalMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{ content: this.buildRefreshLocalDirectoryIcon() }]
    }
  }

  private buildLocalTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildLocalTitle(),
      menu: this.buildLocalMenu()
    }
  }

  private buildLocalTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('本地视频')
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
    return this.ownFolderVideos.length + ' 个视频'
  }

  private buildOwnFolderEmptyTitle(): string {
    if (this.ownFolderScanning) {
      return '正在读取'
    }
    if (this.ownFolderScanFailed) {
      return '目录暂不可访问'
    }
    return '本地目录空空如也'
  }

  private buildOwnFolderEmptySubtitle(): string {
    if (this.ownFolderScanning) {
      return '正在读取本地目录'
    }
    if (this.ownFolderScanFailed) {
      return '请确认系统已授权或通过刷新重新激活目录'
    }
    return '请将视频文件放入手机专属下载目录\n我的手机/Download/FanPlayer\n然后返回本页自动同步\n您也可以点击右上角按钮进行同步'
  }

  private buildOwnFolderDanmakuHint(): string {
    if (this.ownFolderScanning || this.ownFolderScanFailed) {
      return ''
    }
    return '弹幕文件可与视频同名放在同一目录\n支持 XML / JSON / ASS，扫描后自动匹配'
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
