import { RecommendCardModel } from '../../models/RecommendCardModel'
import { RecommendCard } from './RecommendCard'
import { Logger } from '../../utils/Logger'

const logger = new Logger('PosterRailSection')

@Component
export struct PosterRailSection {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop @Watch('onItemsChanged') items: RecommendCardModel[] = []
  // 数组引用更新在异步分页场景下不一定触发 @Watch，显式版本号用于通知渲染窗口同步。
  @Prop @Watch('onItemsVersionChanged') itemsVersion: number = 0
  @Prop showRank: boolean = false
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  onMoreClick?: () => void
  onNeedMore?: () => void
  @State waitingForMoreItems: boolean = false
  private previousItemCount: number = 0
  // Scroll.onDidScroll reports the offset delta. Keep the accumulated value here because
  // Scroller.currentOffset() can still be zero while the scroll event is being dispatched.
  private railScrollDistance: number = 0
  private lastNearEnd: boolean = false
  private railScroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.previousItemCount = this.items.length
  }

  private onItemsChanged(): void {
    this.syncVisibleItems()
  }

  private onItemsVersionChanged(): void {
    this.syncVisibleItems()
  }

  private syncVisibleItems(): void {
    if (this.items.length < this.previousItemCount || this.items.length === 0) {
      this.railScrollDistance = 0
      this.lastNearEnd = false
    }
    if (this.items.length > this.previousItemCount) {
      this.waitingForMoreItems = false
      // 新数据追加后，旧的末端判断已经失效。下一帧重新计算，避免用户
      // 必须先向回滑动才能再次触发后续分页。
      this.lastNearEnd = false
      setTimeout(() => {
        this.handleRailScroll(0, true)
      }, 0)
    }
    logger.info('items sync title=%{public}s previous=%{public}s current=%{public}s version=%{public}s',
      this.title,
      this.previousItemCount.toString(),
      this.items.length.toString(),
      this.itemsVersion.toString())
    this.previousItemCount = this.items.length
  }

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

      Scroll(this.railScroller) {
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
          }, (item: RecommendCardModel, index?: number) =>
            'rail_' + this.title + '_' + item.id.toString() + '_' + (index ?? 0).toString())
        }
        .padding({ left: 16, right: 16 })
        .height(this.getCardHeight())
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .onDidScroll((xOffset: number, _yOffset: number, _scrollState: ScrollState) => {
        this.handleRailScroll(xOffset)
      })
      .onScrollEdge((side: Edge) => {
        if (side === Edge.End) {
          this.requestMoreItems('edge')
        }
      })
      .onScrollStop(() => {
        this.handleRailScroll(0, true)
      })
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
    return Math.round(this.getCardWidth() * 4 / 3) + 44
  }

  private handleRailScroll(deltaX: number = 0, forceLog: boolean = false): void {
    // A left swipe produces a negative delta and moves the rail towards its right side.
    this.railScrollDistance = Math.max(0, this.railScrollDistance - deltaX)
    const scrollDistance = this.railScrollDistance
    const itemStride = this.getCardWidth() + 10
    const viewportWidth = this.screenWidthVp > 0 ? this.screenWidthVp : 360
    const renderedWidth = this.items.length * itemStride + 32
    const nearRenderedEnd = scrollDistance + viewportWidth >= renderedWidth - itemStride * 1.5
    if (forceLog || nearRenderedEnd !== this.lastNearEnd) {
      logger.info('rail edge check title=%{public}s offset=%{public}s items=%{public}s nearEnd=%{public}s',
        this.title,
        scrollDistance.toString(),
        this.items.length.toString(),
        nearRenderedEnd ? 'true' : 'false')
    }
    this.lastNearEnd = nearRenderedEnd
    if (!nearRenderedEnd) {
      return
    }

    this.requestMoreItems('offset')
  }

  private requestMoreItems(trigger: string): void {
    if (this.waitingForMoreItems || this.onNeedMore === undefined) {
      return
    }
    this.waitingForMoreItems = true
    logger.info('rail request more title=%{public}s trigger=%{public}s items=%{public}s',
      this.title,
      trigger,
      this.items.length.toString())
    this.onNeedMore()
  }
}
