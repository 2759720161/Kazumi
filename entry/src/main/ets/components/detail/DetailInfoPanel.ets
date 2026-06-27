@Component
export struct DetailInfoPanel {
  @Prop @Watch('onCoverChanged') cover: string = ''
  @Prop @Watch('onCoverChanged') coverFallback: string = ''
  @Prop @Watch('onCoverChanged') bangumiCover: string = ''
  @Prop ratingScore: number = 0
  @Prop rank: number = 0
  @Prop votes: number = 0
  @Link airDate: string
  @Link eps: number
  @State currentCover: string = ''
  @State coverKey: string = ''

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
    this.currentCover = this.selectBestCover()
  }

  build() {
    Row() {
      Image(this.currentCover.length > 0 ? this.currentCover : $r('app.media.ic_placeholder'))
        .width(118)
        .height(168)
        .objectFit(this.currentCover.length > 0 ? ImageFit.Cover : ImageFit.Contain)
        .borderRadius(14)
        .alt($r('app.media.ic_placeholder'))
        .shadow({ radius: 18, color: $r('app.color.shadow_surface'), offsetY: 7 })
        .onError(() => {
          this.tryNextCover()
        })

      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.DashboardMetric(this.getRatingText(), '评分')

          this.DashboardMetric(this.getRankText(), '排名')
        }
        .width('100%')
        .height(79)

        Row({ space: 10 }) {
          this.EpisodeMetric()

          this.VotesMetric()
        }
        .width('100%')
        .height(79)
      }
      .layoutWeight(1)
      .height(168)
      .margin({ left: 16 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .borderRadius(22)
    .backgroundColor($r('app.color.card_surface_blue'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.border_specular') })
    .shadow({ radius: 18, color: $r('app.color.shadow_surface'), offsetY: 7 })
  }

  @Builder
  private DashboardMetric(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(this.getMetricFontSize(label))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')

      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height(79)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 10 })
    .borderRadius(14)
    .backgroundColor($r('app.color.tag_chip_bg'))
  }

  @Builder
  private EpisodeMetric() {
    Column() {
      Text(this.eps > 0 ? `${this.eps}` : '未知')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')

      Text('集数')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height(79)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 10 })
    .borderRadius(14)
    .backgroundColor($r('app.color.tag_chip_bg'))
  }

  @Builder
  private VotesMetric() {
    Column() {
      Text(this.getVotesText())
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')

      Text('评分人数')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height(79)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 10 })
    .borderRadius(14)
    .backgroundColor($r('app.color.tag_chip_bg'))
  }

  private getVotesText(): string {
    if (this.votes <= 0) {
      return '-'
    }
    if (this.votes >= 100000000) {
      return `${this.formatCompactNumber(this.votes / 100000000)}亿`
    }
    if (this.votes >= 10000) {
      return `${this.formatCompactNumber(this.votes / 10000)}万`
    }
    return `${this.votes}`
  }

  private formatCompactNumber(value: number): string {
    const fixed = value.toFixed(1)
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed
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

  private getRatingText(): string {
    return this.ratingScore > 0 ? this.ratingScore.toFixed(1) : '-'
  }

  private getRankText(): string {
    return this.rank > 0 ? `#${this.rank}` : '-'
  }

  private getMetricFontSize(label: string): number {
    return 21
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
