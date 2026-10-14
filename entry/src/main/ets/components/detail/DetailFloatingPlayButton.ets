import {
  API26_MATERIAL_STYLE_DEFAULT,
  PREFS_KEY_API26_MATERIAL_STYLE,
  createControlImmersiveMaterial,
  isImmersiveMaterialSupported
} from '../../utils/ImmersiveMaterial'

class PlayToggleMaterialModifier implements AttributeModifier<ToggleAttribute> {
  private materialStyle: string

  constructor(materialStyle: string) {
    this.materialStyle = materialStyle
  }

  applyNormalAttribute(instance: ToggleAttribute): void {
    instance.backgroundColor($r('app.color.card_surface_blue'))
      .selectedColor($r('app.color.card_surface_blue'))
    const material = createControlImmersiveMaterial(this.materialStyle)
    if (material !== undefined) {
      instance.systemMaterial(material)
    }
  }
}

@Component
export struct DetailFloatingPlayButton {
  @StorageLink(PREFS_KEY_API26_MATERIAL_STYLE) api26MaterialStyle: string = API26_MATERIAL_STYLE_DEFAULT
  @Prop bottomSafeHeight: number = 0
  @State private playButtonOn: boolean = false

  private resetTimer: number = -1

  onPlay: (() => void) | undefined = undefined

  aboutToDisappear(): void {
    clearTimeout(this.resetTimer)
    this.resetTimer = -1
    this.playButtonOn = false
  }

  private onPlayToggleChange(isOn: boolean): void {
    this.playButtonOn = isOn
    clearTimeout(this.resetTimer)
    this.resetTimer = -1
    if (isOn) {
      // This toggle is an action, not a persistent playback state.
      this.resetTimer = setTimeout(() => {
        this.resetTimer = -1
        this.playButtonOn = false
      }, 0)
    }
  }

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
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private NativePlayButton() {
    Toggle({ type: ToggleType.Button, isOn: this.playButtonOn }) {
      this.PlayContent()
    }
    .width(126)
    .height(52)
    .padding(0)
    .borderRadius(26)
    .clip(false)
    .attributeModifier(new PlayToggleMaterialModifier(this.api26MaterialStyle))
    .accessibilityText('开始播放')
    .onChange((isOn: boolean) => {
      this.onPlayToggleChange(isOn)
    })
    .onClick(() => {
      this.onPlay?.()
    })
  }

  @Builder
  private FallbackPlayButton() {
    Toggle({ type: ToggleType.Button, isOn: this.playButtonOn }) {
      this.PlayContent()
    }
    .width(126)
    .height(52)
    .padding(0)
    .borderRadius(26)
    .backgroundColor($r('app.color.card_surface_blue'))
    .selectedColor($r('app.color.card_surface_blue'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.border_specular') })
    .shadow({ radius: 18, color: $r('app.color.shadow_surface'), offsetY: 7 })
    .accessibilityText('开始播放')
    .onChange((isOn: boolean) => {
      this.onPlayToggleChange(isOn)
    })
    .onClick(() => {
      this.onPlay?.()
    })
  }

  build() {
    Row() {
      if (isImmersiveMaterialSupported()) {
        this.NativePlayButton()
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
