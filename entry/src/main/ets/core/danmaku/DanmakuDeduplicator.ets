import { DanmakuItem } from '../../models/DanmakuItem'

const DEFAULT_TIME_WINDOW_MS = 5000

export class DanmakuDeduplicator {
  static mergeDuplicateDanmakus(items: DanmakuItem[], timeWindowMs: number = DEFAULT_TIME_WINDOW_MS): DanmakuItem[] {
    if (items.length <= 1) {
      return items
    }

    const grouped: Map<string, DanmakuItem[]> = new Map()
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      const normalized = DanmakuDeduplicator.normalizeText(item.content)
      if (normalized.length === 0) {
        continue
      }
      const list = grouped.get(normalized)
      if (list === undefined) {
        grouped.set(normalized, [item])
      } else {
        list.push(item)
      }
    }

    const result: DanmakuItem[] = []
    grouped.forEach((list: DanmakuItem[]) => {
      if (list.length === 0) {
        return
      }
      if (timeWindowMs <= 0) {
        DanmakuDeduplicator.addMergedGroup(result, list)
        return
      }

      list.sort((a: DanmakuItem, b: DanmakuItem) => a.timeMs - b.timeMs)
      let currentGroup: DanmakuItem[] = []
      for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (currentGroup.length === 0) {
          currentGroup.push(item)
          continue
        }
        const last = currentGroup[currentGroup.length - 1]
        if (item.timeMs - last.timeMs <= timeWindowMs) {
          currentGroup.push(item)
        } else {
          DanmakuDeduplicator.addMergedGroup(result, currentGroup)
          currentGroup = [item]
        }
      }
      if (currentGroup.length > 0) {
        DanmakuDeduplicator.addMergedGroup(result, currentGroup)
      }
    })

    result.sort((a: DanmakuItem, b: DanmakuItem) => a.timeMs - b.timeMs)
    return result
  }

  private static addMergedGroup(result: DanmakuItem[], group: DanmakuItem[]): void {
    if (group.length === 0) {
      return
    }
    if (group.length === 1) {
      result.push(group[0])
      return
    }

    const first = group[0]
    result.push(new DanmakuItem(
      `${first.content} x${group.length}`,
      first.timeMs,
      '#FFFFFF',
      first.fontSize,
      5,
      first.source
    ))
  }

  private static normalizeText(value: string): string {
    let text = value.trim().toLowerCase()
    if (text.length === 0) {
      return ''
    }

    let converted = ''
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i)
      if (code === 0x3000) {
        converted += ' '
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        converted += String.fromCharCode(code - 0xFEE0)
      } else {
        converted += text.charAt(i)
      }
    }

    text = converted.replace(/\s+/g, '')
    text = text.replace(/[^\w\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff\u31f0-\u31ff\uff65-\uff9f]/g, '')
    return text.replace(/(.)\1{2,}/g, '$1$1$1')
  }
}
