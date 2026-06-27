import { RuleCatalogItem } from '../models/RuleCatalogItem'
import { RuleSource } from '../models/RuleSource'
import { RuleSourceStore } from '../store/RuleSourceStore'
import { DefaultRuleSourceInitializer } from '../utils/DefaultRuleSourceInitializer'
import { AppConstants } from '../constants/AppConstants'
import { Logger } from '../utils/Logger'
import { SettingsChangeSignal } from '../store/SettingsChangeSignal'
import { PreferencesStore } from '../store/PreferencesStore'

const logger = new Logger('RuleCatalogService')
const PREF_RULE_REPOSITORY_URL = 'rule_repository_url'

export class RuleCatalogService {
  static async getSavedRepositoryUrl(): Promise<string> {
    const prefs = PreferencesStore.getInstance()
    return (await prefs.getString(PREF_RULE_REPOSITORY_URL, '')).trim()
  }

  static async fetchCatalog(indexUrl: string): Promise<RuleCatalogItem[]> {
    if (indexUrl.trim().length === 0) {
      return []
    }
    const indexBody = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(indexUrl)
    const parsed: Object = JSON.parse(indexBody)
    if (!Array.isArray(parsed)) {
      throw new Error('Rule catalog index must be a JSON array')
    }
    const items: RuleCatalogItem[] = []
    const list = parsed as Object[]
    for (let i = 0; i < list.length; i++) {
      try {
        const item = RuleCatalogItem.fromJSON(list[i] as Record<string, Object>)
        if (item.name.length > 0) {
          items.push(item)
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        logger.warn('Failed to parse catalog item at index %{public}d: %{public}s', i, msg)
      }
    }
    logger.info('Fetched catalog with %{public}d items', items.length)
    return items
  }

  static getRuleStatus(item: RuleCatalogItem, localRules: RuleSource[]): string {
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

    const apiNum = parseInt(rule.api, 10)
    if (!isNaN(apiNum) && apiNum > AppConstants.SUPPORTED_API_LEVEL) {
      logger.warn('Rule %{public}s api=%{public}d exceeds supported level %{public}d',
        name, apiNum, AppConstants.SUPPORTED_API_LEVEL)
      return 1
    }

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
