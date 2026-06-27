import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuPlaybackBinding')

export class DanmakuPlaybackBinding {
  episodeId: number = 0
  animeId: number = 0
  animeTitle: string = ''
  episodeTitle: string = ''
  sourceId: number = -1
  episodeUrl: string = ''
  updatedAt: number = 0
}

const BINDING_KEY_PREFIX: string = 'dm_bind_'
const BINDING_INDEX_PREFIX: string = 'dm_bind_idx_'
const MAX_KEY_LENGTH: number = 128

export function computeEpisodeUrlHash(episodeUrl: string): string {
  if (episodeUrl.length === 0) {
    return ''
  }
  let hash: number = 0xFFFFFFFF
  for (let i = 0; i < episodeUrl.length; i++) {
    hash = hash ^ episodeUrl.charCodeAt(i)
    for (let j = 0; j < 8; j++) {
      if ((hash & 1) !== 0) {
        hash = (hash >>> 1) ^ 0xEDB88320
      } else {
        hash = hash >>> 1
      }
    }
  }
  hash = (hash ^ 0xFFFFFFFF) >>> 0
  return hash.toString(16).padStart(8, '0').substring(0, 8)
}

export class DanmakuPlaybackBindingStore {
  private static instance: DanmakuPlaybackBindingStore | null = null

  private constructor() {}

  static getInstance(): DanmakuPlaybackBindingStore {
    if (DanmakuPlaybackBindingStore.instance === null) {
      DanmakuPlaybackBindingStore.instance = new DanmakuPlaybackBindingStore()
    }
    return DanmakuPlaybackBindingStore.instance
  }

  async lookupBinding(bangumiId: number, episodeNo: number, animeName: string,
    sourceId: number = -1, episodeUrl: string = ''): Promise<DanmakuPlaybackBinding | null> {
    try {
      if (this.isStrongBindingApplicable(sourceId, episodeUrl)) {
        const strongKey: string = this.buildStrongBindingKey(bangumiId, episodeNo, animeName, sourceId, episodeUrl)
        const strongPrefsKey: string = BINDING_KEY_PREFIX + strongKey
        const prefs: PreferencesStore = PreferencesStore.getInstance()
        const strongJson: string = await prefs.getString(strongPrefsKey, '')
        if (strongJson.length > 0) {
          logger.info('强绑定命中: %{public}s', strongKey)
          return this.parseBinding(strongJson)
        }
      }
      const key: string = this.buildBindingKey(bangumiId, episodeNo, animeName)
      const prefsKey: string = BINDING_KEY_PREFIX + key
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const jsonStr: string = await prefs.getString(prefsKey, '')
      if (jsonStr.length === 0) {
        return null
      }
      return this.parseBinding(jsonStr)
    } catch (_err) {
      logger.warn('lookupBinding failed for bangumiId=%{public}d episodeNo=%{public}d', bangumiId, episodeNo)
      return null
    }
  }

  async saveBinding(bangumiId: number, episodeNo: number, animeName: string,
    binding: DanmakuPlaybackBinding, sourceId: number = -1, episodeUrl: string = ''): Promise<void> {
    try {
      binding.updatedAt = Date.now()
      if (this.isStrongBindingApplicable(sourceId, episodeUrl)) {
        binding.sourceId = sourceId
        binding.episodeUrl = episodeUrl
      }
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const jsonStr: string = JSON.stringify(binding)
      if (this.isStrongBindingApplicable(sourceId, episodeUrl)) {
        const strongKey: string = this.buildStrongBindingKey(bangumiId, episodeNo, animeName, sourceId, episodeUrl)
        const strongPrefsKey: string = BINDING_KEY_PREFIX + strongKey
        await prefs.setString(strongPrefsKey, jsonStr)
        await this.addToBindingIndex(sourceId, episodeUrl, strongKey)
        logger.info('强绑定保存: %{public}s → epId=%{public}d', strongKey, binding.episodeId)
      }
      const key: string = this.buildBindingKey(bangumiId, episodeNo, animeName)
      const prefsKey: string = BINDING_KEY_PREFIX + key
      await prefs.setString(prefsKey, jsonStr)
      logger.info('弱绑定保存: %{public}s → epId=%{public}d', key, binding.episodeId)
    } catch (_err) {
      logger.warn('saveBinding failed for bangumiId=%{public}d episodeNo=%{public}d', bangumiId, episodeNo)
    }
  }

  async clearBinding(bangumiId: number, episodeNo: number, animeName: string,
    sourceId: number = -1, episodeUrl: string = ''): Promise<boolean> {
    try {
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      if (this.isStrongBindingApplicable(sourceId, episodeUrl)) {
        const strongKey: string = this.buildStrongBindingKey(bangumiId, episodeNo, animeName, sourceId, episodeUrl)
        const strongPrefsKey: string = BINDING_KEY_PREFIX + strongKey
        await prefs.delete(strongPrefsKey)
        await this.removeFromBindingIndex(sourceId, episodeUrl, strongKey)
        logger.info('强绑定清除: %{public}s', strongKey)
      }
      const key: string = this.buildBindingKey(bangumiId, episodeNo, animeName)
      const prefsKey: string = BINDING_KEY_PREFIX + key
      await prefs.delete(prefsKey)
      logger.info('弱绑定清除: %{public}s', key)
      return true
    } catch (_err) {
      logger.warn('clearBinding failed for bangumiId=%{public}d episodeNo=%{public}d', bangumiId, episodeNo)
      return false
    }
  }

  async clearBindingByPlaybackRecord(sourceId: number, episodeUrl: string): Promise<void> {
    if (!this.isStrongBindingApplicable(sourceId, episodeUrl)) {
      return
    }
    try {
      const urlHash: string = computeEpisodeUrlHash(episodeUrl)
      const indexKey: string = `${BINDING_INDEX_PREFIX}${sourceId}_${urlHash}`
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const indexJson: string = await prefs.getString(indexKey, '')
      if (indexJson.length === 0) {
        logger.info('按播放记录清理绑定: 无索引记录 sourceId=%{public}d urlHash=%{public}s', sourceId, urlHash)
        return
      }
      const keys: string[] = this.parseIndexEntries(indexJson)
      let removedCount: number = 0
      for (let i = 0; i < keys.length; i++) {
        const prefsKey: string = BINDING_KEY_PREFIX + keys[i]
        try {
          await prefs.delete(prefsKey)
          removedCount++
        } catch (_delErr) {
          logger.warn('删除强绑定key失败: %{public}s', keys[i])
        }
      }
      await prefs.delete(indexKey)
      logger.info('按播放记录清理绑定: sourceId=%{public}d urlHash=%{public}s, removed=%{public}d',
        sourceId, urlHash, removedCount)
    } catch (_err) {
      logger.warn('clearBindingByPlaybackRecord failed: sourceId=%{public}d', sourceId)
    }
  }

  private async addToBindingIndex(sourceId: number, episodeUrl: string, strongKey: string): Promise<void> {
    try {
      const urlHash: string = computeEpisodeUrlHash(episodeUrl)
      const indexKey: string = `${BINDING_INDEX_PREFIX}${sourceId}_${urlHash}`
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const existingJson: string = await prefs.getString(indexKey, '')
      let keys: string[] = existingJson.length > 0 ? this.parseIndexEntries(existingJson) : []
      let alreadyExists: boolean = false
      for (let i = 0; i < keys.length; i++) {
        if (keys[i] === strongKey) {
          alreadyExists = true
          break
        }
      }
      if (!alreadyExists) {
        keys.push(strongKey)
        await prefs.setString(indexKey, JSON.stringify(keys))
      }
    } catch (_err) {
      logger.warn('addToBindingIndex failed')
    }
  }

  private async removeFromBindingIndex(sourceId: number, episodeUrl: string, strongKey: string): Promise<void> {
    try {
      const urlHash: string = computeEpisodeUrlHash(episodeUrl)
      const indexKey: string = `${BINDING_INDEX_PREFIX}${sourceId}_${urlHash}`
      const prefs: PreferencesStore = PreferencesStore.getInstance()
      const existingJson: string = await prefs.getString(indexKey, '')
      if (existingJson.length === 0) {
        return
      }
      let keys: string[] = this.parseIndexEntries(existingJson)
      let writeIndex = 0
      for (let i = 0; i < keys.length; i++) {
        if (keys[i] !== strongKey) {
          if (writeIndex !== i) {
            keys[writeIndex] = keys[i]
          }
          writeIndex++
        }
      }
      if (writeIndex < keys.length) {
        keys.length = writeIndex
      }
      if (keys.length === 0) {
        await prefs.delete(indexKey)
      } else {
        await prefs.setString(indexKey, JSON.stringify(keys))
      }
    } catch (_err) {
      logger.warn('removeFromBindingIndex failed')
    }
  }

  private parseIndexEntries(jsonStr: string): string[] {
    try {
      const arr: Object[] = JSON.parse(jsonStr) as Object[]
      const result: string[] = []
      for (let i = 0; i < arr.length; i++) {
        const item: string = arr[i] as string
        if (item.length > 0) {
          result.push(item)
        }
      }
      return result
    } catch (_err) {
      return []
    }
  }

  private buildBindingKey(bangumiId: number, episodeNo: number, animeName: string): string {
    if (bangumiId > 0) {
      return `${bangumiId}_${episodeNo}`
    }
    return `${animeName}_${episodeNo}`
  }

  private buildStrongBindingKey(bangumiId: number, episodeNo: number, animeName: string,
    sourceId: number, episodeUrl: string): string {
    const baseKey: string = this.buildBindingKey(bangumiId, episodeNo, animeName)
    const urlHash: string = computeEpisodeUrlHash(episodeUrl)
    const suffix: string = `_${sourceId}_${urlHash}`
    const maxBaseLength: number = MAX_KEY_LENGTH - BINDING_KEY_PREFIX.length - suffix.length
    const safeBaseKey: string = baseKey.length > maxBaseLength
      ? baseKey.substring(0, maxBaseLength) : baseKey
    return `${safeBaseKey}${suffix}`
  }

  private isStrongBindingApplicable(sourceId: number, episodeUrl: string): boolean {
    return sourceId >= 0 && episodeUrl.length > 0
  }

  private parseBinding(jsonStr: string): DanmakuPlaybackBinding {
    const binding: DanmakuPlaybackBinding = new DanmakuPlaybackBinding()
    try {
      const obj: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>
      if (obj['episodeId'] !== undefined && typeof obj['episodeId'] === 'number') {
        binding.episodeId = obj['episodeId'] as number
      }
      if (obj['animeId'] !== undefined && typeof obj['animeId'] === 'number') {
        binding.animeId = obj['animeId'] as number
      }
      if (obj['animeTitle'] !== undefined && typeof obj['animeTitle'] === 'string') {
        binding.animeTitle = obj['animeTitle'] as string
      }
      if (obj['episodeTitle'] !== undefined && typeof obj['episodeTitle'] === 'string') {
        binding.episodeTitle = obj['episodeTitle'] as string
      }
      if (obj['updatedAt'] !== undefined && typeof obj['updatedAt'] === 'number') {
        binding.updatedAt = obj['updatedAt'] as number
      }
      if (obj['sourceId'] !== undefined && typeof obj['sourceId'] === 'number') {
        binding.sourceId = obj['sourceId'] as number
      }
      if (obj['episodeUrl'] !== undefined && typeof obj['episodeUrl'] === 'string') {
        binding.episodeUrl = obj['episodeUrl'] as string
      }
    } catch (_err) {
      logger.warn('parseBinding failed, using defaults')
    }
    return binding
  }
}
