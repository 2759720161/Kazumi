import { CollectedBangumi } from '../../models/CollectedBangumi'
import { router } from '@kit.ArkUI'
import { Logger } from '../../utils/Logger'

const logger = new Logger('CollectCard')

@Component
export struct CollectCard {
  @Prop collectedBangumi: CollectedBangumi
  @Prop isEditMode: boolean = false
  @State isPressed: boolean = false
  onRemove?: () => void

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.getCoverSource())
          .draggable(false)
          .width('100%')
          .height('100%')
          .objectFit(this.collectedBangumi.getBestCover().length > 0 ? ImageFit.Cover : ImageFit.Contain)
          .borderRadius(12)
          .alt($r('app.media.ic_placeholder'))
          .onError(() => {
            logger.warn('Cover load failed: %{public}s', this.collectedBangumi.animeName)
          })

        if (this.isEditMode) {
          this.StatusButton()
        } else {
          this.StatusBadge()
        }
      }
      .width('100%')
      .aspectRatio(3 / 4)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
      .clip(true)

      Text(this.collectedBangumi.animeName)
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
      if (this.isEditMode) {
        this.requestRemove()
      } else {
        router.pushUrl({
          url: 'pages/detail/DetailPage',
          params: {
            animeName: this.collectedBangumi.animeName,
            animeCover: this.collectedBangumi.animeCover,
            animeCoverFallback: this.collectedBangumi.coverFallback,
            animeBangumiCover: this.collectedBangumi.bangumiCover,
            animeDesc: this.collectedBangumi.animeDesc,
            animeUrl: this.collectedBangumi.animeUrl,
            sourceName: this.collectedBangumi.sourceName,
            sourceId: this.collectedBangumi.sourceId,
            bangumiId: this.collectedBangumi.bangumiId
          }
        })
      }
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
  private StatusBadge(): void {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(12)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(24)
      .height(24)
      .borderRadius(12)
      .backgroundColor($r('app.color.button_accent_bg'))
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.End)
    .padding({ top: 6, right: 6 })
    .position({ x: 0, y: 0 })
  }

  @Builder
  private StatusButton(): void {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.heart_slash'))
          .fontSize(16)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor($r('app.color.button_primary_bg'))
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.requestRemove()
      })
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.End)
    .padding({ top: 6, right: 6 })
    .position({ x: 0, y: 0 })
  }

  private getCoverSource(): ResourceStr {
    const cover = this.collectedBangumi.getBestCover()
    return cover.length > 0 ? cover : $r('app.media.ic_placeholder')
  }

  private requestRemove(): void {
    this.onRemove?.()
  }
}
