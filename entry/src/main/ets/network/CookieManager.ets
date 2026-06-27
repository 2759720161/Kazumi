import { webview } from '@kit.ArkWeb';
import { Logger } from '../utils/Logger';

const logger = new Logger('CookieManager');

export class CookieManager {
  private cookies: Map<string, Map<string, string>> = new Map();
  private scopedCookies: Map<string, Map<string, Map<string, string>>> = new Map();
  private static instance: CookieManager | null = null;

  private constructor() {}

  static getInstance(): CookieManager {
    if (CookieManager.instance === null) {
      CookieManager.instance = new CookieManager();
    }
    return CookieManager.instance;
  }

  private scopeKey(ruleSourceId: number): string {
    return ruleSourceId >= 0 ? 'r' + String(ruleSourceId) : ''
  }

  getCookiesForUrl(url: string, ruleSourceId: number = -1): Map<string, string> {
    const domain = this.extractDomain(url);
    const sk = this.scopeKey(ruleSourceId)
    if (sk.length > 0) {
      const scopeMap = this.scopedCookies.get(sk)
      if (scopeMap !== undefined) {
        const stored = scopeMap.get(domain)
        if (stored !== undefined) {
          return stored
        }
      }
    }
    const stored = this.cookies.get(domain);
    if (stored !== undefined) {
      return stored;
    }
    return new Map<string, string>();
  }

  getCookieHeaderForUrl(url: string, ruleSourceId: number = -1): string {
    this.syncFromWebView(url);
    const cookieMap = this.getCookiesForUrl(url, ruleSourceId);
    if (cookieMap.size === 0) {
      return '';
    }
    const parts: string[] = [];
    cookieMap.forEach((value: string, key: string) => {
      parts.push(`${key}=${value}`);
    });
    return parts.join('; ');
  }

  extractCookiesFromSetCookieHeader(url: string, setCookieValue: string, ruleSourceId: number = -1): void {
    if (setCookieValue.length === 0) {
      return;
    }

    const domain = this.extractDomain(url);
    const sk = this.scopeKey(ruleSourceId)

    let targetMap: Map<string, Map<string, string>>
    if (sk.length > 0) {
      let scopeMap = this.scopedCookies.get(sk)
      if (scopeMap === undefined) {
        scopeMap = new Map<string, Map<string, string>>()
        this.scopedCookies.set(sk, scopeMap)
      }
      targetMap = scopeMap
    } else {
      targetMap = this.cookies
    }

    let domainCookies = targetMap.get(domain);
    if (domainCookies === undefined) {
      domainCookies = new Map<string, string>();
      targetMap.set(domain, domainCookies);
    }

    const parts = setCookieValue.split(';');
    if (parts.length > 0) {
      const nameValue = parts[0].trim();
      const eqIdx = nameValue.indexOf('=');
      if (eqIdx > 0) {
        const name = nameValue.substring(0, eqIdx).trim();
        const value = nameValue.substring(eqIdx + 1).trim();
        domainCookies.set(name, value);
        logger.debug('Cookie stored for %{public}s (scope=%{public}s): %{public}s', domain, sk.length > 0 ? sk : 'global', name);
      }
    }
  }

  extractCookiesFromCookieHeader(url: string, cookieValue: string, ruleSourceId: number = -1): void {
    if (cookieValue.length === 0) {
      return;
    }

    let normalized = cookieValue.trim();
    if (normalized.startsWith('"') && normalized.endsWith('"') && normalized.length >= 2) {
      normalized = normalized.substring(1, normalized.length - 1);
    }

    const parts = normalized.split(';');
    for (let i = 0; i < parts.length; i++) {
      const item = parts[i].trim();
      if (item.length > 0) {
        this.extractCookiesFromSetCookieHeader(url, item, ruleSourceId);
      }
    }
  }

  clearCookies(url: string, ruleSourceId: number = -1): void {
    const domain = this.extractDomain(url);
    const sk = this.scopeKey(ruleSourceId)
    if (sk.length > 0) {
      const scopeMap = this.scopedCookies.get(sk)
      if (scopeMap !== undefined) {
        scopeMap.delete(domain)
      }
    } else {
      this.cookies.delete(domain);
    }
  }

  clearAll(): void {
    this.cookies.clear();
    this.scopedCookies.clear();
  }

  syncFromWebView(url: string): void {
    try {
      const cookieValue = webview.WebCookieManager.fetchCookieSync(url, false);
      if (cookieValue.length > 0) {
        this.extractCookiesFromCookieHeader(url, cookieValue);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (message.indexOf('17100002') === -1) {
        logger.debug('WebView cookie sync skipped for %{public}s: %{public}s', this.extractDomain(url), message);
      }
    }
  }

  private extractDomain(url: string): string {
    try {
      const protoEnd = url.indexOf('://');
      if (protoEnd === -1) {
        return url;
      }
      const afterProto = url.substring(protoEnd + 3);
      const slashIdx = afterProto.indexOf('/');
      if (slashIdx === -1) {
        return afterProto;
      }
      return afterProto.substring(0, slashIdx);
    } catch (err) {
      return url;
    }
  }
}
