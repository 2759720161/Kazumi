@Component
export struct CurrentWeekdayPill {
  @Prop weekdayName: string = ''
  @Prop pillTopOffset: number = 54
  onPillClick?: () => void

  build() {
    Row() {
      Text(this.weekdayName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .transition(TransitionEffect.OPACITY.animation({
          duration: 200,
          curve: Curve.EaseInOut
        }))
    }
    .width(72)
    .height(36)
    .borderRadius(18)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
    .position({ x: '100%', y: this.pillTopOffset })
    .markAnchor({ x: '100%', y: 0 })
    .translate({ x: -16 })
    .animation({
      duration: 200,
      curve: Curve.EaseInOut
    })
    .onClick(() => {
      this.onPillClick?.()
    })
  }
}