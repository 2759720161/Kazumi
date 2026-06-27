import { DanmakuSettingsPanelContent } from './DanmakuSettingsPanel'

@Component
export struct DanmakuSettingsSidePanel {
  @Prop showPanel: boolean = false
  @Prop isDanmakuEnabled: boolean = true
  @Prop isFullScreen: boolean = true
  @Prop settingsVersion: number = 0
  onPanelClose: () => void = () => {}
  onToggleDanmaku: () => void = () => {}
  onPauseAutoHide: () => void = () => {}
  onResumeAutoHide: () => void = () => {}

  @State private panelOffsetX: number = 0
  private panStartOffsetX: number = 0

  build() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .opacity(this.showPanel ? 1 : 0)
        .hitTestBehavior(this.showPanel ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          this.onPanelClose()
        })

      Column() {
        DanmakuSettingsPanelContent({
          isDanmakuEnabled: this.isDanmakuEnabled,
          isFullScreen: this.isFullScreen,
          settingsVersion: this.settingsVersion,
          onToggleDanmaku: () => {
            this.onToggleDanmaku()
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
      .width('40%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: { left: 0.5 }, color: $r('app.color.divider_color') })
      .translate({ x: this.showPanel ? this.panelOffsetX : '100%' })
      .animation({ duration: 300, curve: Curve.EaseInOut })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 10 })
          .onActionStart(() => {
            this.panStartOffsetX = this.panelOffsetX
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event.offsetX > 0) {
              this.panelOffsetX = this.panStartOffsetX + event.offsetX
            }
          })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX > 50) {
              this.onPanelClose()
            }
            this.panelOffsetX = 0
          })
      )
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.showPanel ? HitTestMode.Default : HitTestMode.None)
  }
}
