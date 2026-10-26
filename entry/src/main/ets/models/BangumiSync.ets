import { CollectedBangumi } from './CollectedBangumi'
import { CollectType } from './CollectType'

export class BangumiSyncConfig {
  enabled: boolean = false
  token: string = ''
  immediateToast: boolean = true
  priority: number = 0
}

export class BangumiSyncPlan {
  uploads: CollectedBangumi[] = []
  downloads: CollectedBangumi[] = []
}

export class BangumiSyncProtocol {
  static toRemoteType(type: number): number {
    switch (type) {
      case CollectType.watching: return 3
      case CollectType.planToWatch: return 1
      case CollectType.onHold: return 4
      case CollectType.watched: return 2
      case CollectType.abandoned: return 5
      default: throw new Error('无效的收藏状态')
    }
  }

  static toLocalType(type: number): number {
    switch (type) {
      case 1: return CollectType.planToWatch
      case 2: return CollectType.watched
      case 3: return CollectType.watching
      case 4: return CollectType.onHold
      case 5: return CollectType.abandoned
      default: throw new Error('Bangumi 返回了无效的收藏状态')
    }
  }

  static plan(local: CollectedBangumi[], remote: CollectedBangumi[], priority: number): BangumiSyncPlan {
    const localMap = BangumiSyncProtocol.byId(local)
    const remoteMap = BangumiSyncProtocol.byId(remote)
    const plan = new BangumiSyncPlan()
    localMap.forEach((item: CollectedBangumi, id: number) => {
      const other = remoteMap.get(id)
      if (other === undefined || (item.collectType !== other.collectType && priority !== 1)) {
        plan.uploads.push(item)
      }
    })
    remoteMap.forEach((item: CollectedBangumi, id: number) => {
      const other = localMap.get(id)
      if (other === undefined || (item.collectType !== other.collectType && priority === 1)) {
        plan.downloads.push(item)
      }
    })
    return plan
  }

  private static byId(items: CollectedBangumi[]): Map<number, CollectedBangumi> {
    const result = new Map<number, CollectedBangumi>()
    items.forEach((item: CollectedBangumi) => {
      if (item.bangumiId <= 0 || !CollectType.isFavorite(item.collectType)) return
      const previous = result.get(item.bangumiId)
      if (previous === undefined || item.createdAt > previous.createdAt) result.set(item.bangumiId, item)
    })
    return result
  }
}
