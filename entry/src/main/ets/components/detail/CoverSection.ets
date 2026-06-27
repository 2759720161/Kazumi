@Component
export struct CoverSection {

  @Prop @Watch('onCoverChanged') cover: string = ''
  @Prop @Watch('onCoverChanged') coverFallback: string = ''
  @Prop @Watch('onCoverChanged') bangumiCover: string = ''
  @Prop title: string = ''
  @Prop originalName: string = ''
  @Prop ratingScore: number = 0
  @Prop rank: number = 0
  @Link airDate: string
  @Prop votes: number = 0
  @Link eps: number
  @State currentCover: string = ''
  @State coverKey: string = ''

  topSpacerHeight: number = 0


  aboutToAppear(): void {

    this.coverKey = this.buildCoverKey()
    this.currentCover = this.selectBestCover()
  }

  build() {
    Stack() {
      if (this.currentCover.length > 0) {
        Image(this.currentCover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(26)
          .opacity(0.38)
          .onError(() => {
            this.tryNextCover()
          })
      }

      Column() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [$r('app.color.hero_gradient_start'), 0],
          [$r('app.color.hero_gradient_dark'), 0.28],
          [$r('app.color.hero_gradient_mid'), 0.72],
          [$r('app.color.page_background_media'), 1]
        ]
      })

      Column() {
        Blank()

        this.HeroTitle()

        Blank()
          .height(16)

        this.InfoDashboard()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height(340 + this.topSpacerHeight)
    .backgroundColor($r('app.color.page_background_media'))
  }

  @Builder
  private HeroTitle() {
    Column() {
      Text(this.getDisplayTitle())
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .lineHeight(40)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.originalName.length > 0 && this.originalName !== this.title) {
        Text(this.originalName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  @Builder
  private InfoDashboard() {
    Row() {
      this.AirDateInfoLine()
      this.VerticalDivider()
      this.EpisodeInfoLine()
      this.VerticalDivider()
      this.RatingMetricBlock()
      this.VerticalDivider()
      this.RankMetricBlock()
    }
    .width('100%')
    .height(112)
    .padding({ left: 12, right: 12, top: 14, bottom: 14 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_surface_blue'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 0.5, color: $r('app.color.border_specular') })
    .shadow({ radius: 22, color: $r('app.color.shadow_surface'), offsetY: 8 })
  }

  @Builder
  private AirDateInfoLine() {
    Column() {
      Text(this.getAirDateText())
        .fontSize(this.airDate.length > 0 ? 15 : 17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      Text('放送')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private EpisodeInfoLine() {
    Column() {
      Text(this.getEpisodeText())
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      Text('全集')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private RatingMetricBlock() {
    Column() {
      Text(this.getRatingText())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      Text('Bgm 评分')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private RankMetricBlock() {
    Column() {
      Text(this.getRankText())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      Text('全站排名')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private VerticalDivider() {
    Row()
      .width(1)
      .height(48)
      .backgroundColor($r('app.color.divider_blue'))
      .margin({ left: 4, right: 4 })
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

  private getDisplayTitle(): string {
    if (this.title.length > 0) {
      return this.title
    }
    if (this.originalName.length > 0) {
      return this.originalName
    }
    return '未知番剧'
  }

  private getRatingText(): string {
    return this.ratingScore > 0 ? this.ratingScore.toFixed(1) : '-'
  }

  private getRankText(): string {
    return this.rank > 0 ? `#${this.rank}` : '-'
  }

  private getEpisodeText(): string {
    return this.eps > 0 ? `${this.eps} 集` : '未知'
  }

  private getAirDateText(): string {
    return this.airDate.length > 0 ? this.airDate : '未知'
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
    const nextCover = this.selectBestCover()
    if (nextCover.length > 0 && nextCover !== this.currentCover) {
      this.currentCover = nextCover
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
