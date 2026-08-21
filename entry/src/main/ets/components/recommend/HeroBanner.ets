import { RecommendCardModel } from '../../models/RecommendCardModel'
import { buildRecommendDetailParams } from '../../utils/AnimeNavigation'
import { navigateToDetail } from '../../utils/DetailNavigation'
import { CachedRemoteImage } from '../common/CachedRemoteImage'

@Component
export struct HeroBanner {
  @State currentIndex: number = 0
  @Prop items: RecommendCardModel[] = []
  @Prop topInset: number = 0
  @Prop version: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  private swiperController: SwiperController = new SwiperController()
  private autoPlayInterval: number = 5000

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Swiper(this.swiperController) {
        ForEach(this.items, (item: RecommendCardModel, index?: number) => {
          this.HeroSlide(item)
        }, (item: RecommendCardModel, index?: number) => 'hero_' + this.version.toString() + '_' + item.id.toString() + '_' + (index ?? 0).toString())
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
        }, (_: RecommendCardModel, index?: number) => 'dot_' + this.version.toString() + '_' + (index ?? 0).toString())
      }
      .margin({ bottom: 16, left: 20 })
    }
    .width('100%')
    .height(this.getHeroHeight())
  }

  @Builder
  private HeroBackground(item: RecommendCardModel) {
    Stack({ alignContent: Alignment.Top }) {
      if (item.getHeroBackdrop().length > 0) {
        if (this.screenWidthVp >= 600) {
          CachedRemoteImage({
            source: item.getHeroBackdrop(),
            sources: this.getCoverCandidates(item),
            cornerRadius: 0,
            pauseWhenHomeInactive: true
          })
            .width('100%')
            .aspectRatio(16 / 9)
            .blur(14)
            .opacity(0.72)
        } else {
          CachedRemoteImage({
            source: item.getHeroBackdrop(),
            sources: this.getCoverCandidates(item),
            cornerRadius: 0,
            pauseWhenHomeInactive: true
          })
            .width('100%')
            .height('100%')
            .blur(14)
            .opacity(0.72)
        }
      }

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [$r('app.color.hero_gradient_start'), 0],
            [$r('app.color.hero_gradient_dark'), 0.34],
            [$r('app.color.hero_gradient_mid'), 0.78],
            [$r('app.color.page_background'), 1]
          ]
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private HeroSlide(item: RecommendCardModel) {
    Stack() {
      this.HeroBackground(item)

      Row() {
        Column({ space: 8 }) {
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
                  .fontSize(11)
                  .fontColor('#FFD700')
                Text(item.getScoreText())
                  .fontSize(11)
                  .fontColor('#CCFFFFFF')
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

            if (item.getMetaText().length > 0) {
              Text(item.getMetaText())
                .fontSize(11)
                .fontColor('#CCFFFFFF')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .backgroundColor('#4D000000')
            }
          }

          if (item.tags.length > 0) {
            Text(item.getTagText())
              .fontSize(11)
              .fontColor('#99FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

        }
        .layoutWeight(1)
        .padding({ left: 20, right: 10 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        Column() {
          CachedRemoteImage({
            source: item.getGridCover(),
            sources: this.getCoverCandidates(item),
            sharedId: this.getSharedCoverId(item),
            pauseWhenHomeInactive: true
          })
            .width('100%')
            .height('100%')
            .borderRadius(12)
            .shadow({ radius: 20, color: '#4D000000', offsetY: 8 })
        }
        .width(this.getPosterWidth())
        .height(this.getPosterHeight())
        .padding({ left: 4, right: 18 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getContentTopPadding(), bottom: this.getContentBottomPadding() })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.getHeroHeight())
    .onClick(() => {
      this.navigateToDetail(item)
    })
  }

  private getHeroHeight(): number {
    if (this.screenWidthVp >= 840) {
      return 360 + this.topInset
    } else if (this.screenWidthVp >= 600) {
      return 340 + this.topInset
    }
    return 300 + this.topInset
  }

  private getPosterWidth(): number {
    if (this.screenWidthVp >= 1200) {
      return 198
    } else if (this.screenWidthVp >= 840) {
      return 192
    } else if (this.screenWidthVp >= 600) {
      return 180
    }
    return 122
  }

  private getPosterHeight(): number {
    return Math.round(this.getPosterWidth() * 4 / 3)
  }

  private getContentTopPadding(): number {
    if (this.screenWidthVp >= 600) {
      return this.topInset + 28
    }
    return this.topInset + 24
  }

  private getContentBottomPadding(): number {
    if (this.screenWidthVp >= 600) {
      return 54
    }
    return 48
  }

  private navigateToDetail(item: RecommendCardModel): void {
    navigateToDetail(buildRecommendDetailParams(item, this.getSharedCoverId(item)))
  }

  private getCoverCandidates(item: RecommendCardModel): string[] {
    return [
      item.coverLarge,
      item.coverCommon,
      item.coverMedium,
      item.bangumiCover,
      item.cover,
      item.coverFallback
    ]
  }

  private getSharedCoverId(item: RecommendCardModel): string {
    const subjectId = item.bangumiId > 0 ? item.bangumiId : item.id
    return 'hero-cover-' + subjectId.toString()
  }
}
