@Component
export struct DanmakuCanvas {
  @Prop isDanmakuEnabled: boolean = true
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  onCanvasReady?: (context: CanvasRenderingContext2D, width: number, height: number) => void
  onCanvasSizeChanged?: (width: number, height: number) => void

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        const width = this.context.width
        const height = this.context.height
        if (this.onCanvasReady) {
          this.onCanvasReady(this.context, width, height)
        }
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width)
        const height = Number(newArea.height)
        if (width > 0 && height > 0 && this.onCanvasSizeChanged) {
          this.onCanvasSizeChanged(width, height)
        }
      })
  }
}