import { RecommendCardModel } from '../../models/RecommendCardModel'
import { router } from '@kit.ArkUI'

@Component
export struct HeroBanner {
  @State currentIndex: number = 0
  @Prop items: RecommendCardModel[] = []
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
      .height(320)

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
    .height(320)
  }

  @Builder
  private HeroSlide(item: RecommendCardModel) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(item.getHeroBackdrop().length > 0 ? item.getHeroBackdrop() : $r('app.media.ic_placeholder'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .blur(12)
        .alt($r('app.media.ic_placeholder'))

      Column() {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })

      Column() {
        Row().width('100%').height(80)

        Column({ space: 8 }) {
          Text(item.title)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('60%')

          if (item.summary.length > 0) {
            Text(item.summary.length > 50 ? item.summary.substring(0, 50) + '...' : item.summary)
              .fontSize(13)
              .fontColor('#CCFFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('60%')
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

            Button('收藏')
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
        .padding({ left: 20, right: 16 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(320)
    .onClick(() => {
      this.navigateToDetail(item)
    })
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
