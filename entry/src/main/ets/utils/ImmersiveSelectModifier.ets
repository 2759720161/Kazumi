import { deviceInfo } from '@kit.BasicServicesKit'
import { createControlImmersiveMaterial, createMenuImmersiveMaterial, normalizeApi26MaterialStyle } from './ImmersiveMaterial'

/** Select's button and popup have separate component-level material interfaces. */
export class ImmersiveSelectModifier implements AttributeModifier<SelectAttribute> {
  private materialStyle: string

  constructor(materialStyle: string) {
    this.materialStyle = normalizeApi26MaterialStyle(materialStyle)
  }

  applyNormalAttribute(instance: SelectAttribute): void {
    instance.backgroundColor($r('app.color.page_background'))
    try {
      if (deviceInfo.apiAvailable('26.0.0')) {
        const buttonMaterial = createControlImmersiveMaterial(this.materialStyle)
        const menuMaterial = createMenuImmersiveMaterial(this.materialStyle)
        if (buttonMaterial !== undefined && menuMaterial !== undefined) {
          instance.backgroundColor(Color.Transparent)
            .systemMaterial(buttonMaterial)
            .menuSystemMaterial(menuMaterial)
        }
      }
    } catch (_) {
      instance.backgroundColor($r('app.color.page_background'))
    }
  }
}
