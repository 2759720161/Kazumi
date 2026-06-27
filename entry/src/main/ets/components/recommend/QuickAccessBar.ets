@Component
export struct QuickAccessBar {
  @StorageLink('currentTab') currentTab: number = 0
  onScrollToHighScore?: () => void
  onScrollToSeasonal?: () => void

  build() {
    Row({ space: 0 }) {
      this.QuickItem('时间表', $r('sys.symbol.calendar'), 1)
      this.QuickItemWithAction('高分佳作', $r('sys.symbol.star'))
      this.QuickItemWithAction('本季新番', $r('sys.symbol.arrow_clockwise'))
      this.QuickItem('我的追番', $r('sys.symbol.heart'), 2)
    }
    .width('100%')
  }

  @Builder
  private QuickItem(label: string, icon: Resource, targetTab: number) {
    Column({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('app.color.accent_blue')])

      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => {
      if (targetTab >= 0) {
        this.currentTab = targetTab
      }
    })
  }

  @Builder
  private QuickItemWithAction(label: string, icon: Resource) {
    Column({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('app.color.accent_blue')])

      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .onClick(() => {
      if (label === '高分佳作' && this.onScrollToHighScore) {
        this.onScrollToHighScore()
      } else if (label === '本季新番' && this.onScrollToSeasonal) {
        this.onScrollToSeasonal()
      }
    })
  }
}
