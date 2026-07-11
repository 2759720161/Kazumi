import { AnimeItem } from '../../models/AnimeItem'
import { PlaybackRoad } from '../../models/PlaybackRoad'
import { RuleSource } from '../../models/RuleSource'
import { ApiChapterConfig, ApiRequestConfig, ApiSearchConfig, ApiBodyType, ApiChapterFormat } from '../../models/ApiRuleConfig'
import { HttpClient } from '../../network/HttpClient'
import { RequestConfig, RetryPolicy } from '../../network/RequestConfig'
import { UrlUtils } from '../../utils/UrlUtils'
import { Logger } from '../../utils/Logger'

const logger = new Logger('ApiRuleStrategy')

class PreparedApiRequest {
  url: string = ''
  method: string = 'GET'
  headers: Record<string, string> = ApiRuleStrategyUtils.emptyStringRecord()
  body: string = ''
}

export class ApiRuleStrategy {
  private client: HttpClient = new HttpClient()

  async search(rule: RuleSource, keyword: string): Promise<AnimeItem[]> {
    const variables: Record<string, Object> = ApiRuleStrategyUtils.emptyObjectRecord()
    variables['keyword'] = keyword
    const request = this.prepareRequest(rule.searchApiConfig.request, rule.baseUrl, variables)
    const raw = await this.execute(request)
    return this.parseSearch(raw, rule.searchApiConfig, rule)
  }

  async queryRoads(rule: RuleSource, source: string): Promise<PlaybackRoad[]> {
    const variables: Record<string, Object> = ApiRuleStrategyUtils.emptyObjectRecord()
    variables['source'] = source
    const request = this.prepareRequest(rule.chapterApiConfig.request, rule.baseUrl, variables)
    const raw = await this.execute(request)
    return this.parseChapters(raw, rule.chapterApiConfig, rule, source)
  }

  private prepareRequest(config: ApiRequestConfig, baseUrl: string, variables: Record<string, Object>): PreparedApiRequest {
    const request = new PreparedApiRequest()
    const method = config.method.toUpperCase()
    if (method !== 'GET' && method !== 'POST') {
      throw new Error(`仅支持 GET/POST，当前为 ${method}`)
    }
    if (config.url.trim().length === 0) {
      throw new Error('API 请求 URL 不能为空')
    }
    request.method = method
    const renderedUrl = this.renderTemplate(config.url.trim(), variables, true)
    request.url = UrlUtils.resolveUrl(baseUrl, renderedUrl)
    request.headers = this.renderHeaderMap(config.headers, variables)
    if (request.headers['User-Agent'] === undefined) {
      request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36'
    }
    if (request.headers['Accept'] === undefined) {
      request.headers['Accept'] = 'application/json,text/plain,*/*'
    }

    const query = this.renderQueryMap(config.query, variables)
    if (Object.keys(query).length > 0) {
      request.url = UrlUtils.buildUrl(request.url, query)
    }

    if (request.method === 'POST') {
      if (config.bodyType === ApiBodyType.JSON) {
        request.body = JSON.stringify(this.renderValue(config.body, variables))
        request.headers['Content-Type'] = 'application/json'
      } else if (config.bodyType === ApiBodyType.FORM) {
        const bodyRecord = this.objectToStringRecord(this.renderValue(config.body, variables))
        request.body = UrlUtils.encodeParams(bodyRecord)
        request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      }
    }
    return request
  }

  private async execute(request: PreparedApiRequest): Promise<string> {
    const config = request.method === 'POST'
      ? RequestConfig.createPost(request.url, request.body, request.headers)
      : RequestConfig.createGet(request.url, request.headers)
    config.timeout = 12000
    config.retryPolicy = new RetryPolicy(1, 800)
    const response = await this.client.request(config)
    if (!response.isSuccessful) {
      throw new Error(`HTTP ${response.statusCode}`)
    }
    return response.body
  }

  private parseSearch(raw: string, config: ApiSearchConfig, rule: RuleSource): AnimeItem[] {
    this.validateSearchConfig(config)
    const root = this.decodeResponse(raw)
    const nodes = RestrictedJsonPath.select(root, config.listPath)
    const items: AnimeItem[] = []
    for (let i = 0; i < nodes.length; i++) {
      const itemNode = nodes[i]
      const name = this.stringValue(RestrictedJsonPath.first(itemNode, config.namePath))
      const source = this.stringValue(RestrictedJsonPath.first(itemNode, config.sourcePath))
      if (name.length === 0 || source.length === 0) continue
      const item = new AnimeItem()
      item.name = name
      item.url = source
      item.sourceId = rule.id
      item.sourceName = rule.name
      items.push(item)
    }
    logger.info('API search parsed: rule=%{public}s count=%{public}d', rule.name, items.length)
    return items
  }

  private parseChapters(raw: string, config: ApiChapterConfig, rule: RuleSource, source: string): PlaybackRoad[] {
    this.validateChapterConfig(config)
    const root = this.decodeResponse(raw)
    const rootVariables: Record<string, Object> = ApiRuleStrategyUtils.emptyObjectRecord()
    rootVariables['source'] = source
    const variableNames = Object.keys(config.variables)
    for (let i = 0; i < variableNames.length; i++) {
      const key = variableNames[i]
      const value = RestrictedJsonPath.first(root, config.variables[key])
      if (value === undefined || value === null) {
        throw new Error(`章节响应变量 ${key} 未匹配到值: ${config.variables[key]}`)
      }
      rootVariables[key] = value
    }

    if (config.format === ApiChapterFormat.DELIMITED) {
      return this.parseDelimitedChapters(root, config, rule, source, rootVariables)
    }
    return this.parseNestedChapters(root, config, rule, source, rootVariables)
  }

  private parseNestedChapters(
    root: Object,
    config: ApiChapterConfig,
    rule: RuleSource,
    source: string,
    rootVariables: Record<string, Object>
  ): PlaybackRoad[] {
    const hasRoads = config.roadsPath.trim().length > 0
    const roadNodes = hasRoads ? RestrictedJsonPath.select(root, config.roadsPath) : [root]
    const roads: PlaybackRoad[] = []
    for (let i = 0; i < roadNodes.length; i++) {
      const roadNode = roadNodes[i]
      const roadNameRaw = hasRoads && config.roadNamePath.trim().length > 0
        ? this.stringValue(RestrictedJsonPath.first(roadNode, config.roadNamePath))
        : ''
      const roadName = roadNameRaw.length > 0 ? roadNameRaw : `播放线路${roads.length + 1}`
      const episodeNodes = RestrictedJsonPath.select(roadNode, config.episodesPath)
      const episodeNames: string[] = []
      const episodeUrls: string[] = []
      for (let j = 0; j < episodeNodes.length; j++) {
        const episodeNode = episodeNodes[j]
        const episodeNameRaw = this.stringValue(RestrictedJsonPath.first(episodeNode, config.episodeNamePath))
        let rawUrl = config.episodeUrlPath.trim().length > 0
          ? this.stringValue(RestrictedJsonPath.first(episodeNode, config.episodeUrlPath))
          : ''
        if (rawUrl.length === 0 && rule.name.toLowerCase() === 'tvtfun') {
          const episodeId = this.stringValue(RestrictedJsonPath.first(episodeNode, '$.id'))
          if (episodeId.length > 0) {
            rawUrl = 'https://www.tvtfun.net/api/videos/resolve-play-url?episodeId=' + encodeURIComponent(episodeId)
          }
        }
        episodeNames.push(episodeNameRaw.length > 0 ? episodeNameRaw : `第${j + 1}集`)
        if (rawUrl.indexOf('/api/videos/resolve-play-url?') >= 0) {
          episodeUrls.push(rawUrl)
        } else {
          episodeUrls.push(this.resolveEpisodeUrl(config, rootVariables, rawUrl, i, j, rule.baseUrl))
        }
      }
      if (episodeUrls.length > 0) {
        roads.push(PlaybackRoad.create(roadName, episodeNames, episodeUrls, rule.id, rule.name, source))
      }
    }
    logger.info('API chapters parsed: rule=%{public}s roads=%{public}d', rule.name, roads.length)
    return roads
  }

  private parseDelimitedChapters(
    root: Object,
    config: ApiChapterConfig,
    rule: RuleSource,
    source: string,
    rootVariables: Record<string, Object>
  ): PlaybackRoad[] {
    const namesValue = this.stringValue(RestrictedJsonPath.first(root, config.roadNamesPath))
    const episodesValue = this.stringValue(RestrictedJsonPath.first(root, config.roadEpisodesPath))
    if (episodesValue.length === 0) return []
    const roadNames = namesValue.split(config.roadSeparator)
    const roadGroups = episodesValue.split(config.roadSeparator)
    const roads: PlaybackRoad[] = []
    for (let i = 0; i < roadGroups.length; i++) {
      const entries = roadGroups[i].split(config.episodeSeparator)
      const episodeNames: string[] = []
      const episodeUrls: string[] = []
      for (let j = 0; j < entries.length; j++) {
        const entry = entries[j].trim()
        if (entry.length === 0) continue
        const separatorIndex = entry.indexOf(config.fieldSeparator)
        if (separatorIndex < 0) {
          logger.warn('API delimited episode entry missing field separator: rule=%{public}s road=%{public}d episode=%{public}d',
            rule.name, i, j)
          continue
        }
        const name = entry.substring(0, separatorIndex).trim()
        const rawUrl = entry.substring(separatorIndex + config.fieldSeparator.length).trim()
        const pageUrl = this.resolveEpisodeUrl(config, rootVariables, rawUrl, i, j, rule.baseUrl)
        if (pageUrl.length === 0) {
          continue
        }
        episodeNames.push(name.length > 0 ? name : `第${j + 1}集`)
        episodeUrls.push(pageUrl)
      }
      if (episodeUrls.length === 0) {
        continue
      }
      const configuredName = i < roadNames.length ? roadNames[i].trim() : ''
      const roadName = configuredName.length > 0 ? configuredName : `播放线路${roads.length + 1}`
      roads.push(PlaybackRoad.create(roadName, episodeNames, episodeUrls, rule.id, rule.name, source))
    }
    logger.info('API delimited chapters parsed: rule=%{public}s roads=%{public}d', rule.name, roads.length)
    return roads
  }

  private resolveEpisodeUrl(
    config: ApiChapterConfig,
    rootVariables: Record<string, Object>,
    rawUrl: string,
    roadIndex: number,
    episodeIndex: number,
    baseUrl: string
  ): string {
    if (config.episodePage === undefined) {
      if (rawUrl.trim().length === 0) return ''
      return UrlUtils.resolveUrl(baseUrl, rawUrl)
    }
    const variables: Record<string, Object> = ApiRuleStrategyUtils.emptyObjectRecord()
    const rootKeys = Object.keys(rootVariables)
    for (let i = 0; i < rootKeys.length; i++) {
      variables[rootKeys[i]] = rootVariables[rootKeys[i]]
    }
    variables['episodeUrl'] = rawUrl
    variables['roadIndex'] = roadIndex
    variables['roadNumber'] = roadIndex + 1
    variables['episodeIndex'] = episodeIndex
    variables['episodeNumber'] = episodeIndex + 1

    let url = this.renderTemplate(config.episodePage.url, variables, true)
    url = UrlUtils.resolveUrl(baseUrl, url)
    const query = this.renderQueryMap(config.episodePage.query, variables)
    if (Object.keys(query).length > 0) {
      url = UrlUtils.buildUrl(url, query)
    }
    return url
  }

  private renderHeaderMap(input: Record<string, Object>, variables: Record<string, Object>): Record<string, string> {
    const result: Record<string, string> = ApiRuleStrategyUtils.emptyStringRecord()
    const keys = Object.keys(input)
    for (let i = 0; i < keys.length; i++) {
      const value = this.renderValue(input[keys[i]], variables)
      result[this.renderTemplate(keys[i], variables, false)] = this.stringValue(value)
    }
    return result
  }

  private renderQueryMap(input: Record<string, Object>, variables: Record<string, Object>): Record<string, string> {
    const result: Record<string, string> = ApiRuleStrategyUtils.emptyStringRecord()
    const keys = Object.keys(input)
    for (let i = 0; i < keys.length; i++) {
      const value = this.renderValue(input[keys[i]], variables)
      result[this.renderTemplate(keys[i], variables, false)] = this.stringValue(value)
    }
    return result
  }

  private renderValue(value: Object | undefined, variables: Record<string, Object>): Object {
    if (value === undefined || value === null) return ''
    if (typeof value === 'string') {
      const text = value as string
      if (text.startsWith('@') && text.indexOf(' ') < 0 && text.indexOf('/') < 0) {
        const key = text.substring(1)
        if (variables[key] === undefined) {
          throw new Error(`缺少模板变量 @${key}`)
        }
        return variables[key]
      }
      return this.renderTemplate(text, variables, false)
    }
    if (Array.isArray(value)) {
      const raw = value as Object[]
      const arr: Object[] = []
      for (let i = 0; i < raw.length; i++) {
        arr.push(this.renderValue(raw[i], variables))
      }
      return arr
    }
    if (typeof value === 'object') {
      const source = value as Record<string, Object>
      const result: Record<string, Object> = ApiRuleStrategyUtils.emptyObjectRecord()
      const keys = Object.keys(source)
      for (let i = 0; i < keys.length; i++) {
        result[keys[i]] = this.renderValue(source[keys[i]], variables)
      }
      return result
    }
    return value
  }

  private renderTemplate(template: string, variables: Record<string, Object>, encode: boolean): string {
    let output = template
    const keys = Object.keys(variables)
    for (let i = 0; i < keys.length; i++) {
      const token = '@' + keys[i]
      const raw = this.stringValue(variables[keys[i]])
      const value = encode ? encodeURIComponent(raw) : raw
      output = output.replace(new RegExp(`(^|[^A-Za-z0-9_])${token}`, 'g'), (match: string): string => {
        const prefix = match.substring(0, match.length - token.length)
        return prefix + value
      })
    }
    if (output.indexOf('@') >= 0) {
      const match = output.match(/@[A-Za-z_][A-Za-z0-9_]*/)
      if (match !== null && match.length > 0) {
        throw new Error(`缺少模板变量 ${match[0]}`)
      }
    }
    return output
  }

  private objectToStringRecord(value: Object): Record<string, string> {
    const result: Record<string, string> = ApiRuleStrategyUtils.emptyStringRecord()
    if (value === undefined || value === null || Array.isArray(value) || typeof value !== 'object') {
      return result
    }
    const record = value as Record<string, Object>
    const keys = Object.keys(record)
    for (let i = 0; i < keys.length; i++) {
      result[keys[i]] = this.stringValue(record[keys[i]])
    }
    return result
  }

  private stringValue(value: Object | undefined): string {
    if (value === undefined || value === null) return ''
    return String(value).trim()
  }

  private decodeResponse(raw: string): Object {
    try {
      return JSON.parse(raw) as Object
    } catch (err) {
      throw new Error(`API 响应不是有效 JSON: ${err instanceof Error ? err.message : String(err)}`)
    }
  }

  private validateSearchConfig(config: ApiSearchConfig): void {
    RestrictedJsonPath.validate(config.listPath)
    RestrictedJsonPath.validate(config.namePath)
    RestrictedJsonPath.validate(config.sourcePath)
  }

  private validateChapterConfig(config: ApiChapterConfig): void {
    const variableKeys = Object.keys(config.variables)
    for (let i = 0; i < variableKeys.length; i++) {
      RestrictedJsonPath.validate(config.variables[variableKeys[i]])
    }
    if (config.format === ApiChapterFormat.DELIMITED) {
      RestrictedJsonPath.validate(config.roadNamesPath)
      RestrictedJsonPath.validate(config.roadEpisodesPath)
      if (config.roadSeparator.length === 0 || config.episodeSeparator.length === 0 ||
        config.fieldSeparator.length === 0) {
        throw new Error('章节分隔符不能为空')
      }
      return
    }
    if (config.roadsPath.trim().length > 0) RestrictedJsonPath.validate(config.roadsPath)
    if (config.roadNamePath.trim().length > 0) RestrictedJsonPath.validate(config.roadNamePath)
    RestrictedJsonPath.validate(config.episodesPath)
    RestrictedJsonPath.validate(config.episodeNamePath)
    if (config.episodeUrlPath.trim().length > 0) {
      RestrictedJsonPath.validate(config.episodeUrlPath)
    } else if (config.episodePage === undefined) {
      throw new Error('必须配置播放入口地址路径或播放页地址模板')
    }
    if (config.episodePage !== undefined && config.episodePage.url.trim().length === 0) {
      throw new Error('播放页地址模板不能为空')
    }
  }
}

class ApiRuleStrategyUtils {
  static emptyObjectRecord(): Record<string, Object> {
    const result: Record<string, Object> = {}
    return result
  }

  static emptyStringRecord(): Record<string, string> {
    const result: Record<string, string> = {}
    return result
  }
}

class RestrictedJsonPath {
  static validate(path: string): void {
    if (path.length === 0 || !path.startsWith('$')) {
      throw new Error(`JSONPath 必须以 $ 开头: ${path}`)
    }
    RestrictedJsonPath.parse(path)
  }

  static select(root: Object, path: string): Object[] {
    const trimmed = path.trim()
    if (trimmed.length === 0 || trimmed === '$') {
      return [root]
    }
    RestrictedJsonPath.validate(trimmed)
    let nodes: Object[] = [root]
    const segments = RestrictedJsonPath.parse(trimmed)
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i]
      const next: Object[] = []
      for (let j = 0; j < nodes.length; j++) {
        if (segment.kind === 'field') {
          const child = RestrictedJsonPath.child(nodes[j], segment.value)
          if (child !== undefined && child !== null) next.push(child)
        } else if (segment.kind === 'index') {
          if (Array.isArray(nodes[j])) {
            const arr = nodes[j] as Object[]
            const index = Number.parseInt(segment.value)
            if (index >= 0 && index < arr.length) next.push(arr[index])
          }
        } else if (segment.kind === 'wildcard') {
          if (Array.isArray(nodes[j])) {
            const arr = nodes[j] as Object[]
            for (let k = 0; k < arr.length; k++) next.push(arr[k])
          }
        } else {
          const child = RestrictedJsonPath.child(nodes[j], segment.value)
          if (child !== undefined && child !== null) next.push(child)
        }
      }
      nodes = next
    }
    return nodes
  }

  static first(root: Object, path: string): Object | undefined {
    const values = RestrictedJsonPath.select(root, path)
    return values.length > 0 ? values[0] : undefined
  }

  private static child(node: Object, key: string): Object | undefined {
    if (node === undefined || node === null || Array.isArray(node) || typeof node !== 'object') {
      return undefined
    }
    const record = node as Record<string, Object>
    return record[key]
  }

  private static parse(path: string): JsonPathSegment[] {
    const segments: JsonPathSegment[] = []
    let index = 1
    while (index < path.length) {
      const char = path.charAt(index)
      if (char === '.') {
        index++
        const start = index
        while (index < path.length && RestrictedJsonPath.isFieldChar(path.charAt(index))) {
          index++
        }
        if (index === start) {
          throw new Error(`不支持的 JSONPath: ${path}`)
        }
        const segment = new JsonPathSegment()
        segment.kind = 'field'
        segment.value = path.substring(start, index)
        segments.push(segment)
        continue
      }
      if (char === '[') {
        const end = RestrictedJsonPath.findBracketEnd(path, index)
        const content = path.substring(index + 1, end).trim()
        const segment = new JsonPathSegment()
        if (content === '*') {
          segment.kind = 'wildcard'
          segment.value = ''
        } else if (/^\d+$/.test(content)) {
          segment.kind = 'index'
          segment.value = content
        } else if (RestrictedJsonPath.isQuoted(content)) {
          segment.kind = 'quotedField'
          segment.value = content.substring(1, content.length - 1)
        } else {
          throw new Error(`不支持的 JSONPath 片段: [${content}]`)
        }
        segments.push(segment)
        index = end + 1
        continue
      }
      throw new Error(`不支持的 JSONPath: ${path}`)
    }
    return segments
  }

  private static findBracketEnd(path: string, start: number): number {
    let quote = ''
    let escaped = false
    for (let i = start + 1; i < path.length; i++) {
      const char = path.charAt(i)
      if (escaped) {
        escaped = false
        continue
      }
      if (char === '\\') {
        escaped = true
        continue
      }
      if (quote.length > 0) {
        if (char === quote) quote = ''
        continue
      }
      if (char === '\'' || char === '"') {
        quote = char
        continue
      }
      if (char === ']') return i
    }
    throw new Error(`JSONPath 缺少 ]: ${path}`)
  }

  private static isQuoted(content: string): boolean {
    if (content.length < 2) return false
    return (content.startsWith('\'') && content.endsWith('\'')) ||
      (content.startsWith('"') && content.endsWith('"'))
  }

  private static isFieldChar(char: string): boolean {
    return /^[A-Za-z0-9_$-]$/.test(char)
  }
}

class JsonPathSegment {
  kind: string = ''
  value: string = ''
}
