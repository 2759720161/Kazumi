import { AnimeItem } from '../../models/AnimeItem'
import { router } from '@kit.ArkUI'
import { ImageCacheStore } from '../../store/ImageCacheStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('TimelineAnimeCard')

@Component
export struct TimelineAnimeCard {
  @Prop @Watch('onAnimeItemChanged') animeItem: AnimeItem = new AnimeItem()
  @State currentCover: string = ''
  @State coverKey: string = ''
  @State hasCoverError: boolean = false
  @State isPressed: boolean = false

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
    this.currentCover = ''
    this.hasCoverError = false
    this.prepareCachedCover(this.coverKey)
  }

  build() {
    Row() {
      Stack() {
        Image(this.getCoverSource())
          .draggable(false)
          .width(92)
          .height(132)
          .objectFit(this.currentCover.length > 0 && !this.hasCoverError ? ImageFit.Cover : ImageFit.Contain)
          .borderRadius(10)
          .alt($r('app.media.ic_placeholder'))
          .onError(() => {
            const urlPrefix = this.currentCover.length > 120 ?
              this.currentCover.substring(0, 120) : this.currentCover
            logger.warn('Timeline cover load failed: %{public}s', urlPrefix)
            this.tryNextCover()
          })
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
      router.pushUrl({
        url: 'pages/detail/DetailPage',
        params: {
          animeName: this.animeItem.name,
          animeCover: this.animeItem.cover,
          animeCoverFallback: this.animeItem.coverFallback,
          animeBangumiCover: this.animeItem.bangumiCover,
          animeDesc: this.animeItem.desc,
          animeOriginalName: this.animeItem.originalName,
          animeAirDate: this.animeItem.airDate,
          animeRatingScore: this.animeItem.ratingScore,
          animeRank: this.animeItem.rank,
          animeTags: JSON.stringify(this.animeItem.tags),
          animeVotes: this.animeItem.votes,
          animeVotesCount: JSON.stringify(this.animeItem.votesCount),
          animeAirWeekday: this.animeItem.airWeekday,
          animeEps: this.animeItem.eps,
          animeUrl: this.animeItem.url,
          sourceName: this.animeItem.sourceName,
          sourceId: this.animeItem.sourceId,
          bangumiId: this.animeItem.bangumiId
        }
      })
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
  }

  private getCoverSource(): ResourceStr {
    if (this.currentCover.length > 0 && !this.hasCoverError) {
      return this.currentCover
    }
    return $r('app.media.ic_placeholder')
  }

  private selectBestCover(): string {
    return this.animeItem.getGridCover()
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
    return `${this.animeItem.coverCommon}|${this.animeItem.coverMedium}|${this.animeItem.bangumiCover}|${this.animeItem.cover}|${this.animeItem.coverFallback}`
  }

  private onAnimeItemChanged(): void {
    const nextKey = this.buildCoverKey()
    if (nextKey === this.coverKey) {
      return
    }
    this.coverKey = nextKey
    this.currentCover = ''
    this.hasCoverError = false
    this.prepareCachedCover(nextKey)
  }

  private async prepareCachedCover(expectedKey: string): Promise<void> {
    const urls: string[] = this.buildCoverUrls()
    if (urls.length === 0) {
      return
    }

    const localUri = await ImageCacheStore.getInstance().getCachedImageUri(urls)
    if (this.coverKey !== expectedKey) {
      return
    }
    if (localUri.length > 0) {
      this.currentCover = localUri
      this.hasCoverError = false
    } else if (this.coverKey === expectedKey) {
      this.currentCover = this.selectBestCover()
      this.hasCoverError = false
    }
  }

  private buildCoverUrls(): string[] {
    const urls: string[] = []
    this.pushCoverUrl(urls, this.animeItem.coverCommon)
    this.pushCoverUrl(urls, this.animeItem.coverMedium)
    this.pushCoverUrl(urls, this.animeItem.bangumiCover)
    this.pushCoverUrl(urls, this.animeItem.cover)
    this.pushCoverUrl(urls, this.animeItem.coverFallback)
    return urls
  }

  private pushCoverUrl(urls: string[], url: string): void {
    if (url.length === 0) {
      return
    }
    const compactUrl = this.compactBangumiCoverUrl(url)
    if (urls.indexOf(compactUrl) < 0) {
      urls.push(compactUrl)
    }
    if (compactUrl !== url && urls.indexOf(url) < 0) {
      urls.push(url)
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

  private tryNextCover(): void {
    if (this.currentCover === this.animeItem.coverCommon && this.animeItem.coverMedium.length > 0) {
      this.currentCover = this.animeItem.coverMedium
      this.hasCoverError = false
      return
    }
    if ((this.currentCover === this.animeItem.coverCommon || this.currentCover === this.animeItem.coverMedium) &&
      this.animeItem.bangumiCover.length > 0) {
      this.currentCover = this.animeItem.bangumiCover
      this.hasCoverError = false
      return
    }
    if (this.currentCover !== this.animeItem.cover && this.animeItem.cover.length > 0) {
      this.currentCover = this.animeItem.cover
      this.hasCoverError = false
      return
    }
    if (this.currentCover !== this.animeItem.coverFallback && this.animeItem.coverFallback.length > 0) {
      this.currentCover = this.animeItem.coverFallback
      this.hasCoverError = false
      return
    }
    this.currentCover = ''
    this.hasCoverError = true
  }
}
