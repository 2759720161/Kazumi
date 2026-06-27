import { AnimeItem } from '../../models/AnimeItem'
import { router } from '@kit.ArkUI'

@Component
export struct TimelineAnimeCard {
  @Prop animeItem: AnimeItem = new AnimeItem()

  build() {
    Row() {
      Stack() {
        Image(this.animeItem.getGridCover())
          .width(100)
          .height(143)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .alt($r('app.media.ic_placeholder'))
      }
      .width(100)
      .height(143)

      Column() {
        Text(this.animeItem.name.length > 0 ? this.animeItem.name : '未知番剧')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .lineHeight(22)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.animeItem.desc.length > 0 ? this.animeItem.desc : this.animeItem.airDate)
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
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(143)
      .margin({ left: 14 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
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
  }
}