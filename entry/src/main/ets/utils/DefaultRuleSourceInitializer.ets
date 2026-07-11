import { RuleSource } from '../models/RuleSource'
import { RuleSourceStore } from '../store/RuleSourceStore'
import { HttpClient } from '../network/HttpClient'
import { RequestConfig, RetryPolicy } from '../network/RequestConfig'
import { Logger } from '../utils/Logger'
import { AppConstants } from '../constants/AppConstants'

const logger = new Logger('DefaultRuleSourceInitializer')
const GITHUB_MIRROR_PREFIXES: string[] = [
  'https://ghfast.top/'
]

export class DefaultRuleSourceInitializer {
  /**
   * @deprecated Legacy method — not used in current startup path. Use RuleCatalogService instead.
   */
  static async initializeIfNeeded(): Promise<boolean> {
    const store = new RuleSourceStore()
    const count = await store.count()
    if (count > 0) {
      logger.info('Rule sources already exist: %{public}d, skip initialization', count)
      return false
    }

    logger.info('No rule sources found; default built-in rules are disabled')
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

  /**
   * @deprecated Legacy method — built-in rules are disabled. Use RuleCatalogService or user import instead.
   */
  static getDefaultRules(): RuleSource[] {
    return []
  }

  static async importFromJson(jsonStr: string): Promise<number> {
    const store = new RuleSourceStore()
    let count = 0
    let failed = 0
    try {
      const parsed: Object = JSON.parse(jsonStr)
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[]
        if (arr.length > 0 && DefaultRuleSourceInitializer.isCatalogIndexArray(arr)) {
          throw new Error('链接内容是规则仓库索引，不是单个规则 JSON')
        }
        for (let i = 0; i < arr.length; i++) {
          try {
            const rawRule = arr[i] as Record<string, Object>
            DefaultRuleSourceInitializer.assertValidRuleJson(rawRule)
            const rule = RuleSource.fromJSON(rawRule)
            const existing = await store.getByName(rule.name)
            if (existing !== null) {
              rule.id = existing.id
              await store.update(rule)
            } else {
              await store.insert(rule)
            }
            count++
          } catch (err) {
            failed++
            const msg = err instanceof Error ? err.message : String(err)
            logger.error('Failed to import rule at index %{public}d: %{public}s', i, msg)
          }
        }
      } else {
        const rawRule = parsed as Record<string, Object>
        DefaultRuleSourceInitializer.assertValidRuleJson(rawRule)
        const rule = RuleSource.fromJSON(rawRule)
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
      throw new Error('规则 JSON 校验失败: ' + msg)
    }
    if (count === 0) {
      throw new Error(failed > 0 ? '链接内容不是有效的 Kazumi 规则' : '没有可导入的规则')
    }
    return count
  }

  static async importFromUrl(url: string): Promise<number> {
    const body = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(url)
    return await DefaultRuleSourceInitializer.importFromJson(body)
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

    logger.info('Rule catalog import finished: imported=%{public}d failed=%{public}d',
      imported, failed)
    if (imported === 0 && failed > 0) {
      throw new Error(`Rule catalog import failed: ${failed} rules failed`)
    }
    return imported
  }

  static buildCatalogRuleUrl(indexUrl: string, name: string): string {
    const normalized = DefaultRuleSourceInitializer.normalizeGithubRawUrl(indexUrl)
    const marker = '/index.json'
    if (normalized.endsWith(marker)) {
      return normalized.substring(0, normalized.length - marker.length + 1) + encodeURIComponent(name) + '.json'
    }
    throw new Error('Rule catalog URL must point to index.json')
  }

  static isValidCatalogItemJson(json: Record<string, Object>): boolean {
    if (!DefaultRuleSourceInitializer.hasNonEmptyString(json, 'name') ||
      !DefaultRuleSourceInitializer.hasNonEmptyString(json, 'version')) {
      return false
    }
    if (DefaultRuleSourceInitializer.hasRuleSpecificField(json)) {
      return false
    }
    return json['author'] !== undefined ||
      json['lastUpdate'] !== undefined ||
      json['useNativePlayer'] !== undefined ||
      json['antiCrawlerEnabled'] !== undefined
  }

  private static assertValidRuleJson(json: Record<string, Object>): void {
    const commonRequired: string[] = [
      'name',
      'version',
      'api'
    ]
    for (let i = 0; i < commonRequired.length; i++) {
      if (!DefaultRuleSourceInitializer.hasNonEmptyString(json, commonRequired[i])) {
        throw new Error(`缺少 Kazumi 规则字段: ${commonRequired[i]}`)
      }
    }
    const apiText = String(json['api']).trim()
    const apiNum = parseInt(apiText, 10)
    if (isNaN(apiNum)) {
      throw new Error('Kazumi 规则 api 字段不是数字')
    }
    if (apiNum > AppConstants.SUPPORTED_API_LEVEL) {
      throw new Error(`Kazumi 规则 api=${apiNum} 高于当前支持的 ${AppConstants.SUPPORTED_API_LEVEL}`)
    }

    const searchMode = json['searchMode'] === 'api' ? 'api' : 'xpath'
    const chapterMode = json['chapterMode'] === 'api' ? 'api' : 'xpath'
    if (searchMode === 'api') {
      DefaultRuleSourceInitializer.assertValidApiSearchJson(json)
    }
    if (chapterMode === 'api') {
      DefaultRuleSourceInitializer.assertValidApiChapterJson(json)
    }
    if (searchMode === 'api' && chapterMode === 'api') {
      return
    }

    const required: string[] = [
      'searchURL',
      'searchList',
      'searchName',
      'searchResult',
      'chapterRoads',
      'chapterResult'
    ]
    for (let i = 0; i < required.length; i++) {
      if (!DefaultRuleSourceInitializer.hasNonEmptyString(json, required[i])) {
        throw new Error(`缺少 Kazumi 规则字段: ${required[i]}`)
      }
    }
    if (searchMode !== 'api' && !DefaultRuleSourceInitializer.looksLikeHttpTemplate(String(json['searchURL']))) {
      throw new Error('Kazumi 规则 searchURL 不是有效 HTTP 检索模板')
    }
    if (searchMode !== 'api' && String(json['searchURL']).indexOf('@keyword') < 0) {
      throw new Error('Kazumi 规则 searchURL 缺少 @keyword 占位符')
    }
    const xpathFields: string[] = [
      'searchList',
      'searchName',
      'searchResult',
      'chapterRoads',
      'chapterResult'
    ]
    for (let i = 0; i < xpathFields.length; i++) {
      const value = String(json[xpathFields[i]]).trim()
      if (!DefaultRuleSourceInitializer.looksLikeXPath(value)) {
        throw new Error(`Kazumi 规则 ${xpathFields[i]} 不是有效 XPath`)
      }
    }
  }

  private static assertValidApiSearchJson(json: Record<string, Object>): void {
    const config = DefaultRuleSourceInitializer.asRecord(json['searchApiConfig'])
    const request = DefaultRuleSourceInitializer.asRecord(config['request'])
    if (!DefaultRuleSourceInitializer.hasNonEmptyString(request, 'url')) {
      throw new Error('Kazumi API 规则 searchApiConfig.request.url 不能为空')
    }
    if (!DefaultRuleSourceInitializer.hasNonEmptyString(config, 'listPath') ||
      !DefaultRuleSourceInitializer.hasNonEmptyString(config, 'namePath') ||
      !DefaultRuleSourceInitializer.hasNonEmptyString(config, 'sourcePath')) {
      throw new Error('Kazumi API 规则 searchApiConfig 缺少必要 JSONPath')
    }
  }

  private static assertValidApiChapterJson(json: Record<string, Object>): void {
    const config = DefaultRuleSourceInitializer.asRecord(json['chapterApiConfig'])
    const request = DefaultRuleSourceInitializer.asRecord(config['request'])
    if (!DefaultRuleSourceInitializer.hasNonEmptyString(request, 'url')) {
      throw new Error('Kazumi API 规则 chapterApiConfig.request.url 不能为空')
    }
    if (config['format'] === 'delimited') {
      if (!DefaultRuleSourceInitializer.hasNonEmptyString(config, 'roadNamesPath') ||
        !DefaultRuleSourceInitializer.hasNonEmptyString(config, 'roadEpisodesPath')) {
        throw new Error('Kazumi API 分隔章节规则缺少 roadNamesPath 或 roadEpisodesPath')
      }
      return
    }
    const hasEpisodeUrl = DefaultRuleSourceInitializer.hasNonEmptyString(config, 'episodeUrlPath')
    const episodePage = DefaultRuleSourceInitializer.asRecord(config['episodePage'])
    const hasEpisodePage = DefaultRuleSourceInitializer.hasNonEmptyString(episodePage, 'url')
    if (!hasEpisodeUrl && !hasEpisodePage) {
      throw new Error('Kazumi API 规则必须配置 episodeUrlPath 或 episodePage.url')
    }
  }

  private static asRecord(value: Object | undefined): Record<string, Object> {
    if (value === undefined || value === null || Array.isArray(value) || typeof value !== 'object') {
      return {}
    }
    return value as Record<string, Object>
  }

  private static isCatalogIndexArray(arr: Object[]): boolean {
    if (arr.length === 0) {
      return false
    }
    let validItems = 0
    for (let i = 0; i < arr.length; i++) {
      if (DefaultRuleSourceInitializer.isValidCatalogItemJson(arr[i] as Record<string, Object>)) {
        validItems++
      }
    }
    return validItems === arr.length
  }

  private static hasRuleSpecificField(json: Record<string, Object>): boolean {
    return json['searchURL'] !== undefined ||
      json['searchList'] !== undefined ||
      json['searchName'] !== undefined ||
      json['searchResult'] !== undefined ||
      json['chapterRoads'] !== undefined ||
      json['chapterResult'] !== undefined
  }

  private static hasNonEmptyString(json: Record<string, Object>, key: string): boolean {
    const value = json[key]
    return typeof value === 'string' && (value as string).trim().length > 0
  }

  private static looksLikeHttpTemplate(value: string): boolean {
    const text = value.trim()
    return text.startsWith('http://') || text.startsWith('https://')
  }

  private static looksLikeXPath(value: string): boolean {
    const text = value.trim()
    return text.startsWith('/') ||
      text.startsWith('./') ||
      text.startsWith('(') ||
      text.startsWith('@') ||
      text.indexOf('::') >= 0
  }

  static async fetchTextWithGithubMirror(url: string): Promise<string> {
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
        if (DefaultRuleSourceInitializer.isJsDelivrGithubUrl(candidate)) {
          logger.info('Fetched via jsDelivr CDN: %{public}s', candidate.substring(0, 80))
        } else if (DefaultRuleSourceInitializer.isGithubMirrorUrl(candidate)) {
          logger.info('Fetched via GitHub mirror: %{public}s', candidate.substring(0, 80))
        } else if (i > 0) {
          logger.info('Fetched via direct GitHub: %{public}s', candidate.substring(0, 80))
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
    if (!DefaultRuleSourceInitializer.isGithubUrl(normalized)) {
      return [normalized]
    }

    const urls: string[] = []
    const jsDelivrUrl = DefaultRuleSourceInitializer.toJsDelivrGithubUrl(normalized)
    if (jsDelivrUrl.length > 0) {
      urls.push(jsDelivrUrl)
    }
    for (let i = 0; i < GITHUB_MIRROR_PREFIXES.length; i++) {
      const prefix = GITHUB_MIRROR_PREFIXES[i]
      urls.push(prefix + normalized)
    }
    urls.push(normalized)
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

  private static toJsDelivrGithubUrl(url: string): string {
    const rawPrefix = 'https://raw.githubusercontent.com/'
    if (!url.startsWith(rawPrefix)) {
      return ''
    }
    const parts = url.substring(rawPrefix.length).split('/')
    if (parts.length >= 4 && parts[0].length > 0 && parts[1].length > 0 && parts[2].length > 0) {
      const owner = parts[0]
      const repo = parts[1]
      if (parts.length >= 6 && parts[2] === 'refs' && parts[3] === 'heads' && parts[4].length > 0) {
        const ref = parts[4]
        const path = parts.slice(5).join('/')
        if (path.length > 0) {
          return `https://cdn.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path}`
        }
      }
      const ref = parts[2]
      const path = parts.slice(3).join('/')
      if (path.length > 0) {
        return `https://cdn.jsdelivr.net/gh/${owner}/${repo}@${ref}/${path}`
      }
    }
    return ''
  }

  private static isGithubUrl(url: string): boolean {
    return url.startsWith('https://raw.githubusercontent.com/') ||
      url.startsWith('https://github.com/')
  }

  private static isJsDelivrGithubUrl(url: string): boolean {
    return url.startsWith('https://cdn.jsdelivr.net/gh/')
  }

  private static isGithubMirrorUrl(url: string): boolean {
    for (let i = 0; i < GITHUB_MIRROR_PREFIXES.length; i++) {
      if (url.startsWith(GITHUB_MIRROR_PREFIXES[i])) {
        return true
      }
    }
    return false
  }
}
