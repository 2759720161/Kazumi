import { Logger } from '../../utils/Logger'
import { ImageCacheStore } from '../../store/ImageCacheStore'

const logger = new Logger('AnimeCard')

@Component
export struct AnimeCard {
  @Prop name: string = '';
  @Prop @Watch('onCoverChanged') cover: string = '';
  @Prop @Watch('onCoverChanged') coverFallback: string = '';
  @Prop @Watch('onCoverChanged') bangumiCover: string = '';
  @Prop sourceName: string = '';
  @State currentCover: string = '';
  @State hasError: boolean = false;
  @State coverKey: string = '';
  @State isPressed: boolean = false;
  onCardClick?: () => void;

  aboutToAppear(): void {
    this.coverKey = this.buildCoverKey()
    this.currentCover = this.selectBestCover()
    this.hasError = false
    const selected = this.selectBestCover()
    logger.info('Card[%{public}s]: bangumi=%{public}d rule=%{public}d fallback=%{public}d selected=%{public}s',
      this.name.substring(0, 15),
      this.bangumiCover.length > 0 ? 1 : 0,
      this.cover.length > 0 ? 1 : 0,
      this.coverFallback.length > 0 ? 1 : 0,
      selected.length > 40 ? selected.substring(0, 40) : selected)
    this.prepareCachedCover(this.coverKey)
  }

  build() {
    Column({ space: 8 }) {
      if (this.hasError && this.currentCover.length === 0) {
        Image($r('app.media.ic_placeholder'))
          .draggable(false)
          .width('100%')
          .height(0)
          .aspectRatio(3 / 4)
          .objectFit(ImageFit.Contain)
          .borderRadius(12)
      } else {
        Image(this.currentCover.length > 0 ? this.currentCover : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width('100%')
          .height(0)
          .aspectRatio(3 / 4)
          .objectFit(this.currentCover.length > 0 ? ImageFit.Cover : ImageFit.Contain)
          .borderRadius(12)
          .alt($r('app.media.ic_placeholder'))
          .onError(() => {
            const urlPrefix = this.currentCover.length > 120 ?
              this.currentCover.substring(0, 120) : this.currentCover
            logger.warn('Image load failed: %{public}s', urlPrefix)
            this.tryNextCover()
          })
      }

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

  private selectBestCover(): string {
    if (this.bangumiCover.length > 0) {
      return this.bangumiCover;
    }
    if (this.cover.length > 0) {
      return this.cover;
    }
    if (this.coverFallback.length > 0) {
      return this.coverFallback;
    }
    return '';
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
    this.currentCover = this.selectBestCover()
    this.hasError = false
    this.prepareCachedCover(nextKey)
  }

  private tryNextCover(): void {
    if (this.currentCover === this.bangumiCover && this.cover.length > 0) {
      logger.info('Bangumi cover failed, trying rule cover')
      this.currentCover = this.cover
      this.hasError = false
    } else if (this.currentCover === this.cover && this.coverFallback.length > 0) {
      logger.info('Rule cover failed, trying fallback')
      this.currentCover = this.coverFallback
      this.hasError = false
    } else {
      logger.info('All covers failed for: %{public}s', this.name.substring(0, 30))
      this.currentCover = ''
      this.hasError = true
    }
  }

  private async prepareCachedCover(expectedKey: string): Promise<void> {
    const urls: string[] = [];
    if (this.bangumiCover.length > 0) {
      urls.push(this.bangumiCover);
    }
    if (this.cover.length > 0) {
      urls.push(this.cover);
    }
    if (this.coverFallback.length > 0) {
      urls.push(this.coverFallback);
    }
    if (urls.length === 0) {
      return;
    }

    const localUri = await ImageCacheStore.getInstance().getCachedImageUri(urls)
    if (this.coverKey !== expectedKey) {
      return;
    }
    if (localUri.length > 0) {
      this.currentCover = localUri
      this.hasError = false
    }
  }
}
