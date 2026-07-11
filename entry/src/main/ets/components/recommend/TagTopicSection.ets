import { RecommendCardModel } from '../../models/RecommendCardModel'
import { RECOMMEND_GENRE_TAGS } from '../../constants/RecommendTags'
import { buildRecommendDetailParams } from '../../utils/AnimeNavigation'
import { router } from '@kit.ArkUI'
import { ImageCacheStore } from '../../store/ImageCacheStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('TagTopicSection')

@Component
export struct TagTopicSection {
  @Prop items: RecommendCardModel[] = []
  @Prop selectedTag: string = ''
  @Prop isLoading: boolean = false
  @Prop tagBarPinned: boolean = false
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  onTagSelect?: (tag: string) => void
  onTagBarAreaChange?: (top: number, height: number) => void

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

      this.TagBar()

      Column() {
        if (this.selectedTag.length === 0) {
          Text('选择一个标签发现番剧')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 24, bottom: 24 })
        } else if (this.isLoading && this.items.length === 0) {
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
                TagTopicCard({ item: item })
              }
            }, (item: RecommendCardModel, index?: number) => 'tag_item_' + item.id.toString() + '_' + (index ?? 0).toString())
          }
          .columnsTemplate(this.getGridColumns())
          .columnsGap(10)
          .rowsGap(10)
          .scrollBar(BarState.Off)
          .width('100%')
          .opacity(this.isLoading ? 0.88 : 1)
          .animation({ duration: 160, curve: Curve.EaseOut })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
  }

  @Builder
  private TagBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(RECOMMEND_GENRE_TAGS, (tag: string, index?: number) => {
          this.TagChip(tag)
        }, (tag: string, index?: number) => 'tag_' + tag)
      }
      .constraintSize({ minWidth: '100%' })
      .justifyContent(FlexAlign.Start)
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .opacity(this.tagBarPinned ? 0 : 1)
    .enabled(!this.tagBarPinned)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      if (this.onTagBarAreaChange) {
        this.onTagBarAreaChange(this.normalizeLength(newArea.globalPosition.y), this.normalizeLength(newArea.height))
      }
    })
  }

  @Builder
  private TagChip(tag: string) {
    Row({ space: 5 }) {
      if (this.isLoading && tag === this.selectedTag) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(Color.White)
      }

      Text(tag)
        .fontSize(13)
        .fontColor(tag === this.selectedTag ? Color.White : $r('app.color.text_primary'))
        .fontWeight(tag === this.selectedTag ? FontWeight.Medium : FontWeight.Normal)
    }
      .height(30)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(tag === this.selectedTag ? $r('app.color.accent_blue') : $r('app.color.tag_chip_bg'))
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onClick(() => {
        this.selectedTag = tag === this.selectedTag ? '' : tag
        if (this.onTagSelect) {
          this.onTagSelect(this.selectedTag)
        }
      })
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

  private normalizeLength(value: Length | undefined): number {
    if (value === undefined) {
      return 0
    }
    if (typeof value === 'number') {
      return value
    }
    const parsed = Number.parseFloat(value.toString())
    return Number.isNaN(parsed) ? 0 : parsed
  }
}

@Component
struct TagTopicCard {
  @Prop @Watch('onItemChanged') item: RecommendCardModel = new RecommendCardModel()
  @State currentCover: string = ''
  @State coverKey: string = ''
  @State hasCoverError: boolean = false
  @State isPressed: boolean = false

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
    this.currentCover = this.selectBestCover()
    this.hasCoverError = false
    this.prepareCachedCover(this.coverKey)
  }

  build() {
    Column({ space: 8 }) {
      Image(this.getCoverSource())
        .draggable(false)
        .width('100%')
        .aspectRatio(3 / 4)
        .objectFit(this.currentCover.length > 0 && !this.hasCoverError ? ImageFit.Cover : ImageFit.Contain)
        .borderRadius(12)
        .alt($r('app.media.ic_placeholder'))
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') })
        .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
        .onError(() => {
          const urlPrefix = this.currentCover.length > 120 ? this.currentCover.substring(0, 120) : this.currentCover
          logger.warn('Tag topic cover load failed: %{public}s', urlPrefix)
          this.currentCover = ''
          this.hasCoverError = true
        })

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
    .alignItems(HorizontalAlign.Start)
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150 })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/detail/DetailPage',
        params: buildRecommendDetailParams(this.item)
      })
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
  }

  private getCoverSource(): ResourceStr {
    if (this.currentCover.length > 0 && !this.hasCoverError) {
      return this.currentCover
    }
    return $r('app.media.ic_placeholder')
  }

  private selectBestCover(): string {
    const cover = this.item.getGridCover()
    return cover.length > 0 ? cover : ''
  }

  private buildCoverKey(): string {
    return this.item.id.toString() + '|' + this.selectBestCover()
  }

  private onItemChanged(): void {
    const nextKey = this.buildCoverKey()
    if (nextKey === this.coverKey) {
      return
    }
    this.coverKey = nextKey
    this.currentCover = this.selectBestCover()
    this.hasCoverError = false
    this.prepareCachedCover(nextKey)
  }

  private async prepareCachedCover(expectedKey: string): Promise<void> {
    const cover = this.selectBestCover()
    if (cover.length === 0) {
      return
    }
    const localUri = await ImageCacheStore.getInstance().getCachedImageUri([cover])
    if (this.coverKey !== expectedKey) {
      return
    }
    if (localUri.length > 0) {
      this.currentCover = localUri
      this.hasCoverError = false
    } else {
      this.currentCover = cover
      this.hasCoverError = false
    }
  }
}
