import { RuleInstallOrigin, RuleSource } from '../models/RuleSource'
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
  private static repositoryRequests: Map<string, Promise<string>> = new Map()
  private static preferredChannels: Map<string, string> = new Map()
  private static readonly REPOSITORY_TIMEOUT_MS: number = 5000
  private static readonly REPOSITORY_FALLBACK_DELAY_MS: number = 700
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

  static async importFromJson(jsonStr: string,
    installOrigin: string = RuleInstallOrigin.IMPORTED): Promise<number> {
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
            DefaultRuleSourceInitializer.validateRuleJson(rawRule)
            const rule = RuleSource.fromJSON(rawRule)
            rule.installOrigin = RuleInstallOrigin.normalize(installOrigin)
            await DefaultRuleSourceInitializer.saveImportedRule(store, rule)
            count++
          } catch (err) {
            failed++
            const msg = err instanceof Error ? err.message : String(err)
            logger.error('Failed to import rule at index %{public}d: %{public}s', i, msg)
          }
        }
      } else {
        const rawRule = parsed as Record<string, Object>
        DefaultRuleSourceInitializer.validateRuleJson(rawRule)
        const rule = RuleSource.fromJSON(rawRule)
        rule.installOrigin = RuleInstallOrigin.normalize(installOrigin)
        await DefaultRuleSourceInitializer.saveImportedRule(store, rule)
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

  private static async saveImportedRule(store: RuleSourceStore, rule: RuleSource): Promise<void> {
    const existing = await store.getByName(rule.name)
    if (existing !== null) {
      rule.id = existing.id
      rule.enabled = existing.enabled
      rule.sortOrder = existing.sortOrder
      await store.update(rule)
      return
    }
    rule.enabled = true
    rule.sortOrder = await store.getNextSortOrder()
    await store.insert(rule)
  }

  static async importFromUrl(url: string,
    installOrigin: string = RuleInstallOrigin.IMPORTED): Promise<number> {
    const body = await DefaultRuleSourceInitializer.fetchTextWithGithubMirror(url)
    return await DefaultRuleSourceInitializer.importFromJson(body, installOrigin)
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
        imported += await DefaultRuleSourceInitializer.importFromJson(ruleBody, RuleInstallOrigin.REPOSITORY)
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

  static validateRuleJson(json: Record<string, Object>): void {
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
    const required: string[] = []
    const xpathFields: string[] = []
    if (searchMode === 'xpath') {
      required.push('searchURL', 'searchList', 'searchName', 'searchResult')
      xpathFields.push('searchList', 'searchName', 'searchResult')
    }
    if (chapterMode === 'xpath') {
      required.push('chapterRoads', 'chapterResult')
      xpathFields.push('chapterRoads', 'chapterResult')
    }
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
    const sourceTemplate = config['sourceTemplate']
    if (sourceTemplate !== undefined && typeof sourceTemplate !== 'string') {
      throw new Error('详情页地址模板必须是字符串')
    }
    if (typeof sourceTemplate === 'string' && (sourceTemplate as string).trim().length > 0 &&
      (sourceTemplate as string).indexOf('@source') < 0) {
      throw new Error('详情页地址模板必须引用 @source')
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
    const normalized = DefaultRuleSourceInitializer.normalizeGithubRawUrl(url)
    const existing = DefaultRuleSourceInitializer.repositoryRequests.get(normalized)
    if (existing !== undefined) {
      logger.info('Joining repository request: %{public}s', normalized.substring(0, 100))
      return existing
    }
    const pending = DefaultRuleSourceInitializer.fetchRepositoryText(normalized)
    DefaultRuleSourceInitializer.repositoryRequests.set(normalized, pending)
    try {
      return await pending
    } finally {
      DefaultRuleSourceInitializer.repositoryRequests.delete(normalized)
    }
  }

  private static fetchRepositoryText(url: string): Promise<string> {
    const urls = DefaultRuleSourceInitializer.buildGithubMirrorCandidates(url)
    const repositoryKey = url.substring(0, url.lastIndexOf('/') + 1)
    const preferred = DefaultRuleSourceInitializer.preferredChannels.get(repositoryKey)
    if (preferred !== undefined) {
      const preferredIndex = urls.findIndex((candidate: string) =>
        DefaultRuleSourceInitializer.repositoryChannel(candidate) === preferred)
      if (preferredIndex > 0) {
        const candidate = urls.splice(preferredIndex, 1)[0]
        urls.unshift(candidate)
      }
    }
    return new Promise<string>((resolve, reject) => {
      let nextIndex = 0
      let failedCount = 0
      let settled = false
      let timerId = -1
      const errors: string[] = []
      const launchNext = (): void => {
        if (settled || nextIndex >= urls.length) return
        if (timerId >= 0) clearTimeout(timerId)
        timerId = -1
        const candidate = urls[nextIndex++]
        if (nextIndex < urls.length) {
          timerId = setTimeout(launchNext, DefaultRuleSourceInitializer.REPOSITORY_FALLBACK_DELAY_MS)
        }
        DefaultRuleSourceInitializer.fetchRepositoryCandidate(candidate).then((body: string) => {
          if (settled) return
          settled = true
          if (timerId >= 0) clearTimeout(timerId)
          DefaultRuleSourceInitializer.preferredChannels.set(repositoryKey,
            DefaultRuleSourceInitializer.repositoryChannel(candidate))
          resolve(body)
        }).catch((err: Error) => {
          if (settled) return
          failedCount++
          errors.push(DefaultRuleSourceInitializer.repositoryChannel(candidate) + ': ' + err.message)
          if (nextIndex < urls.length) {
            launchNext()
          } else if (failedCount === urls.length) {
            settled = true
            if (timerId >= 0) clearTimeout(timerId)
            reject(new Error(errors.join('; ')))
          }
        })
      }
      launchNext()
    })
  }

  private static async fetchRepositoryCandidate(url: string): Promise<string> {
    const channel = DefaultRuleSourceInitializer.repositoryChannel(url)
    const startTime = Date.now()
    logger.info('Repository request started: channel=%{public}s url=%{public}s', channel, url.substring(0, 120))
    try {
      const config = RequestConfig.createGet(url, {
        'Accept': 'application/json,text/plain,*/*',
        'User-Agent': 'KazumiOHOS/1.0'
      })
      config.timeout = DefaultRuleSourceInitializer.REPOSITORY_TIMEOUT_MS
      config.retryPolicy = new RetryPolicy(0, 0)
      config.connectionRetryPolicy = new RetryPolicy(0, 0)
      const response = await new HttpClient().request(config)
      if (!response.isSuccessful || response.body.trim().length === 0) {
        throw new Error(`HTTP ${response.statusCode}: ${response.body.substring(0, 120)}`)
      }
      // Error pages from a mirror must not beat a valid JSON response.
      const parsed: Object = JSON.parse(response.body)
      if (parsed === null || typeof parsed !== 'object') {
        throw new Error('仓库返回的内容不是 JSON 对象或数组')
      }
      if (url.split('?')[0].split('#')[0].endsWith('/index.json') &&
        (!Array.isArray(parsed) || ((parsed as Object[]).length > 0 &&
        !DefaultRuleSourceInitializer.isCatalogIndexArray(parsed as Object[])))) {
        throw new Error('仓库返回的内容不是有效的 Kazumi 规则目录')
      }
      logger.info('Repository request succeeded: channel=%{public}s elapsed=%{public}dms url=%{public}s',
        channel, Date.now() - startTime, url.substring(0, 120))
      return response.body
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      logger.warn('Repository request failed: channel=%{public}s elapsed=%{public}dms error=%{public}s url=%{public}s',
        channel, Date.now() - startTime, message, url.substring(0, 120))
      throw new Error(message)
    }
  }

  private static repositoryChannel(url: string): string {
    if (DefaultRuleSourceInitializer.isJsDelivrGithubUrl(url)) return 'jsdelivr'
    if (DefaultRuleSourceInitializer.isGithubMirrorUrl(url)) return 'mirror'
    return 'direct'
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
    urls.push(normalized)
    for (let i = 0; i < GITHUB_MIRROR_PREFIXES.length; i++) {
      const prefix = GITHUB_MIRROR_PREFIXES[i]
      urls.push(prefix + normalized)
    }
    return urls
  }

  static normalizeGithubRawUrl(url: string): string {
    let trimmed = url.trim()
    for (let i = 0; i < GITHUB_MIRROR_PREFIXES.length; i++) {
      if (trimmed.startsWith(GITHUB_MIRROR_PREFIXES[i])) {
        trimmed = trimmed.substring(GITHUB_MIRROR_PREFIXES[i].length)
        break
      }
    }
    const jsDelivrPrefix = 'https://cdn.jsdelivr.net/gh/'
    if (trimmed.startsWith(jsDelivrPrefix)) {
      const parts = trimmed.substring(jsDelivrPrefix.length).split('/')
      if (parts.length >= 3) {
        const refIndex = parts[1].indexOf('@')
        const repo = refIndex >= 0 ? parts[1].substring(0, refIndex) : parts[1]
        const ref = refIndex >= 0 ? parts[1].substring(refIndex + 1) : 'main'
        return `https://raw.githubusercontent.com/${parts[0]}/${repo}/${ref}/${parts.slice(2).join('/')}`
      }
    }
    const rawPrefix = 'https://raw.githubusercontent.com/'
    if (trimmed.startsWith(rawPrefix)) {
      const parts = trimmed.substring(rawPrefix.length).split('/')
      if (parts.length >= 6 && parts[2] === 'refs' && parts[3] === 'heads') {
        return rawPrefix + parts.slice(0, 2).join('/') + '/' + parts.slice(4).join('/')
      }
      return trimmed
    }
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
      return DefaultRuleSourceInitializer.normalizeGithubRawUrl(
        `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path}`)
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
