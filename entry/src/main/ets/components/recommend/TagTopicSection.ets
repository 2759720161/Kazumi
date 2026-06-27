import { RecommendCardModel } from '../../models/RecommendCardModel'
import { router } from '@kit.ArkUI'

const GENRE_TAGS: string[] = [
  '日常', '原创', '校园', '搞笑', '奇幻',
  '百合', '恋爱', '悬疑', '热血', '后宫',
  '机战', '轻改', '偶像', '治愈', '异世界'
]

@Component
export struct TagTopicSection {
  @Prop items: RecommendCardModel[] = []
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @State selectedTag: string = ''
  onTagSelect?: (tag: string) => void

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('分类专题')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(GENRE_TAGS, (tag: string, index?: number) => {
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

      if (this.items.length > 0) {
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
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  private TagResultCard(item: RecommendCardModel) {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(item.getGridCover().length > 0 ? item.getGridCover() : $r('app.media.ic_placeholder'))
          .width('100%')
          .aspectRatio(3 / 4)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 10, topRight: 10 })
          .alt($r('app.media.ic_placeholder'))

        if (item.score > 0) {
          Row({ space: 2 }) {
            Text('\u2605')
              .fontSize(9)
              .fontColor('#FFD700')
            Text(item.getScoreText())
              .fontSize(11)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('#B3000000')
          .margin({ top: 4, right: 4 })
        }
      }
      .width('100%')
      .clip(true)
      .borderRadius({ topLeft: 10, topRight: 10 })

      Text(item.title)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 4, right: 4, top: 4 })
    }
    .borderRadius(10)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .clip(true)
    .onClick(() => {
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
    })
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
