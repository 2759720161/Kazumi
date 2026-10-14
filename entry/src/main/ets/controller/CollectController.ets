import { FavoriteStore } from '../store/FavoriteStore'
import { CollectedBangumi } from '../models/CollectedBangumi'
import { CollectType } from '../models/CollectType'
import { AnimeItem } from '../models/AnimeItem'
import { Logger } from '../utils/Logger'
import { CollectChangeSignal } from '../store/CollectChangeSignal'
import { CollectChangeStore } from '../store/CollectChangeStore'
import { HistorySyncService } from '../services/HistorySyncService'
import { RdbManager } from '../store/RdbManager'

const logger = new Logger('CollectController')

export class CollectController {
  private favoriteStore: FavoriteStore
  private changeStore: CollectChangeStore
  private rdbManager: RdbManager

  constructor() {
    this.favoriteStore = new FavoriteStore()
    this.changeStore = new CollectChangeStore()
    this.rdbManager = RdbManager.getInstance()
  }

  async loadCollectibles(): Promise<CollectedBangumi[]> {
    try {
      return await this.favoriteStore.getAllCollected()
    } catch (err) {
      logger.error('loadCollectibles failed: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  async addCollect(animeItem: AnimeItem, type: number): Promise<void> {
    const normalizedType = CollectType.normalize(type)
    if (normalizedType === CollectType.none) {
      await this.deleteCollect(animeItem)
      return
    }

    try {
      const existing = await this.findExistingCollect(animeItem)
      const isExisting = existing !== null
      const bangumiId = existing !== null && existing.bangumiId > 0 ? existing.bangumiId : animeItem.bangumiId
      this.rdbManager.beginTransaction()
      try {
        if (existing !== null) {
          await this.favoriteStore.updateCollectType(existing.animeId, normalizedType)
        } else {
          const item = new CollectedBangumi()
          item.animeId = animeItem.getUniqueId()
          item.bangumiId = animeItem.bangumiId
          item.animeName = animeItem.name
          item.animeCover = animeItem.cover
          item.bangumiCover = animeItem.bangumiCover
          item.coverFallback = animeItem.coverFallback
          item.animeDesc = animeItem.desc
          item.animeUrl = animeItem.url
          item.sourceName = animeItem.sourceName
          item.sourceId = animeItem.sourceId
          item.collectType = normalizedType
          item.createdAt = Date.now()
          await this.favoriteStore.addCollected(item)
        }
        await this.appendCollectChange(bangumiId, isExisting ? 2 : 1, normalizedType)
        this.rdbManager.commit()
      } catch (err) {
        this.rdbManager.rollBack()
        throw new Error(err instanceof Error ? err.message : String(err))
      }
      this.scheduleCollectSync(bangumiId)

      CollectChangeSignal.notifyChanged()
      logger.info('addCollect: %{public}s -> type %{public}d', animeItem.name, normalizedType)
    } catch (err) {
      logger.error('addCollect failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('addCollect failed')
    }
  }

  async deleteCollect(animeItem: AnimeItem): Promise<void> {
    try {
      const existing = await this.findExistingCollect(animeItem)
      this.rdbManager.beginTransaction()
      try {
        await this.favoriteStore.remove(existing !== null ? existing.animeId : animeItem.getUniqueId())
        if (existing !== null) {
          await this.appendCollectChange(existing.bangumiId, 3, CollectType.abandoned)
        }
        this.rdbManager.commit()
      } catch (err) {
        this.rdbManager.rollBack()
        throw new Error(err instanceof Error ? err.message : String(err))
      }
      this.scheduleCollectSync(existing !== null ? existing.bangumiId : -1)
      CollectChangeSignal.notifyChanged()
      logger.info('deleteCollect: %{public}s', animeItem.name)
    } catch (err) {
      logger.error('deleteCollect failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('deleteCollect failed')
    }
  }

  async deleteCollectByAnimeId(animeId: string): Promise<void> {
    try {
      const existing = await this.favoriteStore.getCollectedByAnimeId(animeId)
      this.rdbManager.beginTransaction()
      try {
        await this.favoriteStore.remove(animeId)
        if (existing !== null) {
          await this.appendCollectChange(existing.bangumiId, 3, CollectType.abandoned)
        }
        this.rdbManager.commit()
      } catch (err) {
        this.rdbManager.rollBack()
        throw new Error(err instanceof Error ? err.message : String(err))
      }
      this.scheduleCollectSync(existing !== null ? existing.bangumiId : -1)
      CollectChangeSignal.notifyChanged()
      logger.info('deleteCollectByAnimeId: %{public}s', animeId)
    } catch (err) {
      logger.error('deleteCollectByAnimeId failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('deleteCollectByAnimeId failed')
    }
  }

  async updateCollectType(animeId: string, type: number): Promise<void> {
    try {
      const normalizedType = CollectType.normalize(type)
      const existing = await this.favoriteStore.getCollectedByAnimeId(animeId)
      this.rdbManager.beginTransaction()
      try {
        if (normalizedType === CollectType.none) {
          await this.favoriteStore.remove(animeId)
        } else {
          await this.favoriteStore.updateCollectType(animeId, normalizedType)
        }
        if (existing !== null) {
          await this.appendCollectChange(existing.bangumiId, normalizedType === CollectType.none ? 3 : 2,
            normalizedType === CollectType.none ? CollectType.abandoned : normalizedType)
        }
        this.rdbManager.commit()
      } catch (err) {
        this.rdbManager.rollBack()
        throw new Error(err instanceof Error ? err.message : String(err))
      }
      this.scheduleCollectSync(existing !== null ? existing.bangumiId : -1)
      CollectChangeSignal.notifyChanged()
      logger.info('updateCollectType: %{public}s -> type %{public}d', animeId, normalizedType)
    } catch (err) {
      logger.error('updateCollectType failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('updateCollectType failed')
    }
  }

  async getCollectType(animeId: string, bangumiId: number = -1): Promise<number> {
    try {
      const directType = await this.favoriteStore.getCollectType(animeId)
      if (directType !== CollectType.none || bangumiId <= 0) {
        return directType
      }
      const byBangumi = await this.favoriteStore.getCollectedByBangumiId(bangumiId)
      return byBangumi !== null ? CollectType.normalize(byBangumi.collectType) : CollectType.none
    } catch (err) {
      logger.error('getCollectType failed: %{public}s', err instanceof Error ? err.message : String(err))
      return CollectType.none
    }
  }

  private async findExistingCollect(animeItem: AnimeItem): Promise<CollectedBangumi | null> {
    const direct = await this.favoriteStore.getCollectedByAnimeId(animeItem.getUniqueId())
    if (direct !== null || animeItem.bangumiId <= 0) {
      return direct
    }
    return await this.favoriteStore.getCollectedByBangumiId(animeItem.bangumiId)
  }

  private async appendCollectChange(bangumiId: number, action: number, type: number): Promise<void> {
    if (bangumiId <= 0) {
      return
    }
    await this.changeStore.appendChange(bangumiId, action, type)
  }

  private scheduleCollectSync(bangumiId: number): void {
    if (bangumiId > 0) {
      HistorySyncService.getInstance().scheduleAutoUploadAfterLocalChange()
    }
  }

  async getCollectTypeMap(animeIds: string[]): Promise<Map<string, number>> {
    try {
      return await this.favoriteStore.getCollectTypeMap(animeIds)
    } catch (err) {
      logger.error('getCollectTypeMap failed: %{public}s', err instanceof Error ? err.message : String(err))
      return new Map<string, number>()
    }
  }
}
