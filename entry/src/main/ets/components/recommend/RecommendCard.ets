import { RecommendCardModel } from '../../models/RecommendCardModel'
import { router } from '@kit.ArkUI'

@Component
export struct RecommendCard {
  @Prop item: RecommendCardModel = new RecommendCardModel()
  @Prop showRank: boolean = false
  @Prop showScore: boolean = true

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.item.getGridCover().length > 0 ? this.item.getGridCover() : $r('app.media.ic_placeholder'))
          .width('100%')
          .aspectRatio(3 / 4)
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

        if (this.showScore && this.item.score > 0) {
          Row({ space: 2 }) {
            Text('\u2605')
              .fontSize(9)
              .fontColor('#FFD700')
            Text(this.item.getScoreText())
              .fontSize(11)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor('#B3000000')
          .position({ x: '68%', y: 4 })
        }
      }
      .width('100%')
      .aspectRatio(3 / 4)
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
          .lineHeight(16)

        if (this.item.getMetaText().length > 0) {
          Text(this.item.getMetaText())
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .alignItems(HorizontalAlign.Start)
    }
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
}
