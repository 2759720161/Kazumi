@Component
export struct RouteTabs {
  @Prop routes: string[] = [];
  @Link currentRoute: number;

  build() {
    if (this.routes.length > 1) {
      Tabs() {
        ForEach(this.routes, (route: string, index?: number) => {
          TabContent() {
            Column()
          }
          .tabBar(route)
        }, (route: string, index?: number) => `route_${index}`)
      }
      .barMode(BarMode.Scrollable)
      .width('100%')
      .height(48)
      .onChange((index: number) => {
        this.currentRoute = index;
      })
    }
  }
}