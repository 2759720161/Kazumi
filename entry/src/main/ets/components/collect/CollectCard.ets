import { CollectedBangumi } from '../../models/CollectedBangumi'
import { CollectType } from '../../models/CollectType'
import { router } from '@kit.ArkUI'
import { Logger } from '../../utils/Logger'

const logger = new Logger('CollectCard')

@Component
export struct CollectCard {
  @Prop collectedBangumi: CollectedBangumi
  @Prop isEditMode: boolean = false
  onStatusChange?: (type: number) => void

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image(this.getCoverSource())
            .width('100%')
            .height(0)
            .aspectRatio(3 / 4)
            .objectFit(this.collectedBangumi.getBestCover().length > 0 ? ImageFit.Cover : ImageFit.Contain)
            .borderRadius({ topLeft: 8, topRight: 8 })
            .alt($r('app.media.ic_placeholder'))
            .onError(() => {
              logger.warn('Cover load failed: %{public}s', this.collectedBangumi.animeName)
            })

        }
        .width('100%')

        Column() {
          Text(this.collectedBangumi.animeName)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
            .width('100%')
        }
        .height(48)
        .padding({ left: 6, right: 6, top: 4 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .borderRadius(8)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .clip(true)
      .onClick(() => {
        if (this.isEditMode) {
          this.showStatusMenu()
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

    }
    .width('100%')
  }

  @Builder
  private StatusBadge(): void {
    Row() {
      SymbolGlyph(CollectType.getIcon(this.collectedBangumi.collectType))
        .fontSize(12)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(24)
    .height(24)
    .borderRadius(12)
    .backgroundColor($r('app.color.button_accent_bg'))
    .justifyContent(FlexAlign.Center)
    .margin({ top: 6, right: 6 })
  }

  @Builder
  private StatusButton(): void {
    Row() {
      SymbolGlyph(CollectType.getIcon(this.collectedBangumi.collectType))
        .fontSize(16)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor($r('app.color.button_primary_bg'))
    .justifyContent(FlexAlign.Center)
    .margin({ top: 6, right: 6 })
    .onClick(() => {
      this.showStatusMenu()
    })
  }

  private getCoverSource(): ResourceStr {
    const cover = this.collectedBangumi.getBestCover()
    return cover.length > 0 ? cover : $r('app.media.ic_placeholder')
  }

  private showStatusMenu(): void {
    if (this.onStatusChange) {
      this.onStatusChange!(this.collectedBangumi.collectType)
    }
  }
}
