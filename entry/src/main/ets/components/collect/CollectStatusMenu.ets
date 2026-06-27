import { CollectType } from '../../models/CollectType'

@Component
export struct CollectStatusMenu {
  @Prop currentType: number = 1
  @Link isVisible: boolean
  onSelect?: (type: number) => void

  private readonly menuItems: string[] = ['未追', '在看', '想看', '搁置', '看过', '抛弃']

  build() {
    Column() {
      Text('收藏状态')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 16 })

      ForEach(this.menuItems, (label: string, index?: number) => {
        Row() {
          SymbolGlyph(CollectType.getIcon(index ?? 0))
            .fontSize(18)
            .fontColor([(index ?? 0) === this.currentType ? $r('app.color.tab_icon_selected') :
              $r('app.color.text_primary')])

          Text(label)
            .fontSize(16)
            .fontColor((index ?? 0) === this.currentType ? $r('app.color.tab_icon_selected') :
              $r('app.color.text_primary'))
            .fontWeight((index ?? 0) === this.currentType ? FontWeight.Medium : FontWeight.Normal)
            .margin({ left: 12 })
            .layoutWeight(1)

          if ((index ?? 0) === this.currentType) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(16)
              .fontColor([$r('app.color.tab_icon_selected')])
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .borderRadius(10)
        .backgroundColor((index ?? 0) === this.currentType ?
          $r('app.color.category_menu_item_selected') : $r('app.color.color_transparent'))
        .margin({ bottom: 2 })
        .onClick(() => {
          if ((index ?? 0) !== this.currentType && this.onSelect) {
            this.onSelect!(index ?? 0)
          }
          this.isVisible = false
        })
      }, (label: string, index?: number) => `status_${index}`)
    }
    .width('100%')
    .padding(16)
  }
}
