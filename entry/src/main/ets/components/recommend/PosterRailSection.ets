import { RecommendCardModel } from '../../models/RecommendCardModel'
import { RecommendCard } from './RecommendCard'

@Component
export struct PosterRailSection {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop items: RecommendCardModel[] = []
  @Prop showRank: boolean = false
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  onMoreClick?: () => void

  build() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.onMoreClick !== undefined) {
          Row({ space: 4 }) {
            Text('更多')
              .fontSize(13)
              .fontColor($r('app.color.accent_blue'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('app.color.accent_blue')])
          }
          .onClick(() => {
            if (this.onMoreClick) {
              this.onMoreClick()
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.items, (item: RecommendCardModel, index?: number) => {
            Column() {
              RecommendCard({
                item: item,
                showRank: this.showRank,
                cardWidth: this.getCardWidth()
              })
            }
            .width(this.getCardWidth())
            .height(this.getCardHeight())
          }, (item: RecommendCardModel, index?: number) => 'rail_' + this.title + '_' + item.id.toString() + '_' + (index ?? 0).toString())
        }
        .padding({ left: 16, right: 16 })
        .height(this.getCardHeight())
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
    }
    .width('100%')
  }

  private getCardWidth(): number {
    if (this.screenWidthVp >= 840) {
      return 156
    } else if (this.screenWidthVp >= 600) {
      return 132
    }
    return 112
  }

  private getCardHeight(): number {
    return Math.round(this.getCardWidth() * 4 / 3)
  }
}
