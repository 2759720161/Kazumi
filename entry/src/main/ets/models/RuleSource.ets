export class AntiCrawlerConfig {
  enabled: boolean = false;
  captchaType: number = 1;
  captchaImage: string = '';
  captchaInput: string = '';
  captchaButton: string = '';
  captchaDetectType: number = 1;
  captchaDetectValue: string = '';
  captchaScript: string = '';

  static fromJSON(json: Record<string, Object>): AntiCrawlerConfig {
    const config = new AntiCrawlerConfig();
    if (json['enabled'] !== undefined) {
      config.enabled = json['enabled'] as boolean;
    }
    if (json['captchaType'] !== undefined) {
      config.captchaType = json['captchaType'] as number;
    }
    if (json['captchaImage'] !== undefined) {
      config.captchaImage = json['captchaImage'] as string;
    }
    if (json['captchaInput'] !== undefined) {
      config.captchaInput = json['captchaInput'] as string;
    }
    if (json['captchaButton'] !== undefined) {
      config.captchaButton = json['captchaButton'] as string;
    }
    if (json['captchaDetectType'] !== undefined) {
      config.captchaDetectType = json['captchaDetectType'] as number;
    }
    if (json['captchaDetectValue'] !== undefined) {
      config.captchaDetectValue = json['captchaDetectValue'] as string;
    }
    if (json['captchaScript'] !== undefined) {
      config.captchaScript = json['captchaScript'] as string;
    }
    return config;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['enabled'] = this.enabled;
    result['captchaType'] = this.captchaType;
    result['captchaImage'] = this.captchaImage;
    result['captchaInput'] = this.captchaInput;
    result['captchaButton'] = this.captchaButton;
    result['captchaDetectType'] = this.captchaDetectType;
    result['captchaDetectValue'] = this.captchaDetectValue;
    result['captchaScript'] = this.captchaScript;
    return result;
  }
}

export class RuleSource {
  id: number = -1;
  api: string = '';
  type: string = '';
  name: string = '';
  version: string = '';
  multiSources: boolean = false;
  useWebview: boolean = false;
  useNativePlayer: boolean = false;
  usePost: boolean = false;
  useLegacyParser: boolean = false;
  adBlocker: boolean = false;
  userAgent: string = '';
  baseUrl: string = '';
  searchURL: string = '';
  searchList: string = '';
  searchName: string = '';
  searchResult: string = '';
  chapterRoads: string = '';
  chapterResult: string = '';
  referer: string = '';
  antiCrawlerConfig: AntiCrawlerConfig = new AntiCrawlerConfig();
  enabled: boolean = true;
  createdAt: number = 0;
  updatedAt: number = 0;

  static fromJSON(json: Record<string, Object>): RuleSource {
    const rule = new RuleSource();
    if (json['api'] !== undefined) rule.api = json['api'] as string;
    if (json['type'] !== undefined) rule.type = json['type'] as string;
    if (json['name'] !== undefined) rule.name = json['name'] as string;
    if (json['version'] !== undefined) rule.version = json['version'] as string;
    if (json['muliSources'] !== undefined) rule.multiSources = json['muliSources'] as boolean;
    if (json['multiSources'] !== undefined) rule.multiSources = json['multiSources'] as boolean;
    if (json['useWebview'] !== undefined) rule.useWebview = json['useWebview'] as boolean;
    if (json['useNativePlayer'] !== undefined) rule.useNativePlayer = json['useNativePlayer'] as boolean;
    if (json['usePost'] !== undefined) rule.usePost = json['usePost'] as boolean;
    if (json['useLegacyParser'] !== undefined) rule.useLegacyParser = json['useLegacyParser'] as boolean;
    if (json['adBlocker'] !== undefined) rule.adBlocker = json['adBlocker'] as boolean;
    if (json['userAgent'] !== undefined) rule.userAgent = json['userAgent'] as string;
    if (json['baseURL'] !== undefined) rule.baseUrl = json['baseURL'] as string;
    if (json['baseUrl'] !== undefined) rule.baseUrl = json['baseUrl'] as string;
    if (json['searchURL'] !== undefined) rule.searchURL = json['searchURL'] as string;
    if (json['searchList'] !== undefined) rule.searchList = json['searchList'] as string;
    if (json['searchName'] !== undefined) rule.searchName = json['searchName'] as string;
    if (json['searchResult'] !== undefined) rule.searchResult = json['searchResult'] as string;
    if (json['chapterRoads'] !== undefined) rule.chapterRoads = json['chapterRoads'] as string;
    if (json['chapterResult'] !== undefined) rule.chapterResult = json['chapterResult'] as string;
    if (json['referer'] !== undefined) rule.referer = json['referer'] as string;
    if (json['antiCrawlerConfig'] !== undefined) {
      rule.antiCrawlerConfig = AntiCrawlerConfig.fromJSON(json['antiCrawlerConfig'] as Record<string, Object>);
    }
    if (json['enabled'] !== undefined) rule.enabled = json['enabled'] as boolean;
    return rule;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['api'] = this.api;
    result['type'] = this.type;
    result['name'] = this.name;
    result['version'] = this.version;
    result['muliSources'] = this.multiSources;
    result['useWebview'] = this.useWebview;
    result['useNativePlayer'] = this.useNativePlayer;
    result['usePost'] = this.usePost;
    result['useLegacyParser'] = this.useLegacyParser;
    result['adBlocker'] = this.adBlocker;
    result['userAgent'] = this.userAgent;
    result['baseURL'] = this.baseUrl;
    result['searchURL'] = this.searchURL;
    result['searchList'] = this.searchList;
    result['searchName'] = this.searchName;
    result['searchResult'] = this.searchResult;
    result['chapterRoads'] = this.chapterRoads;
    result['chapterResult'] = this.chapterResult;
    result['referer'] = this.referer;
    result['antiCrawlerConfig'] = this.antiCrawlerConfig.toJSON();
    return result;
  }
}