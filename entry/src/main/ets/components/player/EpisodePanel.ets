@Component
export struct EpisodePanel {
  @Prop isVisible: boolean = false;
  @Prop episodes: EpisodePanelItem[] = [];
  @Prop currentIndex: number = -1;
  onEpisodeSelected?: (index: number) => void;
  onClose?: () => void;

  build() {
    if (this.isVisible) {
      Column() {
        Row() {
          Text('选集')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_on_primary'))
            .layoutWeight(1)

          Text(this.currentIndex >= 0 ? `当前 ${this.currentIndex + 1}/${this.episodes.length}` : `${this.episodes.length} 集`)
            .fontSize(12)
            .fontColor($r('app.color.text_overlay_dim'))
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 10 })

        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.episodes, (ep: EpisodePanelItem, index?: number) => {
              Row() {
                Text(ep.name)
                  .fontSize(14)
                  .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(index === this.currentIndex ? $r('app.color.text_title') : $r('app.color.text_on_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
              }
              .height(42)
              .width('30.5%')
              .padding({ left: 8, right: 8 })
              .margin({ right: '2.8%', bottom: 10 })
              .backgroundColor(index === this.currentIndex ? $r('app.color.accent_blue_light') : $r('app.color.border_light'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: index === this.currentIndex ? $r('app.color.border_subtle') : $r('app.color.border_light') })
              .borderRadius(8)
              .onClick(() => {
                if (this.onEpisodeSelected && index !== undefined) {
                  this.onEpisodeSelected(index);
                }
                if (this.onClose) {
                  this.onClose();
                }
              })
            }, (ep: EpisodePanelItem, index?: number) => `panel_ep_${index}`)
          }
          .padding({ left: 18, right: 18, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('52%')
      .backgroundColor($r('app.color.panel_dark_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius({ topLeft: 22, topRight: 22 })
      .shadow({ radius: 26, color: $r('app.color.overlay_topbar_bg'), offsetY: -8 })
      .align(Alignment.Bottom)
    }
  }
}

export class EpisodePanelItem {
  name: string = '';
  url: string = '';
}
