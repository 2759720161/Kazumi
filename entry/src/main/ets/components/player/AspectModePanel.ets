import { VideoAspectMode } from '../../core/player/IPlayerEngine'

class AspectModeItem {
  mode: VideoAspectMode = VideoAspectMode.contain
  label: string = ''
}

@Component
export struct AspectModePanel {
  @Prop currentMode: VideoAspectMode = VideoAspectMode.contain
  onSelectMode?: (mode: VideoAspectMode) => void

  private modeItems: AspectModeItem[] = []

  aboutToAppear(): void {
    const items: AspectModeItem[] = []
    let item0 = new AspectModeItem()
    item0.mode = VideoAspectMode.contain
    item0.label = '自动适应'
    items.push(item0)
    let item1 = new AspectModeItem()
    item1.mode = VideoAspectMode.cover
    item1.label = '裁切填充'
    items.push(item1)
    let item2 = new AspectModeItem()
    item2.mode = VideoAspectMode.fill
    item2.label = '拉伸填充'
    items.push(item2)
    this.modeItems = items
  }

  build() {
    Menu() {
      ForEach(this.modeItems, (item: AspectModeItem) => {
        MenuItem() {
          Row() {
            Text(item.label)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.currentMode === item.mode ?
                $r('app.color.accent_blue') : $r('app.color.text_primary'))
              .layoutWeight(1)
          }
          .width('100%')
          .height(44)
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.onSelectMode) {
            this.onSelectMode(item.mode)
          }
        })
      })
    }
    .width(160)
    .borderRadius(16)
  }
}
