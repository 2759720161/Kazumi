import { WebDavClient } from '../network/WebDavClient'
import { FavoriteStore } from '../store/FavoriteStore'
import { CollectChangeStore } from '../store/CollectChangeStore'
import { CollectChangeSignal } from '../store/CollectChangeSignal'
import { CollectedBangumi } from '../models/CollectedBangumi'
import { CollectChangeRecord } from '../models/CollectChangeRecord'
import { CollectType } from '../models/CollectType'
import { KazumiHiveCollectCodec } from './KazumiHiveCollectCodec'
import { Logger } from '../utils/Logger'
import { BangumiSyncService } from './BangumiSyncService'

const logger = new Logger('CollectSyncService')
const COLLECT_ROOT_PATH: string = '/kazumiSync'
const COLLECTIBLES_PATH: string = '/kazumiSync/collectibles.tmp'
const COLLECTIBLES_CACHE_PATH: string = '/kazumiSync/collectibles.tmp.cache'
const COLLECT_CHANGES_PATH: string = '/kazumiSync/collectchanges.tmp'
const COLLECT_CHANGES_CACHE_PATH: string = '/kazumiSync/collectchanges.tmp.cache'

export class CollectSyncResult {
  localCount: number = 0
  remoteCount: number = 0
  mergedCount: number = 0
}

export class CollectSyncService {
  private favoriteStore: FavoriteStore = new FavoriteStore()
  private changeStore: CollectChangeStore = new CollectChangeStore()
  private syncing: boolean = false

  async sync(client: WebDavClient): Promise<CollectSyncResult> {
    let result = new CollectSyncResult()
    await BangumiSyncService.getInstance().runCollectOperation(async () => {
      result = await this.syncInternal(client)
    })
    return result
  }

  private async syncInternal(client: WebDavClient): Promise<CollectSyncResult> {
    if (this.syncing) {
      throw new Error('收藏同步正在进行')
    }
    this.syncing = true
    try {
      const localCollectibles = await this.favoriteStore.getAllCollected()
      let localChanges = await this.changeStore.getAllChanges()
      const remoteCollectibles = await this.downloadCollectibles(client)
      const remoteChanges = await this.downloadChanges(client)

      await this.seedLegacyLocalChanges(localCollectibles, localChanges, remoteCollectibles)
      localChanges = await this.changeStore.getAllChanges()

      const mergedCollectibles = this.mergeCollectibles(
        localCollectibles, localChanges, remoteCollectibles, remoteChanges)
      const mergedChanges = this.mergeChanges(localChanges, remoteChanges)

      await this.favoriteStore.replaceSyncedCollectibles(mergedCollectibles)
      await this.changeStore.replaceAllChanges(mergedChanges)
      await this.uploadMergedFiles(client, mergedCollectibles, mergedChanges)
      CollectChangeSignal.notifyChanged()

      const result = new CollectSyncResult()
      result.localCount = this.countExportable(localCollectibles)
      result.remoteCount = remoteCollectibles.length
      result.mergedCount = mergedCollectibles.length
      logger.info('Collect sync complete local=%{public}d remote=%{public}d merged=%{public}d changes=%{public}d',
        result.localCount, result.remoteCount, result.mergedCount, mergedChanges.length)
      return result
    } finally {
      this.syncing = false
    }
  }

  private async downloadCollectibles(client: WebDavClient): Promise<CollectedBangumi[]> {
    const bytes = await client.downloadBytesAtPath(COLLECTIBLES_PATH)
    if (bytes === null || bytes.length === 0) {
      return []
    }
    try {
      return KazumiHiveCollectCodec.decodeCollectibles(bytes)
    } catch (err) {
      throw new Error('Kazumi 远端收藏文件无法解析: ' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private async downloadChanges(client: WebDavClient): Promise<CollectChangeRecord[]> {
    const bytes = await client.downloadBytesAtPath(COLLECT_CHANGES_PATH)
    if (bytes === null || bytes.length === 0) {
      return []
    }
    try {
      return KazumiHiveCollectCodec.decodeChanges(bytes)
    } catch (err) {
      throw new Error('Kazumi 远端收藏变更文件无法解析: ' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private async seedLegacyLocalChanges(local: CollectedBangumi[], changes: CollectChangeRecord[],
    remote: CollectedBangumi[]): Promise<void> {
    const changedBangumiIds: Set<number> = new Set<number>()
    for (let i = 0; i < changes.length; i++) {
      if (changes[i].bangumiId > 0) changedBangumiIds.add(changes[i].bangumiId)
    }
    const remoteById = this.collectibleMap(remote)
    const localById = this.collectibleMap(local)
    const localIds: number[] = []
    localById.forEach((_item: CollectedBangumi, bangumiId: number) => localIds.push(bangumiId))
    for (let i = 0; i < localIds.length; i++) {
      const bangumiId = localIds[i]
      if (changedBangumiIds.has(bangumiId)) {
        continue
      }
      const localItem = localById.get(bangumiId)
      if (localItem === undefined) {
        continue
      }
      const remoteItem = remoteById.get(bangumiId)
      if (remoteItem === undefined) {
        await this.changeStore.appendChange(bangumiId, 1, CollectType.normalize(localItem.collectType))
      } else if (localItem.createdAt > remoteItem.createdAt &&
        CollectType.normalize(localItem.collectType) !== CollectType.normalize(remoteItem.collectType)) {
        await this.changeStore.appendChange(bangumiId, 2, CollectType.normalize(localItem.collectType))
      }
    }
  }

  private mergeCollectibles(localCollectibles: CollectedBangumi[], localChanges: CollectChangeRecord[],
    remoteCollectibles: CollectedBangumi[], remoteChanges: CollectChangeRecord[]): CollectedBangumi[] {
    const merged = this.collectibleMap(remoteCollectibles)
    const local = this.collectibleMap(localCollectibles)
    const remoteChangeIds: Set<number> = new Set<number>()
    for (let i = 0; i < remoteChanges.length; i++) remoteChangeIds.add(remoteChanges[i].id)
    const pending: CollectChangeRecord[] = localChanges
      .filter((change: CollectChangeRecord) => !remoteChangeIds.has(change.id))
      .sort((a: CollectChangeRecord, b: CollectChangeRecord) => {
        if (a.timestamp !== b.timestamp) return a.timestamp - b.timestamp
        return a.id - b.id
      })

    for (let i = 0; i < pending.length; i++) {
      const change = pending[i]
      if (change.action === 3) {
        merged.delete(change.bangumiId)
        continue
      }
      const localItem = local.get(change.bangumiId)
      if (localItem === undefined) {
        continue
      }
      const changed = this.copyCollectible(localItem)
      changed.collectType = CollectType.normalize(change.type)
      if (change.action === 1 || (change.action === 2 && merged.has(change.bangumiId))) {
        merged.set(change.bangumiId, changed)
      }
    }

    const result: CollectedBangumi[] = []
    merged.forEach((remoteItem: CollectedBangumi, bangumiId: number) => {
      const localItem = local.get(bangumiId)
      result.push(localItem !== undefined ? this.mergeRemoteWithLocalSource(remoteItem, localItem) : remoteItem)
    })
    result.sort((a: CollectedBangumi, b: CollectedBangumi) => b.createdAt - a.createdAt)
    return result
  }

  private mergeChanges(local: CollectChangeRecord[], remote: CollectChangeRecord[]): CollectChangeRecord[] {
    const merged: Map<number, CollectChangeRecord> = new Map<number, CollectChangeRecord>()
    for (let i = 0; i < remote.length; i++) merged.set(remote[i].id, remote[i])
    for (let i = 0; i < local.length; i++) merged.set(local[i].id, local[i])
    const result: CollectChangeRecord[] = []
    merged.forEach((change: CollectChangeRecord) => result.push(change))
    result.sort((a: CollectChangeRecord, b: CollectChangeRecord) => {
      if (a.timestamp !== b.timestamp) return a.timestamp - b.timestamp
      return a.id - b.id
    })
    return result
  }

  private async uploadMergedFiles(client: WebDavClient, collectibles: CollectedBangumi[],
    changes: CollectChangeRecord[]): Promise<void> {
    await client.ensureRemoteDirAtPath(COLLECT_ROOT_PATH)
    const collectibleBytes = KazumiHiveCollectCodec.encodeCollectibles(collectibles)
    logger.info('Upload merged collectibles items=%{public}d bytes=%{public}d', collectibles.length,
      collectibleBytes.length)
    await client.replaceBytesAtPath(COLLECTIBLES_PATH, COLLECTIBLES_CACHE_PATH, collectibleBytes)
    if (changes.length > 0) {
      const changeBytes = KazumiHiveCollectCodec.encodeChanges(changes)
      logger.info('Upload merged collect changes items=%{public}d bytes=%{public}d', changes.length,
        changeBytes.length)
      await client.replaceBytesAtPath(COLLECT_CHANGES_PATH, COLLECT_CHANGES_CACHE_PATH, changeBytes)
    }
  }

  private collectibleMap(items: CollectedBangumi[]): Map<number, CollectedBangumi> {
    const result: Map<number, CollectedBangumi> = new Map<number, CollectedBangumi>()
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      if (item.bangumiId <= 0 || CollectType.normalize(item.collectType) === CollectType.none) {
        continue
      }
      const existing = result.get(item.bangumiId)
      if (existing === undefined || item.createdAt >= existing.createdAt) {
        result.set(item.bangumiId, item)
      }
    }
    return result
  }

  private countExportable(items: CollectedBangumi[]): number {
    return this.collectibleMap(items).size
  }

  private copyCollectible(source: CollectedBangumi): CollectedBangumi {
    const item = new CollectedBangumi()
    item.animeId = source.animeId
    item.bangumiId = source.bangumiId
    item.animeName = source.animeName
    item.animeCover = source.animeCover
    item.bangumiCover = source.bangumiCover
    item.coverFallback = source.coverFallback
    item.animeDesc = source.animeDesc
    item.animeUrl = source.animeUrl
    item.sourceName = source.sourceName
    item.sourceId = source.sourceId
    item.collectType = CollectType.normalize(source.collectType)
    item.createdAt = source.createdAt
    return item
  }

  private mergeRemoteWithLocalSource(remote: CollectedBangumi, local: CollectedBangumi): CollectedBangumi {
    const item = this.copyCollectible(remote)
    item.animeId = local.animeId.length > 0 ? local.animeId : remote.animeId
    item.animeUrl = local.animeUrl.length > 0 ? local.animeUrl : remote.animeUrl
    item.sourceName = local.sourceName
    item.sourceId = local.sourceId
    if (item.animeName.length === 0) item.animeName = local.animeName
    if (item.animeCover.length === 0) item.animeCover = local.animeCover
    if (item.bangumiCover.length === 0) item.bangumiCover = local.bangumiCover
    if (item.coverFallback.length === 0) item.coverFallback = local.coverFallback
    if (item.animeDesc.length === 0) item.animeDesc = local.animeDesc
    return item
  }
}
