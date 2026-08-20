import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { LocalFilePicker } from '../../services/LocalFilePicker'
import { LocalVideoThumbnailStore } from '../../services/LocalVideoThumbnailStore'
import { LocalVideoRecord } from '../../models/LocalVideoRecord'
import { LocalVideoHistoryStore } from '../../store/LocalVideoHistoryStore'
import { UserDownloadFolder, UserFolderEntry } from '../../services/UserDownloadFolder'
import { Logger } from '../../utils/Logger'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

const logger = new Logger('FolderPage')

@Entry
@Component
struct FolderPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink('appRdbReady') appRdbReady: boolean = false
  @State entries: UserFolderEntry[] = []
  @State relativePath: string = ''
  @State isLoading: boolean = true
  @State isUnavailable: boolean = false
  @State renderVersion: number = 0
  private scroller: Scroller = new Scroller()
  private historyStore: LocalVideoHistoryStore = new LocalVideoHistoryStore()

  aboutToAppear(): void {
    const rawParams = router.getParams()
    if (rawParams !== null && rawParams !== undefined) {
      const params = rawParams as Record<string, Object>
      const path = params['relativePath']
      if (typeof path === 'string') {
        this.relativePath = path
      }
    }
    this.reloadDirectory()
  }

  onPageShow(): void {
    this.reloadDirectory()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          if (this.entries.length > 0) {
            ForEach(this.entries, (entry: UserFolderEntry) => {
              if (entry.isDirectory) {
                this.DirectoryCard(entry)
              } else {
                this.VideoCard(entry.video)
              }
            }, (entry: UserFolderEntry) => 'folder_entry_' + entry.relativePath + '_' + entry.coverUri + '_' +
              entry.video.coverUri + '_' + this.renderVersion)
          } else {
            this.EmptyState()
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
    }
    .width('100%')
    .height('100%')
    .titleBar(this.buildFolderTitleBarOptions())
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .bindToScrollable([this.scroller])
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private DirectoryCard(entry: UserFolderEntry): void {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (entry.coverUri.length > 0) {
          Image(entry.coverUri)
            .draggable(false)
            .width(124)
            .height(78)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
        } else {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(36)
            .fontColor([$r('app.color.accent_blue')])
        }
      }
      .width(124)
      .height(78)
      .borderRadius(12)
      .backgroundColor($r('app.color.button_ghost_bg'))
      .clip(true)

      Column() {
        Text(entry.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(104)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => this.openChildFolder(entry.relativePath))
  }

  @Builder
  private VideoCard(record: LocalVideoRecord): void {
    Row({ space: 12 }) {
      Image(record.coverUri.length > 0 ? record.coverUri : $r('app.media.ic_placeholder'))
        .draggable(false)
        .width(124)
        .height(78)
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .opacity(record.coverUri.length > 0 ? 1 : 0.82)

      Column() {
        Text(record.fileName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .height(78)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(104)
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => this.openVideo(record))
  }

  @Builder
  private EmptyState(): void {
    Column({ space: 12 }) {
      SymbolGlyph(this.isLoading ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.folder'))
        .fontSize(64)
        .fontColor([$r('app.color.accent_blue')])
      Text(this.isLoading ? '正在读取文件夹' : this.isUnavailable ? '文件夹暂不可访问' : '此文件夹为空')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(this.isUnavailable ? '请返回本地目录后重新进入' : '下载视频会显示在这里')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(320)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private async reloadDirectory(): Promise<void> {
    this.isLoading = true
    this.isUnavailable = false
    try {
      const context = getContext(this) as common.UIAbilityContext
      const listed = await UserDownloadFolder.listOwnDirectory(context, this.relativePath)
      if (listed === null) {
        this.entries = []
        this.isUnavailable = true
        return
      }
      const scanned = await UserDownloadFolder.scanOwnVideoFiles(context)
      if (scanned !== null) {
        this.bindScannedMetadata(listed, scanned)
      }
      if (this.appRdbReady) {
        this.bindHistory(listed, await this.historyStore.getAll())
      }
      listed.sort((first: UserFolderEntry, second: UserFolderEntry): number => {
        if (first.isDirectory !== second.isDirectory) {
          return first.isDirectory ? -1 : 1
        }
        return UserDownloadFolder.compareVideoNames(first.name, second.name)
      })
      this.entries = listed
      this.renderVersion++
      this.ensureVideoFrameCovers()
    } catch (err) {
      this.entries = []
      this.isUnavailable = true
      logger.warn('读取文件夹失败: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.isLoading = false
    }
  }

  private bindScannedMetadata(entries: UserFolderEntry[], records: LocalVideoRecord[]): void {
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].isDirectory) {
        continue
      }
      for (let j = 0; j < records.length; j++) {
        if (records[j].fileUri !== entries[i].video.fileUri) {
          continue
        }
        entries[i].video.danmakuFileName = records[j].danmakuFileName
        entries[i].video.danmakuUri = records[j].danmakuUri
        entries[i].video.danmakuFormat = records[j].danmakuFormat
        entries[i].video.danmakuCount = records[j].danmakuCount
        entries[i].video.danmakuOffsetMs = records[j].danmakuOffsetMs
        entries[i].video.drmScheme = records[j].drmScheme
        entries[i].video.drmPluginName = records[j].drmPluginName
        entries[i].video.drmOfflineKeyId = records[j].drmOfflineKeyId
        if (entries[i].video.coverUri.length === 0) {
          entries[i].video.coverUri = records[j].coverUri
        }
        break
      }
    }
  }

  private bindHistory(entries: UserFolderEntry[], history: LocalVideoRecord[]): void {
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].isDirectory) {
        continue
      }
      for (let j = 0; j < history.length; j++) {
        if (history[j].fileUri !== entries[i].video.fileUri || history[j].fileSize !== entries[i].video.fileSize) {
          continue
        }
        entries[i].video.durationMs = history[j].durationMs
        entries[i].video.positionMs = history[j].positionMs
        entries[i].video.lastPlayedAt = history[j].lastPlayedAt
        if (entries[i].video.coverUri.length === 0) {
          entries[i].video.coverUri = history[j].coverUri
        }
        break
      }
    }
  }

  private async ensureVideoFrameCovers(): Promise<void> {
    const snapshot = this.entries.slice()
    for (let i = 0; i < snapshot.length; i++) {
      const entry = snapshot[i]
      if (entry.isDirectory || entry.video.fileUri.length === 0) {
        continue
      }
      if (!await LocalFilePicker.ensureReadableUri(entry.video.fileUri)) {
        logger.warn('跳过视频帧封面生成，文件暂不可读: %{public}s', entry.video.fileName)
        continue
      }
      const frameUri = await LocalVideoThumbnailStore.getInstance().ensureRandomThumbnail(
        entry.video.fileUri,
        entry.video.fileName,
        entry.video.fileSize
      )
      if (frameUri.length === 0) {
        continue
      }
      for (let j = 0; j < this.entries.length; j++) {
        if (this.entries[j].video.fileUri !== entry.video.fileUri) {
          continue
        }
        if (this.entries[j].video.coverUri !== frameUri) {
          this.entries[j].video.coverUri = frameUri
          this.entries = this.entries.slice()
          this.renderVersion++
        }
        break
      }
    }
  }

  private openChildFolder(relativePath: string): void {
    router.pushUrl({ url: 'pages/local/FolderPage', params: { relativePath: relativePath } })
  }

  private async openVideo(record: LocalVideoRecord): Promise<void> {
    if (!await LocalFilePicker.ensureReadableUri(record.fileUri)) {
      try {
        const context = getContext(this) as common.UIAbilityContext
        if (!await LocalFilePicker.authorizeExistingUri(context, record.fileUri)) {
          return
        }
      } catch (err) {
        logger.warn('本地视频授权失败: %{public}s', err instanceof Error ? err.message : String(err))
        return
      }
    }
    const queue: LocalVideoRecord[] = []
    let queueIndex: number = -1
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].isDirectory) {
        continue
      }
      queue.push(this.entries[i].video)
      if (this.entries[i].video.fileUri === record.fileUri) {
        queueIndex = queue.length - 1
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
        danmakuCount: record.danmakuCount,
        drmScheme: record.drmScheme,
        drmPluginName: record.drmPluginName,
        drmOfflineKeyId: record.drmOfflineKeyId,
        playlistJson: JSON.stringify(queue),
        queueIndex: queueIndex
      }
    })
  }

  private getTitle(): string {
    if (this.relativePath.length === 0) {
      return '本地目录'
    }
    const slashIndex = this.relativePath.lastIndexOf('/')
    return slashIndex >= 0 ? this.relativePath.substring(slashIndex + 1) : this.relativePath
  }

  private buildFolderTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildTitleBarOptions(this.getTitle(), this.hdsMaterialLevel)
  }

}
