import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuMappingStore')

export class DanmakuMappingRecord {
  animeId: number = 0
  episodeId: number = 0
  animeTitle: string = ''
  episodeTitle: string = ''
  createdAt: number = 0
}

const MAPPING_KEY_PREFIX: string = 'dm_map_'

export class DanmakuMappingStore {
  private static instance: DanmakuMappingStore | null = null

  private constructor() {}

  static getInstance(): DanmakuMappingStore {
    if (DanmakuMappingStore.instance === null) {
      DanmakuMappingStore.instance = new DanmakuMappingStore()
    }
    return DanmakuMappingStore.instance
  }

  async lookupMapping(bangumiId: number, episodeNo: number, animeName: string): Promise<DanmakuMappingRecord | null> {
    try {
      const key: string = this.buildMappingKey(bangumiId, episodeNo, animeName)
      const prefsKey: string = MAPPING_KEY_PREFIX + key
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const jsonStr: string = await prefs.getString(prefsKey, '')
      if (jsonStr.length === 0) {
        return null
      }
      const record: DanmakuMappingRecord = this.parseRecord(jsonStr)
      return record
    } catch (_err) {
      logger.warn('lookupMapping failed for bangumiId=%{public}d episodeNo=%{public}d', bangumiId, episodeNo)
      return null
    }
  }

  async saveMapping(bangumiId: number, episodeNo: number, animeName: string, record: DanmakuMappingRecord): Promise<void> {
    try {
      record.createdAt = Date.now()
      const key: string = this.buildMappingKey(bangumiId, episodeNo, animeName)
      const prefsKey: string = MAPPING_KEY_PREFIX + key
      const jsonStr: string = JSON.stringify(record)
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      await prefs.setString(prefsKey, jsonStr)
      logger.info('Mapping saved: %{public}s → animeId=%{public}d epId=%{public}d', key, record.animeId, record.episodeId)
    } catch (_err) {
      logger.warn('saveMapping failed for bangumiId=%{public}d episodeNo=%{public}d', bangumiId, episodeNo)
    }
  }

  async clearMapping(bangumiId: number, episodeNo: number, animeName: string): Promise<boolean> {
    try {
      const key: string = this.buildMappingKey(bangumiId, episodeNo, animeName)
      const prefsKey: string = MAPPING_KEY_PREFIX + key
      await PreferencesStore.getInstance().delete(prefsKey)
      logger.info('Mapping cleared: %{public}s', key)
      return true
    } catch (_err) {
      logger.warn('clearMapping failed for bangumiId=%{public}d episodeNo=%{public}d', bangumiId, episodeNo)
      return false
    }
  }

  private buildMappingKey(bangumiId: number, episodeNo: number, animeName: string): string {
    if (bangumiId > 0) {
      return `${bangumiId}_${episodeNo}`
    }
    return `${animeName}_${episodeNo}`
  }

  private parseRecord(jsonStr: string): DanmakuMappingRecord {
    const record: DanmakuMappingRecord = new DanmakuMappingRecord()
    try {
      const obj: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>
      if (obj['animeId'] !== undefined && typeof obj['animeId'] === 'number') {
        record.animeId = obj['animeId'] as number
      }
      if (obj['episodeId'] !== undefined && typeof obj['episodeId'] === 'number') {
        record.episodeId = obj['episodeId'] as number
      }
      if (obj['animeTitle'] !== undefined && typeof obj['animeTitle'] === 'string') {
        record.animeTitle = obj['animeTitle'] as string
      }
      if (obj['episodeTitle'] !== undefined && typeof obj['episodeTitle'] === 'string') {
        record.episodeTitle = obj['episodeTitle'] as string
      }
      if (obj['createdAt'] !== undefined && typeof obj['createdAt'] === 'number') {
        record.createdAt = obj['createdAt'] as number
      }
    } catch (_err) {
      logger.warn('parseRecord failed, using defaults')
    }
    return record
  }
}
