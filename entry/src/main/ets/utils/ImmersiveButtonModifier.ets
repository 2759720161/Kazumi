import { deviceInfo } from '@kit.BasicServicesKit'
import { createControlImmersiveMaterial, normalizeApi26MaterialStyle } from './ImmersiveMaterial'

export class ImmersiveButtonModifier implements AttributeModifier<ButtonAttribute> {
  private materialStyle: string
  private fallbackColor: ResourceColor

  constructor(materialStyle: string, fallbackColor: ResourceColor = Color.Transparent) {
    this.materialStyle = normalizeApi26MaterialStyle(materialStyle)
    this.fallbackColor = fallbackColor
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.backgroundColor(this.fallbackColor)
    try {
      if (deviceInfo.apiAvailable('26.0.0')) {
        const material = createControlImmersiveMaterial(this.materialStyle)
        if (material !== undefined) {
          instance.systemMaterial(material)
        }
      }
    } catch (_) {
      instance.backgroundColor(this.fallbackColor)
    }
  }
}
