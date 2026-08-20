import { ImageCacheStore } from '../../store/ImageCacheStore'

@Component
export struct CachedRemoteImage {
  @Prop @Watch('onSourceChanged') source: string = ''
  @Prop sources: string[] = []
  @Prop sharedId: string = ''
  @Prop blurRadius: number = 0
  @Prop imageOpacity: number = 1
  @Prop cornerRadius: number = 12
  @State currentSource: string = ''
  @State fallbackIndex: number = 0
  private requestKey: string = ''

  aboutToAppear(): void {
    this.reloadSource(this.source)
  }

  build() {
    Stack() {
      if (this.sharedId.length > 0) {
        Image(this.currentSource.length > 0 ? this.currentSource : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.blurRadius)
          .opacity(this.imageOpacity)
          .alt($r('app.media.ic_placeholder'))
          .borderRadius(this.cornerRadius)
          .clip(true)
          .sharedTransition(this.sharedId, { duration: 420, curve: Curve.FastOutSlowIn })
          .onError(() => {
            this.handleImageError()
          })
      } else {
        Image(this.currentSource.length > 0 ? this.currentSource : $r('app.media.ic_placeholder'))
          .draggable(false)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.blurRadius)
          .opacity(this.imageOpacity)
          .alt($r('app.media.ic_placeholder'))
          .borderRadius(this.cornerRadius)
          .clip(true)
          .onError(() => {
            this.handleImageError()
          })
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.cornerRadius)
    .clip(true)
  }

  private onSourceChanged(): void {
    this.reloadSource(this.source)
  }

  private reloadSource(source: string): void {
    this.requestKey = source
    this.fallbackIndex = 0
    if (source.length === 0 && this.sources.length === 0) {
      this.currentSource = ''
      return
    }
    if (source.length > 0 && (source.startsWith('file://') || source.startsWith('/'))) {
      this.currentSource = source
      return
    }
    // Do not give the remote URL to Image until the shared cache request has
    // completed. This prevents duplicate downloads during page construction.
    this.currentSource = ''
    this.loadCachedSource(source)
  }

  private async loadCachedSource(expectedSource: string): Promise<void> {
    const candidates = this.getCandidates()
    const localUri = await ImageCacheStore.getInstance().getCachedImageUri(candidates)
    if (this.requestKey !== expectedSource) {
      return
    }
    this.currentSource = localUri.length > 0 ? localUri : candidates[0]
  }

  private handleImageError(): void {
    const candidates = this.getCandidates()
    if (candidates.length === 0) {
      this.currentSource = ''
      return
    }
    const currentIndex = candidates.indexOf(this.currentSource)
    const nextIndex = currentIndex >= 0 ? currentIndex + 1 : this.fallbackIndex
    if (nextIndex < candidates.length) {
      this.fallbackIndex = nextIndex + 1
      this.currentSource = candidates[nextIndex]
    } else {
      this.currentSource = ''
    }
  }

  private getCandidates(): string[] {
    const candidates: string[] = []
    this.pushCandidate(candidates, this.source)
    for (let i = 0; i < this.sources.length; i++) {
      this.pushCandidate(candidates, this.sources[i])
    }
    return candidates
  }

  private pushCandidate(candidates: string[], value: string): void {
    if (value.length > 0 && candidates.indexOf(value) < 0) {
      candidates.push(value)
    }
  }
}
