import { CollectController } from '../../controller/CollectController'
import { CollectType } from '../../models/CollectType'
import { AnimeItem } from '../../models/AnimeItem'
import { CollectStatusMenu } from '../../components/collect/CollectStatusMenu'
import { DetailHeroBackground } from '../../components/detail/DetailHeroBackground'
import { DetailTitleBlock } from '../../components/detail/DetailTitleBlock'
import { DetailInfoPanel } from '../../components/detail/DetailInfoPanel'
import { DetailFloatingPlayButton } from '../../components/detail/DetailFloatingPlayButton'
import { SourceSheet } from '../../components/detail/SourceSheet'
import { BangumiApi } from '../../core/api/BangumiApi'
import { BangumiConfig } from '../../core/api/BangumiConfig'
import { PlaybackRoad, PlaybackSource } from '../../models/PlaybackRoad'
import { EpisodeData } from '../../models/EpisodeData'
import { HistoryStore } from '../../store/HistoryStore'
import { HistoryRecord } from '../../models/HistoryRecord'
import { Logger } from '../../utils/Logger'
import { LengthMetrics, router } from '@kit.ArkUI'
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
  getEffectiveTopSafeHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle
} from '../../utils/HdsPageStyle'

const logger = new Logger('DetailPage')
const COLLAPSED_SYNOPSIS_TEXT_HEIGHT: number = 198
const COLLAPSED_SYNOPSIS_ACTION_HEIGHT: number = 64
const COLLAPSED_TAGS_HEIGHT: number = 320

class InitialEpisodeSelection {
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
export struct DetailPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State animeName: string = ''
  @State animeCover: string = ''
  @State animeCoverFallback: string = ''
  @State animeBangumiCover: string = ''
  @State animeDesc: string = ''
  @State animeOriginalName: string = ''
  @State animeAliases: string[] = []
  @State animeAirDate: string = ''
  @State animeRatingScore: number = 0
  @State animeRank: number = 0
  @State animeTags: string[] = []
  @State animeEps: number = 0
  @State sourceName: string = ''
  @State currentCollectType: number = CollectType.none
  @State showSourceSheet: boolean = false
  @State autoOpenSourceSheet: boolean = false
  @State sourceSheetCloseSignal: number = 0
  @State bangumiId: number = -1
  @State descExpanded: boolean = false
  @State animeVotes: number = 0
  @State animeVotesCount: number[] = []
  @State animeAirWeekday: number = 0
  @State tagsExpanded: boolean = false
  @State isSubjectDetailLoading: boolean = false
  @State showCollectMenu: boolean = false


  private animeUrl: string = ''
  private ruleSourceId: number = -1
  private collectController: CollectController = new CollectController()
  private historyStore: HistoryStore = new HistoryStore()
  private contentScroller: Scroller = new Scroller()


  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>
    if (params !== null) {
      if (params['animeName'] !== undefined) this.animeName = params['animeName'] as string
      if (params['animeCover'] !== undefined) this.animeCover = params['animeCover'] as string
      if (params['animeCoverFallback'] !== undefined) this.animeCoverFallback = params['animeCoverFallback'] as string
      if (params['animeBangumiCover'] !== undefined) this.animeBangumiCover = params['animeBangumiCover'] as string
      if (params['animeDesc'] !== undefined) this.animeDesc = params['animeDesc'] as string
      if (params['animeOriginalName'] !== undefined) this.animeOriginalName = params['animeOriginalName'] as string
      if (params['animeAirDate'] !== undefined) this.animeAirDate = params['animeAirDate'] as string
      if (params['animeRatingScore'] !== undefined) this.animeRatingScore = params['animeRatingScore'] as number
      if (params['animeRank'] !== undefined) this.animeRank = params['animeRank'] as number
      if (params['animeEps'] !== undefined) this.animeEps = params['animeEps'] as number
      if (params['animeTags'] !== undefined) this.animeTags = this.parseTags(params['animeTags'] as string)
      if (params['animeVotes'] !== undefined) this.animeVotes = params['animeVotes'] as number
      if (params['animeVotesCount'] !== undefined) this.animeVotesCount = this.parseNumberList(params['animeVotesCount'] as string)
      if (params['animeAirWeekday'] !== undefined) this.animeAirWeekday = params['animeAirWeekday'] as number
      if (params['animeUrl'] !== undefined) this.animeUrl = params['animeUrl'] as string
      if (params['sourceName'] !== undefined) this.sourceName = params['sourceName'] as string
      if (params['sourceId'] !== undefined) this.ruleSourceId = params['sourceId'] as number
      if (params['bangumiId'] !== undefined) this.bangumiId = params['bangumiId'] as number
      if (params['autoOpenSourceSheet'] !== undefined) this.autoOpenSourceSheet = params['autoOpenSourceSheet'] as boolean
    }
    this.loadDetail()
    this.fetchSubjectDetail()

    if (this.autoOpenSourceSheet) {
      setTimeout(() => {
        this.showSourceSheet = true
      }, 300)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {

      HdsNavigation() {
        Scroll(this.contentScroller) {
          Stack({ alignContent: Alignment.TopStart }) {
            DetailHeroBackground({
              cover: this.animeCover,
              coverFallback: this.animeCoverFallback,
              bangumiCover: this.animeBangumiCover,
              topSafeHeight: getEffectiveTopSafeHeight(this.topSafeHeight)
            })

            Column() {
              Blank()
                .height(getTopSpacerHeight(this.topSafeHeight) + 12)
                .width('100%')
                .hitTestBehavior(HitTestMode.None)

              DetailTitleBlock({
                title: this.animeName,
                originalName: this.animeOriginalName,
                airDate: $animeAirDate
              })

              this.ContentPanel()

              Blank()
                .height(getBottomSpacerHeight(this.bottomSafeHeight))
                .width('100%')
                .hitTestBehavior(HitTestMode.None)
            }
              .width('100%')
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
      .titleBar(this.buildDetailTitleBarOptions())
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .bindToScrollable([this.contentScroller])
      .bindSheet($$this.showSourceSheet, this.SourceSheetContent, {
        height: '75%',
        dragBar: true,
        showClose: false,
        radius: LengthMetrics.vp(24),
        backgroundColor: $r('app.color.page_background'),
        onDisappear: () => {
          this.sourceSheetCloseSignal++
          this.showSourceSheet = false
        }
      })

      DetailFloatingPlayButton({
        bottomSafeHeight: this.bottomSafeHeight,
        onPlay: () => {
          logger.info('Open source sheet from floating play button')
          this.showSourceSheet = true
        }
      })


    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_media'))
    .bindSheet($$this.showCollectMenu, this.CollectSheetContent, {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      radius: LengthMetrics.vp(24),
      backgroundColor: $r('app.color.page_background'),
      onDisappear: () => {
        this.showCollectMenu = false
      }
    })
  }

  @Builder
  private CollectSheetContent() {
    CollectStatusMenu({
      currentType: this.currentCollectType,
      isVisible: $showCollectMenu,
      onSelect: (type: number) => {
        this.onCollectMenuSelect(type)
      }
    })
  }

  @Builder
  private SourceSheetContent() {
    SourceSheet({
      animeName: this.animeName,
      animeOriginalName: this.animeOriginalName,
      animeAliases: this.animeAliases,
      closeSignal: this.sourceSheetCloseSignal,
      onRoadsReady: (source: PlaybackSource) => {
        this.onRoadsReady(source)
      },
      onOpenExternal: this.bangumiId > 0 ? () => {
        this.openBangumiPage()
      } : undefined
    })
  }

  @Builder
  private ContentPanel() {
    Column() {
      DetailInfoPanel({
        cover: this.animeCover,
        coverFallback: this.animeCoverFallback,
        bangumiCover: this.animeBangumiCover,
        ratingScore: this.animeRatingScore,
        rank: this.animeRank,
        votes: this.animeVotes,
        airDate: $animeAirDate,
        eps: $animeEps
      })

      this.SynopsisSection()
      this.TagSection()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 0, bottom: 16 })
  }

  @Builder
  private SynopsisSection() {
    Column() {
      Column() {
        Text('简介')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .width('100%')
          .margin({ bottom: 16 })

        Column() {
          if (this.isSynopsisSkeletonVisible()) {
            this.SynopsisSkeleton()
          } else {
            Text(this.animeDesc.length > 0 ? this.animeDesc : '暂无简介')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.animeDesc.length > 0 ? $r('app.color.text_body') : $r('app.color.text_placeholder'))
              .lineHeight(30)
              .width('100%')
              .maxLines(this.descExpanded ? 50 : 5)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .height(this.descExpanded ? undefined : 150)
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Row() {
          Blank()

          if (this.animeDesc.length > 120) {
            Text(this.descExpanded ? '收起' : '展开全文')
              .fontSize(14)
              .fontColor($r('app.color.accent_blue'))
              .padding({ left: 8, right: 8, top: 8, bottom: 8 })
              .onClick(() => {
                this.descExpanded = !this.descExpanded
              })
          }
        }
        .height(40)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.End)
        .width('100%')
      }
      .width('100%')
      .padding(20)
      .borderRadius(22)
      .backgroundColor($r('app.color.card_surface_blue'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
      .shadow({ radius: 18, color: $r('app.color.shadow_surface'), offsetY: 7 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 16 })
  }

  @Builder
  private TagSection() {
    Column() {
      Column() {
        Text('标签')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .width('100%')
          .margin({ bottom: 18 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          if (this.isTagSkeletonVisible()) {
            this.TagSkeleton()
          } else {
            ForEach(this.tagsExpanded ? this.animeTags : this.animeTags.slice(0, 12), (tag: string) => {
              Row() {
                Text(tag)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_title'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .height(40)
              .padding({ left: 16, right: 16 })
              .border({ width: 0.5, color: $r('app.color.border_tag') })
              .borderRadius(20)
              .backgroundColor($r('app.color.tag_chip_bg'))
              .margin({ right: 10, bottom: 12 })
            }, (tag: string) => tag)

            if (this.animeTags.length > 12) {
              Row() {
                Text(this.tagsExpanded ? '收起' : '更多')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.rating_star'))
              }
              .height(40)
              .padding({ left: 16, right: 16 })
              .borderRadius(20)
              .backgroundColor($r('app.color.surface_button_bg'))
              .margin({ right: 10, bottom: 12 })
              .onClick(() => {
                this.tagsExpanded = !this.tagsExpanded
              })
            }
          }
        }
        .width('100%')
        .height(this.tagsExpanded ? undefined : 206)
      }
      .width('100%')
      .padding(20)
      .borderRadius(22)
      .backgroundColor($r('app.color.card_surface_blue'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
      .shadow({ radius: 18, color: $r('app.color.shadow_surface'), offsetY: 7 })
    }
    .width('100%')
    .padding({ top: 0, bottom: 0 })
  }

  @Builder
  private SynopsisSkeleton() {
    Column() {
      this.SkeletonBlock('96%', 22)
      this.SkeletonBlock('88%', 22)
      this.SkeletonBlock('92%', 22)
      this.SkeletonBlock('76%', 22)
      this.SkeletonBlock('84%', 22)
    }
    .width('100%')
    .padding({ top: 6 })
  }

  @Builder
  private TagSkeleton() {
    Row() {
      this.SkeletonChip(96)
      this.SkeletonChip(142)
    }
    .margin({ bottom: 14 })

    Row() {
      this.SkeletonChip(118)
      this.SkeletonChip(92)
      this.SkeletonChip(108)
    }
    .margin({ bottom: 14 })

    Row() {
      this.SkeletonChip(132)
      this.SkeletonChip(104)
    }
    .margin({ bottom: 14 })
  }

  @Builder
  private SkeletonBlock(widthValue: string, heightValue: number) {
    Row()
      .width(widthValue)
      .height(heightValue)
      .borderRadius(heightValue / 2)
      .backgroundColor($r('app.color.skeleton_background'))
      .margin({ bottom: 14 })
  }

  @Builder
  private SkeletonChip(widthValue: number) {
    Row()
      .width(widthValue)
      .height(46)
      .borderRadius(9)
      .backgroundColor($r('app.color.skeleton_background'))
      .margin({ right: 10 })
  }

  private onRoadsReady(source: PlaybackSource): void {
    if (source.status === 'success' && source.roads.length > 0) {
      this.showSourceSheet = false
      this.openPlayerWithHistory(source)
    }
  }

  private async openPlayerWithHistory(source: PlaybackSource): Promise<void> {
    const selected = await this.resolveInitialEpisode(source)
    if (selected === null) {
      logger.warn('No playable episode found for source %{public}s', source.name)
      return
    }

    const selectedSourceId = selected.episode.sourceId >= 0 ? selected.episode.sourceId : source.sourceId
    const selectedAnimeUrl = selected.episode.animeUrl.length > 0 ? selected.episode.animeUrl : source.animeUrl
    const animeId = `${selectedSourceId}_${selectedAnimeUrl}`

    let historyPositionMs: number = 0
    try {
      const history = await this.historyStore.getByAnimeId(animeId)
      if (history !== null && history.positionMs > 0 && this.isHistorySelectionMatched(history, selected)) {
        historyPositionMs = history.positionMs
      }
    } catch (_err) { /* ignore */ }

    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        episodeUrl: selected.episode.url,
        ruleSourceId: selectedSourceId,
        animeName: this.animeName,
        episodeName: selected.episode.name,
        animeId: animeId,
        animeCover: this.animeCover,
        animeUrl: selectedAnimeUrl,
        sourceId: selectedSourceId,
        episodesJson: JSON.stringify(source.roads[selected.roadIndex].episodes),
        currentEpisodeIndex: selected.episodeIndex,
        roadsJson: JSON.stringify(source.roads),
        selectedRoadIndex: selected.roadIndex,
        bangumiId: this.bangumiId > 0 ? this.bangumiId : 0,
        bangumiCover: this.animeBangumiCover,
        coverFallback: this.animeCoverFallback,
        animeDesc: this.animeDesc,
        sourceName: this.sourceName,
        historyPositionMs: historyPositionMs
      }
    })
  }

  private isHistorySelectionMatched(history: HistoryRecord, selected: InitialEpisodeSelection): boolean {
    if (history.roadIndex === selected.roadIndex && history.episodeIndex === selected.episodeIndex) {
      return true
    }
    return history.episodeUrl.length > 0 && history.episodeUrl === selected.episode.url
  }

  private async resolveInitialEpisode(source: PlaybackSource): Promise<InitialEpisodeSelection | null> {
    const fallback = this.findFirstEpisode(source.roads)
    if (fallback === null) {
      return null
    }

    const animeId = `${source.sourceId}_${source.animeUrl}`
    let history: HistoryRecord | null = null
    try {
      history = await this.historyStore.getByAnimeId(animeId)
    } catch (err) {
      logger.warn('Load watch history failed: %{public}s', err instanceof Error ? err.message : String(err))
    }

    if (history !== null) {
      if (history.roadIndex >= 0 && history.episodeIndex >= 0 &&
        history.roadIndex < source.roads.length &&
        history.episodeIndex < source.roads[history.roadIndex].episodes.length) {
        return new InitialEpisodeSelection(
          history.roadIndex,
          history.episodeIndex,
          source.roads[history.roadIndex].episodes[history.episodeIndex]
        )
      }
      if (history.episodeUrl.length > 0) {
        const matched = this.findEpisodeByUrl(source.roads, history.episodeUrl)
        if (matched !== null) {
          return matched
        }
      }
    }
    return fallback
  }

  private findFirstEpisode(roads: PlaybackRoad[]): InitialEpisodeSelection | null {
    for (let i = 0; i < roads.length; i++) {
      if (roads[i].episodes.length > 0) {
        return new InitialEpisodeSelection(i, 0, roads[i].episodes[0])
      }
    }
    return null
  }

  private findEpisodeByUrl(roads: PlaybackRoad[], episodeUrl: string): InitialEpisodeSelection | null {
    for (let i = 0; i < roads.length; i++) {
      for (let j = 0; j < roads[i].episodes.length; j++) {
        if (roads[i].episodes[j].url === episodeUrl) {
          return new InitialEpisodeSelection(i, j, roads[i].episodes[j])
        }
      }
    }
    return null
  }

  private async loadDetail(): Promise<void> {
    try {
      const animeId = `${this.ruleSourceId}_${this.animeUrl}`
      this.currentCollectType = await this.collectController.getCollectType(animeId)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Load collect type failed: %{public}s', msg)
    }
  }

  private buildAnimeItem(): AnimeItem {
    const item = new AnimeItem()
    item.name = this.animeName
    item.cover = this.animeCover
    item.coverFallback = this.animeCoverFallback
    item.bangumiCover = this.animeBangumiCover
    item.desc = this.animeDesc
    item.url = this.animeUrl
    item.sourceName = this.sourceName
    item.sourceId = this.ruleSourceId
    item.bangumiId = this.bangumiId
    item.originalName = this.animeOriginalName
    item.aliases = this.animeAliases
    return item
  }

  private async onCollectMenuSelect(type: number): Promise<void> {
    if (type === CollectType.none) {
      try {
        const animeItem = this.buildAnimeItem()
        await this.collectController.deleteCollect(animeItem)
        this.currentCollectType = CollectType.none
        this.showCollectMenu = false
      } catch (err) {
        logger.error('Delete collect failed: %{public}s', err instanceof Error ? err.message : String(err))
      }
      return
    }
    try {
      const animeItem = this.buildAnimeItem()
      await this.collectController.addCollect(animeItem, type)
      this.currentCollectType = type
      this.showCollectMenu = false
    } catch (err) {
      logger.error('onCollectMenuSelect failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }


  private parseTags(raw: string): string[] {
    if (raw.length === 0) return []
    try {
      return JSON.parse(raw) as string[]
    } catch (err) {
      return []
    }
  }

  private parseNumberList(raw: string): number[] {
    if (raw.length === 0) return []
    try {
      return JSON.parse(raw) as number[]
    } catch (err) {
      return []
    }
  }

  private async fetchSubjectDetail(): Promise<void> {
    if (this.bangumiId <= 0) return
    this.isSubjectDetailLoading = true
    try {
      const subject = await BangumiApi.getSubject(this.bangumiId)
      if (subject !== null) {
        if (this.animeName.length === 0 && subject.name.length > 0) this.animeName = subject.name
        const detailCover = subject.getDetailCover()
        if (this.animeBangumiCover.length === 0 && detailCover.length > 0) this.animeBangumiCover = detailCover
        else if (this.animeBangumiCover.length === 0 && subject.bangumiCover.length > 0) this.animeBangumiCover = subject.bangumiCover
        if (this.animeCover.length === 0 && subject.cover.length > 0) this.animeCover = subject.cover
        if (this.animeDesc.length === 0 && subject.desc.length > 0) this.animeDesc = subject.desc
        if (this.animeOriginalName.length === 0 && subject.originalName.length > 0) this.animeOriginalName = subject.originalName
        if (this.animeAliases.length === 0 && subject.aliases.length > 0) this.animeAliases = subject.aliases
        if (this.shouldReplaceText(this.animeAirDate) && subject.airDate.length > 0) this.animeAirDate = subject.airDate
        if (this.animeAirWeekday <= 0 && subject.airWeekday > 0) this.animeAirWeekday = subject.airWeekday
        if (this.animeRatingScore <= 0 && subject.ratingScore > 0) this.animeRatingScore = subject.ratingScore
        if (this.animeRank <= 0 && subject.rank > 0) this.animeRank = subject.rank
        if (this.animeEps <= 0 && subject.eps > 0) this.animeEps = subject.eps
        if (this.animeTags.length === 0 && subject.tags.length > 0) this.animeTags = subject.tags
        if (this.animeVotes <= 0 && subject.votes > 0) this.animeVotes = subject.votes
        if (this.animeVotesCount.length === 0 && subject.votesCount.length > 0) this.animeVotesCount = subject.votesCount
        logger.info('Detail subject applied: %{public}s eps=%{public}d airDate=%{public}s',
          this.animeName, this.animeEps, this.animeAirDate)
      }
    } catch (err) {
      logger.warn('Fetch subject detail failed: %{public}s',
        err instanceof Error ? err.message : String(err))
    } finally {
      this.isSubjectDetailLoading = false
    }
  }

  private isSynopsisSkeletonVisible(): boolean {
    return this.isSubjectDetailLoading && this.animeDesc.length === 0
  }

  private isTagSkeletonVisible(): boolean {
    return this.isSubjectDetailLoading && this.animeTags.length === 0
  }

  private shouldReplaceText(value: string): boolean {
    const trimmed = value.trim()
    return trimmed.length === 0 || trimmed === '-' || trimmed === '未知' || trimmed === 'null' || trimmed === 'undefined'
  }

  private openBangumiPage(): void {
    if (this.bangumiId > 0) {
      const url = BangumiConfig.getSubjectWebUrl(this.bangumiId)
      logger.info('Open Bangumi page: %{public}s', url)
    }
  }

  private buildShareIcon(): HdsNavigationIconOptions {
    return {
      icon: $r('sys.symbol.share'),
      label: 'share',
      action: () => {
        this.openBangumiPage()
      }
    }
  }

  private buildCollectIcon(): HdsNavigationIconOptions {
    return {
      icon: this.currentCollectType > CollectType.none ?
        CollectType.getIcon(this.currentCollectType) : $r('sys.symbol.heart'),
      label: this.currentCollectType > CollectType.none ?
        CollectType.getLabel(this.currentCollectType) : '追番',
      action: () => {
        this.showCollectMenu = true
      }
    }
  }

  private buildDetailMenu(): HdsNavigationMenuContentOptions {
    if (this.bangumiId > 0) {
      return {
        value: [
          { content: this.buildCollectIcon() },
          { content: this.buildShareIcon() }
        ]
      }
    }
    return {
      value: [{ content: this.buildCollectIcon() }]
    }
  }

  private buildDetailTitle(): HdsNavigationTitle {
    return {
      mainTitle: ''
    }
  }

  private buildDetailTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildDetailTitle(),
      menu: this.buildDetailMenu()
    }
  }

  private buildDetailTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle()
    if (style.scrollEffectOpts) {
      style.scrollEffectOpts.blurEffectiveStartOffset = LengthMetrics.vp(0)
      style.scrollEffectOpts.blurEffectiveEndOffset = LengthMetrics.vp(80)
    }
    if (style.originalStyle?.backgroundStyle) {
      style.originalStyle.backgroundStyle.maskExtraHeight = 0
    }
    if (style.scrollEffectStyle?.backgroundStyle) {
      style.scrollEffectStyle.backgroundStyle.maskExtraHeight = 0
    }
    return {
      style: style,
      content: this.buildDetailTitleBarContent(),
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
  }

}
