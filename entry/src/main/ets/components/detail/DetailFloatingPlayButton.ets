import { hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit'
import { deviceInfo } from '@kit.BasicServicesKit'

@Component
export struct DetailFloatingPlayButton {
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true
  @Prop bottomSafeHeight: number = 0

  onPlay: (() => void) | undefined = undefined

  private tabsController: HdsTabsController = new HdsTabsController()

  @Builder
  private PlayContent() {
    Row() {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(22)
        .fontColor([$r('app.color.accent_blue')])
        .margin({ right: 9 })

      Text('开始播放')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accent_blue'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(26)
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => {
      if (this.onPlay) {
        this.onPlay()
      }
    })
  }

  @Builder
  private HdsPlayButton() {
    HdsTabs({ controller: this.tabsController }) {
      TabContent()
        .clip(false)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .width(126)
    .height(52)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .barWidth(126)
    .barHeight(52)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .backgroundColor(Color.Transparent)
    .vertical(false)
    .barFloatingStyle({
      barWidth: { smallWidth: 126, mediumWidth: 126, largeWidth: 126 },
      gradientMask: {
        maskColor: Color.Transparent
      },
      barBottomMargin: 0,
      barSideMargin: 0,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      },
      miniBar: {
        miniBarBuilder: () => {
          this.PlayContent()
        },
        miniBarStyle: 1
      },
      lightColor: Color.Transparent
    })
  }

  @Builder
  private FallbackPlayButton() {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(22)
          .fontColor([$r('app.color.accent_blue')])
          .margin({ right: 9 })

        Text('开始播放')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_blue'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width(126)
    .height(52)
    .borderRadius(26)
    .backgroundColor($r('app.color.card_surface_blue'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.border_specular') })
    .shadow({ radius: 18, color: $r('app.color.shadow_surface'), offsetY: 7 })
    .onClick(() => {
      if (this.onPlay) {
        this.onPlay()
      }
    })
  }

  build() {
    Row() {
      if (this.isHdsTabsEnabled && deviceInfo.distributionOSApiVersion >= 60100) {
        this.HdsPlayButton()
      } else {
        this.FallbackPlayButton()
      }
    }
    .width('100%')
    .height(72 + this.bottomSafeHeight)
    .padding({ right: 16, bottom: this.bottomSafeHeight + 20 })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Bottom)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
