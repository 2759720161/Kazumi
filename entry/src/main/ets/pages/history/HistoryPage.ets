import { HistoryStore } from '../../store/HistoryStore'
import { HistoryRecord } from '../../models/HistoryRecord'
import { HistoryCard } from '../../components/history/HistoryCard'
import { ErrorRetry } from '../../components/common/ErrorRetry'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { PluginSearchService } from '../../core/engine/PluginSearchService'
import { SearchResultRef } from '../../models/PluginSearchState'
import { PlaybackRoad, PlaybackSource } from '../../models/PlaybackRoad'
import { EpisodeData } from '../../models/EpisodeData'
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

const logger = new Logger('HistoryPage')
const CARD_MARGIN_H: number = 16
const CARD_MARGIN_V: number = 4
const GRID_GAP: number = 8

class HistoryEpisodeSelection {
  roadIndex: number
  episodeIndex: number
  episode: EpisodeData

  constructor(roadIndex: number, episodeIndex: number, episode: EpisodeData) {
    this.roadIndex = roadIndex
    this.episodeIndex = episodeIndex
    this.episode = episode
  }
}

@Entry
@Component
export struct HistoryPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State histories: HistoryRecord[] = []
  @State isLoading: boolean = true
  @State loadError: boolean = false
  @State isEditMode: boolean = false
  @State selectedIds: string[] = []
  @State showDeleteDialog: boolean = false
  @State historyRenderVersion: number = 0
  private historyStore: HistoryStore = new HistoryStore()
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private playbackSearchService: PluginSearchService = new PluginSearchService()
  private scroller: Scroller = new Scroller()
  private isFirstAppear: boolean = true

  aboutToAppear(): void {
    this.loadHistories()
  }

  onPageShow(): void {
    if (this.isFirstAppear) {
      this.isFirstAppear = false
      return
    }
    this.loadHistories()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        if (this.isLoading) {
          this.SkeletonList()
        } else if (this.loadError) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')
            Column() {
              ErrorRetry({ message: '暂时无法读取观看记录', onRetry: () => { this.loadHistories() } })
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .height('100%')
        } else if (this.histories.length === 0) {
          this.EmptyHistoryState()
        } else {
          Row() {
            Column() {
              List({ space: 0, initialIndex: 0, scroller: this.scroller }) {
                ListItem() {
                  Column()
                    .height(getTopSpacerHeight(this.topSafeHeight))
                    .width('100%')
                    .hitTestBehavior(HitTestMode.None)
                }
                .selectable(false)

                ForEach(this.getRows(), (row: HistoryRecord[], rowIndex: number) => {
                  ListItem() {
                    Row({ space: GRID_GAP }) {
                      ForEach(row, (record: HistoryRecord) => {
                        HistoryCard({
                          record: record,
                          isEditMode: this.isEditMode,
                          isSelected: this.selectedIds.indexOf(record.animeId) >= 0,
                          onDelete: (animeId: string) => { this.deleteRecord(animeId) },
                          onToggleSelect: (animeId: string) => { this.toggleSelect(animeId) },
                          onOpen: (history: HistoryRecord) => { this.openHistoryRecord(history) }
                        })
                          .width(this.getCardWidth())
                      }, (record: HistoryRecord) => this.buildRecordKey(record))
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)
                  }
                  .padding({ left: CARD_MARGIN_H, right: CARD_MARGIN_H, top: CARD_MARGIN_V, bottom: CARD_MARGIN_V })
                }, (row: HistoryRecord[], rowIndex: number) => this.buildRowKey(row, rowIndex))

                ListItem() {
                  Column()
                    .width('100%')
                    .height(getBottomSpacerHeight(this.bottomSafeHeight))
                    .hitTestBehavior(HitTestMode.None)
                }
                .selectable(false)
              }
              .id('history_list_' + String(this.historyRenderVersion))
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
            }
            .width('100%')
            .height('100%')
            .constraintSize({ maxWidth: this.getContentMaxWidth() })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .titleBar(this.buildCustomTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (this.showDeleteDialog) {
        this.DeleteConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  SkeletonList() {
    Row() {
      Column() {
        Blank()
          .height(getTopSpacerHeight(this.topSafeHeight))
          .width('100%')

        ForEach(this.getSkeletonRows(), (row: number[], rowIndex: number) => {
          Row({ space: GRID_GAP }) {
            ForEach(row, (colIndex: number) => {
              Row() {
                Column()
                  .width(80)
                  .height(108)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.skeleton_background'))

                Column() {
                  Column()
                    .width('60%')
                    .height(16)
                    .borderRadius(4)
                    .backgroundColor($r('app.color.skeleton_background'))
                  Column()
                    .width('45%')
                    .height(16)
                    .borderRadius(4)
                    .margin({ top: 4 })
                    .backgroundColor($r('app.color.skeleton_background'))
                  Column()
                    .width('40%')
                    .height(14)
                    .borderRadius(4)
                    .margin({ top: 8 })
                    .backgroundColor($r('app.color.skeleton_background'))
                  Column()
                    .width('50%')
                    .height(14)
                    .borderRadius(4)
                    .margin({ top: 4 })
                    .backgroundColor($r('app.color.skeleton_background'))
                  Blank()
                  Column()
                    .width('30%')
                    .height(12)
                    .borderRadius(4)
                    .backgroundColor($r('app.color.skeleton_background'))
                }
                .height(108)
                .layoutWeight(1)
                .margin({ left: 12 })
                .alignItems(HorizontalAlign.Start)
              }
              .width(this.getCardWidth())
              .height(132)
              .padding(12)
              .borderRadius(16)
              .backgroundColor($r('app.color.card_background'))
            }, (colIndex: number) => 'sk_' + String(rowIndex) + '_' + String(colIndex))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: CARD_MARGIN_H, right: CARD_MARGIN_H, top: CARD_MARGIN_V, bottom: CARD_MARGIN_V })
        }, (row: number[], rowIndex: number) => 'sk_row_' + String(rowIndex))

        Blank()
          .height(getBottomSpacerHeight(this.bottomSafeHeight))
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: this.getContentMaxWidth() })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  EmptyHistoryState() {
    Column() {
      Blank()
        .height(getTopSpacerHeight(this.topSafeHeight))
        .width('100%')
      Column() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(48)
          .fontColor([$r('app.color.text_secondary')])
        Text('暂无观看记录')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })
        Text('播放动画后，观看记录会显示在这里')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
        Button('返回')
          .height(40)
          .borderRadius(20)
          .margin({ top: 24 })
          .backgroundColor($r('app.color.button_primary_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            router.back()
          })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }


  private async loadHistories(): Promise<void> {
    this.isLoading = true
    this.loadError = false
    try {
      this.histories = await this.historyStore.getAll()
      await this.fillSourceNames()
      this.bumpHistoryRenderVersion()
    } catch (err) {
      logger.error('Load histories failed: %{public}s', JSON.stringify(err))
      this.loadError = true
    } finally {
      this.isLoading = false
    }
  }

  private async fillSourceNames(): Promise<void> {
    const sources: RuleSource[] = await this.ruleSourceStore.getAll()
    const sourceMap: Map<number, string> = new Map()
    for (let i = 0; i < sources.length; i++) {
      sourceMap.set(sources[i].id, sources[i].name)
    }
    for (let i = 0; i < this.histories.length; i++) {
      const name: string | undefined = sourceMap.get(this.histories[i].sourceId)
      if (name !== undefined) {
        this.histories[i].sourceName = name
      }
    }
  }

  private async deleteRecord(animeId: string): Promise<void> {
    const removedRecord: HistoryRecord | null = this.removeHistoryRecordFromView(animeId)
    try {
      await this.historyStore.deleteByAnimeId(animeId)
    } catch (err) {
      logger.error('Delete history failed: %{public}s', JSON.stringify(err))
      if (removedRecord !== null) {
        this.restoreHistoryRecords([removedRecord])
      }
    }
  }

  private async openHistoryRecord(record: HistoryRecord): Promise<void> {
    if (record.episodeUrl.length === 0) {
      return
    }

    try {
      const source = await this.queryPlaybackSource(record)
      if (source.status === 'success' && source.roads.length > 0) {
        const selected: HistoryEpisodeSelection | null = this.resolveHistoryEpisode(source.roads, record)
        if (selected !== null) {
          this.openPlayerWithRoads(record, source, selected)
          return
        }
      }
      logger.warn('Open history without roads fallback: animeId=%{public}s status=%{public}s',
        record.animeId, source.status)
    } catch (err) {
      logger.warn('Query history roads failed: %{public}s', err instanceof Error ? err.message : String(err))
    }

    this.openPlayerFallback(record)
  }

  private async queryPlaybackSource(record: HistoryRecord): Promise<PlaybackSource> {
    const ref = new SearchResultRef()
    ref.name = record.animeName
    ref.url = record.animeUrl
    ref.sourceId = record.sourceId
    ref.sourceName = record.sourceName
    return await this.playbackSearchService.queryRoads(ref)
  }

  private openPlayerWithRoads(record: HistoryRecord, source: PlaybackSource, selected: HistoryEpisodeSelection): void {
    const episode = selected.episode
    const sourceId: number = episode.sourceId >= 0 ? episode.sourceId : record.sourceId
    const animeUrl: string = episode.animeUrl.length > 0 ? episode.animeUrl : record.animeUrl
    const animeId: string = `${sourceId}_${animeUrl}`
    const episodeName: string = episode.name.length > 0 ? episode.name : record.episodeName
    const episodeUrl: string = episode.url.length > 0 ? episode.url : record.episodeUrl
    const historyPositionMs: number = this.isSameHistoryEpisode(record, selected) ? record.positionMs : 0

    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        episodeUrl: episodeUrl,
        animeName: record.animeName,
        episodeName: episodeName,
        animeId: animeId,
        animeCover: record.animeCover,
        animeUrl: animeUrl,
        ruleSourceId: sourceId,
        sourceId: sourceId,
        episodesJson: JSON.stringify(source.roads[selected.roadIndex].episodes),
        currentEpisodeIndex: selected.episodeIndex,
        roadsJson: JSON.stringify(source.roads),
        selectedRoadIndex: selected.roadIndex,
        bangumiCover: '',
        coverFallback: '',
        animeDesc: '',
        sourceName: source.name.length > 0 ? source.name : record.sourceName,
        historyPositionMs: historyPositionMs
      }
    })
  }

  private openPlayerFallback(record: HistoryRecord): void {
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        episodeUrl: record.episodeUrl,
        animeName: record.animeName,
        episodeName: record.episodeName,
        animeId: record.animeId,
        animeCover: record.animeCover,
        animeUrl: record.animeUrl,
        ruleSourceId: record.sourceId,
        sourceId: record.sourceId,
        bangumiCover: '',
        coverFallback: '',
        animeDesc: '',
        sourceName: record.sourceName,
        historyPositionMs: record.positionMs
      }
    })
  }

  private resolveHistoryEpisode(roads: PlaybackRoad[], record: HistoryRecord): HistoryEpisodeSelection | null {
    if (record.roadIndex >= 0 && record.episodeIndex >= 0 &&
      record.roadIndex < roads.length &&
      record.episodeIndex < roads[record.roadIndex].episodes.length) {
      return new HistoryEpisodeSelection(record.roadIndex, record.episodeIndex,
        roads[record.roadIndex].episodes[record.episodeIndex])
    }

    if (record.episodeUrl.length > 0) {
      const matched = this.findEpisodeByUrl(roads, record.episodeUrl)
      if (matched !== null) {
        return matched
      }
    }

    return this.findFirstEpisode(roads)
  }

  private findEpisodeByUrl(roads: PlaybackRoad[], episodeUrl: string): HistoryEpisodeSelection | null {
    for (let i = 0; i < roads.length; i++) {
      for (let j = 0; j < roads[i].episodes.length; j++) {
        if (roads[i].episodes[j].url === episodeUrl) {
          return new HistoryEpisodeSelection(i, j, roads[i].episodes[j])
        }
      }
    }
    return null
  }

  private findFirstEpisode(roads: PlaybackRoad[]): HistoryEpisodeSelection | null {
    for (let i = 0; i < roads.length; i++) {
      if (roads[i].episodes.length > 0) {
        return new HistoryEpisodeSelection(i, 0, roads[i].episodes[0])
      }
    }
    return null
  }

  private isSameHistoryEpisode(record: HistoryRecord, selected: HistoryEpisodeSelection): boolean {
    if (record.roadIndex === selected.roadIndex && record.episodeIndex === selected.episodeIndex) {
      return true
    }
    return record.episodeUrl.length > 0 && record.episodeUrl === selected.episode.url
  }

  private toggleSelect(animeId: string): void {
    const idx: number = this.selectedIds.indexOf(animeId)
    if (idx >= 0) {
      const newIds: string[] = []
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (this.selectedIds[i] !== animeId) {
          newIds.push(this.selectedIds[i])
        }
      }
      this.selectedIds = newIds
    } else {
      const newIds: string[] = [...this.selectedIds, animeId]
      this.selectedIds = newIds
    }
  }

  private handleSelectAllOrExit(): void {

    if (this.selectedIds.length === this.histories.length) {
      this.selectedIds = []
      return
    }
    const allIds: string[] = []
    for (let i = 0; i < this.histories.length; i++) {
      allIds.push(this.histories[i].animeId)
    }
    this.selectedIds = allIds
  }

  private exitEditMode(): void {
    this.isEditMode = false
    this.selectedIds = []
  }

  onBackPress(): boolean {
    if (this.isEditMode) {
      this.exitEditMode()
      return true
    }
    return false
  }

  @Builder
  DeleteConfirmDialog() {
    Column() {
      Column() {
        Text('是否删除此视频？')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
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
              this.confirmDeleteSelected()
            })
        }
        .width('100%')
      }
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0x66000000)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  private async confirmDeleteSelected(): Promise<void> {
    this.showDeleteDialog = false
    const idsToDelete: string[] = [...this.selectedIds]
    const shouldExitEditMode: boolean = idsToDelete.length >= this.histories.length
    const removedRecords: HistoryRecord[] = this.removeHistoryRecordsFromView(idsToDelete)
    if (shouldExitEditMode) {
      this.exitEditMode()
      this.bumpHistoryRenderVersion()
    }
    for (let i = 0; i < idsToDelete.length; i++) {
      try {
        await this.historyStore.deleteByAnimeId(idsToDelete[i])
      } catch (err) {
        logger.error('Delete history failed: %{public}s', JSON.stringify(err))
        const failedRecord: HistoryRecord | null = this.findHistoryRecordInList(removedRecords, idsToDelete[i])
        if (failedRecord !== null) {
          this.restoreHistoryRecords([failedRecord])
        }
      }
    }
  }

  private removeHistoryRecordFromView(animeId: string): HistoryRecord | null {
    const removed: HistoryRecord[] = this.removeHistoryRecordsFromView([animeId])
    return removed.length > 0 ? removed[0] : null
  }

  private removeHistoryRecordsFromView(animeIds: string[]): HistoryRecord[] {
    if (animeIds.length === 0) {
      return []
    }
    const nextHistories: HistoryRecord[] = []
    const removedRecords: HistoryRecord[] = []
    for (let i = 0; i < this.histories.length; i++) {
      const record: HistoryRecord = this.histories[i]
      if (animeIds.indexOf(record.animeId) >= 0) {
        removedRecords.push(record)
      } else {
        nextHistories.push(record)
      }
    }
    this.histories = nextHistories
    this.selectedIds = this.selectedIds.filter((id: string) => animeIds.indexOf(id) < 0)
    if (this.histories.length === 0) {
      this.exitEditMode()
    }
    this.bumpHistoryRenderVersion()
    return removedRecords
  }

  private restoreHistoryRecords(records: HistoryRecord[]): void {
    if (records.length === 0) {
      return
    }
    const restored: HistoryRecord[] = [...this.histories]
    for (let i = 0; i < records.length; i++) {
      if (this.findHistoryRecordInList(restored, records[i].animeId) === null) {
        restored.push(records[i])
      }
    }
    restored.sort((a: HistoryRecord, b: HistoryRecord) => b.updatedAt - a.updatedAt)
    this.histories = restored
    this.bumpHistoryRenderVersion()
  }

  private findHistoryRecordInList(records: HistoryRecord[], animeId: string): HistoryRecord | null {
    for (let i = 0; i < records.length; i++) {
      if (records[i].animeId === animeId) {
        return records[i]
      }
    }
    return null
  }

  private bumpHistoryRenderVersion(): void {
    this.historyRenderVersion = this.historyRenderVersion + 1
  }

  private buildRecordKey(record: HistoryRecord): string {
    return 'record_' + String(record.id) + '_' + record.animeId + '_' + String(this.historyRenderVersion)
  }

  private buildRowKey(row: HistoryRecord[], rowIndex: number): string {
    let key: string = 'row_' + String(rowIndex) + '_' + String(this.historyRenderVersion)
    for (let i = 0; i < row.length; i++) {
      key += '_' + String(row[i].id) + '_' + row[i].animeId
    }
    return key
  }


  private getColumnCount(): number {
    if (this.screenWidthVp >= 840) {
      return 3
    }
    if (this.screenWidthVp >= 600) {
      return 2
    }
    return 1
  }

  private getSkeletonRows(): number[][] {
    const cols: number = this.getColumnCount()
    const total: number = 6
    const rows: number[][] = []
    for (let i = 0; i < total; i += cols) {
      const row: number[] = []
      for (let j = 0; j < cols && i + j < total; j++) {
        row.push(i + j)
      }
      rows.push(row)
    }
    return rows
  }

  private getRows(): HistoryRecord[][] {
    const cols: number = this.getColumnCount()
    if (cols <= 1) {
      const rows: HistoryRecord[][] = []
      for (let i = 0; i < this.histories.length; i++) {
        rows.push([this.histories[i]])
      }
      return rows
    }
    const rows: HistoryRecord[][] = []
    for (let i = 0; i < this.histories.length; i += cols) {
      const row: HistoryRecord[] = []
      for (let j = 0; j < cols && i + j < this.histories.length; j++) {
        row.push(this.histories[i + j])
      }
      rows.push(row)
    }
    return rows
  }

  private getCardWidth(): Length {
    const cols: number = this.getColumnCount()
    if (cols <= 1) {
      return '100%'
    }
    const totalPadding: number = CARD_MARGIN_H * 2
    const totalGaps: number = GRID_GAP * (cols - 1)
    const available: number = Math.min(this.screenWidthVp, this.getContentMaxWidth()) - totalPadding - totalGaps
    const cardW: number = Math.floor(available / cols)
    return cardW
  }

  private getContentMaxWidth(): number {
    if (this.screenWidthVp >= 840) {
      return 1000
    }
    if (this.screenWidthVp >= 600) {
      return 1000
    }
    return this.screenWidthVp
  }

  private buildTitle(): HdsNavigationTitle {
    if (this.isEditMode) {
      return {
        mainTitle: '已选择' + String(this.selectedIds.length) + '项',
        subTitle: ''
      }
    }
    return {
      mainTitle: '历史记录',
      subTitle: this.histories.length > 0 ? '共 ' + String(this.histories.length) + ' 条' : ''
    }
  }

  private buildMenu(): HdsNavigationMenuContentOptions {
    if (this.histories.length === 0) {
      return { value: [] }
    }
    if (this.isEditMode) {
      const trashIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.trash'),
        label: 'delete',
        action: () => {
          if (this.selectedIds.length > 0) {
            this.showDeleteDialog = true
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
        value: [{ content: trashIcon }, { content: selectAllIcon }]
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
      value: [{ content: editIcon }]
    }
  }

  private buildTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildTitle(),
      menu: this.buildMenu()
    }
  }

  private buildCustomTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle()
    return {
      style: style,
      content: this.buildTitleBarContent(),
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
  }
}
