import { EpisodeData } from '../../models/EpisodeData'

@Component
export struct EpisodeList {
  @Prop episodes: EpisodeData[] = [];
  @Prop currentEpisodeIndex: number = -1;
  onEpisodeClick?: (index: number) => void;

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.episodes, (ep: EpisodeData, index?: number) => {
        Button(ep.name)
          .height(36)
          .fontSize(13)
          .margin({ right: 8, bottom: 8 })
          .backgroundColor(index === this.currentEpisodeIndex ? $r('app.color.button_primary_bg') : $r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: index === this.currentEpisodeIndex ? $r('app.color.border_specular') : $r('app.color.border_subtle') })
          .shadow({
            radius: index === this.currentEpisodeIndex ? 12 : 6,
            color: index === this.currentEpisodeIndex ? $r('app.color.shadow_button_primary') : $r('app.color.shadow_light'),
            offsetY: index === this.currentEpisodeIndex ? 4 : 2
          })
          .fontColor(index === this.currentEpisodeIndex ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
          .onClick(() => {
            if (this.onEpisodeClick && index !== undefined) {
              this.onEpisodeClick(index);
            }
          })
      }, (ep: EpisodeData, index?: number) => `ep_${index}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}

