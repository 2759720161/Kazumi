export class RuleMode {
  static readonly XPATH: string = 'xpath'
  static readonly API: string = 'api'

  static normalize(value: Object | undefined): string {
    return value === RuleMode.API ? RuleMode.API : RuleMode.XPATH
  }
}

export class ApiBodyType {
  static readonly NONE: string = 'none'
  static readonly JSON: string = 'json'
  static readonly FORM: string = 'form'

  static normalize(value: Object | undefined): string {
    if (value === ApiBodyType.JSON) return ApiBodyType.JSON
    if (value === ApiBodyType.FORM) return ApiBodyType.FORM
    return ApiBodyType.NONE
  }
}

export class ApiChapterFormat {
  static readonly NESTED: string = 'nested'
  static readonly DELIMITED: string = 'delimited'

  static normalize(value: Object | undefined): string {
    return value === ApiChapterFormat.DELIMITED ? ApiChapterFormat.DELIMITED : ApiChapterFormat.NESTED
  }
}

export class ApiRequestConfig {
  method: string = 'GET'
  url: string = ''
  headers: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()
  query: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()
  bodyType: string = ApiBodyType.NONE
  body: Object | undefined = undefined

  static fromJSON(json: Record<string, Object> | undefined): ApiRequestConfig {
    const config = new ApiRequestConfig()
    if (json === undefined) return config
    if (typeof json['method'] === 'string') config.method = (json['method'] as string).toUpperCase()
    if (typeof json['url'] === 'string') config.url = json['url'] as string
    config.headers = ApiRuleConfigUtils.asRecord(json['headers'])
    config.query = ApiRuleConfigUtils.asRecord(json['query'])
    config.bodyType = ApiBodyType.normalize(json['bodyType'])
    if (json['body'] !== undefined) config.body = json['body']
    return config
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()
    result['method'] = this.method.toUpperCase()
    result['url'] = this.url
    if (Object.keys(this.headers).length > 0) result['headers'] = this.headers
    if (Object.keys(this.query).length > 0) result['query'] = this.query
    if (this.bodyType !== ApiBodyType.NONE) result['bodyType'] = this.bodyType
    if (this.body !== undefined) result['body'] = this.body
    return result
  }
}

export class ApiSearchConfig {
  request: ApiRequestConfig = new ApiRequestConfig()
  listPath: string = '$.data[*]'
  namePath: string = '$.name'
  sourcePath: string = '$.url'

  static fromJSON(json: Record<string, Object> | undefined): ApiSearchConfig {
    const config = new ApiSearchConfig()
    if (json === undefined) return config
    config.request = ApiRequestConfig.fromJSON(ApiRuleConfigUtils.asRecord(json['request']))
    if (typeof json['listPath'] === 'string') config.listPath = json['listPath'] as string
    if (typeof json['namePath'] === 'string') config.namePath = json['namePath'] as string
    if (typeof json['sourcePath'] === 'string') config.sourcePath = json['sourcePath'] as string
    return config
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()
    result['request'] = this.request.toJSON()
    result['listPath'] = this.listPath
    result['namePath'] = this.namePath
    result['sourcePath'] = this.sourcePath
    return result
  }
}

export class ApiEpisodePageConfig {
  url: string = ''
  query: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()

  static fromJSON(json: Record<string, Object> | undefined): ApiEpisodePageConfig | undefined {
    if (json === undefined) return undefined
    const config = new ApiEpisodePageConfig()
    if (typeof json['url'] === 'string') config.url = json['url'] as string
    config.query = ApiRuleConfigUtils.asRecord(json['query'])
    return config
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()
    result['url'] = this.url
    result['query'] = this.query
    return result
  }
}

export class ApiChapterConfig {
  request: ApiRequestConfig = new ApiRequestConfig()
  format: string = ApiChapterFormat.NESTED
  roadsPath: string = '$.data.roads[*]'
  roadNamePath: string = '$.name'
  episodesPath: string = '$.episodes[*]'
  episodeNamePath: string = '$.name'
  episodeUrlPath: string = '$.url'
  roadNamesPath: string = ''
  roadEpisodesPath: string = ''
  roadSeparator: string = '$$$'
  episodeSeparator: string = '#'
  fieldSeparator: string = '$'
  variables: Record<string, string> = ApiRuleConfigUtils.emptyStringRecord()
  episodePage: ApiEpisodePageConfig | undefined = undefined

  static fromJSON(json: Record<string, Object> | undefined): ApiChapterConfig {
    const config = new ApiChapterConfig()
    if (json === undefined) return config
    config.request = ApiRequestConfig.fromJSON(ApiRuleConfigUtils.asRecord(json['request']))
    config.format = ApiChapterFormat.normalize(json['format'])
    if (typeof json['roadsPath'] === 'string') config.roadsPath = json['roadsPath'] as string
    if (typeof json['roadNamePath'] === 'string') config.roadNamePath = json['roadNamePath'] as string
    if (typeof json['episodesPath'] === 'string') config.episodesPath = json['episodesPath'] as string
    if (typeof json['episodeNamePath'] === 'string') config.episodeNamePath = json['episodeNamePath'] as string
    if (typeof json['episodeUrlPath'] === 'string') config.episodeUrlPath = json['episodeUrlPath'] as string
    if (typeof json['roadNamesPath'] === 'string') config.roadNamesPath = json['roadNamesPath'] as string
    if (typeof json['roadEpisodesPath'] === 'string') config.roadEpisodesPath = json['roadEpisodesPath'] as string
    if (typeof json['roadSeparator'] === 'string') config.roadSeparator = json['roadSeparator'] as string
    if (typeof json['episodeSeparator'] === 'string') config.episodeSeparator = json['episodeSeparator'] as string
    if (typeof json['fieldSeparator'] === 'string') config.fieldSeparator = json['fieldSeparator'] as string
    config.variables = ApiRuleConfigUtils.asStringRecord(json['variables'])
    config.episodePage = ApiEpisodePageConfig.fromJSON(ApiRuleConfigUtils.asOptionalRecord(json['episodePage']))
    return config
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = ApiRuleConfigUtils.emptyObjectRecord()
    result['request'] = this.request.toJSON()
    result['format'] = this.format
    if (this.format === ApiChapterFormat.NESTED) {
      result['roadsPath'] = this.roadsPath
      result['roadNamePath'] = this.roadNamePath
      result['episodesPath'] = this.episodesPath
      result['episodeNamePath'] = this.episodeNamePath
      result['episodeUrlPath'] = this.episodeUrlPath
    }
    if (this.format === ApiChapterFormat.DELIMITED || this.roadNamesPath.length > 0 ||
      this.roadEpisodesPath.length > 0) {
      result['roadNamesPath'] = this.roadNamesPath
      result['roadEpisodesPath'] = this.roadEpisodesPath
      result['roadSeparator'] = this.roadSeparator
      result['episodeSeparator'] = this.episodeSeparator
      result['fieldSeparator'] = this.fieldSeparator
    }
    if (Object.keys(this.variables).length > 0) result['variables'] = this.variables
    if (this.episodePage !== undefined) result['episodePage'] = this.episodePage.toJSON()
    return result
  }
}

export class ApiRuleConfigUtils {
  static emptyObjectRecord(): Record<string, Object> {
    const result: Record<string, Object> = {}
    return result
  }

  static emptyStringRecord(): Record<string, string> {
    const result: Record<string, string> = {}
    return result
  }

  static asRecord(value: Object | undefined): Record<string, Object> {
    if (value === undefined || value === null || Array.isArray(value) || typeof value !== 'object') {
      return ApiRuleConfigUtils.emptyObjectRecord()
    }
    return value as Record<string, Object>
  }

  static asOptionalRecord(value: Object | undefined): Record<string, Object> | undefined {
    if (value === undefined || value === null || Array.isArray(value) || typeof value !== 'object') {
      return undefined
    }
    return value as Record<string, Object>
  }

  static asStringRecord(value: Object | undefined): Record<string, string> {
    const result: Record<string, string> = ApiRuleConfigUtils.emptyStringRecord()
    const record = ApiRuleConfigUtils.asRecord(value)
    const keys = Object.keys(record)
    for (let i = 0; i < keys.length; i++) {
      const raw = record[keys[i]]
      if (raw !== undefined && raw !== null) {
        result[keys[i]] = String(raw)
      }
    }
    return result
  }
}
