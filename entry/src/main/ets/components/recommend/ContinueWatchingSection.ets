import { HistoryRecord } from '../../models/HistoryRecord'
import { router } from '@kit.ArkUI'

@Component
export struct ContinueWatchingSection {
  @Prop items: HistoryRecord[] = []

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('继续观看')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.items, (record: HistoryRecord, index?: number) => {
            this.ContinueCard(record)
          }, (record: HistoryRecord, index?: number) => 'continue_' + record.animeId + '_' + (index ?? 0).toString())
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private ContinueCard(record: HistoryRecord) {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(record.animeCover.length > 0 ? record.animeCover : $r('app.media.ic_placeholder'))
          .width('100%')
          .height(64)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 10, topRight: 10 })
          .alt($r('app.media.ic_placeholder'))

        Row() {
          Text(record.episodeName)
            .fontSize(11)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .textShadow({ radius: 2, color: '#66000000', offsetX: 0, offsetY: 1 })

          if (record.durationMs > 0) {
            Text(this.formatProgress(record.positionMs, record.durationMs))
              .fontSize(10)
              .fontColor('#CCFFFFFF')
              .textShadow({ radius: 2, color: '#66000000', offsetX: 0, offsetY: 1 })
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 6 })
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#00000000', 0], ['#66000000', 1]]
        })
      }
      .width('100%')
      .height(64)
      .clip(true)
      .borderRadius({ topLeft: 10, topRight: 10 })

      if (record.durationMs > 0 && record.positionMs > 0) {
        Progress({ value: record.positionMs, total: record.durationMs, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.accent_blue'))
          .backgroundColor($r('app.color.divider_color'))
      }

      Text(record.animeName)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 6, right: 6, top: 4 })
    }
    .width(150)
    .borderRadius(10)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .clip(true)
    .onClick(() => {
      this.resumeOrNavigate(record)
    })
  }

  private resumeOrNavigate(record: HistoryRecord): void {
    const hasPlayableData = record.episodeUrl.length > 0 && record.sourceId >= 0
    if (hasPlayableData) {
      this.navigateToPlayer(record)
    } else {
      this.navigateToDetail(record)
    }
  }

  private navigateToPlayer(record: HistoryRecord): void {
    router.pushUrl({
      url: 'pages/player/PlayerPage',
      params: {
        animeName: record.animeName,
        episodeName: record.episodeName,
        animeId: record.animeId,
        animeCover: record.animeCover,
        animeUrl: record.animeUrl,
        sourceId: record.sourceId,
        sourceName: record.sourceName,
        episodeUrl: record.episodeUrl,
        historyPositionMs: record.positionMs
      }
    })
  }

  private navigateToDetail(record: HistoryRecord): void {
    router.pushUrl({
      url: 'pages/detail/DetailPage',
      params: {
        animeName: record.animeName,
        animeCover: record.animeCover,
        animeUrl: record.animeUrl,
        sourceId: record.sourceId,
        sourceName: record.sourceName,
        bangumiId: -1
      }
    })
  }

  private formatProgress(positionMs: number, durationMs: number): string {
    const posSec = Math.floor(positionMs / 1000)
    const durSec = Math.floor(durationMs / 1000)
    const posMin = Math.floor(posSec / 60)
    const posRemSec = posSec % 60
    const durMin = Math.floor(durSec / 60)
    const durRemSec = durSec % 60
    return posMin.toString() + ':' + posRemSec.toString().padStart(2, '0') + ' / ' +
      durMin.toString() + ':' + durRemSec.toString().padStart(2, '0')
  }
}
