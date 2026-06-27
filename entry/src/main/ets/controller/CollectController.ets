import { FavoriteStore } from '../store/FavoriteStore'
import { CollectedBangumi } from '../models/CollectedBangumi'
import { CollectType } from '../models/CollectType'
import { AnimeItem } from '../models/AnimeItem'
import { Logger } from '../utils/Logger'
import { CollectChangeSignal } from '../store/CollectChangeSignal'

const logger = new Logger('CollectController')

export class CollectController {
  private favoriteStore: FavoriteStore

  constructor() {
    this.favoriteStore = new FavoriteStore()
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
    if (type === CollectType.none) {
      await this.deleteCollect(animeItem)
      return
    }

    try {
      const isExisting = await this.favoriteStore.isFavorite(animeItem.getUniqueId())
      if (isExisting) {
        await this.favoriteStore.updateCollectType(animeItem.getUniqueId(), type)
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
        item.collectType = type
        item.createdAt = Date.now()
        await this.favoriteStore.addCollected(item)
      }

      CollectChangeSignal.notifyChanged()
      logger.info('addCollect: %{public}s -> type %{public}d', animeItem.name, type)
    } catch (err) {
      logger.error('addCollect failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('addCollect failed')
    }
  }

  async deleteCollect(animeItem: AnimeItem): Promise<void> {
    try {
      await this.favoriteStore.remove(animeItem.getUniqueId())
      CollectChangeSignal.notifyChanged()
      logger.info('deleteCollect: %{public}s', animeItem.name)
    } catch (err) {
      logger.error('deleteCollect failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('deleteCollect failed')
    }
  }

  async deleteCollectByAnimeId(animeId: string): Promise<void> {
    try {
      await this.favoriteStore.remove(animeId)
      CollectChangeSignal.notifyChanged()
      logger.info('deleteCollectByAnimeId: %{public}s', animeId)
    } catch (err) {
      logger.error('deleteCollectByAnimeId failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('deleteCollectByAnimeId failed')
    }
  }

  async updateCollectType(animeId: string, type: number): Promise<void> {
    try {
      await this.favoriteStore.updateCollectType(animeId, type)
      CollectChangeSignal.notifyChanged()
      logger.info('updateCollectType: %{public}s -> type %{public}d', animeId, type)
    } catch (err) {
      logger.error('updateCollectType failed: %{public}s', err instanceof Error ? err.message : String(err))
      throw new Error('updateCollectType failed')
    }
  }

  async getCollectType(animeId: string): Promise<number> {
    try {
      return await this.favoriteStore.getCollectType(animeId)
    } catch (err) {
      logger.error('getCollectType failed: %{public}s', err instanceof Error ? err.message : String(err))
      return CollectType.none
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
