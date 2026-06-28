import { RecommendCardModel } from '../../models/RecommendCardModel'
import { RECOMMEND_GENRE_TAGS } from '../../constants/RecommendTags'
import { buildRecommendDetailParams } from '../../utils/AnimeNavigation'
import { router } from '@kit.ArkUI'

@Component
export struct TagTopicSection {
  @Prop items: RecommendCardModel[] = []
  @Prop selectedTag: string = ''
  @Prop isLoading: boolean = false
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  onTagSelect?: (tag: string) => void

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.getTitleText())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(RECOMMEND_GENRE_TAGS, (tag: string, index?: number) => {
            Text(tag)
              .fontSize(13)
              .fontColor(tag === this.selectedTag ? Color.White : $r('app.color.text_primary'))
              .fontWeight(tag === this.selectedTag ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor(tag === this.selectedTag ? $r('app.color.accent_blue') : $r('app.color.tag_chip_bg'))
              .onClick(() => {
                this.selectedTag = tag === this.selectedTag ? '' : tag
                if (this.onTagSelect) {
                  this.onTagSelect(this.selectedTag)
                }
              })
          }, (tag: string, index?: number) => 'tag_' + tag)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')

      Column() {
        if (this.selectedTag.length === 0) {
          Text('选择一个标签发现番剧')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else if (this.isLoading) {
          this.SkeletonGrid()
        } else if (this.items.length === 0) {
          Text('暂无相关番组')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else {
          Grid() {
            ForEach(this.items, (item: RecommendCardModel, index?: number) => {
              GridItem() {
                this.TagResultCard(item)
              }
            }, (item: RecommendCardModel, index?: number) => 'tag_item_' + item.id.toString() + '_' + (index ?? 0).toString())
          }
          .columnsTemplate(this.getGridColumns())
          .columnsGap(10)
          .rowsGap(10)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
  }

  @Builder
  private SkeletonGrid() {
    Grid() {
      ForEach([0, 1, 2, 3, 4, 5], (i: number, index?: number) => {
        GridItem() {
          Column()
            .width('100%')
            .aspectRatio(3 / 4)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_background'))
        }
      }, (i: number, index?: number) => 'skeleton_' + i.toString())
    }
    .columnsTemplate(this.getGridColumns())
    .columnsGap(10)
    .rowsGap(10)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private TagResultCard(item: RecommendCardModel) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(item.getGridCover().length > 0 ? item.getGridCover() : $r('app.media.ic_placeholder'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .alt($r('app.media.ic_placeholder'))

      this.CardBottomGradient()

      Text(item.title)
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
    .width('100%')
    .aspectRatio(3 / 4)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
    .clip(true)
    .onClick(() => {
      router.pushUrl({
        url: 'pages/detail/DetailPage',
        params: buildRecommendDetailParams(item)
      })
    })
  }

  @Builder
  private CardBottomGradient() {
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

  private getTitleText(): string {
    if (this.selectedTag.length > 0) {
      return this.selectedTag + '专题'
    }
    return '分类专题'
  }

  private getGridColumns(): string {
    if (this.screenWidthVp >= 840) {
      return '1fr 1fr 1fr 1fr 1fr'
    } else if (this.screenWidthVp >= 600) {
      return '1fr 1fr 1fr 1fr'
    }
    return '1fr 1fr 1fr'
  }
}
