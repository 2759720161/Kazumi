import { CachedRemoteImage } from './CachedRemoteImage'
import { BangumiConfig } from '../../core/api/BangumiConfig'

@Component
export struct AnimeCard {
  @Prop name: string = '';
  @Prop @Watch('onCoverChanged') cover: string = '';
  @Prop @Watch('onCoverChanged') coverFallback: string = '';
  @Prop @Watch('onCoverChanged') bangumiCover: string = '';
  @Prop @Watch('onCoverChanged') coverLarge: string = '';
  @Prop @Watch('onCoverChanged') coverCommon: string = '';
  @Prop @Watch('onCoverChanged') coverMedium: string = '';
  @Prop @Watch('onCoverChanged') bangumiId: number = -1;
  @Prop imagePriority: boolean = false;
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
        sharedId: this.sharedCoverId,
        priority: this.imagePriority
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
    return `${this.bangumiId}|${this.bangumiCover}|${this.coverLarge}|${this.coverCommon}|${this.coverMedium}|${this.cover}|${this.coverFallback}`;
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
    if (this.bangumiId > 0) {
      const fallbackUrls = BangumiConfig.getSubjectImageUrls(this.bangumiId)
      for (let i = 0; i < fallbackUrls.length; i++) {
        this.pushCoverUrl(urls, fallbackUrls[i])
      }
    }
    // Grid cards should prefer the common/medium variants. They are smaller,
    // load faster, and avoid stalling the visible search result on a large CDN
    // response while the home page is preloading in the background.
    this.pushCoverUrl(urls, this.coverCommon)
    this.pushCoverUrl(urls, this.coverMedium)
    this.pushCoverUrl(urls, this.bangumiCover)
    this.pushCoverUrl(urls, this.coverLarge)
    this.pushCoverUrl(urls, this.cover)
    this.pushCoverUrl(urls, this.coverFallback)
    return urls
  }

  private pushCoverUrl(urls: string[], url: string): void {
    const raw = url.trim()
    if (raw.length === 0) {
      return
    }
    const normalized = raw.startsWith('file://') || raw.startsWith('/')
      ? raw
      : BangumiConfig.normalizeImageUrl(raw)
    if (normalized.length === 0) {
      return
    }
    const compact = this.compactBangumiCoverUrl(normalized)
    if (urls.indexOf(compact) < 0) {
      urls.push(compact)
    }
    if (compact !== normalized && urls.indexOf(normalized) < 0) {
      urls.push(normalized)
    }
  }

  private compactBangumiCoverUrl(url: string): string {
    if (url.indexOf('/r/800/') >= 0) {
      return url.replace('/r/800/', '/r/200/')
    }
    if (url.indexOf('/r/400/') >= 0) {
      return url.replace('/r/400/', '/r/200/')
    }
    return url
  }

  private getPrimaryCoverUrl(): string {
    const urls = this.getCoverUrls()
    return urls.length > 0 ? urls[0] : ''
  }
}
