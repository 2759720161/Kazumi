@Component
export struct CoverSection {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @Prop @Watch('onCoverChanged') cover: string = ''
  @Prop @Watch('onCoverChanged') coverFallback: string = ''
  @Prop @Watch('onCoverChanged') bangumiCover: string = ''
  @Prop title: string = ''
  @Prop originalName: string = ''
  @Prop ratingScore: number = 0
  @Prop rank: number = 0
  @Prop airDate: string = ''
  @Prop votes: number = 0
  @Prop eps: number = 0
  @Prop isFavorite: boolean = false
  @State currentCover: string = ''
  @State coverKey: string = ''
  @State stableTopPadding: number = 92
  onFavoriteToggle?: () => void
  onBack?: () => void
  onOpenExternal?: () => void

  aboutToAppear(): void {
    this.stableTopPadding = this.computeTopPadding()
    this.coverKey = this.buildCoverKey()
    this.currentCover = this.selectBestCover()
  }

  build() {
    Stack() {
      if (this.currentCover.length > 0) {
        Image(this.currentCover)
          .width('100%')
          .height(486)
          .objectFit(ImageFit.Cover)
          .blur(26)
          .opacity(0.42)
          .onError(() => {
            this.tryNextCover()
          })
      }

      Column() {
        Row() {
          this.SymbolIconButton($r('sys.symbol.chevron_left'), () => {
            if (this.onBack) {
              this.onBack()
            }
          })

          Blank()

          if (this.onOpenExternal) {
            this.SymbolIconButton($r('sys.symbol.share'), () => {
              if (this.onOpenExternal) {
                this.onOpenExternal()
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 28, right: 28, top: this.stableTopPadding })

        Text(this.title)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title_green'))
          .lineHeight(36)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 28, right: 28, top: 12 })

        Row() {
          Image(this.currentCover.length > 0 ? this.currentCover : $r('app.media.ic_placeholder'))
            .width(156)
            .height(222)
            .objectFit(this.currentCover.length > 0 ? ImageFit.Cover : ImageFit.Contain)
            .borderRadius(12)
            .alt($r('app.media.ic_placeholder'))
            .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })

          Column() {
            Text('放送开始:')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_label_green'))

            Text(this.airDate.length > 0 ? this.airDate : '未知')
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.rating_star'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })

            Text(this.votes > 0 ? `${this.votes} 人评分:` : 'Bangumi 评分:')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_label_green'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 12 })

            Row() {
              Text(this.ratingScore > 0 ? this.ratingScore.toFixed(1) : '-')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.rating_star'))
                .margin({ right: 6 })
              this.Star(1)
              this.Star(2)
              this.Star(3)
              this.Star(4)
              this.Star(5)
            }
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })

            Text('Bangumi Ranked:')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_label_green'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 12 })

            Text(this.rank > 0 ? `#${this.rank}` : '#-')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.rating_star'))
              .margin({ top: 4 })

            Blank()

            Button() {
              Row() {
                SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_on_primary')])
                Text(this.isFavorite ? '已追' : '未追')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_on_primary'))
                  .margin({ left: 12 })
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
            }
            .width(136)
            .height(52)
            .borderRadius(26)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 16, color: $r('app.color.shadow_button_accent'), offsetY: 5 })
            .onClick(() => {
              if (this.onFavoriteToggle) {
                this.onFavoriteToggle()
              }
            })
          }
          .height(222)
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 18 })
        }
        .width('100%')
        .padding({ left: 28, right: 28, top: 18 })
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(486)
    .backgroundColor($r('app.color.page_background_green'))
  }

  @Builder
  private SymbolIconButton(symbol: Resource, action: () => void) {
    Button() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(44)
    .height(44)
    .backgroundColor($r('app.color.button_ghost_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.border_subtle') })
    .shadow({ radius: 14, color: $r('app.color.shadow_surface'), offsetY: 4 })
    .borderRadius(22)
    .onClick(() => {
      action()
    })
  }

  @Builder
  private Star(index: number) {
    SymbolGlyph($r('sys.symbol.star_fill'))
      .fontSize(19)
      .fontColor([this.ratingScore / 2 >= index ? $r('app.color.rating_star') : $r('app.color.rating_star_empty')])
      .margin({ right: 1 })
  }

  private selectBestCover(): string {
    if (this.bangumiCover.length > 0) {
      return this.bangumiCover
    }
    if (this.cover.length > 0) {
      return this.cover
    }
    return this.coverFallback
  }

  private computeTopPadding(): number {
    const safeHeight: number = this.topSafeHeight > 0 ? this.topSafeHeight : 36
    return safeHeight + 56
  }

  private buildCoverKey(): string {
    return `${this.bangumiCover}|${this.cover}|${this.coverFallback}`
  }

  private onCoverChanged(): void {
    const nextKey = this.buildCoverKey()
    if (nextKey === this.coverKey) {
      return
    }
    this.coverKey = nextKey
    if (this.currentCover.length === 0) {
      this.currentCover = this.selectBestCover()
    }
  }

  private tryNextCover(): void {
    if (this.currentCover === this.bangumiCover && this.cover.length > 0) {
      this.currentCover = this.cover
    } else if (this.currentCover === this.cover && this.coverFallback.length > 0) {
      this.currentCover = this.coverFallback
    } else {
      this.currentCover = ''
    }
  }
}
