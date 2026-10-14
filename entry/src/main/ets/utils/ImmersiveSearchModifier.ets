import { deviceInfo } from '@kit.BasicServicesKit'
import { createControlImmersiveMaterial, normalizeApi26MaterialStyle } from './ImmersiveMaterial'

export class ImmersiveSearchModifier implements AttributeModifier<SearchAttribute> {
  private materialStyle: string

  constructor(materialStyle: string) {
    this.materialStyle = normalizeApi26MaterialStyle(materialStyle)
  }

  applyNormalAttribute(instance: SearchAttribute): void {
    try {
      if (deviceInfo.apiAvailable('26.0.0')) {
        const material = createControlImmersiveMaterial(this.materialStyle)
        if (material !== undefined) {
          instance.backgroundColor(Color.Transparent)
          instance.systemMaterial(material)
          return
        }
      }
    } catch (_) {
      // Retain a visible input surface if the runtime cannot create a material.
    }
    instance.backgroundColor($r('app.color.surface_button_bg'))
    instance.backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    instance.border({ width: 0.5, color: $r('app.color.border_light') })
    instance.shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
  }
}
