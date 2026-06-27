import { RecommendCardModel } from '../../models/RecommendCardModel'
import { router } from '@kit.ArkUI'

@Component
export struct HeroBanner {
  @State currentIndex: number = 0
  @Prop items: RecommendCardModel[] = []
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  private swiperController: SwiperController = new SwiperController()
  private autoPlayInterval: number = 5000

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Swiper(this.swiperController) {
        ForEach(this.items, (item: RecommendCardModel, index?: number) => {
          this.HeroSlide(item)
        }, (item: RecommendCardModel, index?: number) => 'hero_' + item.id.toString() + '_' + (index ?? 0).toString())
      }
      .autoPlay(this.items.length > 1)
      .interval(this.autoPlayInterval)
      .indicator(false)
      .loop(this.items.length > 1)
      .onChange((index: number) => {
        this.currentIndex = index
      })
      .width('100%')
      .height(this.getHeroHeight())

      Row({ space: 6 }) {
        ForEach(this.items, (_: RecommendCardModel, index?: number) => {
          Row()
            .width((index ?? 0) === this.currentIndex ? 20 : 8)
            .height(4)
            .borderRadius(2)
            .backgroundColor((index ?? 0) === this.currentIndex ? $r('sys.color.icon_primary') : $r('app.color.text_hint'))
            .animation({ duration: 200, curve: Curve.EaseOut })
        }, (_: RecommendCardModel, index?: number) => 'dot_' + (index ?? 0).toString())
      }
      .margin({ bottom: 16, left: 20 })
    }
    .width('100%')
    .height(this.getHeroHeight())
  }

  @Builder
  private HeroSlide(item: RecommendCardModel) {
    Stack() {
      Image(item.getHeroBackdrop().length > 0 ? item.getHeroBackdrop() : $r('app.media.ic_placeholder'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .blur(20)
        .alt($r('app.media.ic_placeholder'))

      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

      Row() {
        Column({ space: 8 }) {
          Row().width('100%').height(60)

          Text(item.title)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .lineHeight(28)

          if (item.summary.length > 0) {
            Text(item.summary.length > 60 ? item.summary.substring(0, 60) + '...' : item.summary)
              .fontSize(13)
              .fontColor('#CCFFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .lineHeight(18)
          }

          Row({ space: 8 }) {
            if (item.score > 0) {
              Row({ space: 4 }) {
                Text('\u2605')
                  .fontSize(12)
                  .fontColor('#FFD700')
                Text(item.getScoreText())
                  .fontSize(13)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Medium)
              }
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(10)
              .backgroundColor('#4D000000')
            }

            if (item.rank > 0) {
              Text('Rank ' + item.getRankText())
                .fontSize(11)
                .fontColor('#CCFFFFFF')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .backgroundColor('#4D000000')
            }

            Text(item.getMetaText())
              .fontSize(11)
              .fontColor('#CCFFFFFF')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(10)
              .backgroundColor('#4D000000')
          }

          if (item.tags.length > 0) {
            Text(item.getTagText())
              .fontSize(11)
              .fontColor('#99FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Row({ space: 10 }) {
            Button('查看详情')
              .height(32)
              .padding({ left: 18, right: 18 })
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.accent_blue'))
              .borderRadius(16)
              .onClick(() => {
                this.navigateToDetail(item)
              })

            Button('详情')
              .height(32)
              .padding({ left: 18, right: 18 })
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor('#4D000000')
              .borderRadius(16)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .onClick(() => {
                this.navigateToDetail(item)
              })
          }
          .margin({ top: 4 })
        }
        .width(this.getTextWidth())
        .padding({ left: 20, right: 12 })
        .justifyContent(FlexAlign.Start)

        Column() {
          Image(item.getGridCover().length > 0 ? item.getGridCover() : $r('app.media.ic_placeholder'))
            .width('100%')
            .aspectRatio(3 / 4)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
            .shadow({ radius: 20, color: '#4D000000', offsetY: 8 })
            .alt($r('app.media.ic_placeholder'))
        }
        .width(this.getPosterWidth())
        .padding({ right: 16 })
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(this.getHeroHeight())
    .onClick(() => {
      this.navigateToDetail(item)
    })
  }

  private getHeroHeight(): number {
    if (this.screenWidthVp >= 840) {
      return 360
    } else if (this.screenWidthVp >= 600) {
      return 340
    }
    return 300
  }

  private getTextWidth(): string {
    if (this.screenWidthVp >= 600) {
      return '58%'
    }
    return '72%'
  }

  private getPosterWidth(): string {
    if (this.screenWidthVp >= 600) {
      return '42%'
    }
    return '28%'
  }

  private navigateToDetail(item: RecommendCardModel): void {
    router.pushUrl({
      url: 'pages/detail/DetailPage',
      params: {
        animeName: item.title,
        animeCover: item.cover,
        animeCoverFallback: item.coverFallback,
        animeBangumiCover: item.bangumiCover,
        animeDesc: item.summary,
        animeOriginalName: item.originalTitle,
        animeAirDate: item.date,
        animeRatingScore: item.score,
        animeRank: item.rank,
        animeTags: JSON.stringify(item.tags),
        animeVotes: item.votes,
        animeVotesCount: JSON.stringify(item.votesCount),
        animeAirWeekday: item.airWeekday,
        animeEps: item.eps,
        animeUrl: item.url,
        sourceName: item.sourceName,
        sourceId: item.sourceId,
        bangumiId: item.bangumiId
      }
    })
  }
}
