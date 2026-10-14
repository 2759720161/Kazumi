import { deviceInfo } from '@kit.BasicServicesKit'
import {
  API26_MATERIAL_STYLE_DEFAULT,
  PREFS_KEY_API26_MATERIAL_STYLE,
  createControlImmersiveMaterial
} from '../../utils/ImmersiveMaterial'

class TopicTagMaterialModifier implements AttributeModifier<ButtonAttribute> {
  private materialStyle: string

  constructor(materialStyle: string) {
    this.materialStyle = materialStyle
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    // Keep a visible surface where the system does not apply immersive material.
    instance.backgroundColor($r('app.color.tag_chip_bg'))
    try {
      if (deviceInfo.apiAvailable('26.0.0')) {
        const material = createControlImmersiveMaterial(this.materialStyle)
        if (material !== undefined) {
          instance.systemMaterial(material)
        }
      }
    } catch (_) {
      instance.backgroundColor($r('app.color.tag_chip_bg'))
    }
  }
}

@Component
export struct TopicTagButton {
  @StorageLink(PREFS_KEY_API26_MATERIAL_STYLE) api26MaterialStyle: string = API26_MATERIAL_STYLE_DEFAULT
  @Prop tag: string = ''
  @Prop selectedTag: string = ''
  @Prop isLoading: boolean = false
  @Prop chipWidth: number = 0
  onSelected?: (tag: string) => void

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 5 }) {
        if (this.isLoading && this.isSelected()) {
          LoadingProgress()
            .width(12)
            .height(12)
            .color(Color.White)
        }

        Text(this.tag)
          .fontSize(13)
          .fontColor(this.isSelected() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .fontWeight(this.isSelected() ? FontWeight.Bold : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width(this.getWidth())
    .height(30)
    .padding({ left: 12, right: 12 })
    .clip(false)
    .attributeModifier(new TopicTagMaterialModifier(this.api26MaterialStyle))
    .onClick(() => {
      this.onSelected?.(this.isSelected() ? '' : this.tag)
    })
  }

  private isSelected(): boolean {
    return this.tag === this.selectedTag
  }

  private getWidth(): number {
    if (this.chipWidth > 0) {
      return this.chipWidth
    }
    return Math.max(52, this.tag.length * 13 + 24 + (this.isLoading && this.isSelected() ? 17 : 0))
  }
}
