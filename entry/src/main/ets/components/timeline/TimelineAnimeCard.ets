import { AnimeItem } from '../../models/AnimeItem'
import { BangumiConfig } from '../../core/api/BangumiConfig'
import { CachedRemoteImage } from '../common/CachedRemoteImage'
import { DetailNavigationParams, navigateToDetail } from '../../utils/DetailNavigation'

@Component
export struct TimelineAnimeCard {
  @Prop @Watch('onAnimeItemChanged') animeItem: AnimeItem = new AnimeItem()
  @State coverKey: string = ''
  @State isPressed: boolean = false

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
  }

  build() {
    Row() {
      Stack() {
        CachedRemoteImage({
          source: this.getPrimaryCoverUrl(),
          sources: this.buildCoverUrls(),
          sharedId: this.getSharedCoverId(),
          cornerRadius: 10
        })
          .borderRadius(10)
          .clip(true)
      }
      .width(92)
      .height(132)

      Column() {
        Text(this.animeItem.name.length > 0 ? this.animeItem.name : '未知番剧')
          .fontSize(16)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .lineHeight(22)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.buildSubtitle())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .margin({ top: 4 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Blank()
          .layoutWeight(1)

        Row() {
          if (this.animeItem.ratingScore > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(13)
                .fontColor([$r('app.color.rating_star')])
              Text(this.animeItem.ratingScore.toFixed(1))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 2 })
            }
            .margin({ right: 16 })
          }

          if (this.animeItem.rank > 0) {
            Text(`#${this.animeItem.rank}`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent_blue'))
              .margin({ right: 16 })
          }

          if (this.animeItem.votes > 0) {
            Text(`${this.animeItem.votes}人评分`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.animeItem.ratingScore <= 0 && this.animeItem.rank <= 0 && this.animeItem.votes <= 0) {
            Text(this.buildMetaText())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(132)
      .margin({ left: 14 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 6, color: $r('app.color.shadow_surface'), offsetY: 2 })
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150 })
    .onClick(() => {
      const params = new DetailNavigationParams()
      params.animeName = this.animeItem.name
      params.animeCover = this.animeItem.cover
      params.animeCoverFallback = this.animeItem.coverFallback
      params.animeBangumiCover = this.animeItem.bangumiCover
      params.animeDesc = this.animeItem.desc
      params.animeOriginalName = this.animeItem.originalName
      params.animeAirDate = this.animeItem.airDate
      params.animeRatingScore = this.animeItem.ratingScore
      params.animeRank = this.animeItem.rank
      params.animeTags = JSON.stringify(this.animeItem.tags)
      params.animeVotes = this.animeItem.votes
      params.animeVotesCount = JSON.stringify(this.animeItem.votesCount)
      params.animeAirWeekday = this.animeItem.airWeekday
      params.animeEps = this.animeItem.eps
      params.animeUrl = this.animeItem.url
      params.sourceName = this.animeItem.sourceName
      params.sourceId = this.animeItem.sourceId
      params.bangumiId = this.animeItem.bangumiId
      params.sharedCoverId = this.getSharedCoverId()
      params.transitionCover = this.getPrimaryCoverUrl()
      navigateToDetail(params)
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
  }

  private buildSubtitle(): string {
    if (this.animeItem.desc.length > 0) {
      return this.animeItem.desc
    }
    if (this.animeItem.originalName.length > 0 && this.animeItem.originalName !== this.animeItem.name) {
      return this.animeItem.originalName
    }
    if (this.animeItem.airDate.length > 0) {
      return `放送开始 ${this.animeItem.airDate}`
    }
    return '条目信息同步中'
  }

  private buildMetaText(): string {
    const parts: string[] = []
    if (this.animeItem.airDate.length > 0) {
      parts.push(this.animeItem.airDate)
    }
    if (this.animeItem.eps > 0) {
      parts.push(`${this.animeItem.eps} 集`)
    }
    if (parts.length === 0) {
      return 'Bangumi 时间表'
    }
    return parts.join(' · ')
  }

  private buildCoverKey(): string {
    return `${this.animeItem.bangumiId}|${this.animeItem.coverCommon}|${this.animeItem.coverMedium}|${this.animeItem.bangumiCover}|${this.animeItem.cover}|${this.animeItem.coverFallback}`
  }

  private getSharedCoverId(): string {
    const subjectId = this.animeItem.bangumiId > 0 ? this.animeItem.bangumiId.toString() : this.animeItem.name
    return 'timeline-cover-' + subjectId
  }

  private onAnimeItemChanged(): void {
    const nextKey = this.buildCoverKey()
    if (nextKey === this.coverKey) {
      return
    }
    this.coverKey = nextKey
  }

  private buildCoverUrls(): string[] {
    const urls: string[] = []
    this.pushCoverUrl(urls, this.animeItem.coverCommon)
    this.pushCoverUrl(urls, this.animeItem.coverMedium)
    this.pushCoverUrl(urls, this.animeItem.bangumiCover)
    this.pushCoverUrl(urls, this.animeItem.cover)
    this.pushCoverUrl(urls, this.animeItem.coverFallback)
    const subjectImageUrls = BangumiConfig.getSubjectImageUrls(this.animeItem.bangumiId)
    for (let i = 0; i < subjectImageUrls.length; i++) {
      this.pushCoverUrl(urls, subjectImageUrls[i])
    }
    return urls
  }

  private pushCoverUrl(urls: string[], url: string): void {
    const normalizedUrl = BangumiConfig.normalizeImageUrl(url)
    if (normalizedUrl.length === 0) {
      return
    }
    const compactUrl = this.compactBangumiCoverUrl(normalizedUrl)
    if (urls.indexOf(compactUrl) < 0) {
      urls.push(compactUrl)
    }
    if (compactUrl !== normalizedUrl && urls.indexOf(normalizedUrl) < 0) {
      urls.push(normalizedUrl)
    }
  }

  private compactBangumiCoverUrl(url: string): string {
    if (url.indexOf('/r/400/') >= 0) {
      return url.replace('/r/400/', '/r/200/')
    }
    if (url.indexOf('/r/800/') >= 0) {
      return url.replace('/r/800/', '/r/200/')
    }
    return url
  }

  private getPrimaryCoverUrl(): string {
    const urls = this.buildCoverUrls()
    return urls.length > 0 ? urls[0] : ''
  }
}
