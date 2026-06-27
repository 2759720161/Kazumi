import { HistoryRecord } from '../../models/HistoryRecord'
import { router } from '@kit.ArkUI'

@Component
export struct ContinueWatchingSection {
  @Prop items: HistoryRecord[] = []
  private readonly maxVisible: number = 5

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('继续观看')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Row({ space: 4 }) {
          Text('全部')
            .fontSize(13)
            .fontColor($r('app.color.accent_blue'))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13)
            .fontColor([$r('app.color.accent_blue')])
        }
        .onClick(() => {
          router.pushUrl({ url: 'pages/history/HistoryPage' })
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Column({ space: 8 }) {
        ForEach(this.getVisibleItems(), (record: HistoryRecord, index?: number) => {
          this.ContinueCard(record)
        }, (record: HistoryRecord, index?: number) => 'continue_' + record.animeId + '_' + (index ?? 0).toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
  }

  private getVisibleItems(): HistoryRecord[] {
    if (this.items.length > this.maxVisible) {
      return this.items.slice(0, this.maxVisible)
    }
    return this.items
  }

  @Builder
  private ContinueCard(record: HistoryRecord) {
    Row({ space: 12 }) {
      Image(record.animeCover.length > 0 ? record.animeCover : $r('app.media.ic_placeholder'))
        .width(52)
        .height(72)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .alt($r('app.media.ic_placeholder'))

      Column({ space: 4 }) {
        Text(record.animeName)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(record.episodeName)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (record.durationMs > 0 && record.positionMs > 0) {
          Progress({ value: record.positionMs, total: record.durationMs, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color($r('app.color.accent_blue'))
            .backgroundColor($r('app.color.divider_color'))
            .borderRadius(2)
            .margin({ top: 2 })
        }

        if (record.durationMs > 0) {
          Text(this.formatProgress(record.positionMs, record.durationMs))
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
            .width('100%')
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(12)
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
        ruleSourceId: record.sourceId,
        sourceId: record.sourceId,
        episodeUrl: record.episodeUrl,
        sourceName: record.sourceName,
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
