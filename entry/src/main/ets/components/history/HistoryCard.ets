import { HistoryRecord } from '../../models/HistoryRecord'
import { router } from '@kit.ArkUI'

@Component
export struct HistoryCard {
  @Prop record: HistoryRecord
  @State isPressed: boolean = false
  @Prop isEditMode: boolean = false
  @Prop isSelected: boolean = false

  onDelete?: (animeId: string) => void
  onToggleSelect?: (animeId: string) => void
  onOpen?: (record: HistoryRecord) => void

  build() {
    Row() {
      Image(this.record.animeCover)
        .width(80)
        .height(108)
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .alt($r('app.media.ic_placeholder'))

      Column() {
        Column() {
          Text(this.record.animeName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row() {
            SymbolGlyph($r('sys.symbol.play_circle'))
              .fontSize(14)
              .fontColor([$r('app.color.text_secondary')])
            Text(this.record.episodeName)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: 2 })

          if (this.record.sourceName.length > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.template'))
                .fontSize(14)
                .fontColor([$r('app.color.text_secondary')])
              Text(this.record.sourceName)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 4 })
            }
            .alignItems(VerticalAlign.Center)
            .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(12)
            .fontColor([$r('app.color.text_secondary')])
            .opacity(0.6)
          Text(this.buildUpdateTimeText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.6)
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
      }
      .height(108)
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)

      if (this.isEditMode) {
        SymbolGlyph(this.isSelected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'))
          .fontSize(24)
          .fontColor([this.isSelected ? $r('sys.color.font_emphasize') : $r('app.color.text_secondary')])
          .margin({ left: 8 })
          .onClick(() => {
            if (this.onToggleSelect) {
              this.onToggleSelect!(this.record.animeId)
            }
          })
      }
    }
    .width('100%')
    .height(132)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .animation({ duration: 150 })
    .onClick(() => {
      if (this.isEditMode) {
        if (this.onToggleSelect) {
          this.onToggleSelect!(this.record.animeId)
        }
        return
      }
      if (this.record.episodeUrl.length > 0) {
        if (this.onOpen) {
          this.onOpen!(this.record)
          return
        }
        router.pushUrl({
          url: 'pages/player/PlayerPage',
          params: {
            episodeUrl: this.record.episodeUrl,
            animeName: this.record.animeName,
            episodeName: this.record.episodeName,
            animeId: this.record.animeId,
            animeCover: this.record.animeCover,
            animeUrl: this.record.animeUrl,
            ruleSourceId: this.record.sourceId,
            sourceId: this.record.sourceId,
            bangumiCover: '',
            coverFallback: '',
            animeDesc: '',
            sourceName: this.record.sourceName,
            historyPositionMs: this.record.positionMs
          }
        })
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false
      }
    })
    .bindContextMenu(!this.isEditMode ? this.DeleteMenuBuilder : undefined, ResponseType.LongPress)
  }

  @Builder
  DeleteMenuBuilder() {
    Menu() {
      MenuItem() {
        Row() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([$r('app.color.status_error')])
          Text('删除记录')
            .fontSize(16)
            .margin({ left: 8 })
        }
      }
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete!(this.record.animeId)
        }
      })
    }
  }


  private buildUpdateTimeText(): string {
    return this.formatRelativeTime(this.record.updatedAt)
  }


  private formatRelativeTime(timestamp: number): string {
    const now: number = Date.now()
    const diffMs: number = now - timestamp
    const diffMinutes: number = Math.floor(diffMs / 60000)
    const diffHours: number = Math.floor(diffMs / 3600000)
    const offsetMs: number = new Date().getTimezoneOffset() * 60000
    const localNow: number = now - offsetMs
    const todayStart: number = localNow - localNow % 86400000 + offsetMs
    const yesterdayStart: number = todayStart - 86400000
    const date: Date = new Date(timestamp)
    const hour: number = date.getHours()
    const minute: number = date.getMinutes()
    const timeStr: string = this.padZero(hour) + ':' + this.padZero(minute)

    if (diffMinutes < 1) {
      return '刚刚'
    }
    if (diffMinutes < 60 && timestamp >= todayStart) {
      return String(diffMinutes) + '分钟前'
    }
    if (diffHours < 24 && timestamp >= todayStart) {
      return String(diffHours) + '小时前'
    }
    if (timestamp >= yesterdayStart) {
      return '昨天 ' + timeStr
    }
    const month: number = date.getMonth() + 1
    const day: number = date.getDate()
    return String(month) + '月' + String(day) + '日'
  }

  private padZero(n: number): string {
    if (n < 10) {
      return '0' + String(n)
    }
    return String(n)
  }
}
