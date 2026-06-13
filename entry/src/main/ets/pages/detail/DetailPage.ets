import { FavoriteStore } from '../../store/FavoriteStore'
import { FavoriteRecord } from '../../models/FavoriteRecord'
import { CoverSection } from '../../components/detail/CoverSection'
import { SourceSheet } from '../../components/detail/SourceSheet'
import { BangumiApi } from '../../core/api/BangumiApi'
import { BangumiConfig } from '../../core/api/BangumiConfig'
import { PlaybackSource } from '../../models/PlaybackRoad'
import { Logger } from '../../utils/Logger'
import { LengthMetrics, router } from '@kit.ArkUI'

const logger = new Logger('DetailPage')
const COLLAPSED_SYNOPSIS_TEXT_HEIGHT: number = 198
const COLLAPSED_SYNOPSIS_ACTION_HEIGHT: number = 64
const COLLAPSED_TAGS_HEIGHT: number = 320

@Entry
@Component
export struct DetailPage {
  @State animeName: string = ''
  @State animeCover: string = ''
  @State animeCoverFallback: string = ''
  @State animeBangumiCover: string = ''
  @State animeDesc: string = ''
  @State animeOriginalName: string = ''
  @State animeAirDate: string = ''
  @State animeRatingScore: number = 0
  @State animeRank: number = 0
  @State animeTags: string[] = []
  @State animeEps: number = 0
  @State sourceName: string = ''
  @State isFavorite: boolean = false
  @State showSourceSheet: boolean = false
  @State sourceSheetCloseSignal: number = 0
  @State bangumiId: number = -1
  @State descExpanded: boolean = false
  @State animeVotes: number = 0
  @State animeVotesCount: number[] = []
  @State animeAirWeekday: number = 0
  @State tagsExpanded: boolean = false
  @State isSubjectDetailLoading: boolean = false
  private animeUrl: string = ''
  private ruleSourceId: number = -1
  private favoriteStore: FavoriteStore = new FavoriteStore()

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
    }
    this.loadDetail()
    this.fetchSubjectDetail()
  }

  build() {
    Column() {
      Stack() {
        Scroll() {
          Column() {
            CoverSection({
              cover: this.animeCover,
              coverFallback: this.animeCoverFallback,
              bangumiCover: this.animeBangumiCover,
              title: this.animeName,
              originalName: this.animeOriginalName,
              ratingScore: this.animeRatingScore,
              rank: this.animeRank,
              airDate: this.animeAirDate,
              votes: this.animeVotes,
              eps: this.animeEps,
              isFavorite: this.isFavorite,
              onFavoriteToggle: () => {
                this.toggleFavorite()
              },
              onBack: () => {
                router.back()
              },
              onOpenExternal: this.bangumiId > 0 ? () => {
                this.openBangumiPage()
              } : undefined
            })

            this.SynopsisSection()
            this.TagSection()

            Row()
              .height(96)
          }
        }
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        this.FloatingWatchButton()
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_green'))
    .ignoreLayoutSafeArea()
    .bindSheet($$this.showSourceSheet, this.SourceSheetContent(), {
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
  }

  @Builder
  private FloatingWatchButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(36)
        .fontColor([$r('app.color.text_title_green')])
    }
    .width(64)
    .height(64)
    .borderRadius(32)
    .backgroundColor($r('app.color.button_floating_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.border_subtle') })
    .shadow({ radius: 22, color: $r('app.color.shadow_button_accent'), offsetY: 7 })
    .position({ x: '78%', y: '82%' })
    .onClick(() => {
      this.showSourceSheet = true
    })
  }

  @Builder
  private SourceSheetContent() {
    SourceSheet({
      animeName: this.animeName,
      animeOriginalName: this.animeOriginalName,
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
  private SynopsisSection() {
    Column() {
      Text('简介')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title_green'))
        .width('100%')
        .margin({ bottom: 18 })

      Column() {
        if (this.isSynopsisSkeletonVisible()) {
          this.SynopsisSkeleton()
        } else {
          Text(this.animeDesc.length > 0 ? this.animeDesc : '暂无简介')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.animeDesc.length > 0 ? $r('app.color.text_body_green') : $r('app.color.text_placeholder_green'))
            .lineHeight(33)
            .width('100%')
            .maxLines(this.descExpanded ? 50 : 6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .height(this.descExpanded ? undefined : COLLAPSED_SYNOPSIS_TEXT_HEIGHT)
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row() {
        Blank()

        if (this.animeDesc.length > 120) {
          Text(this.descExpanded ? '收起' : '加载更多')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.rating_star'))
            .padding({ left: 16, right: 16, top: 9, bottom: 9 })
            .borderRadius(19)
            .backgroundColor($r('app.color.surface_button_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 3 })
            .textAlign(TextAlign.End)
            .onClick(() => {
              this.descExpanded = !this.descExpanded
            })
        }
      }
      .height(COLLAPSED_SYNOPSIS_ACTION_HEIGHT)
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.End)
      .padding({ top: 26 })
      .width('100%')
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 22, bottom: 0 })
  }

  @Builder
  private TagSection() {
    Column() {
      Text('标签')
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title_green'))
        .width('100%')
        .margin({ bottom: 20 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        if (this.isTagSkeletonVisible()) {
          this.TagSkeleton()
        } else {
          ForEach(this.tagsExpanded ? this.animeTags : this.animeTags.slice(0, 12), (tag: string) => {
            Row() {
              Text(tag)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_title_green'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(46)
            .padding({ left: 20, right: 20 })
            .border({ width: 1, color: $r('app.color.border_tag') })
            .borderRadius(9)
            .margin({ right: 10, bottom: 14 })
          }, (tag: string) => tag)

          if (this.animeTags.length > 12) {
            Row() {
              Text(this.tagsExpanded ? '收起' : '更多')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.rating_star'))
            }
            .height(46)
            .padding({ left: 20, right: 20 })
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .borderRadius(9)
            .backgroundColor($r('app.color.surface_button_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 3 })
            .margin({ right: 10, bottom: 14 })
            .onClick(() => {
              this.tagsExpanded = !this.tagsExpanded
            })
          }
        }
      }
      .width('100%')
      .height(this.tagsExpanded ? undefined : COLLAPSED_TAGS_HEIGHT)
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 0, bottom: 0 })
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
      let roadsJson = JSON.stringify(source.roads)
      router.pushUrl({
        url: 'pages/detail/EpisodePage',
        params: {
          sourceName: source.name,
          animeName: this.animeName,
          animeCover: this.animeCover,
          sourceId: source.sourceId,
          animeUrl: source.animeUrl,
          roadsJson: roadsJson,
          bangumiId: this.bangumiId > 0 ? this.bangumiId : 0
        }
      })
    }
  }

  private async loadDetail(): Promise<void> {
    try {
      const animeId = `${this.ruleSourceId}_${this.animeUrl}`
      this.isFavorite = await this.favoriteStore.isFavorite(animeId)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Load favorite state failed: %{public}s', msg)
    }
  }

  private async toggleFavorite(): Promise<void> {
    try {
      const animeId = `${this.ruleSourceId}_${this.animeUrl}`
      if (this.isFavorite) {
        await this.favoriteStore.remove(animeId)
        this.isFavorite = false
      } else {
        const record = new FavoriteRecord()
        record.animeId = animeId
        record.animeName = this.animeName
        record.animeCover = this.animeCover
        record.animeDesc = this.animeDesc
        record.animeUrl = this.animeUrl
        record.sourceName = this.sourceName
        record.sourceId = this.ruleSourceId
        await this.favoriteStore.add(record)
        this.isFavorite = true
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Toggle favorite failed: %{public}s', msg)
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
        if (this.animeAirDate.length === 0 && subject.airDate.length > 0) this.animeAirDate = subject.airDate
        if (this.animeAirWeekday <= 0 && subject.airWeekday > 0) this.animeAirWeekday = subject.airWeekday
        if (this.animeRatingScore <= 0 && subject.ratingScore > 0) this.animeRatingScore = subject.ratingScore
        if (this.animeRank <= 0 && subject.rank > 0) this.animeRank = subject.rank
        if (this.animeEps <= 0 && subject.eps > 0) this.animeEps = subject.eps
        if (this.animeTags.length === 0 && subject.tags.length > 0) this.animeTags = subject.tags
        if (this.animeVotes <= 0 && subject.votes > 0) this.animeVotes = subject.votes
        if (this.animeVotesCount.length === 0 && subject.votesCount.length > 0) this.animeVotesCount = subject.votesCount
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

  private openBangumiPage(): void {
    if (this.bangumiId > 0) {
      const url = BangumiConfig.getSubjectWebUrl(this.bangumiId)
      logger.info('Open Bangumi page: %{public}s', url)
    }
  }

}
