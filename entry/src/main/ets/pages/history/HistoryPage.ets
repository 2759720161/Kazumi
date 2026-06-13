import { HistoryStore } from '../../store/HistoryStore'
import { HistoryRecord } from '../../models/HistoryRecord'
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

const logger = new Logger('HistoryPage')

@Component
export struct HistoryPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State histories: HistoryRecord[] = []
  @State isLoading: boolean = true
  private historyStore: HistoryStore = new HistoryStore()
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadHistories()
  }

  build() {
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
      } else if (this.histories.length === 0) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')
          EmptyState({ message: '暂无观看历史' })
        }
        .width('100%')
        .height('100%')
      } else {
        List({ space: 0, initialIndex: 0, scroller: this.scroller }) {
          ListItem() {
            Column()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .hitTestBehavior(HitTestMode.None)
          }
          .selectable(false)

          ForEach(this.histories, (record: HistoryRecord) => {
            ListItem() {
              Row() {
                Image(record.animeCover)
                  .width(80)
                  .height(107)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(4)
                  .alt($r('app.media.ic_placeholder'))
                  .onError(() => {
                    logger.warn('History cover load failed: %{public}s',
                      record.animeCover.length > 80 ? record.animeCover.substring(0, 80) : record.animeCover)
                  })

                Column() {
                  Text(record.animeName)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(record.episodeName)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })

                  Row() {
                    Text(this.formatTime(record.positionMs))
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))

                    Text(' / ')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))

                    Text(this.formatTime(record.durationMs))
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => {
                if (record.episodeUrl.length > 0) {
                  router.pushUrl({
                    url: 'pages/player/PlayerPage',
                    params: {
                      episodeUrl: record.episodeUrl,
                      animeName: record.animeName,
                      episodeName: record.episodeName,
                      animeId: record.animeId,
                      animeCover: record.animeCover,
                      animeUrl: record.animeUrl,
                      ruleSourceId: record.sourceId,
                      sourceId: record.sourceId
                    }
                  })
                }
              })
            }
          }, (record: HistoryRecord) => String(record.id))

          ListItem() {
            Column()
              .width('100%')
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .hitTestBehavior(HitTestMode.None)
          }
          .selectable(false)
        }
        .width('100%')
        .height('100%')
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider_color') })
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .titleBar(buildTitleBarOptions('历史'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  private async loadHistories(): Promise<void> {
    try {
      this.histories = await this.historyStore.getAll()
    } catch (err) {
      logger.error('Load histories failed: %{public}s', JSON.stringify(err))
    } finally {
      this.isLoading = false
    }
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`
  }
}
