import { RuleSource } from '../models/RuleSource'
import { RuleSourceStore } from '../store/RuleSourceStore'
import { HttpClient } from '../network/HttpClient'
import { RequestConfig, RetryPolicy } from '../network/RequestConfig'
import { Logger } from '../utils/Logger'

const logger = new Logger('DefaultRuleSourceInitializer')
const KAZUMI_RULES_RAW_BASE = 'https://raw.githubusercontent.com/Predidit/KazumiRules/main/'
const KAZUMI_RULES_INDEX_URL = KAZUMI_RULES_RAW_BASE + 'index.json'
const GITHUB_MIRROR_PREFIX = 'https://ghfast.top/'

export class DefaultRuleSourceInitializer {
  static async initializeIfNeeded(): Promise<boolean> {
    const store = new RuleSourceStore()
    const count = await store.count()
    if (count > 0) {
      logger.info('Rule sources already exist: %{public}d, skip initialization', count)
      return false
    }

    logger.info('No rule sources found, initializing default rules')
    const defaultRules = DefaultRuleSourceInitializer.getDefaultRules()
    let inserted = 0
    for (let i = 0; i < defaultRules.length; i++) {
      try {
        await store.insert(defaultRules[i])
        inserted++
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err)
        logger.error('Failed to insert default rule %{public}s: %{public}s', defaultRules[i].name, msg)
      }
    }
    logger.info('Default rule sources initialized: %{public}d/%{public}d', inserted, defaultRules.length)
    return true
  }

  static getDefaultRules(): RuleSource[] {
    const rules: RuleSource[] = []

    const rule1 = new RuleSource()
    rule1.api = 'https://api.example.com'
    rule1.type = 'anime'
    rule1.name = 'AgeFans'
    rule1.version = '1.0.0'
    rule1.baseUrl = 'https://www.agefans.cc'
    rule1.searchURL = '/search?query=@keyword'
    rule1.searchList = '//div[@class="blockcontent1"]//a'
    rule1.searchName = './/text()'
    rule1.searchResult = './@href'
    rule1.chapterRoads = '//div[@class="fullsitec"]//a'
    rule1.chapterResult = '.'
    rule1.useWebview = true
    rule1.enabled = true
    rules.push(rule1)

    const rule2 = new RuleSource()
    rule2.api = 'https://api.example2.com'
    rule2.type = 'anime'
    rule2.name = 'Yhdm'
    rule2.version = '1.0.0'
    rule2.baseUrl = 'https://www.yhdm.io'
    rule2.searchURL = '/search/@keyword/'
    rule2.searchList = '//div[@class="lpic"]//a'
    rule2.searchName = './/h2/text()'
    rule2.searchResult = './@href'
    rule2.chapterRoads = '//div[@class="movurl"]//a'
    rule2.chapterResult = '.'
    rule2.enabled = true
    rules.push(rule2)

    return rules
  }

  static async importFromJson(jsonStr: string): Promise<number> {
    const store = new RuleSourceStore()
    let count = 0
    try {
      const parsed: Object = JSON.parse(jsonStr)
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[]
        for (let i = 0; i < arr.length; i++) {
          try {
            const rule = RuleSource.fromJSON(arr[i] as Record<string, Object>)
            const existing = await store.getByName(rule.name)
            if (existing !== null) {
              rule.id = existing.id
              await store.update(rule)
            } else {
              await store.insert(rule)
            }
            count++
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err)
            logger.error('Failed to import rule at index %{public}d: %{public}s', i, msg)
          }
        }
      } else {
        const rule = RuleSource.fromJSON(parsed as Record<string, Object>)
        const existing = await store.getByName(rule.name)
        if (existing !== null) {
          rule.id = existing.id
          await store.update(rule)
        } else {
          await store.insert(rule)
        }
        count = 1
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Failed to parse JSON: %{public}s', msg)
      throw new Error('JSON parse failed: ' + msg)
    }
    return count
  }

  static async importFromUrl(url: string): Promise<number> {
    const body = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(url)
    return await DefaultRuleSourceInitializer.importFromJson(body)
  }

  static async importFromKazumiRulesCatalog(): Promise<number> {
    return await DefaultRuleSourceInitializer.importFromCatalogUrl(KAZUMI_RULES_INDEX_URL)
  }

  static async importFromCatalogUrl(indexUrl: string): Promise<number> {
    const indexBody = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(indexUrl)
    const parsed: Object = JSON.parse(indexBody)
    if (!Array.isArray(parsed)) {
      throw new Error('Rule catalog index must be a JSON array')
    }

    const list = parsed as Object[]
    let imported = 0
    let failed = 0
    for (let i = 0; i < list.length; i++) {
      try {
        const item = list[i] as Record<string, Object>
        const name = (item['name'] as string) ?? ''
        if (name.length === 0) {
          failed++
          continue
        }
        const ruleUrl = DefaultRuleSourceInitializer.buildCatalogRuleUrl(indexUrl, name)
        const ruleBody = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(ruleUrl)
        imported += await DefaultRuleSourceInitializer.importFromJson(ruleBody)
      } catch (err) {
        failed++
        const msg = err instanceof Error ? err.message : String(err)
        logger.warn('Failed to import catalog rule at index %{public}d: %{public}s', i, msg)
      }
    }

    logger.info('KazumiRules catalog import finished: imported=%{public}d failed=%{public}d',
      imported, failed)
    if (imported === 0 && failed > 0) {
      throw new Error(`Rule catalog import failed: ${failed} rules failed`)
    }
    return imported
  }

  private static buildCatalogRuleUrl(indexUrl: string, name: string): string {
    const normalized = DefaultRuleSourceInitializer.normalizeGithubRawUrl(indexUrl)
    const marker = '/index.json'
    if (normalized.endsWith(marker)) {
      return normalized.substring(0, normalized.length - marker.length + 1) + encodeURIComponent(name) + '.json'
    }
    return KAZUMI_RULES_RAW_BASE + encodeURIComponent(name) + '.json'
  }

  private static async fetchTextWithGithubMirror(url: string): Promise<string> {
    const urls = DefaultRuleSourceInitializer.buildGithubMirrorCandidates(url)
    let lastError = ''
    for (let i = 0; i < urls.length; i++) {
      const candidate = urls[i]
      const client = new HttpClient()
      const config = RequestConfig.createGet(candidate, {
        'Accept': 'application/json,text/plain,*/*',
        'User-Agent': 'KazumiOHOS/1.0'
      })
      config.timeout = 12000
      config.retryPolicy = new RetryPolicy(1, 800)
      const response = await client.request(config)
      if (response.isSuccessful && response.body.length > 0) {
        if (i > 0) {
          logger.info('Fetched via GitHub mirror: %{public}s', candidate.substring(0, 80))
        }
        return response.body
      }
      lastError = `HTTP ${response.statusCode}: ${response.body.substring(0, 120)}`
      logger.warn('Fetch failed: %{public}s, url=%{public}s',
        lastError, candidate.length > 100 ? candidate.substring(0, 100) : candidate)
    }
    throw new Error(lastError.length > 0 ? lastError : 'Fetch failed')
  }

  private static buildGithubMirrorCandidates(url: string): string[] {
    const normalized = DefaultRuleSourceInitializer.normalizeGithubRawUrl(url)
    const urls: string[] = [normalized]
    if (DefaultRuleSourceInitializer.isGithubUrl(normalized) && !normalized.startsWith(GITHUB_MIRROR_PREFIX)) {
      urls.push(GITHUB_MIRROR_PREFIX + normalized)
    }
    return urls
  }

  private static normalizeGithubRawUrl(url: string): string {
    const trimmed = url.trim()
    const githubBlobPrefix = 'https://github.com/'
    if (!trimmed.startsWith(githubBlobPrefix)) {
      return trimmed
    }
    const parts = trimmed.substring(githubBlobPrefix.length).split('/')
    if (parts.length >= 5 && parts[2] === 'blob') {
      const owner = parts[0]
      const repo = parts[1]
      const ref = parts[3]
      const path = parts.slice(4).join('/')
      return `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path}`
    }
    return trimmed
  }

  private static isGithubUrl(url: string): boolean {
    return url.startsWith('https://raw.githubusercontent.com/') ||
      url.startsWith('https://github.com/')
  }
}
