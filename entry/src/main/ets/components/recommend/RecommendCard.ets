import { RecommendCardModel } from '../../models/RecommendCardModel'
import { buildRecommendDetailParams } from '../../utils/AnimeNavigation'
import { router } from '@kit.ArkUI'

@Component
export struct RecommendCard {
  @Prop item: RecommendCardModel = new RecommendCardModel()
  @Prop showRank: boolean = false
  @Prop cardWidth: number = 112

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(this.item.getGridCover().length > 0 ? this.item.getGridCover() : $r('app.media.ic_placeholder'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .alt($r('app.media.ic_placeholder'))

      this.BottomGradient()
      this.TitleOverlay()

      if (this.showRank && this.item.rank > 0) {
        this.RankBadge()
      }
    }
    .width('100%')
    .height(this.getPosterHeight())
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
    .clip(true)
    .onClick(() => {
      this.navigateToDetail()
    })
  }

  @Builder
  private BottomGradient() {
    Column()
      .width('100%')
      .height('48%')
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          ['#00000000', 0],
          ['#88000000', 0.55],
          ['#D9000000', 1]
        ]
      })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private TitleOverlay() {
    Text(this.item.title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .lineHeight(18)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(TextAlign.Start)
      .width('100%')
      .padding({ left: 9, right: 9, bottom: 10 })
      .textShadow({
        radius: 6,
        color: '#99000000',
        offsetX: 0,
        offsetY: 1
      })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private RankBadge() {
    Text('TOP ' + this.item.rank.toString())
      .fontSize(10)
      .fontColor(Color.White)
      .fontWeight(FontWeight.Medium)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .borderRadius({ topLeft: 12, bottomRight: 8 })
      .backgroundColor($r('app.color.accent_blue'))
      .position({ x: 0, y: 0 })
  }

  private navigateToDetail(): void {
    router.pushUrl({
      url: 'pages/detail/DetailPage',
      params: buildRecommendDetailParams(this.item)
    })
  }

  private getPosterHeight(): number {
    return Math.round(this.cardWidth * 4 / 3)
  }

  private getCardHeight(): number {
    return this.getPosterHeight()
  }
}
