@Component
export struct SearchBar {
  @Link keyword: string;
  @Prop placeholder: string = '搜索动漫...';
  onSearch?: () => void;

  build() {
    Row() {
      TextInput({ placeholder: this.placeholder, text: this.keyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor($r('app.color.button_ghost_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_subtle') })
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.keyword = value;
        })
        .onSubmit(() => {
          if (this.onSearch) {
            this.onSearch();
          }
        })

      Button('搜索')
        .height(40)
        .padding({ left: 18, right: 18 })
        .borderRadius(20)
        .backgroundColor($r('app.color.button_primary_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .shadow({ radius: 14, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
        .margin({ left: 8 })
        .onClick(() => {
          if (this.onSearch) {
            this.onSearch();
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}
