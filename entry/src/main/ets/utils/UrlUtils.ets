import { AppConstants } from '../constants/AppConstants';
import { Logger } from './Logger';

const logger = new Logger('UrlUtils');

export class UrlUtils {
  static replaceKeyword(template: string, keyword: string): string {
    return template.replace(AppConstants.SEARCH_KEYWORD_PLACEHOLDER, encodeURIComponent(keyword));
  }

  static replaceKeywordRaw(template: string, keyword: string): string {
    return template.replace(AppConstants.SEARCH_KEYWORD_PLACEHOLDER, keyword);
  }

  static encodeParams(params: Record<string, string>): string {
    const parts: string[] = [];
    const keys = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]));
    }
    return parts.join('&');
  }

  static buildUrl(baseUrl: string, params: Record<string, string>): string {
    const separator = baseUrl.includes('?') ? '&' : '?';
    return baseUrl + separator + UrlUtils.encodeParams(params);
  }

  static isValidUrl(url: string): boolean {
    try {
      const trimmed = url.trim();
      if (trimmed.length === 0) {
        return false;
      }
      return trimmed.startsWith('http://') || trimmed.startsWith('https://');
    } catch (err) {
      logger.error('URL validation failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  static isVideoUrl(url: string): boolean {
    const lower = url.toLowerCase();
    for (let i = 0; i < AppConstants.VIDEO_EXTENSIONS.length; i++) {
      if (lower.includes(AppConstants.VIDEO_EXTENSIONS[i])) {
        return true;
      }
    }
    return false;
  }

  static isM3u8Url(url: string): boolean {
    return url.toLowerCase().includes('.m3u8');
  }

  static isMp4Url(url: string): boolean {
    return url.toLowerCase().includes('.mp4');
  }

  static extractBaseUrl(url: string): string {
    try {
      const protoEnd = url.indexOf('://');
      if (protoEnd === -1) {
        return url;
      }
      const afterProto = url.substring(protoEnd + 3);
      const slashIdx = afterProto.indexOf('/');
      if (slashIdx === -1) {
        return url;
      }
      return url.substring(0, protoEnd + 3 + slashIdx);
    } catch (err) {
      return url;
    }
  }

  static resolveUrl(base: string, relative: string): string {
    if (UrlUtils.isValidUrl(relative)) {
      return relative;
    }
    if (relative.startsWith('//')) {
      const protoEnd = base.indexOf('://');
      if (protoEnd !== -1) {
        return base.substring(0, protoEnd + 1) + relative;
      }
    }
    if (relative.startsWith('/')) {
      return UrlUtils.extractBaseUrl(base) + relative;
    }
    const lastSlash = base.lastIndexOf('/');
    if (lastSlash !== -1) {
      return base.substring(0, lastSlash + 1) + relative;
    }
    return base + '/' + relative;
  }

  static isAdUrl(url: string): boolean {
    const lower = url.toLowerCase();
    for (let i = 0; i < AppConstants.AD_DOMAINS.length; i++) {
      if (lower.includes(AppConstants.AD_DOMAINS[i])) {
        return true;
      }
    }
    return false;
  }
}