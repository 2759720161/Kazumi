import { ImageCacheStore } from '../../store/ImageCacheStore'
import { HOME_PRELOAD_ENABLED_KEY, isHomePreloadEnabled } from '../../utils/HomePreloadGate'

@Component
export struct CachedRemoteImage {
  @Prop @Watch('onSourceChanged') source: string = ''
  @Prop sources: string[] = []
  @Prop sharedId: string = ''
  @Prop priority: boolean = false
  @Prop pauseWhenHomeInactive: boolean = false
  @StorageLink(HOME_PRELOAD_ENABLED_KEY) @Watch('onHomePreloadGateChanged')
  homePreloadEnabled: boolean = true
  @Prop blurRadius: number = 0
  @Prop imageOpacity: number = 1
  @Prop cornerRadius: number = 12
  @State currentSource: string = ''
  @State fallbackIndex: number = 0
  private requestKey: string = ''
  private requestSerial: number = 0

  aboutToAppear(): void {
    if (this.canLoadImage()) {
      this.reloadSource(this.source)
    }
  }

  private onHomePreloadGateChanged(): void {
    if (!this.pauseWhenHomeInactive) {
      return
    }
    if (this.canLoadImage()) {
      this.reloadSource(this.source)
    } else {
      this.requestSerial++
      this.requestKey = ''
      this.currentSource = ''
    }
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
    if (!this.canLoadImage()) {
      this.requestSerial++
      this.requestKey = ''
      this.currentSource = ''
      return
    }
    const serial = ++this.requestSerial
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
    this.loadCachedSource(source, serial)
  }

  private async loadCachedSource(expectedSource: string, serial: number): Promise<void> {
    const candidates = this.getCandidates()
    const localUri = await ImageCacheStore.getInstance().getCachedImageUri(candidates, this.priority)
    if (this.requestKey !== expectedSource || this.requestSerial !== serial || !this.canLoadImage()) {
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

  private canLoadImage(): boolean {
    return !this.pauseWhenHomeInactive || (this.homePreloadEnabled && isHomePreloadEnabled())
  }

  private pushCandidate(candidates: string[], value: string): void {
    if (value.length > 0 && candidates.indexOf(value) < 0) {
      candidates.push(value)
    }
  }
}
