@Component
export struct DetailTitleBlock {
  @Prop title: string = ''
  @Prop originalName: string = ''
  @Link airDate: string
  isWideLayout: boolean = false

  build() {
    Column() {
      Text(this.getDisplayTitle())
        .fontSize(this.isWideLayout ? 28 : 31)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .lineHeight(this.isWideLayout ? 36 : 40)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.getSubtitleText())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(this.isWideLayout ? { bottom: 20 } : { left: 24, right: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  private getDisplayTitle(): string {
    if (this.title.length > 0) {
      return this.title
    }
    if (this.originalName.length > 0) {
      return this.originalName
    }
    return '未知番剧'
  }

  private getSubtitleText(): string {
    if (this.originalName.length > 0 && this.originalName !== this.title) {
      return this.originalName
    }
    return '番剧详情'
  }
}
