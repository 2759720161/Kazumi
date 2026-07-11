import { RecommendCardModel } from '../../models/RecommendCardModel'
import { buildRecommendDetailParams } from '../../utils/AnimeNavigation'
import { router } from '@kit.ArkUI'

@Component
export struct RecommendCard {
  @Prop item: RecommendCardModel = new RecommendCardModel()
  @Prop showRank: boolean = false
  @Prop cardWidth: number = 112
  @State isPressed: boolean = false

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.item.getGridCover().length > 0 ? this.item.getGridCover() : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .alt($r('app.media.ic_placeholder'))

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

      Text(this.item.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(18)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')
    }
    .width('100%')
    .height(this.getCardHeight())
    .alignItems(HorizontalAlign.Start)
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150 })
    .onClick(() => {
      this.navigateToDetail()
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
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
    return this.getPosterHeight() + 44
  }
}
