import { RuleSource } from '../models/RuleSource';
import { UrlUtils } from '../utils/UrlUtils';

export class RuleRuntimeModel {
  rule: RuleSource;
  fullSearchUrl: string = '';

  constructor(rule: RuleSource) {
    this.rule = rule;
  }

  buildSearchUrl(keyword: string): string {
    const template = this.rule.searchURL;
    if (template.length === 0) {
      return '';
    }
    const replaced = UrlUtils.replaceKeyword(template, keyword);
    if (replaced.startsWith('http://') || replaced.startsWith('https://')) {
      this.fullSearchUrl = replaced;
    } else if (replaced.startsWith('/')) {
      this.fullSearchUrl = this.rule.baseUrl + replaced;
    } else {
      this.fullSearchUrl = this.rule.baseUrl + '/' + replaced;
    }
    return this.fullSearchUrl;
  }

  buildFullUrl(relativeUrl: string): string {
    return UrlUtils.resolveUrl(this.rule.baseUrl, relativeUrl);
  }

  getSearchHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    if (this.rule.userAgent.length > 0) {
      headers['User-Agent'] = this.rule.userAgent;
    } else {
      headers['User-Agent'] = 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    }
    if (this.rule.referer.length > 0) {
      headers['Referer'] = this.rule.referer;
    } else if (this.rule.baseUrl.length > 0) {
      headers['Referer'] = this.rule.baseUrl + '/';
    }
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    headers['Connection'] = 'keep-alive';
    return headers;
  }

  get hasAntiCrawler(): boolean {
    return this.rule.antiCrawlerConfig.enabled;
  }

  get needsWebView(): boolean {
    return this.rule.useWebview;
  }

  get isPost(): boolean {
    return this.rule.usePost;
  }
}