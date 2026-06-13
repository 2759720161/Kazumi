import { AppConstants } from '../constants/AppConstants';

export class UrlBuilder {
  static buildSearchUrl(baseUrl: string, searchUrlTemplate: string, keyword: string): string {
    const replaced = searchUrlTemplate.replace(AppConstants.SEARCH_KEYWORD_PLACEHOLDER, keyword);
    if (replaced.startsWith('http://') || replaced.startsWith('https://')) {
      return replaced;
    }
    if (replaced.startsWith('/')) {
      return baseUrl + replaced;
    }
    return baseUrl + '/' + replaced;
  }

  static buildSearchUrlEncoded(baseUrl: string, searchUrlTemplate: string, keyword: string): string {
    const replaced = searchUrlTemplate.replace(AppConstants.SEARCH_KEYWORD_PLACEHOLDER, encodeURIComponent(keyword));
    if (replaced.startsWith('http://') || replaced.startsWith('https://')) {
      return replaced;
    }
    if (replaced.startsWith('/')) {
      return baseUrl + replaced;
    }
    return baseUrl + '/' + replaced;
  }

  static buildPostBody(searchUrlTemplate: string, keyword: string): string {
    const replaced = searchUrlTemplate.replace(AppConstants.SEARCH_KEYWORD_PLACEHOLDER, keyword);
    const questionIdx = replaced.indexOf('?');
    if (questionIdx !== -1 && questionIdx < replaced.length - 1) {
      return replaced.substring(questionIdx + 1);
    }
    return '';
  }
}