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
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(this.getCoverSource())
        .width('100%')
        .height('100%')
        .objectFit(this.collectedBangumi.getBestCover().length > 0 ? ImageFit.Cover : ImageFit.Contain)
        .borderRadius(12)
        .alt($r('app.media.ic_placeholder'))
        .onError(() => {
          logger.warn('Cover load failed: %{public}s', this.collectedBangumi.animeName)
        })

      this.BottomGradient()
      this.TitleOverlay()

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

  @Builder
  private BottomGradient(): void {
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
  private TitleOverlay(): void {
    Text(this.collectedBangumi.animeName)
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
  private StatusBadge(): void {
    Row() {
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
        SymbolGlyph(CollectType.getIcon(this.collectedBangumi.collectType))
          .fontSize(16)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor($r('app.color.button_primary_bg'))
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.showStatusMenu()
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

  private showStatusMenu(): void {
    if (this.onStatusChange) {
      this.onStatusChange!(this.collectedBangumi.collectType)
    }
  }
}
