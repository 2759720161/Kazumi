import { CachedRemoteImage } from './CachedRemoteImage'

@Component
export struct AnimeCard {
  @Prop name: string = '';
  @Prop @Watch('onCoverChanged') cover: string = '';
  @Prop @Watch('onCoverChanged') coverFallback: string = '';
  @Prop @Watch('onCoverChanged') bangumiCover: string = '';
  @Prop sourceName: string = '';
  @Prop sharedCoverId: string = '';
  @State coverKey: string = '';
  @State isPressed: boolean = false;
  onCardClick?: () => void;

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
  }

  build() {
    Column({ space: 8 }) {
      CachedRemoteImage({
        source: this.getPrimaryCoverUrl(),
        sources: this.getCoverUrls(),
        sharedId: this.sharedCoverId
      })
        .width('100%')
        .height(0)
        .aspectRatio(3 / 4)
        .borderRadius(12)

      Column() {
        Text(this.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .height(44)
      .alignItems(HorizontalAlign.Start)
    }
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150 })
    .onClick(() => {
      if (this.onCardClick) {
        this.onCardClick();
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
  }

  private buildCoverKey(): string {
    return `${this.bangumiCover}|${this.cover}|${this.coverFallback}`;
  }

  private onCoverChanged(): void {
    const nextKey = this.buildCoverKey()
    if (nextKey === this.coverKey) {
      return
    }
    this.coverKey = nextKey
  }

  private getCoverUrls(): string[] {
    const urls: string[] = []
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

  private getPrimaryCoverUrl(): string {
    const urls = this.getCoverUrls()
    return urls.length > 0 ? urls[0] : ''
  }
}
