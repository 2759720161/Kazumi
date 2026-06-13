import { Logger } from '../utils/Logger';

const logger = new Logger('CookieManager');

export class CookieManager {
  private cookies: Map<string, Map<string, string>> = new Map();
  private static instance: CookieManager | null = null;

  private constructor() {}

  static getInstance(): CookieManager {
    if (CookieManager.instance === null) {
      CookieManager.instance = new CookieManager();
    }
    return CookieManager.instance;
  }

  getCookiesForUrl(url: string): Map<string, string> {
    const domain = this.extractDomain(url);
    const stored = this.cookies.get(domain);
    if (stored !== undefined) {
      return stored;
    }
    return new Map<string, string>();
  }

  getCookieHeaderForUrl(url: string): string {
    const cookieMap = this.getCookiesForUrl(url);
    if (cookieMap.size === 0) {
      return '';
    }
    const parts: string[] = [];
    cookieMap.forEach((value: string, key: string) => {
      parts.push(`${key}=${value}`);
    });
    return parts.join('; ');
  }

  extractCookiesFromSetCookieHeader(url: string, setCookieValue: string): void {
    if (setCookieValue.length === 0) {
      return;
    }

    const domain = this.extractDomain(url);
    let domainCookies = this.cookies.get(domain);
    if (domainCookies === undefined) {
      domainCookies = new Map<string, string>();
      this.cookies.set(domain, domainCookies);
    }

    const parts = setCookieValue.split(';');
    if (parts.length > 0) {
      const nameValue = parts[0].trim();
      const eqIdx = nameValue.indexOf('=');
      if (eqIdx > 0) {
        const name = nameValue.substring(0, eqIdx).trim();
        const value = nameValue.substring(eqIdx + 1).trim();
        domainCookies.set(name, value);
        logger.debug('Cookie stored for %{public}s: %{public}s', domain, name);
      }
    }
  }

  extractCookiesFromCookieHeader(url: string, cookieValue: string): void {
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
        this.extractCookiesFromSetCookieHeader(url, item);
      }
    }
  }

  clearCookies(url: string): void {
    const domain = this.extractDomain(url);
    this.cookies.delete(domain);
  }

  clearAll(): void {
    this.cookies.clear();
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
