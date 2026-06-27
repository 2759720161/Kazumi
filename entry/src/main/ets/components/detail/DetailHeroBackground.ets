@Component
export struct DetailHeroBackground {
  @Prop @Watch('onCoverChanged') cover: string = ''
  @Prop @Watch('onCoverChanged') coverFallback: string = ''
  @Prop @Watch('onCoverChanged') bangumiCover: string = ''
  @State currentCover: string = ''
  @State coverKey: string = ''

  topSafeHeight: number = 0

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
          .blur(14)
          .opacity(0.72)
          .onError(() => {
            this.tryNextCover()
          })
      }

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [$r('app.color.hero_gradient_start'), 0],
            [$r('app.color.hero_gradient_dark'), 0.34],
            [$r('app.color.hero_gradient_mid'), 0.78],
            [$r('app.color.page_background_media'), 1]
          ]
        })
    }
    .width('100%')
    .height(420 + this.topSafeHeight)
    .backgroundColor($r('app.color.page_background_media'))
    .hitTestBehavior(HitTestMode.None)
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
