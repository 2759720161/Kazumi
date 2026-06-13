import { FavoriteStore } from '../../store/FavoriteStore'
import { FavoriteRecord } from '../../models/FavoriteRecord'
import { EmptyState } from '../../components/common/EmptyState'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'

const logger = new Logger('FavoritePage')

@Component
export struct FavoritePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State favorites: FavoriteRecord[] = []
  @State isLoading: boolean = true
  @State selectedSourceFilter: string = '全部'
  @State showDeleteDialog: boolean = false
  @State deleteTargetId: string = ''
  @State deleteTargetName: string = ''
  private favoriteStore: FavoriteStore = new FavoriteStore()
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadFavorites()
  }

  build() {
    Stack() {
      HdsNavigation() {
      if (this.isLoading) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.loading_color'))
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      } else if (this.favorites.length === 0) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')
          EmptyState({ message: '暂无收藏' })
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          this.SourceFilterBar()

          List({ space: 0, initialIndex: 0, scroller: this.scroller }) {
            ListItem() {
              Column()
                .height(getTopSpacerHeight(this.topSafeHeight))
                .hitTestBehavior(HitTestMode.None)
            }
            .selectable(false)

            ForEach(this.filteredFavorites(), (record: FavoriteRecord) => {
              ListItem() {
                Row() {
                  Image(record.animeCover)
                    .width(80)
                    .height(107)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(4)
                    .alt($r('app.media.ic_placeholder'))
                    .onError(() => {
                      logger.warn('Favorite cover load failed: %{public}s',
                        record.animeCover.length > 80 ? record.animeCover.substring(0, 80) : record.animeCover)
                    })

                  Column() {
                    Text(record.animeName)
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (record.sourceName.length > 0) {
                      Text(record.sourceName)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 4 })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })
                  .justifyContent(FlexAlign.Center)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/detail/DetailPage',
                    params: {
                      animeName: record.animeName,
                      animeCover: record.animeCover,
                      animeDesc: record.animeDesc,
                      animeUrl: record.animeUrl,
                      sourceName: record.sourceName,
                      sourceId: record.sourceId
                    }
                  })
                })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction(() => {
                      this.deleteTargetId = record.animeId
                      this.deleteTargetName = record.animeName
                      this.showDeleteDialog = true
                    })
                )
              }
            }, (record: FavoriteRecord) => String(record.id))

            ListItem() {
              Column()
                .width('100%')
                .height(getBottomSpacerHeight(this.bottomSafeHeight))
                .hitTestBehavior(HitTestMode.None)
            }
            .selectable(false)
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: $r('app.color.divider_color') })
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .titleBar(buildTitleBarOptions('收藏'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

    if (this.showDeleteDialog) {
      this.DeleteConfirmDialog()
    }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private SourceFilterBar() {
    Scroll() {
      Row() {
        ForEach(this.getSourceFilters(), (source: string) => {
          Text(source)
            .fontSize(13)
            .fontColor(this.selectedSourceFilter === source ? $r('app.color.text_on_primary') : $r('app.color.text_primary'))
            .backgroundColor(this.selectedSourceFilter === source ? $r('app.color.button_primary_bg') : $r('app.color.surface_button_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .borderRadius(16)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .margin({ right: 8 })
            .onClick(() => {
              this.selectedSourceFilter = source
            })
        }, (source: string) => `filter_${source}`)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(40)
    .margin({ top: 4, bottom: 4 })
  }

  @Builder
  private DeleteConfirmDialog() {
    Column() {
      Column() {
        Text('取消收藏')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 12 })

        Text(`确定要取消收藏「${this.deleteTargetName}」吗？`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 20 })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface_button_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .onClick(() => {
              this.showDeleteDialog = false
            })

          Button('删除')
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.status_error'))
            .fontColor($r('app.color.text_on_primary'))
            .margin({ left: 12 })
            .onClick(() => {
              this.confirmDelete()
            })
        }
        .width('100%')
      }
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0x66000000)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  private getSourceFilters(): string[] {
    const sourceSet: Set<string> = new Set()
    for (let i = 0; i < this.favorites.length; i++) {
      const name = this.favorites[i].sourceName
      if (name.length > 0) {
        sourceSet.add(name)
      }
    }
    const filters: string[] = ['全部']
    sourceSet.forEach((value: string) => {
      filters.push(value)
    })
    return filters
  }

  private filteredFavorites(): FavoriteRecord[] {
    if (this.selectedSourceFilter === '全部') {
      return this.favorites
    }
    return this.favorites.filter((r: FavoriteRecord) => r.sourceName === this.selectedSourceFilter)
  }

  private async loadFavorites(): Promise<void> {
    try {
      this.favorites = await this.favoriteStore.getAll()
    } catch (err) {
      logger.error('Load favorites failed: %{public}s', JSON.stringify(err))
    } finally {
      this.isLoading = false
    }
  }

  private async confirmDelete(): Promise<void> {
    this.showDeleteDialog = false
    try {
      await this.favoriteStore.remove(this.deleteTargetId)
      await this.loadFavorites()
    } catch (err) {
      logger.error('Delete favorite failed: %{public}s', JSON.stringify(err))
    }
  }
}
