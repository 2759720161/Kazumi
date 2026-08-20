import { CollectController } from '../../controller/CollectController'
import { CollectType } from '../../models/CollectType'
import { AnimeItem } from '../../models/AnimeItem'
import { DetailHeroBackground } from '../../components/detail/DetailHeroBackground'
import { DetailTitleBlock } from '../../components/detail/DetailTitleBlock'
import { DetailInfoPanel } from '../../components/detail/DetailInfoPanel'
import { DetailFloatingPlayButton } from '../../components/detail/DetailFloatingPlayButton'
import { SourceSheet, SourceSheetSnapshot } from '../../components/detail/SourceSheet'
import { BangumiApi } from '../../core/api/BangumiApi'
import { BangumiConfig } from '../../core/api/BangumiConfig'
import { PlaybackRoad, PlaybackSource } from '../../models/PlaybackRoad'
import { EpisodeData } from '../../models/EpisodeData'
import { HistoryStore } from '../../store/HistoryStore'
import { ImageCacheStore } from '../../store/ImageCacheStore'
import { HistoryRecord } from '../../models/HistoryRecord'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { ThemeColorStore } from '../../services/ThemeColorStore'
import { Logger } from '../../utils/Logger'
import { LengthMetrics, promptAction, router } from '@kit.ArkUI'
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
  buildImmersiveTitleBarStyle,
  isWideDetailLayout,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import { ContinuationDetailParams, ContinuationPlayerParams, ContinuationState } from '../../utils/ContinuationState'

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

@Component
export struct DetailPageContent {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
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
  @State preserveSourceSheetOnDisappear: boolean = false
  @State sectionThemeBackground: string = '#00000000'
  @State sectionThemeBorder: string = '#00000000'
  @State tagThemeBackground: string = ''
  @State tagThemeBorder: string = ''
  @State sectionThemeKey: string = ''
  @State currentCoverImage: string = ''
  @State sharedCoverId: string = ''
  @State transitionCover: string = ''


  private animeUrl: string = ''
  private ruleSourceId: number = -1
  private collectController: CollectController = new CollectController()
  private historyStore: HistoryStore = new HistoryStore()
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private contentScroller: Scroller = new Scroller()
  private sourceSheetSnapshot: SourceSheetSnapshot | null = null
  private coverCacheRequestKey: string = ''


  aboutToAppear(): void {
    const params: Record<string, Object> = router.getParams() as Record<string, Object>
    if (params !== null) {
      if (params['animeName'] !== undefined) this.animeName = params['animeName'] as string
      if (params['animeCover'] !== undefined) this.animeCover = BangumiConfig.normalizeImageUrl(params['animeCover'] as string)
      if (params['animeCoverFallback'] !== undefined) this.animeCoverFallback = BangumiConfig.normalizeImageUrl(params['animeCoverFallback'] as string)
      if (params['animeBangumiCover'] !== undefined) this.animeBangumiCover = BangumiConfig.normalizeImageUrl(params['animeBangumiCover'] as string)
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
      if (params['sharedCoverId'] !== undefined) this.sharedCoverId = params['sharedCoverId'] as string
      if (params['transitionCover'] !== undefined) this.transitionCover = BangumiConfig.normalizeImageUrl(params['transitionCover'] as string)
      if (params['autoOpenSourceSheet'] !== undefined) this.autoOpenSourceSheet = params['autoOpenSourceSheet'] as boolean
    }
    this.markContinuationState()
    this.loadDetail()
    this.refreshSectionTheme()
    this.fetchSubjectDetail()
    this.currentCoverImage = this.selectBestCoverImage()
    this.prepareCachedCover(this.buildCoverKey())

    if (this.autoOpenSourceSheet) {
      setTimeout(() => {
        this.openSourceSheetIfRulesAvailable()
      }, 300)
    }

    this.restoreSourceSheetAfterPlayerIfNeeded()
  }

  onPageShow(): void {
    this.restoreSourceSheetAfterPlayerIfNeeded()
  }

  private restoreSourceSheetAfterPlayerIfNeeded(): void {
    if (this.preserveSourceSheetOnDisappear) {
      logger.info('DetailPage restored from player, keep source sheet visible')
      this.preserveSourceSheetOnDisappear = false
      this.showSourceSheet = true
    }
  }

  private async openSourceSheetIfRulesAvailable(): Promise<void> {
    try {
      const enabledRules = await this.ruleSourceStore.getEnabled()
      if (enabledRules.length === 0) {
        promptAction.showToast({ message: '请前往规则仓库导入规则' })
        return
      }
      this.showSourceSheet = true
    } catch (err) {
      logger.error('Check rule source before opening source sheet failed: %{public}s', JSON.stringify(err))
      promptAction.showToast({ message: '请前往规则仓库导入规则' })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {

      HdsNavigation() {
        if (this.isTabletWideLayout()) {
          this.TabletDetailContent()
        } else {
          this.PhoneDetailContent()
        }
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
        height: this.getSourceSheetHeight(),
        width: this.getSourceSheetWidth(),
        preferType: this.getSourceSheetType(),
        enableOutsideInteractive: false,
        dragBar: true,
        showClose: false,
        radius: LengthMetrics.vp(24),
        backgroundColor: $r('app.color.page_background'),
        onDisappear: () => {
          if (this.preserveSourceSheetOnDisappear) {
            logger.info('SourceSheet disappeared during player navigation, preserve sheet state')
            return
          }
          this.sourceSheetCloseSignal++
          this.showSourceSheet = false
          this.sourceSheetSnapshot = null
        }
      })

      DetailFloatingPlayButton({
        bottomSafeHeight: this.bottomSafeHeight,
        onPlay: () => {
          logger.info('Open source sheet from floating play button')
          this.openSourceSheetIfRulesAvailable()
        }
      })

    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_media'))
  }

  @Builder
  private PhoneDetailContent() {
    Scroll(this.contentScroller) {
      Stack({ alignContent: Alignment.TopStart }) {
          DetailHeroBackground({
          cover: this.getCoverImageSrc(),
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

  @Builder
  private TabletDetailContent() {
    Row() {
      Column() {
        Blank()
          .height(getTopSpacerHeight(this.topSafeHeight) + 12)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)

        Image(this.getTransitionCoverSrc())
          .draggable(false)
          .width('100%')
          .aspectRatio(118 / 168)
          .objectFit(this.getTransitionCoverSrc().length > 0 ? ImageFit.Cover : ImageFit.Contain)
          .borderRadius(12)
          .clip(true)
          .alt($r('app.media.ic_placeholder'))
          .shadow({ radius: 20, color: $r('app.color.detail_info_shadow'), offsetY: 8 })
          .onError(() => {
            this.tryNextCoverImage()
          })
          .sharedTransition(this.getSharedCoverIdForRender(), { duration: 420, curve: Curve.FastOutSlowIn })
      }
      .width('36%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 8 })

      Scroll(this.contentScroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight) + 12)
            .width('100%')
            .hitTestBehavior(HitTestMode.None)

          DetailTitleBlock({
            title: this.animeName,
            originalName: this.animeOriginalName,
            airDate: $animeAirDate,
            isWideLayout: true
          })

          this.TabletMetricsSection()
          this.SynopsisSection()
          this.TagSection()

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 8, right: 24 })
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Top)
  }

  private isTabletWideLayout(): boolean {
    return isWideDetailLayout(this.screenWidthVp)
  }

  private getSourceSheetHeight(): Length {
    return this.isTabletWideLayout() ? '92%' : '84%'
  }

  private getSourceSheetWidth(): Dimension {
    if (!this.isTabletWideLayout()) {
      return '100%'
    }
    if (this.screenWidthVp >= 1200) {
      return Math.min(this.screenWidthVp - 64, 1180)
    }
    if (this.screenWidthVp >= 840) {
      return Math.min(this.screenWidthVp - 32, 960)
    }
    return '96%'
  }

  private getSourceSheetType(): SheetType {
    return this.isTabletWideLayout() ? SheetType.CENTER : SheetType.BOTTOM
  }

  @Builder
  private SourceSheetContent() {
    SourceSheet({
      animeName: this.animeName,
      animeOriginalName: this.animeOriginalName,
      animeAliases: this.animeAliases,
      closeSignal: this.sourceSheetCloseSignal,
      preserveOnDisappear: this.preserveSourceSheetOnDisappear,
      restoreSnapshot: this.sourceSheetSnapshot,
      onRoadsReady: (source: PlaybackSource) => {
        this.onRoadsReady(source)
      },
      onSnapshotChanged: (snapshot: SourceSheetSnapshot) => {
        this.sourceSheetSnapshot = snapshot
      }
    })
  }

  @Builder
  private ContentPanel() {
    Column() {
      DetailInfoPanel({
        cover: this.getCoverImageSrc(),
        coverFallback: this.animeCoverFallback,
        bangumiCover: this.animeBangumiCover,
        sharedCover: this.getTransitionCoverSrc(),
        sharedCoverId: this.getSharedCoverIdForRender(),
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
  private TabletMetricsSection() {
    Column() {
      Row() {
        Column() {
          Text(this.animeRatingScore > 0 ? this.animeRatingScore.toFixed(1) : '-')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.rating_star'))
            .maxLines(1)
          Text('Bangumi 评分')
            .fontSize(11)
            .fontColor($r('app.color.text_subtitle'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text(this.animeRank > 0 ? `#${this.animeRank}` : '-')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .maxLines(1)
          Text('排名')
            .fontSize(11)
            .fontColor($r('app.color.text_subtitle'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text(this.animeEps > 0 ? `${this.animeEps} 集` : '未知')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .maxLines(1)
          Text('集数')
            .fontSize(11)
            .fontColor($r('app.color.text_subtitle'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text(this.getVotesText())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .maxLines(1)
          Text('评分人数')
            .fontSize(11)
            .fontColor($r('app.color.text_subtitle'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ left: 8, right: 8, top: 12, bottom: 12 })
      .borderRadius(14)
      .backgroundColor(this.sectionThemeBackground)
      .border({ width: 0.5, color: this.sectionThemeBorder })
    }
    .width('100%')
    .margin({ top: 4, bottom: 8 })
  }

  @Builder
  private SynopsisSection() {
    Column() {
      Text('简介')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .width('100%')
        .margin({ bottom: 14 })

      Column() {
        if (this.isSynopsisSkeletonVisible()) {
          this.SynopsisSkeleton()
        } else {
          Text(this.animeDesc.length > 0 ? this.animeDesc : '暂无简介')
            .fontSize(15)
            .fontWeight(FontWeight.Regular)
            .fontColor(this.animeDesc.length > 0 ? $r('app.color.text_body') : $r('app.color.text_placeholder'))
            .lineHeight(24)
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
      .height(36)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 10 })
    .borderRadius(18)
    .backgroundColor(this.sectionThemeBackground)
    .border({ width: 0.5, color: this.sectionThemeBorder })
    .margin({ top: 10 })
  }

  @Builder
  private TagSection() {
    Column() {
      Text('标签')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .width('100%')
        .margin({ bottom: 16 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        if (this.isTagSkeletonVisible()) {
          this.TagSkeleton()
        } else {
          ForEach(this.tagsExpanded ? this.animeTags : this.animeTags.slice(0, 12), (tag: string) => {
            Row() {
              Text(tag)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_on_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(30)
            .padding({ left: 10, right: 10 })
            .border({ width: 0.5, color: this.getTagThemeBorder() })
            .borderRadius(15)
            .backgroundColor(this.getTagThemeBackground())
            .margin({ right: 10, bottom: 12 })
            .onClick(() => {
              this.openTagSearch(tag)
            })
          }, (tag: string) => tag)

          if (this.animeTags.length > 12) {
            Row() {
              Text(this.tagsExpanded ? '收起' : '更多')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_on_primary'))
            }
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .backgroundColor(this.getTagThemeBackground())
            .border({ width: 0.5, color: this.getTagThemeBorder() })
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
    .padding({ left: 14, right: 14, top: 14, bottom: 2 })
    .borderRadius(18)
    .backgroundColor(this.sectionThemeBackground)
    .border({ width: 0.5, color: this.sectionThemeBorder })
    .margin({ top: 12 })
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
      logger.info('onRoadsReady accepted, push player and preserve source sheet')
      this.openPlayerWithHistory(source, true)
    }
  }

  private async openPlayerWithHistory(source: PlaybackSource, preserveSourceSheet: boolean = false): Promise<void> {
    logger.info('openPlayerWithHistory source=%{public}s roads=%{public}d', source.name, source.roads.length)
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

    logger.info('router.pushUrl to PlayerPage episodeUrl=%{public}s ruleSourceId=%{public}d',
      selected.episode.url.length > 0 ? 'ok' : 'empty', selectedSourceId)
    if (preserveSourceSheet) {
      this.preserveSourceSheetOnDisappear = true
      this.showSourceSheet = true
    }
    const playerParams = new ContinuationPlayerParams()
    playerParams.episodeUrl = selected.episode.url
    playerParams.ruleSourceId = selectedSourceId
    playerParams.animeName = this.animeName
    playerParams.episodeName = selected.episode.name
    playerParams.animeId = animeId
    playerParams.animeCover = this.animeCover
    playerParams.animeUrl = selectedAnimeUrl
    playerParams.sourceId = selectedSourceId
    playerParams.episodesJson = JSON.stringify(source.roads[selected.roadIndex].episodes)
    playerParams.currentEpisodeIndex = selected.episodeIndex
    playerParams.roadsJson = JSON.stringify(source.roads)
    playerParams.selectedRoadIndex = selected.roadIndex
    playerParams.bangumiId = this.bangumiId > 0 ? this.bangumiId : 0
    playerParams.bangumiCover = this.animeBangumiCover
    playerParams.coverFallback = this.animeCoverFallback
    playerParams.animeDesc = this.animeDesc
    playerParams.sourceName = source.name.length > 0 ? source.name : this.sourceName
    playerParams.historyPositionMs = historyPositionMs
    ContinuationState.markPlayer(playerParams, historyPositionMs)
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: playerParams
    }).catch((err: Error) => {
      if (preserveSourceSheet) {
        this.preserveSourceSheetOnDisappear = false
      }
      logger.error('router.pushUrl PlayerPage failed: %{public}s', err.message)
    })
  }

  private markContinuationState(): void {
    ContinuationState.markDetail(this.buildContinuationParams())
  }

  private buildContinuationParams(): ContinuationDetailParams {
    const params = new ContinuationDetailParams()
    params.animeName = this.animeName
    params.animeCover = this.animeCover
    params.animeCoverFallback = this.animeCoverFallback
    params.animeBangumiCover = this.animeBangumiCover
    params.animeDesc = this.animeDesc
    params.animeOriginalName = this.animeOriginalName
    params.animeAirDate = this.animeAirDate
    params.animeRatingScore = this.animeRatingScore
    params.animeRank = this.animeRank
    params.animeTags = JSON.stringify(this.animeTags)
    params.animeVotes = this.animeVotes
    params.animeVotesCount = JSON.stringify(this.animeVotesCount)
    params.animeAirWeekday = this.animeAirWeekday
    params.animeEps = this.animeEps
    params.animeUrl = this.animeUrl
    params.sourceName = this.sourceName
    params.sourceId = this.ruleSourceId
    params.bangumiId = this.bangumiId
    return params
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

  private async toggleCollect(): Promise<void> {
    try {
      const animeItem = this.buildAnimeItem()
      if (CollectType.isFavorite(this.currentCollectType)) {
        await this.collectController.deleteCollect(animeItem)
        this.currentCollectType = CollectType.none
      } else {
        await this.collectController.addCollect(animeItem, CollectType.favorite)
        this.currentCollectType = CollectType.favorite
      }
    } catch (err) {
      logger.error('toggleCollect failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private openTagSearch(rawTag: string): void {
    const tag = rawTag.trim()
    if (tag.length === 0) {
      return
    }
    router.pushUrl({
      url: 'pages/search/SearchPage',
      params: {
        tag: tag,
        searchMode: 1
      }
    })
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
        if (this.animeBangumiCover.length === 0 && detailCover.length > 0) this.animeBangumiCover = BangumiConfig.normalizeImageUrl(detailCover)
        else if (this.animeBangumiCover.length === 0 && subject.bangumiCover.length > 0) this.animeBangumiCover = BangumiConfig.normalizeImageUrl(subject.bangumiCover)
        if (this.animeCover.length === 0 && subject.cover.length > 0) this.animeCover = BangumiConfig.normalizeImageUrl(subject.cover)
        if (this.animeDesc.length === 0 && subject.desc.length > 0) this.animeDesc = subject.desc
        if (this.animeOriginalName.length === 0 && subject.originalName.length > 0) this.animeOriginalName = subject.originalName
        if (this.animeAliases.length === 0 && subject.aliases.length > 0) this.animeAliases = subject.aliases
        if (this.shouldReplaceText(this.animeAirDate) && subject.airDate.length > 0) this.animeAirDate = subject.airDate
        if (this.animeAirWeekday <= 0 && subject.airWeekday > 0) this.animeAirWeekday = subject.airWeekday
        if (this.animeRatingScore <= 0 && subject.ratingScore > 0) this.animeRatingScore = subject.ratingScore
        if (this.animeRank <= 0 && subject.rank > 0) this.animeRank = subject.rank
        if (this.animeEps <= 0 && subject.eps > 0) this.animeEps = subject.eps
        if (subject.tags.length > this.animeTags.length) this.animeTags = subject.tags
        if (this.animeVotes <= 0 && subject.votes > 0) this.animeVotes = subject.votes
        if (this.animeVotesCount.length === 0 && subject.votesCount.length > 0) this.animeVotesCount = subject.votesCount
        logger.info('Detail subject applied: %{public}s eps=%{public}d airDate=%{public}s',
          this.animeName, this.animeEps, this.animeAirDate)
        this.currentCoverImage = this.selectBestCoverImage()
        this.prepareCachedCover(this.buildCoverKey())
        this.refreshSectionTheme()
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

  private refreshSectionTheme(): void {
    const urls = this.getThemeSourceUrls()
    const key = urls.join('|')
    if (key.length === 0) {
      this.clearSectionTheme()
      return
    }
    if (key === this.sectionThemeKey && this.sectionThemeBackground !== '#00000000') {
      return
    }
    this.sectionThemeKey = key
    ThemeColorStore.getInstance().getThemeColor(urls).then((color: string) => {
      if (this.sectionThemeKey !== key) {
        return
      }
      if (color.length === 0) {
        this.clearSectionTheme()
        return
      }
      this.sectionThemeBackground = this.withAlpha(color, '12')
      this.sectionThemeBorder = this.withAlpha(color, '28')
      this.tagThemeBackground = this.withAlpha(color, '1C')
      this.tagThemeBorder = this.withAlpha(color, '34')
    }).catch((err: Error) => {
      logger.warn('Refresh detail section theme failed: %{public}s', err.message)
    })
  }

  private clearSectionTheme(): void {
    this.sectionThemeBackground = '#00000000'
    this.sectionThemeBorder = '#00000000'
    this.tagThemeBackground = ''
    this.tagThemeBorder = ''
  }

  private getThemeSourceUrls(): string[] {
    const urls: string[] = []
    if (this.animeBangumiCover.trim().length > 0) {
      urls.push(this.animeBangumiCover)
    }
    if (this.animeCover.trim().length > 0) {
      urls.push(this.animeCover)
    }
    if (this.animeCoverFallback.trim().length > 0) {
      urls.push(this.animeCoverFallback)
    }
    return urls
  }

  private getTagThemeBackground(): ResourceColor {
    return $r('app.color.accent_blue')
  }

  private getTagThemeBorder(): ResourceColor {
    return $r('app.color.accent_blue')
  }

  private withAlpha(color: string, alpha: string): string {
    if (color.length !== 7 || !color.startsWith('#') || alpha.length !== 2) {
      return '#00000000'
    }
    return `#${alpha}${color.substring(1)}`
  }

  private shouldReplaceText(value: string): boolean {
    const trimmed = value.trim()
    return trimmed.length === 0 || trimmed === '-' || trimmed === '未知' || trimmed === 'null' || trimmed === 'undefined'
  }

  private buildCollectIcon(): HdsNavigationIconOptions {
    return {
      icon: CollectType.isFavorite(this.currentCollectType) ?
        CollectType.getIcon(this.currentCollectType) : $r('sys.symbol.heart'),
      label: CollectType.isFavorite(this.currentCollectType) ? '已收藏' : '收藏',
      action: () => {
        this.toggleCollect()
      }
    }
  }

  private buildDetailMenu(): HdsNavigationMenuContentOptions {
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
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
    const collectIconColor: ResourceColor = CollectType.isFavorite(this.currentCollectType) ?
      $r('app.color.status_error') : $r('sys.color.icon_primary')
    if (style.originalStyle?.contentStyle?.menuStyle) {
      style.originalStyle.contentStyle.menuStyle.iconColor = collectIconColor
    }
    if (style.scrollEffectStyle?.contentStyle?.menuStyle) {
      style.scrollEffectStyle.contentStyle.menuStyle.iconColor = collectIconColor
    }
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

  private selectBestCoverImage(): string {
    if (this.animeBangumiCover.length > 0) {
      return this.animeBangumiCover
    }
    if (this.animeCover.length > 0) {
      return this.animeCover
    }
    return this.animeCoverFallback
  }

  private getCoverImageSrc(): string {
    return this.currentCoverImage.length > 0 ? this.currentCoverImage : ''
  }

  private getTransitionCoverSrc(): string {
    if (this.transitionCover.length > 0) {
      return this.transitionCover
    }
    return this.getCoverImageSrc()
  }

  private getSharedCoverIdForRender(): string {
    return this.sharedCoverId
  }

  private tryNextCoverImage(): void {
    const urls = this.buildCoverUrls()
    const currentIndex = urls.indexOf(this.currentCoverImage)
    if (currentIndex >= 0 && currentIndex + 1 < urls.length) {
      this.currentCoverImage = urls[currentIndex + 1]
      this.prepareCachedCover(this.buildCoverKey())
      return
    }
    if (this.currentCoverImage.startsWith('file://') || this.currentCoverImage.startsWith('/')) {
      this.currentCoverImage = this.selectBestCoverImage()
      this.prepareCachedCover(this.buildCoverKey())
      return
    }
    this.currentCoverImage = ''
  }

  private buildCoverKey(): string {
    return `${this.animeBangumiCover}|${this.animeCover}|${this.animeCoverFallback}|${this.bangumiId}`
  }

  private buildCoverUrls(): string[] {
    const urls: string[] = []
    this.appendCoverUrl(urls, this.animeBangumiCover)
    this.appendCoverUrl(urls, this.animeCover)
    this.appendCoverUrl(urls, this.animeCoverFallback)
    const subjectImageUrls = BangumiConfig.getSubjectImageUrls(this.bangumiId)
    for (let i = 0; i < subjectImageUrls.length; i++) {
      this.appendCoverUrl(urls, subjectImageUrls[i])
    }
    return urls
  }

  private appendCoverUrl(urls: string[], raw: string): void {
    const url = BangumiConfig.normalizeImageUrl(raw)
    if (url.length === 0 || urls.indexOf(url) >= 0) {
      return
    }
    urls.push(url)
  }

  private async prepareCachedCover(expectedKey: string): Promise<void> {
    const urls = this.buildCoverUrls()
    if (urls.length === 0 || this.coverCacheRequestKey === expectedKey) {
      return
    }
    this.coverCacheRequestKey = expectedKey
    try {
      const localUri = await ImageCacheStore.getInstance().getCachedImageUri(urls)
      if (this.buildCoverKey() === expectedKey && localUri.length > 0) {
        this.currentCoverImage = localUri
      }
    } catch (err) {
      logger.warn('Detail cover cache failed: %{public}s',
        err instanceof Error ? err.message : String(err))
    } finally {
      if (this.coverCacheRequestKey === expectedKey) {
        this.coverCacheRequestKey = ''
      }
    }
  }

  private getVotesText(): string {
    if (this.animeVotes <= 0) {
      return '-'
    }
    if (this.animeVotes >= 100000000) {
      return `${this.formatCompactNumber(this.animeVotes / 100000000)}亿`
    }
    if (this.animeVotes >= 10000) {
      return `${this.formatCompactNumber(this.animeVotes / 10000)}万`
    }
    return `${this.animeVotes}`
  }

  private formatCompactNumber(value: number): string {
    const fixed = value.toFixed(1)
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed
  }

}

@Entry
@Component
struct DetailPage {
  build() {
    Column() {
      DetailPageContent()
    }
    .width('100%')
    .height('100%')
  }
}
