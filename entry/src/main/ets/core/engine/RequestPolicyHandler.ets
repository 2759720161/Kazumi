import { RuleSource } from '../../models/RuleSource';
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel';
import { HttpClient } from '../../network/HttpClient';
import { RequestConfig, RetryPolicy } from '../../network/RequestConfig';
import { CookieManager } from '../../network/CookieManager';
import { SecurityPolicy } from '../../network/SecurityPolicy';
import { Logger } from '../../utils/Logger';

const logger = new Logger('RequestPolicyHandler');

export class RequestPolicyHandler {
  private httpClient: HttpClient;
  private cookieManager: CookieManager;
  private securityPolicy: SecurityPolicy;

  constructor() {
    this.httpClient = new HttpClient();
    this.cookieManager = CookieManager.getInstance();
    this.securityPolicy = SecurityPolicy.getInstance();
  }

  async fetchWithRule(runtime: RuleRuntimeModel, keyword: string): Promise<string> {
    const url = runtime.buildSearchUrl(keyword);
    const headers = runtime.getSearchHeaders();

    if (!this.securityPolicy.checkUrl(url)) {
      throw new Error(`Request blocked by security policy: ${url}`);
    }

    let config: RequestConfig;
    if (runtime.isPost) {
      const body = UrlBuilder_extractPostBody(runtime.rule.searchURL, keyword);
      config = RequestConfig.createPost(url, body, headers);
    } else {
      config = RequestConfig.createGet(url, headers);
    }
    config.timeout = 10000;
    config.retryPolicy = new RetryPolicy(0, 500);

    const response = await this.httpClient.request(config);
    if (!response.isSuccessful) {
      if (this.isTimeoutResponse(response.statusCode, response.body)) {
        throw new Error('搜索超时，可重试');
      }
      if (response.statusCode === 403 || response.statusCode === 429) {
        logger.warn('Rule %{public}s blocked (HTTP %{public}d)', runtime.rule.name, response.statusCode);
        throw new Error(`Rule blocked: HTTP ${response.statusCode}`);
      }
      throw new Error(`HTTP ${response.statusCode}: ${response.body.substring(0, 200)}`);
    }

    return response.body;
  }

  async fetchUrl(url: string, headers?: Record<string, string>): Promise<string> {
    if (!this.securityPolicy.checkUrl(url)) {
      throw new Error(`Request blocked by security policy: ${url}`);
    }

    const config = RequestConfig.createGet(url, headers);
    const response = await this.httpClient.request(config);
    if (!response.isSuccessful) {
      if (this.isTimeoutResponse(response.statusCode, response.body)) {
        throw new Error('请求超时，可重试');
      }
      throw new Error(`HTTP ${response.statusCode}`);
    }
    return response.body;
  }

  async fetchUrlWithRuleHeaders(runtime: RuleRuntimeModel, url: string): Promise<string> {
    const headers = runtime.getSearchHeaders();

    if (!this.securityPolicy.checkUrl(url)) {
      throw new Error(`Request blocked by security policy: ${url}`);
    }

    const config = RequestConfig.createGet(url, headers);
    config.timeout = 30000;
    config.retryPolicy = new RetryPolicy(1, 1000);

    const response = await this.httpClient.request(config);
    if (!response.isSuccessful) {
      if (this.isTimeoutResponse(response.statusCode, response.body)) {
        throw new Error('获取剧集超时，可重试');
      }
      if (response.statusCode === 403 || response.statusCode === 429 || response.statusCode === 522) {
        logger.warn('Detail page blocked for rule %{public}s (HTTP %{public}d)', runtime.rule.name, response.statusCode);
        throw new Error(`Detail page blocked: HTTP ${response.statusCode}`);
      }
      throw new Error(`HTTP ${response.statusCode}: ${response.body.substring(0, 200)}`);
    }

    return response.body;
  }

  getHttpClient(): HttpClient {
    return this.httpClient;
  }

  private isTimeoutResponse(statusCode: number, body: string): boolean {
    if (statusCode !== 0) {
      return false;
    }
    const text = body.toLowerCase();
    return text.indexOf('timeout') !== -1 ||
      text.indexOf('timed out') !== -1 ||
      text.indexOf('curl_code=28') !== -1 ||
      text.indexOf('2300028') !== -1;
  }
}

function UrlBuilder_extractPostBody(searchUrlTemplate: string, keyword: string): string {
  const replaced = searchUrlTemplate.replace('@keyword', keyword);
  const questionIdx = replaced.indexOf('?');
  if (questionIdx !== -1 && questionIdx < replaced.length - 1) {
    return replaced.substring(questionIdx + 1);
  }
  return '';
}
