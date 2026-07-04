import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitle,
  TitleBarContentOptions
} from '@kit.UIDesignKit'
import { LocalFilePicker, LocalVideoResult } from '../../services/LocalFilePicker'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { Logger } from '../../utils/Logger'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'

const logger = new Logger('LocalPage')

@Component
export struct LocalPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State localHistory: LocalVideoRecord[] = []
  @State showClearConfirm: boolean = false
  private scroller: Scroller = new Scroller()
  private localVideoHistoryStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()

  aboutToAppear(): void {
    this.loadLocalHistory()
  }

  onPageShow(): void {
    this.loadLocalHistory()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 14 }) {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          if (this.localHistory.length > 0) {
            this.HeroCard()
          }
          this.RecentSection()
          this.DanmakuInfoSection()

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
  }

  @Builder
  private HeroCard(): void {
    Column() {
      Row() {
        Column() {
          Text('继续播放')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(this.localHistory[0].fileName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
          Text(this.buildProgressText(this.localHistory[0]))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.play_circle'))
          .fontSize(30)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 22, bottom: 22 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.openHistoryRecord(this.localHistory[0])
    })
  }

  @Builder
  private RecentSection(): void {
    Column() {
      Row() {
        Text('最近播放')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
          .layoutWeight(1)
        if (this.localHistory.length > 0) {
          Button('清空')
            .height(30)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .borderRadius(10)
            .onClick(() => {
              this.showClearConfirm = true
            })
        }
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 8 })

      if (this.localHistory.length === 0) {
        Column() {
          Text('暂无本地播放记录')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(92)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') })
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
    Column() {
      Row() {
        Column() {
          Text(record.fileName)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.buildProgressText(record))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('sys.color.icon_secondary')])
      }
      .width('100%')

      if (record.durationMs > 0) {
        Progress({
          value: Math.min(record.positionMs, record.durationMs),
          total: record.durationMs,
          type: ProgressType.Linear
        })
          .height(3)
          .color($r('app.color.accent_blue'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .margin({ top: 10 })
      }

      if (record.danmakuFileName.length > 0) {
        Text(this.buildDanmakuText(record))
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => {
      this.openHistoryRecord(record)
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.deleteHistoryRecord(record.id)
        })
    )
  }

  @Builder
  private DanmakuInfoSection(): void {
    Column() {
      Text('本地弹幕')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('进入播放器后可加载、追加、替换和校准弹幕。支持 B站 XML、弹弹 JSON、ASS 字幕。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
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

  private async pickAndOpenVideo(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const videoResult: LocalVideoResult | null = await LocalFilePicker.pickVideoFile(context)
      if (videoResult === null) {
        return
      }
      router.pushUrl({
        url: 'pages/player/LocalPlayerPage',
        params: {
          videoUri: videoResult.uri,
          videoFileName: videoResult.fileName,
          videoFileSize: videoResult.fileSize
        }
      })
    } catch (err) {
      logger.warn('打开本地视频失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private openHistoryRecord(record: LocalVideoRecord): void {
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
    } catch (err) {
      logger.warn('加载本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.localHistory = []
    }
  }

  private async deleteHistoryRecord(id: number): Promise<void> {
    try {
      await this.localVideoHistoryStore.deleteById(id)
      await this.loadLocalHistory()
    } catch (err) {
      logger.warn('删除本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async clearAllHistory(): Promise<void> {
    try {
      await this.localVideoHistoryStore.clearAll()
      this.localHistory = []
    } catch (err) {
      logger.warn('清空本地播放记录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private buildAddVideoIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.folder_badge_plus'),
      label: 'add local video',
      action: () => {
        this.pickAndOpenVideo()
      }
    }
  }

  private buildLocalTitle(): HdsNavigationTitle {
    return {
      mainTitle: '本地',
      subTitle: this.localHistory.length > 0 ? `${this.localHistory.length} 条记录` : '添加本地视频'
    }
  }

  private buildLocalMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{ content: this.buildAddVideoIcon() }]
    }
  }

  private buildLocalTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildLocalTitle(),
      menu: this.buildLocalMenu()
    }
  }

  private buildLocalTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('本地')
    base.content = this.buildLocalTitleBarContent()
    return base
  }

  private buildProgressText(record: LocalVideoRecord): string {
    if (record.durationMs <= 0) {
      return this.formatTime(record.positionMs)
    }
    return this.formatTime(record.positionMs) + ' / ' + this.formatTime(record.durationMs)
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
}
