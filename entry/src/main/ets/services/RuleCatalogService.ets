import { RuleCatalogItem } from '../models/RuleCatalogItem'
import { RuleInstallOrigin, RuleSource } from '../models/RuleSource'
import { RuleSourceStore } from '../store/RuleSourceStore'
import { DefaultRuleSourceInitializer } from '../utils/DefaultRuleSourceInitializer'
import { AppConstants } from '../constants/AppConstants'
import { Logger } from '../utils/Logger'
import { SettingsChangeSignal } from '../store/SettingsChangeSignal'
import { PreferencesStore } from '../store/PreferencesStore'

const logger = new Logger('RuleCatalogService')
const PREF_RULE_REPOSITORY_URL = 'rule_repository_url'
const PREF_RULE_CATALOG_CACHE = 'rule_catalog_cache_v1'
const CATALOG_FRESH_MS = 60000

class RuleCatalogCacheEntry {
  items: RuleCatalogItem[] = []
  updatedAt: number = 0
}

export class RuleCatalogService {
  private static catalogCache: Map<string, RuleCatalogCacheEntry> = new Map()
  private static catalogRequests: Map<string, Promise<RuleCatalogItem[]>> = new Map()
  static async getSavedRepositoryUrl(): Promise<string> {
    const prefs = PreferencesStore.getInstance()
    return (await prefs.getString(PREF_RULE_REPOSITORY_URL, '')).trim()
  }

  static async getCachedCatalog(indexUrl: string): Promise<RuleCatalogItem[]> {
    if (indexUrl.trim().length === 0) return []
    const key = DefaultRuleSourceInitializer.normalizeGithubRawUrl(indexUrl)
    const memory = RuleCatalogService.catalogCache.get(key)
    if (memory !== undefined) return memory.items.slice()
    try {
      const text = await PreferencesStore.getInstance().getString(PREF_RULE_CATALOG_CACHE, '')
      if (text.length === 0) return []
      const saved = JSON.parse(text) as Record<string, Object>
      if (saved['url'] !== key || typeof saved['body'] !== 'string' || typeof saved['updatedAt'] !== 'number') {
        return []
      }
      const entry = new RuleCatalogCacheEntry()
      entry.items = RuleCatalogService.parseCatalog(saved['body'] as string)
      entry.updatedAt = saved['updatedAt'] as number
      RuleCatalogService.catalogCache.set(key, entry)
      logger.info('Loaded cached rule catalog: items=%{public}d', entry.items.length)
      return entry.items.slice()
    } catch (err) {
      logger.warn('Ignoring invalid rule catalog cache: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  static async fetchCatalog(indexUrl: string, forceRefresh: boolean = false): Promise<RuleCatalogItem[]> {
    if (indexUrl.trim().length === 0) {
      return []
    }
    const key = DefaultRuleSourceInitializer.normalizeGithubRawUrl(indexUrl)
    await RuleCatalogService.getCachedCatalog(key)
    const existing = RuleCatalogService.catalogRequests.get(key)
    if (existing !== undefined) {
      logger.info('Joining rule catalog refresh: %{public}s', key.substring(0, 100))
      return (await existing).slice()
    }
    const cached = RuleCatalogService.catalogCache.get(key)
    const age = cached === undefined ? -1 : Date.now() - cached.updatedAt
    if (!forceRefresh && cached !== undefined && age >= 0 && age < CATALOG_FRESH_MS) {
      logger.info('Using recent rule catalog: items=%{public}d age=%{public}dms', cached.items.length, age)
      return cached.items.slice()
    }
    const pending = RuleCatalogService.loadCatalog(key)
    RuleCatalogService.catalogRequests.set(key, pending)
    try {
      return (await pending).slice()
    } finally {
      RuleCatalogService.catalogRequests.delete(key)
    }
  }

  private static async loadCatalog(key: string): Promise<RuleCatalogItem[]> {
    const indexBody = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(key)
    const items = RuleCatalogService.parseCatalog(indexBody)
    await RuleCatalogService.adoptLegacyRepositoryRules(items)
    const entry = new RuleCatalogCacheEntry()
    entry.items = items
    entry.updatedAt = Date.now()
    RuleCatalogService.catalogCache.set(key, entry)
    const saved: Record<string, Object> = {}
    saved['url'] = key
    saved['body'] = indexBody
    saved['updatedAt'] = entry.updatedAt
    try {
      await PreferencesStore.getInstance().setString(PREF_RULE_CATALOG_CACHE, JSON.stringify(saved))
    } catch (err) {
      logger.warn('Failed to save rule catalog cache: %{public}s', err instanceof Error ? err.message : String(err))
    }
    logger.info('Fetched catalog with %{public}d items', items.length)
    return items
  }

  private static parseCatalog(indexBody: string): RuleCatalogItem[] {
    const parsed: Object = JSON.parse(indexBody)
    if (!Array.isArray(parsed)) {
      throw new Error('Rule catalog index must be a JSON array')
    }
    const items: RuleCatalogItem[] = []
    const list = parsed as Object[]
    for (let i = 0; i < list.length; i++) {
      try {
        const rawItem = list[i] as Record<string, Object>
        if (!DefaultRuleSourceInitializer.isValidCatalogItemJson(rawItem)) {
          throw new Error('Invalid Kazumi catalog item')
        }
        const item = RuleCatalogItem.fromJSON(rawItem)
        if (item.name.length > 0) {
          items.push(item)
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        logger.warn('Failed to parse catalog item at index %{public}d: %{public}s', i, msg)
      }
    }
    if (list.length > 0 && items.length === 0) {
      throw new Error('Rule catalog index contains no valid Kazumi rules')
    }
    return items
  }

  private static async adoptLegacyRepositoryRules(items: RuleCatalogItem[]): Promise<void> {
    if (items.length === 0) {
      return
    }
    const store = new RuleSourceStore()
    const localRules = await store.getAll()
    let adopted = 0
    for (let i = 0; i < localRules.length; i++) {
      const rule = localRules[i]
      if (rule.installOrigin !== RuleInstallOrigin.LEGACY || !RuleCatalogService.containsRule(items, rule.name)) {
        continue
      }
      await store.setInstallOrigin(rule.id, RuleInstallOrigin.REPOSITORY)
      adopted++
    }
    if (adopted > 0) {
      logger.info('Adopted %{public}d legacy rules as repository-managed', adopted)
    }
  }

  private static containsRule(items: RuleCatalogItem[], name: string): boolean {
    for (let i = 0; i < items.length; i++) {
      if (items[i].name === name) {
        return true
      }
    }
    return false
  }

  static getRuleStatus(item: RuleCatalogItem, localRules: RuleSource[]): string {
    if (item.repositoryMissing) {
      return 'nonexistent'
    }
    for (let i = 0; i < localRules.length; i++) {
      if (localRules[i].name === item.name) {
        if (localRules[i].version === item.version) {
          return 'installed'
        }
        return 'update'
      }
    }
    return 'install'
  }

  static async tryInstallRule(name: string, indexUrl: string): Promise<number> {
    if (indexUrl.trim().length === 0) {
      return 2
    }
    const ruleUrl = DefaultRuleSourceInitializer.buildCatalogRuleUrl(indexUrl, name)
    let ruleBody: string
    try {
      ruleBody = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(ruleUrl)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Failed to fetch rule %{public}s: %{public}s', name, msg)
      return 2
    }

    const parsed: Object = JSON.parse(ruleBody)
    const rule = RuleSource.fromJSON(parsed as Record<string, Object>)
    rule.installOrigin = RuleInstallOrigin.REPOSITORY

    const apiNum = parseInt(rule.api, 10)
    if (!isNaN(apiNum) && apiNum > AppConstants.SUPPORTED_API_LEVEL) {
      logger.warn('Rule %{public}s api=%{public}d exceeds supported level %{public}d',
        name, apiNum, AppConstants.SUPPORTED_API_LEVEL)
      return 1
    }

    DefaultRuleSourceInitializer.validateRuleJson(parsed as Record<string, Object>)

    const store = new RuleSourceStore()
    const existing = await store.getByName(rule.name)
    if (existing !== null) {
      rule.id = existing.id
      rule.enabled = existing.enabled
      rule.sortOrder = existing.sortOrder
      await store.update(rule)
      logger.info('Updated rule %{public}s v%{public}s', rule.name, rule.version)
    } else {
      rule.sortOrder = await store.getNextSortOrder()
      rule.enabled = true
      await store.insert(rule)
      logger.info('Installed rule %{public}s v%{public}s (sort_order=%{public}d)',
        rule.name, rule.version, rule.sortOrder)
    }
    SettingsChangeSignal.notifyRuleSourceChanged()
    return 0
  }

  static async tryUpdateAllRules(): Promise<number> {
    const indexUrl = await RuleCatalogService.getSavedRepositoryUrl()
    if (indexUrl.length === 0) {
      return 0
    }
    const catalog = await RuleCatalogService.fetchCatalog(indexUrl)
    const store = new RuleSourceStore()
    const localRules = await store.getAll()
    let updated = 0
    for (let i = 0; i < catalog.length; i++) {
      const item = catalog[i]
      const status = RuleCatalogService.getRuleStatus(item, localRules)
      if (status === 'update') {
        const result = await RuleCatalogService.tryInstallRule(item.name, indexUrl)
        if (result === 0) {
          updated++
        }
      }
    }
    logger.info('Updated %{public}d rules', updated)
    return updated
  }

  static async countUpdatableRules(): Promise<number> {
    try {
      const indexUrl = await RuleCatalogService.getSavedRepositoryUrl()
      if (indexUrl.length === 0) {
        return 0
      }
      const catalog = await RuleCatalogService.fetchCatalog(indexUrl)
      const store = new RuleSourceStore()
      const localRules = await store.getAll()
      let count = 0
      for (let i = 0; i < catalog.length; i++) {
        const status = RuleCatalogService.getRuleStatus(catalog[i], localRules)
        if (status === 'update') {
          count++
        }
      }
      return count
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Failed to check for updates: %{public}s', msg)
      return 0
    }
  }
}
