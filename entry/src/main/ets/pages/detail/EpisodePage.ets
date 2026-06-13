import { PlaybackRoad, PlaybackSource } from '../../models/PlaybackRoad'
import { EpisodeData } from '../../models/EpisodeData'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight
} from '../../utils/HdsPageStyle'

const logger = new Logger('EpisodePage')

@Entry
@Component
export struct EpisodePage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State selectedRoadIndex: number = 0
  @State roads: PlaybackRoad[] = []
  @State sourceName: string = ''
  @State animeName: string = ''
  @State animeCover: string = ''
  private sourceId: number = -1
  private animeUrl: string = ''
  private scroller: Scroller = new Scroller()
  private bangumiId: number = 0

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>
    if (params !== null) {
      if (params['sourceName'] !== undefined) this.sourceName = params['sourceName'] as string
      if (params['animeName'] !== undefined) this.animeName = params['animeName'] as string
      if (params['animeCover'] !== undefined) this.animeCover = params['animeCover'] as string
      if (params['sourceId'] !== undefined) this.sourceId = params['sourceId'] as number
      if (params['animeUrl'] !== undefined) this.animeUrl = params['animeUrl'] as string
      if (params['roadsJson'] !== undefined) {
        this.roads = this.parseRoads(params['roadsJson'] as string)
      }
      if (params['bangumiId'] !== undefined) this.bangumiId = params['bangumiId'] as number
    }
  }

  build() {
    Stack() {
      Scroll(this.scroller) {
        Column() {
          Column()
            .height(getTopSpacerHeight(this.topSafeHeight) + 12)
            .hitTestBehavior(HitTestMode.None)

          this.HeaderSection()

          if (this.roads.length > 0) {
            this.RoadSelector()
            this.EpisodeGrid()
          } else {
            this.EmptySection()
          }

          Column()
            .width('100%')
            .height(getBottomSpacerHeight(this.bottomSafeHeight) + 32)
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)

      this.TopBar()
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_green'))
    .ignoreLayoutSafeArea()
  }

  @Builder
  private TopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_title_green')])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.surface_button_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_subtle') })
      .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 3 })
      .onClick(() => {
        router.back()
      })

      Blank()
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: getTopSpacerHeight(this.topSafeHeight) + 4 })
  }

  @Builder
  private HeaderSection() {
    Column() {
      Text(this.animeName.length > 0 ? this.animeName : '播放列表')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title_green'))
        .lineHeight(40)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row() {
        Text(this.sourceName.length > 0 ? this.sourceName : '播放源')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.rating_star'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor($r('app.color.source_badge_bg'))

        Text(`${this.getEpisodeTotal()} 集`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_muted_green'))
          .margin({ left: 10 })
      }
      .margin({ top: 14 })
      .width('100%')
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 46, bottom: 20 })
  }

  @Builder
  private RoadSelector() {
    Column() {
      Text('播放线路')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title_green'))
        .width('100%')
        .margin({ bottom: 14 })

      Scroll() {
        Row() {
          ForEach(this.roads, (road: PlaybackRoad, index?: number) => {
            Row() {
              Text(road.name.length > 0 ? road.name : `线路${(index !== undefined ? index : 0) + 1}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(index === this.selectedRoadIndex ? $r('app.color.text_on_primary') : $r('app.color.text_title_green'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(42)
            .padding({ left: 18, right: 18 })
            .borderRadius(21)
            .backgroundColor(index === this.selectedRoadIndex ? $r('app.color.accent_green') : $r('app.color.road_unselected_bg'))
            .border({ width: 1, color: index === this.selectedRoadIndex ? $r('app.color.accent_green') : $r('app.color.border_item') })
            .margin({ right: 10 })
            .onClick(() => {
              if (index !== undefined) {
                this.selectedRoadIndex = index
              }
            })
          }, (road: PlaybackRoad, index?: number) => `road_${index}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 6, bottom: 24 })
  }

  @Builder
  private EpisodeGrid() {
    Column() {
      Row() {
        Text('剧集')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title_green'))
          .layoutWeight(1)

        Text(`${this.getCurrentEpisodeCount()} 集`)
          .fontSize(14)
          .fontColor($r('app.color.text_muted_green'))
      }
      .width('100%')
      .margin({ bottom: 14 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.getCurrentEpisodes(), (ep: EpisodeData, index?: number) => {
          Row() {
            Text(ep.name.length > 0 ? ep.name : `第${(index !== undefined ? index : 0) + 1}集`)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title_green'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
          }
          .height(48)
          .width('30.5%')
          .padding({ left: 8, right: 8 })
          .borderRadius(9)
          .backgroundColor($r('app.color.episode_card_background'))
          .border({ width: 1, color: $r('app.color.border_item') })
          .shadow({ radius: 8, color: $r('app.color.shadow_light'), offsetY: 2 })
          .margin({ right: '2.8%', bottom: 12 })
          .onClick(() => {
            this.onEpisodeClick(ep, index !== undefined ? index : -1)
          })
        }, (ep: EpisodeData, index?: number) => `ep_${ep.url}_${index}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 0, bottom: 8 })
  }

  @Builder
  private EmptySection() {
    Column() {
      Text('暂无可用剧集')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_muted_green'))
    }
    .width('100%')
    .height(260)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private onEpisodeClick(ep: EpisodeData, index: number): void {
    const selectedSourceId = ep.sourceId >= 0 ? ep.sourceId : this.sourceId
    const selectedAnimeUrl = ep.animeUrl.length > 0 ? ep.animeUrl : this.animeUrl
    const currentEpisodes = this.getCurrentEpisodes()
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        episodeUrl: ep.url,
        ruleSourceId: selectedSourceId,
        animeName: this.animeName,
        episodeName: ep.name,
        animeId: `${selectedSourceId}_${selectedAnimeUrl}`,
        animeCover: this.animeCover,
        animeUrl: selectedAnimeUrl,
        sourceId: selectedSourceId,
        episodesJson: JSON.stringify(currentEpisodes),
        currentEpisodeIndex: index,
        bangumiId: this.bangumiId
      }
    })
  }

  private parseRoads(json: string): PlaybackRoad[] {
    if (json.length === 0) {
      return []
    }
    try {
      const parsed = JSON.parse(json) as PlaybackRoad[]
      for (let i = 0; i < parsed.length; i++) {
        if (parsed[i].episodes.length === 0 && parsed[i].data.length > 0) {
          const episodes: EpisodeData[] = []
          for (let j = 0; j < parsed[i].data.length; j++) {
            const episode = new EpisodeData()
            episode.name = j < parsed[i].identifier.length ? parsed[i].identifier[j] : `第${j + 1}集`
            episode.url = parsed[i].data[j]
            episode.sourceId = this.sourceId
            episode.sourceName = this.sourceName
            episode.animeUrl = this.animeUrl
            episodes.push(episode)
          }
          parsed[i].episodes = episodes
        }
      }
      return parsed
    } catch (err) {
      logger.warn('Parse roads failed: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  private getCurrentEpisodes(): EpisodeData[] {
    if (this.selectedRoadIndex < 0 || this.selectedRoadIndex >= this.roads.length) {
      return []
    }
    return this.roads[this.selectedRoadIndex].episodes
  }

  private getCurrentEpisodeCount(): number {
    return this.getCurrentEpisodes().length
  }

  private getEpisodeTotal(): number {
    let total = 0
    for (let i = 0; i < this.roads.length; i++) {
      total += this.roads[i].episodes.length
    }
    return total
  }
}
