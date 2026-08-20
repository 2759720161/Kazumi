import { CollectedBangumi } from '../../models/CollectedBangumi'
import { CachedRemoteImage } from '../common/CachedRemoteImage'
import { DetailNavigationParams, navigateToDetail } from '../../utils/DetailNavigation'

@Component
export struct CollectCard {
  @Prop collectedBangumi: CollectedBangumi
  @Prop isEditMode: boolean = false
  @State isPressed: boolean = false
  onRemove?: () => void

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        CachedRemoteImage({
          source: this.getCoverUrl(),
          sources: this.getCoverUrls(),
          sharedId: this.getSharedCoverId()
        })
          .width('100%')
          .height('100%')
          .borderRadius(12)

        if (this.isEditMode) {
          this.StatusButton()
        } else {
          this.StatusBadge()
        }
      }
      .width('100%')
      .aspectRatio(3 / 4)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 4 })
      .clip(true)

      Text(this.collectedBangumi.animeName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(18)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150 })
    .onClick(() => {
      if (this.isEditMode) {
        this.requestRemove()
      } else {
        const params = new DetailNavigationParams()
        params.animeName = this.collectedBangumi.animeName
        params.animeCover = this.collectedBangumi.animeCover
        params.animeCoverFallback = this.collectedBangumi.coverFallback
        params.animeBangumiCover = this.collectedBangumi.bangumiCover
        params.animeDesc = this.collectedBangumi.animeDesc
        params.animeUrl = this.collectedBangumi.animeUrl
        params.sourceName = this.collectedBangumi.sourceName
        params.sourceId = this.collectedBangumi.sourceId
        params.bangumiId = this.collectedBangumi.bangumiId
        params.sharedCoverId = this.getSharedCoverId()
        params.transitionCover = this.getTransitionCover()
        navigateToDetail(params)
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

  @Builder
  private StatusBadge(): void {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(12)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(24)
      .height(24)
      .borderRadius(12)
      .backgroundColor($r('app.color.button_accent_bg'))
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.End)
    .padding({ top: 6, right: 6 })
    .position({ x: 0, y: 0 })
  }

  @Builder
  private StatusButton(): void {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.heart_slash'))
          .fontSize(16)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor($r('app.color.button_primary_bg'))
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.requestRemove()
      })
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.End)
    .padding({ top: 6, right: 6 })
    .position({ x: 0, y: 0 })
  }

  private getCoverUrl(): string {
    return this.collectedBangumi.getBestCover()
  }

  private getCoverUrls(): string[] {
    const urls: string[] = []
    this.pushCoverUrl(urls, this.collectedBangumi.bangumiCover)
    this.pushCoverUrl(urls, this.collectedBangumi.animeCover)
    this.pushCoverUrl(urls, this.collectedBangumi.coverFallback)
    return urls
  }

  private pushCoverUrl(urls: string[], url: string): void {
    if (url.length > 0 && urls.indexOf(url) < 0) {
      urls.push(url)
    }
  }

  private requestRemove(): void {
    this.onRemove?.()
  }

  private getSharedCoverId(): string {
    if (this.getTransitionCover().length === 0) {
      return ''
    }
    const subjectId = this.collectedBangumi.bangumiId > 0 ? this.collectedBangumi.bangumiId : this.collectedBangumi.id
    return 'collect-cover-' + subjectId.toString()
  }

  private getTransitionCover(): string {
    return this.collectedBangumi.getBestCover()
  }
}
