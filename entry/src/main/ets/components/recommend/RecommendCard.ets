import { RecommendCardModel } from '../../models/RecommendCardModel'
import { router } from '@kit.ArkUI'

@Component
export struct RecommendCard {
  @Prop item: RecommendCardModel = new RecommendCardModel()
  @Prop showRank: boolean = false
  @Prop cardWidth: number = 112

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.item.getGridCover().length > 0 ? this.item.getGridCover() : $r('app.media.ic_placeholder'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 12, topRight: 12 })
          .alt($r('app.media.ic_placeholder'))

        if (this.showRank && this.item.rank > 0) {
          Text('TOP ' + this.item.rank.toString())
            .fontSize(10)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius({ topLeft: 12, bottomRight: 8 })
            .backgroundColor($r('app.color.accent_blue'))
        }

      }
      .width('100%')
      .height(this.getPosterHeight())
      .clip(true)
      .borderRadius({ topLeft: 12, topRight: 12 })

      Column() {
        Text(this.item.title)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%')
          .height(32)
          .lineHeight(16)
      }
      .width('100%')
      .height(44)
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(this.getCardHeight())
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .clip(true)
    .onClick(() => {
      this.navigateToDetail()
    })
  }

  private navigateToDetail(): void {
    router.pushUrl({
      url: 'pages/detail/DetailPage',
      params: {
        animeName: this.item.title,
        animeCover: this.item.cover,
        animeCoverFallback: this.item.coverFallback,
        animeBangumiCover: this.item.bangumiCover,
        animeDesc: this.item.summary,
        animeOriginalName: this.item.originalTitle,
        animeAirDate: this.item.date,
        animeRatingScore: this.item.score,
        animeRank: this.item.rank,
        animeTags: JSON.stringify(this.item.tags),
        animeVotes: this.item.votes,
        animeVotesCount: JSON.stringify(this.item.votesCount),
        animeAirWeekday: this.item.airWeekday,
        animeEps: this.item.eps,
        animeUrl: this.item.url,
        sourceName: this.item.sourceName,
        sourceId: this.item.sourceId,
        bangumiId: this.item.bangumiId
      }
    })
  }

  private getPosterHeight(): number {
    return Math.round(this.cardWidth * 4 / 3)
  }

  private getCardHeight(): number {
    return this.getPosterHeight() + 44
  }
}
