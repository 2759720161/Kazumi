import { DanmakuSettingsPanelContent } from './DanmakuSettingsPanel'

@Component
export struct DanmakuSettingsSidePanel {
  @Prop showPanel: boolean = false
  @Prop isDanmakuEnabled: boolean = true
  @Prop isFullScreen: boolean = true
  @Prop settingsVersion: number = 0
  onPanelClose: () => void = () => {}
  onSetDanmakuEnabled: (enabled: boolean) => void = () => {}
  onPauseAutoHide: () => void = () => {}
  onResumeAutoHide: () => void = () => {}

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .opacity(this.showPanel ? 1 : 0)
        .hitTestBehavior(this.showPanel ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          this.onPanelClose()
        })

      Column() {
        DanmakuSettingsPanelContent({
          isDanmakuEnabled: this.isDanmakuEnabled,
          isFullScreen: this.isFullScreen,
          showHeader: true,
          useGlassBackground: true,
          settingsVersion: this.settingsVersion,
          onSetDanmakuEnabled: (enabled: boolean) => {
            this.onSetDanmakuEnabled(enabled)
          },
          onPanelClose: () => {
            this.onPanelClose()
          },
          onPauseAutoHide: () => {
            this.onPauseAutoHide()
          },
          onResumeAutoHide: () => {
            this.onResumeAutoHide()
          }
        })
      }
      .width(this.isFullScreen ? '62%' : '88%')
      .height(this.isFullScreen ? 326 : 358)
      .borderRadius(16)
      .clip(true)
      .backgroundColor($r('app.color.speed_menu_surface'))
      .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .zIndex(28)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }
}
