import { RuleSourceStore } from './RuleSourceStore'
import { RuleSource } from '../models/RuleSource'
import { FavoriteStore } from './FavoriteStore'
import { FavoriteRecord } from '../models/FavoriteRecord'
import { HistoryStore } from './HistoryStore'
import { HistoryRecord } from '../models/HistoryRecord'
import { PreferencesStore } from './PreferencesStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('DataMigration')

const MIGRATION_VERSION = 1

export class AppDataBundle {
  version: number = MIGRATION_VERSION
  rules: RuleSource[] = []
  favorites: FavoriteRecord[] = []
  watchHistory: HistoryRecord[] = []
  settings: Record<string, Object> = {}

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['version'] = this.version
    const rulesArr: Object[] = []
    for (let i = 0; i < this.rules.length; i++) {
      rulesArr.push(this.rules[i].toJSON())
    }
    result['rules'] = rulesArr
    const favArr: Object[] = []
    for (let i = 0; i < this.favorites.length; i++) {
      favArr.push(this.favorites[i].toJSON())
    }
    result['favorites'] = favArr
    const histArr: Object[] = []
    for (let i = 0; i < this.watchHistory.length; i++) {
      histArr.push(this.watchHistory[i].toJSON())
    }
    result['watchHistory'] = histArr
    result['settings'] = this.settings
    return result
  }

  static fromJSON(json: Record<string, Object>): AppDataBundle {
    const bundle = new AppDataBundle()
    if (json['version'] !== undefined) bundle.version = json['version'] as number
    if (json['rules'] !== undefined) {
      const arr = json['rules'] as Object[]
      for (let i = 0; i < arr.length; i++) {
        bundle.rules.push(RuleSource.fromJSON(arr[i] as Record<string, Object>))
      }
    }
    if (json['favorites'] !== undefined) {
      const arr = json['favorites'] as Object[]
      for (let i = 0; i < arr.length; i++) {
        bundle.favorites.push(FavoriteRecord.fromJSON(arr[i] as Record<string, Object>))
      }
    }
    if (json['watchHistory'] !== undefined) {
      const arr = json['watchHistory'] as Object[]
      for (let i = 0; i < arr.length; i++) {
        bundle.watchHistory.push(HistoryRecord.fromJSON(arr[i] as Record<string, Object>))
      }
    }
    if (json['settings'] !== undefined) {
      bundle.settings = json['settings'] as Record<string, Object>
    }
    return bundle
  }
}

export class DataMigration {
  static async exportAll(): Promise<AppDataBundle> {
    const bundle = new AppDataBundle()

    const ruleStore = new RuleSourceStore()
    bundle.rules = await ruleStore.getAll()

    const favStore = new FavoriteStore()
    bundle.favorites = await favStore.getAll()

    const histStore = new HistoryStore()
    bundle.watchHistory = await histStore.getAll()

    const prefs = PreferencesStore.getInstance()
    const settingsKeys: string[] = [
      'allow_http_requests', 'defaultPlayerEngine', 'snifferTimeoutMs', 'colorMode'
    ]
    const settings: Record<string, Object> = {}
    for (let i = 0; i < settingsKeys.length; i++) {
      const key = settingsKeys[i]
      try {
        const hasKey = await prefs.has(key)
        if (hasKey) {
          const value = await prefs.getString(key, '')
          if (value.length > 0) {
            settings[key] = value
          } else {
            const numValue = await prefs.getNumber(key, -999999)
            if (numValue !== -999999) {
              settings[key] = numValue
            }
          }
        }
      } catch (err) {
        logger.warn('Export setting %{public}s failed', key)
      }
    }
    bundle.settings = settings

    logger.info('Exported bundle: rules=%{public}d favorites=%{public}d history=%{public}d settings=%{public}d',
      bundle.rules.length, bundle.favorites.length, bundle.watchHistory.length, Object.keys(settings).length)
    return bundle
  }

  static async importAll(bundle: AppDataBundle): Promise<void> {
    const ruleStore = new RuleSourceStore()
    for (let i = 0; i < bundle.rules.length; i++) {
      try {
        const rule = bundle.rules[i]
        const existing = await ruleStore.getByName(rule.name)
        if (existing !== null) {
          rule.id = existing.id
          await ruleStore.update(rule)
        } else {
          await ruleStore.insert(rule)
        }
      } catch (err) {
        logger.warn('Import rule %{public}d failed', i)
      }
    }

    const favStore = new FavoriteStore()
    for (let i = 0; i < bundle.favorites.length; i++) {
      try {
        const record = bundle.favorites[i]
        const isFav = await favStore.isFavorite(record.animeId)
        if (!isFav) {
          await favStore.add(record)
        }
      } catch (err) {
        logger.warn('Import favorite %{public}d failed', i)
      }
    }

    const histStore = new HistoryStore()
    for (let i = 0; i < bundle.watchHistory.length; i++) {
      try {
        await histStore.upsert(bundle.watchHistory[i])
      } catch (err) {
        logger.warn('Import history %{public}d failed', i)
      }
    }

    const prefs = PreferencesStore.getInstance()
    const keys = Object.keys(bundle.settings)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value = bundle.settings[key]
      try {
        if (typeof value === 'string') {
          await prefs.setString(key, value as string)
        } else if (typeof value === 'number') {
          await prefs.setNumber(key, value as number)
        } else if (typeof value === 'boolean') {
          await prefs.setBoolean(key, value as boolean)
        }
      } catch (err) {
        logger.warn('Import setting %{public}s failed', key)
      }
    }

    logger.info('Imported bundle: rules=%{public}d favorites=%{public}d history=%{public}d settings=%{public}d',
      bundle.rules.length, bundle.favorites.length, bundle.watchHistory.length, keys.length)
  }
}