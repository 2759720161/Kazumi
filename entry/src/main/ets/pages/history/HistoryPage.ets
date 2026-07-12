import { HistoryStore } from '../../store/HistoryStore'
import { HistoryRecord } from '../../models/HistoryRecord'
import { HistoryCard } from '../../components/history/HistoryCard'
import { ErrorRetry } from '../../components/common/ErrorRetry'
import { Logger } from '../../utils/Logger'
import { promptAction, router } from '@kit.ArkUI'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { PluginSearchService } from '../../core/engine/PluginSearchService'
import { SearchResultRef } from '../../models/PluginSearchState'
import { PlaybackRoad, PlaybackSource } from '../../models/PlaybackRoad'
import { EpisodeData } from '../../models/EpisodeData'
import { HistorySyncResult, HistorySyncService } from '../../services/HistorySyncService'
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
  buildImmersiveTitleBarStyle,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import { ADVANCED_OPTIONS_UNLOCKED_KEY } from '../../utils/AdvancedOptionsUnlock'

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

class HistoryMenuIconContent {
  content: HdsNavigationIconOptions

  constructor(content: HdsNavigationIconOptions) {
    this.content = content
  }
}

@Entry
@Component
export struct HistoryPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(ADVANCED_OPTIONS_UNLOCKED_KEY) showAdvancedPlayerOptions: boolean = false
  @State histories: HistoryRecord[] = []
  @State isLoading: boolean = true
  @State loadError: boolean = false
  @State isEditMode: boolean = false
  @State selectedIds: string[] = []
  @State showDeleteDialog: boolean = false
  @State historyRenderVersion: number = 0
  @State isSyncing: boolean = false
  private historyStore: HistoryStore = new HistoryStore()
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private playbackSearchService: PluginSearchService = new PluginSearchService()
  private historySyncService: HistorySyncService = HistorySyncService.getInstance()
  private scroller: Scroller = new Scroller()
  private isFirstAppear: boolean = true

  aboutToAppear(): void {
    this.loadHistories(this.histories.length === 0).then(() => {
      this.syncHistoryIfAutoEnabled()
    }).catch((err: Error) => {
      logger.warn('Initial load histories failed: %{public}s', err.message)
      this.syncHistoryIfAutoEnabled()
    })
  }

  onPageShow(): void {
    if (this.isFirstAppear) {
      this.isFirstAppear = false
      return
    }
    this.loadHistories(this.histories.length === 0)
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
              ErrorRetry({ message: '暂时无法读取观看记录', onRetry: () => { this.loadHistories(true) } })
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
          this.HistoryList()
        }
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
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
  HistoryList() {
    Scroll(this.scroller) {
      Column() {
        Column()
          .height(getTopSpacerHeight(this.topSafeHeight))
          .width('100%')
          .hitTestBehavior(HitTestMode.None)

        ForEach(this.getRows(), (row: HistoryRecord[], rowIndex: number) => {
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
          .justifyContent(FlexAlign.Start)
          .padding({ left: CARD_MARGIN_H, right: CARD_MARGIN_H, top: CARD_MARGIN_V, bottom: CARD_MARGIN_V })
        }, (row: HistoryRecord[], rowIndex: number) => this.buildRowKey(row, rowIndex))

        Column()
          .width('100%')
          .height(getBottomSpacerHeight(this.bottomSafeHeight))
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
    .id('history_list_' + String(this.historyRenderVersion))
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .clip(false)
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


  private async loadHistories(showLoading: boolean = true): Promise<void> {
    if (showLoading) {
      this.isLoading = true
    }
    this.loadError = false
    try {
      this.histories = await this.historyStore.getAll()
      await this.fillSourceNames()
      this.bumpHistoryRenderVersion()
    } catch (err) {
      logger.error('Load histories failed: %{public}s', JSON.stringify(err))
      this.loadError = true
    } finally {
      if (showLoading) {
        this.isLoading = false
      }
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
      if (this.showAdvancedPlayerOptions) {
        await this.historySyncService.recordDeleted(animeId)
      }
    } catch (err) {
      logger.error('Delete history failed: %{public}s', JSON.stringify(err))
      if (removedRecord !== null) {
        this.restoreHistoryRecords([removedRecord])
      }
    }
  }

  private async openHistoryRecord(record: HistoryRecord): Promise<void> {
    logger.info('Open history record animeId=%{public}s sourceId=%{public}d sourceName=%{public}s animeUrl=%{public}s episodeUrl=%{public}s',
      record.animeId, record.sourceId, record.sourceName,
      record.animeUrl.length > 0 ? 'ok' : 'empty',
      record.episodeUrl.length > 0 ? 'ok' : 'empty')
    if (record.animeUrl.length === 0 && record.episodeUrl.length === 0) {
      const recovered = await this.recoverMissingHistoryAnimeUrl(record)
      if (!recovered) {
        promptAction.showToast({ message: '未找到关联资源' })
        return
      }
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
      if (record.episodeUrl.length === 0 || record.episodeUrl === record.animeUrl) {
        promptAction.showToast({ message: source.message.length > 0 ? source.message : '无法加载剧集' })
        return
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Query history roads failed: %{public}s', msg)
      if (msg.indexOf('未找到关联番剧源') >= 0 || msg.indexOf('规则源不存在') >= 0) {
        promptAction.showToast({ message: msg })
        return
      }
      if (record.episodeUrl.length === 0 || record.episodeUrl === record.animeUrl) {
        promptAction.showToast({ message: msg.length > 0 ? msg : '无法加载剧集' })
        return
      }
    }

    this.openPlayerFallback(record)
  }

  private async queryPlaybackSource(record: HistoryRecord): Promise<PlaybackSource> {
    await this.resolveRecordRuleSource(record)
    const ref = new SearchResultRef()
    ref.name = record.animeName
    ref.url = record.animeUrl.length > 0 ? record.animeUrl : record.episodeUrl
    if (ref.url.length === 0) {
      throw new Error('历史记录缺少播放页地址')
    }
    ref.sourceId = record.sourceId
    ref.sourceName = record.sourceName
    logger.info('Query history roads sourceId=%{public}d sourceName=%{public}s url=%{public}s',
      ref.sourceId, ref.sourceName, ref.url.length > 0 ? 'ok' : 'empty')
    return await this.playbackSearchService.queryRoads(ref)
  }

  private async recoverMissingHistoryAnimeUrl(record: HistoryRecord): Promise<boolean> {
    try {
      const originalAnimeId: string = record.animeId
      await this.resolveRecordRuleSource(record)
      const refs: SearchResultRef[] = await this.playbackSearchService.searchRuleResults(record.sourceId, record.animeName)
      const matched: SearchResultRef | null = this.pickHistorySearchResult(refs, record.animeName)
      if (matched === null || matched.url.length === 0) {
        logger.warn('Recover history animeUrl no matched result: animeId=%{public}s name=%{public}s count=%{public}d',
          record.animeId, record.animeName, refs.length)
        return false
      }
      record.animeUrl = matched.url
      record.sourceId = matched.sourceId
      record.sourceName = matched.sourceName
      record.animeId = String(record.sourceId) + '_' + record.animeUrl
      await this.historyStore.replaceAnimeId(originalAnimeId, record)
      this.replaceHistoryRecordInView(originalAnimeId, record)
      logger.info('Recovered history animeUrl: name=%{public}s source=%{public}s',
        record.animeName, record.sourceName)
      return true
    } catch (err) {
      logger.warn('Recover history animeUrl failed: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  private pickHistorySearchResult(refs: SearchResultRef[], animeName: string): SearchResultRef | null {
    if (refs.length === 0) {
      return null
    }
    const target = this.normalizeAnimeTitle(animeName)
    for (let i = 0; i < refs.length; i++) {
      if (this.normalizeAnimeTitle(refs[i].name) === target) {
        return refs[i]
      }
    }
    for (let i = 0; i < refs.length; i++) {
      const candidate = this.normalizeAnimeTitle(refs[i].name)
      if (candidate.indexOf(target) >= 0 || target.indexOf(candidate) >= 0) {
        return refs[i]
      }
    }
    return refs[0]
  }

  private normalizeAnimeTitle(title: string): string {
    return title.trim().toLowerCase()
      .replace(/\s/g, '')
      .replace(/[!！?？:：,，.。·・、\-—_＿~～]/g, '')
  }

  private async resolveRecordRuleSource(record: HistoryRecord): Promise<void> {
    if (record.sourceId >= 0) {
      return
    }
    if (record.sourceName.length === 0) {
      record.sourceName = this.resolveLegacySourceNameFromAnimeId(record)
    }
    if (record.sourceName.length === 0) {
      throw new Error('未找到关联番剧源')
    }
    const sources: RuleSource[] = await this.ruleSourceStore.getAll()
    const normalizedSourceName = this.normalizeRuleName(record.sourceName)
    for (let i = 0; i < sources.length; i++) {
      if (this.normalizeRuleName(sources[i].name) === normalizedSourceName) {
        const originalAnimeId: string = record.animeId
        record.sourceId = sources[i].id
        record.sourceName = sources[i].name
        if (record.animeUrl.length > 0) {
          record.animeId = String(record.sourceId) + '_' + record.animeUrl
        }
        try {
          await this.historyStore.replaceAnimeId(originalAnimeId, record)
          this.replaceHistoryRecordInView(originalAnimeId, record)
        } catch (err) {
          logger.warn('Persist resolved history source failed: %{public}s',
            err instanceof Error ? err.message : String(err))
        }
        return
      }
    }
    throw new Error('未找到关联番剧源')
  }

  private resolveLegacySourceNameFromAnimeId(record: HistoryRecord): string {
    if (record.bangumiId <= 0 || record.animeId.length === 0) {
      return ''
    }
    const suffix = String(record.bangumiId)
    if (!record.animeId.endsWith(suffix) || record.animeId.length <= suffix.length) {
      return ''
    }
    return record.animeId.substring(0, record.animeId.length - suffix.length)
  }

  private normalizeRuleName(name: string): string {
    return name.trim().toLowerCase()
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
        bangumiId: record.bangumiId,
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
        bangumiId: record.bangumiId,
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
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 24 })

        Text(this.selectedIds.length > 1 ?
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
            .onClick(() => {
              this.confirmDeleteSelected()
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

  private async confirmDeleteSelected(): Promise<void> {
    this.showDeleteDialog = false
    const idsToDelete: string[] = [...this.selectedIds]
    if (idsToDelete.length === 0) {
      this.exitEditMode()
      return
    }
    const removedRecords: HistoryRecord[] = this.removeHistoryRecordsFromView(idsToDelete)
    this.exitEditMode()
    this.bumpHistoryRenderVersion()
    for (let i = 0; i < idsToDelete.length; i++) {
      try {
        await this.historyStore.deleteByAnimeId(idsToDelete[i])
        if (this.showAdvancedPlayerOptions) {
          await this.historySyncService.recordDeleted(idsToDelete[i])
        }
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

  private replaceHistoryRecordInView(oldAnimeId: string, record: HistoryRecord): void {
    const nextHistories: HistoryRecord[] = []
    let inserted = false
    for (let i = 0; i < this.histories.length; i++) {
      const current = this.histories[i]
      if (current.animeId === oldAnimeId || current.animeId === record.animeId) {
        if (!inserted) {
          nextHistories.push(record)
          inserted = true
        }
      } else {
        nextHistories.push(current)
      }
    }
    if (!inserted) {
      nextHistories.push(record)
    }
    nextHistories.sort((a: HistoryRecord, b: HistoryRecord) => b.updatedAt - a.updatedAt)
    this.histories = nextHistories
    this.selectedIds = this.selectedIds.map((id: string) => id === oldAnimeId ? record.animeId : id)
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
    const available: number = this.screenWidthVp - totalPadding - totalGaps
    const cardW: number = Math.floor(available / cols)
    return cardW
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
    const items: HistoryMenuIconContent[] = []
    if (this.showAdvancedPlayerOptions) {
      const syncIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.arrow_counterclockwise'),
        label: 'sync',
        action: () => {
          this.syncHistoryNow()
        }
      }
      items.push(new HistoryMenuIconContent(syncIcon))
    }
    if (this.histories.length === 0) {
      return {
        value: items
      }
    }
    const editIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.square_and_pencil'),
      label: 'edit',
      action: () => {
        this.isEditMode = true
      }
    }
    items.push(new HistoryMenuIconContent(editIcon))
    return {
      value: items
    }
  }

  private async syncHistoryIfAutoEnabled(): Promise<void> {
    if (!this.showAdvancedPlayerOptions) {
      return
    }
    try {
      const config = await this.historySyncService.getConfig()
      if (config.enabled && config.autoSync) {
        await this.syncHistoryNow(false)
      }
    } catch (err) {
      logger.warn('Auto sync history failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async syncHistoryNow(showToast: boolean = true): Promise<void> {
    if (!this.showAdvancedPlayerOptions) {
      return
    }
    if (this.isSyncing) {
      return
    }
    this.isSyncing = true
    try {
      const result: HistorySyncResult = await this.historySyncService.syncNow()
      await this.loadHistories(false)
      if (showToast) {
        promptAction.showToast({ message: result.message + '，共 ' + String(result.mergedCount) + ' 条' })
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : '同步失败'
      logger.warn('Sync history failed: %{public}s', msg)
      if (showToast) {
        promptAction.showToast({ message: msg })
      }
    } finally {
      this.isSyncing = false
    }
  }

  private buildTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildTitle(),
      menu: this.buildMenu()
    }
  }

  private buildCustomTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
    return {
      style: style,
      content: this.buildTitleBarContent(),
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
  }
}
