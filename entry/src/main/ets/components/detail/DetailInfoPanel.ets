import { CachedRemoteImage } from '../common/CachedRemoteImage'

@Component
export struct DetailInfoPanel {
  @Prop @Watch('onCoverChanged') cover: string = ''
  @Prop @Watch('onCoverChanged') coverFallback: string = ''
  @Prop @Watch('onCoverChanged') bangumiCover: string = ''
  @Prop sharedCover: string = ''
  @Prop sharedCoverId: string = ''
  @Prop ratingScore: number = 0
  @Prop rank: number = 0
  @Prop votes: number = 0
  @Link airDate: string
  @Link eps: number
  @State currentCover: string = ''
  @State coverKey: string = ''
  isWideLayout: boolean = false

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
    this.currentCover = this.selectBestCover()
  }

  build() {
    if (this.isWideLayout) {
      this.WideLayout()
    } else {
      this.CompactLayout()
    }
  }

  @Builder
  private CompactLayout() {
    Row() {
      CachedRemoteImage({
        source: this.getDisplayCover(),
        sources: this.buildCoverUrls(),
        sharedId: this.sharedCoverId,
        cornerRadius: 14
      })
        .width(118)
        .height(168)
        .borderRadius(14)
        .shadow({ radius: 20, color: $r('app.color.detail_info_shadow'), offsetY: 8 })

      Column({ space: 8 }) {
        this.PrimaryMetric()
        this.DetailMetricDivider()
        this.DetailMetricRow('排名', this.getRankText())
        this.DetailMetricRow('集数', this.getEpisodeText())
        this.DetailMetricRow('评分人数', this.getVotesText())
      }
      .layoutWeight(1)
      .height(168)
      .justifyContent(FlexAlign.Center)
      .margin({ left: 18 })
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 2, bottom: 8 })
    .backgroundColor($r('app.color.detail_info_panel_bg'))
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private WideLayout() {
    Column({ space: 14 }) {
      CachedRemoteImage({
        source: this.getDisplayCover(),
        sources: this.buildCoverUrls()
      })
        .width('100%')
        .aspectRatio(118 / 168)
        .borderRadius(12)
        .shadow({ radius: 20, color: $r('app.color.detail_info_shadow'), offsetY: 8 })

      Column({ space: 8 }) {
        this.PrimaryMetric()
        this.DetailMetricDivider()
        this.DetailMetricRow('排名', this.getRankText())
        this.DetailMetricRow('集数', this.getEpisodeText())
        this.DetailMetricRow('评分人数', this.getVotesText())
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 2, bottom: 8 })
    .backgroundColor($r('app.color.detail_info_panel_bg'))
  }

  @Builder
  private PrimaryMetric() {
    Column() {
      Text(this.getRatingText())
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rating_star'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')

      Text('Bangumi 评分')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textAlign(TextAlign.Start)
        .width('100%')
        .margin({ top: 5 })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DetailMetricRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_subtitle'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .layoutWeight(1)

      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height(24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private DetailMetricDivider() {
    Row()
      .width('100%')
      .height(1)
      .backgroundColor($r('app.color.divider_blue'))
      .opacity(0.72)
      .margin({ top: 2, bottom: 2 })
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
    if (this.sharedCover.length > 0) {
      return this.sharedCover
    }
    if (this.cover.startsWith('file://') || this.cover.startsWith('/')) {
      return this.cover
    }
    if (this.bangumiCover.length > 0) {
      return this.bangumiCover
    }
    if (this.cover.length > 0) {
      return this.cover
    }
    return this.coverFallback
  }

  private getDisplayCover(): string {
    if (this.currentCover.length > 0) {
      return this.currentCover
    }
    if (this.sharedCover.length > 0) {
      return this.sharedCover
    }
    return ''
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

  private buildCoverUrls(): string[] {
    const urls: string[] = []
    this.pushCoverUrl(urls, this.sharedCover)
    this.pushCoverUrl(urls, this.bangumiCover)
    this.pushCoverUrl(urls, this.cover)
    this.pushCoverUrl(urls, this.coverFallback)
    return urls
  }

  private pushCoverUrl(urls: string[], url: string): void {
    if (url.length > 0 && urls.indexOf(url) < 0) {
      urls.push(url)
    }
  }
}
