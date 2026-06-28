import { http } from '@kit.NetworkKit';
import { AnimeItem } from '../../models/AnimeItem';
import { SeasonRange } from '../../models/SeasonRange';
import { BangumiConfig } from './BangumiConfig';
import { Logger, extractErrorMsg } from '../../utils/Logger';

const logger: Logger = new Logger('BangumiApi');

const BANGUMI_API_DOMAINS: string[] = BangumiConfig.BANGUMI_API_BASES;
const BANGUMI_NEXT_DOMAINS: string[] = BangumiConfig.BANGUMI_NEXT_BASES;
const BANGUMI_SEARCH_PATH = '/v0/search/subjects?limit=5&offset=0';
const BANGUMI_METADATA_SEARCH_PATH = '/v0/search/subjects?limit=20&offset=0';
const BANGUMI_WEB_SEARCH_URLS: string[] = BangumiConfig.BANGUMI_WEB_SEARCH_URLS;

const MIRROR_CACHE_READ_TIMEOUT_MS: number = 8000;
const MIRROR_CACHE_CONNECT_TIMEOUT_MS: number = 5000;
const API_PROBE_READ_TIMEOUT_MS: number = 3500;
const API_PROBE_CONNECT_TIMEOUT_MS: number = 3000;
const API_SEARCH_READ_TIMEOUT_MS: number = 6000;
const API_SEARCH_CONNECT_TIMEOUT_MS: number = 5000;
const WEB_SEARCH_READ_TIMEOUT_MS: number = 3500;
const WEB_SEARCH_CONNECT_TIMEOUT_MS: number = 3000;

let isSearching: boolean = false;
let apiDomainIndex: number = -1;
let apiProbeCompleted: boolean = false;
let webSearchAvailable: boolean = true;
let webSearchFailedAt: number = 0;

const WEB_FAILURE_COOLDOWN_MS: number = 10 * 60 * 1000;

export class BangumiApi {
  static async searchAnime(keyword: string): Promise<AnimeItem[]> {
    if (keyword.trim().length === 0) {
      return [];
    }

    while (isSearching) {
      await BangumiApi.sleep(500);
    }
    isSearching = true;

    try {
      const body = BangumiApi.buildSearchBody(keyword, 'heat');
      if (apiDomainIndex >= 0 && apiDomainIndex < BANGUMI_API_DOMAINS.length) {
        const cachedDomain = BANGUMI_API_DOMAINS[apiDomainIndex];
        const cachedResults = await BangumiApi.tryAnimeSearch(
          cachedDomain + BANGUMI_METADATA_SEARCH_PATH, body, keyword);
        if (cachedResults.length > 0) {
          return cachedResults;
        }
      }

      for (let i = 0; i < BANGUMI_API_DOMAINS.length; i++) {
        if (i === apiDomainIndex) {
          continue;
        }
        const domain = BANGUMI_API_DOMAINS[i];
        const searchUrl = domain + BANGUMI_METADATA_SEARCH_PATH;
        logger.info('Bangumi metadata search via %{public}s for: %{public}s', domain, keyword);
        const results = await BangumiApi.tryAnimeSearch(searchUrl, body, keyword);
        if (results.length > 0) {
          apiDomainIndex = i;
          apiProbeCompleted = true;
          return results;
        }
      }

      apiProbeCompleted = true;
      logger.warn('Bangumi metadata search returned no results from all domains for %{public}s', keyword);
      return [];
    } finally {
      isSearching = false;
    }
  }

  static async searchCover(keyword: string): Promise<string> {
    if (keyword.trim().length === 0) {
      return '';
    }

    while (isSearching) {
      await BangumiApi.sleep(500);
    }
    isSearching = true;

    try {
      const body = BangumiApi.buildSearchBody(keyword, 'heat');

      if (apiDomainIndex === -1 && !apiProbeCompleted) {
        apiDomainIndex = await BangumiApi.probeApiDomain();
      }

      if (apiDomainIndex >= 0 && apiDomainIndex < BANGUMI_API_DOMAINS.length) {
        const domain = BANGUMI_API_DOMAINS[apiDomainIndex];
        const searchUrl = domain + BANGUMI_SEARCH_PATH;
        logger.info('Bangumi API search via %{public}s for: %{public}s', domain, keyword);
        const cover = await BangumiApi.tryApiSearch(searchUrl, body, keyword);
        if (cover.length > 0) {
          return cover;
        }
      }

      if (!BangumiApi.canTryWebSearch()) {
        logger.info('Bangumi web unavailable, skip cover search for: %{public}s', keyword);
        return '';
      }

      logger.info('Bangumi API unavailable, trying web search for: %{public}s', keyword);
      const webCover = await BangumiApi.tryWebSearch(keyword);
      return webCover;
    } finally {
      isSearching = false;
    }
  }

  private static async probeApiDomain(): Promise<number> {
    for (let i = 0; i < BANGUMI_API_DOMAINS.length; i++) {
      const domain = BANGUMI_API_DOMAINS[i];
      const probeUrl = domain + '/v0/subjects/1';
      const request = http.createHttp();
      try {
        logger.info('Probing %{public}s...', domain);
        const response = await request.request(probeUrl, {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0'
          },
          readTimeout: API_PROBE_READ_TIMEOUT_MS,
          connectTimeout: API_PROBE_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING
        });
        const code = response.responseCode as number;
        logger.info('Probe %{public}s -> HTTP %{public}d', domain, code);
        if (code >= 200 && code < 400) {
          request.destroy();
          return i;
        }
      } catch (err) {
        const msg = extractErrorMsg(err as Object);
        logger.warn('Probe %{public}s failed: %{public}s', domain, msg);
      } finally {
        request.destroy();
      }
    }
    logger.warn('All Bangumi API domains unreachable');
    apiProbeCompleted = true;
    return -1;
  }

  private static async tryApiSearch(searchUrl: string, body: string, keyword: string): Promise<string> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
        },
        readTimeout: API_SEARCH_READ_TIMEOUT_MS,
        connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      };

      const response = await request.request(searchUrl, options);
      const statusCode = response.responseCode as number;
      logger.info('Bangumi API response: HTTP %{public}d', statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return '';
      }

      const bodyStr = response.result as string;
      if (bodyStr.length === 0) {
        return '';
      }

      return BangumiApi.extractCoverFromApi(bodyStr, keyword);
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Bangumi API error: %{public}s', msg);
      return '';
    } finally {
      request.destroy();
    }
  }

  private static async tryAnimeSearch(searchUrl: string, body: string, keyword: string): Promise<AnimeItem[]> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
        },
        readTimeout: API_SEARCH_READ_TIMEOUT_MS,
        connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      };

      const response = await request.request(searchUrl, options);
      const statusCode = response.responseCode as number;
      logger.info('Bangumi metadata response: HTTP %{public}d', statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return [];
      }

      const bodyStr = response.result as string;
      if (bodyStr.length === 0) {
        return [];
      }

      return BangumiApi.extractAnimeItemsFromApi(bodyStr, keyword);
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Bangumi metadata search error: %{public}s', msg);
      return [];
    } finally {
      request.destroy();
    }
  }

  private static buildSearchBody(keyword: string, sort: string): string {
    const bodyObj: Record<string, Object> = {};
    bodyObj['keyword'] = keyword;
    bodyObj['sort'] = sort;
    const filterObj: Record<string, Object> = {};
    filterObj['type'] = [2] as Object;
    filterObj['rank'] = ['>=0', '<=99999'] as Object;
    filterObj['nsfw'] = false as Object;
    bodyObj['filter'] = filterObj as Object;
    return JSON.stringify(bodyObj);
  }

  private static async tryWebSearch(keyword: string): Promise<string> {
    for (let i = 0; i < BANGUMI_WEB_SEARCH_URLS.length; i++) {
      const cover = await BangumiApi.tryWebSearchUrl(BANGUMI_WEB_SEARCH_URLS[i], keyword);
      if (cover.length > 0) {
        return cover;
      }
    }
    BangumiApi.markWebUnavailable();
    return '';
  }

  private static async tryWebSearchUrl(baseUrl: string, keyword: string): Promise<string> {
    const request = http.createHttp();
    try {
      const encoded = encodeURIComponent(keyword);
      const url = baseUrl + encoded + '?cat=2';
      logger.info('Bangumi web search: %{public}s', url.substring(0, 60));

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'text/html',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36'
        },
        readTimeout: WEB_SEARCH_READ_TIMEOUT_MS,
        connectTimeout: WEB_SEARCH_CONNECT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      };

      const response = await request.request(url, options);
      const statusCode = response.responseCode as number;
      logger.info('Bangumi web response: HTTP %{public}d', statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return '';
      }

      const html = response.result as string;
      if (html.length === 0) {
        logger.info('Bangumi web empty response for %{public}s', keyword);
        return '';
      }

      logger.info('Bangumi web html length=%{public}d for %{public}s', html.length, keyword);
      return BangumiApi.extractCoverFromHtml(html, keyword);
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Bangumi web search error: %{public}s', msg);
      return '';
    } finally {
      request.destroy();
    }
  }

  private static extractCoverFromApi(bodyStr: string, keyword: string): string {
    try {
      const json = JSON.parse(bodyStr) as Record<string, Object>;
      const dataList = json['data'] as Object[];
      if (dataList === null || dataList === undefined || dataList.length === 0) {
        return '';
      }

      logger.info('Bangumi API got %{public}d results for: %{public}s', dataList.length, keyword);

      for (let i = 0; i < dataList.length; i++) {
        const item = dataList[i] as Record<string, Object>;
        const nameCn = (item['name_cn'] as string) ?? '';
        const name = (item['name'] as string) ?? '';
        if (nameCn.length === 0 && name.length === 0) {
          continue;
        }

        const imagesObj = item['images'] as Record<string, Object>;
        if (imagesObj === null || imagesObj === undefined) {
          continue;
        }

        const large = (imagesObj['large'] as string) ?? '';
        const common = (imagesObj['common'] as string) ?? '';
        const medium = (imagesObj['medium'] as string) ?? '';

        const cover = large.length > 0 ? large :
          common.length > 0 ? common :
          medium.length > 0 ? medium : '';

        if (cover.length > 0) {
          logger.info('Bangumi cover for %{public}s: %{public}s',
            keyword, cover.length > 60 ? cover.substring(0, 60) : cover);
          return cover;
        }
      }
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Bangumi API parse error: %{public}s', msg);
    }
    return '';
  }

  private static extractAnimeItemsFromApi(bodyStr: string, keyword: string): AnimeItem[] {
    const items: AnimeItem[] = [];
    try {
      const json = JSON.parse(bodyStr) as Record<string, Object>;
      const dataList = json['data'] as Object[];
      if (dataList === null || dataList === undefined || dataList.length === 0) {
        return items;
      }

      logger.info('Bangumi metadata got %{public}d results for: %{public}s', dataList.length, keyword);
      for (let i = 0; i < dataList.length; i++) {
        const subject = dataList[i] as Record<string, Object>;
        const item = BangumiApi.parseAnimeItemFromApi(subject);
        if (item.name.length > 0) {
          items.push(item);
        }
      }
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Bangumi metadata parse error: %{public}s', msg);
    }
    return items;
  }


  private static extractCoverFromHtml(html: string, keyword: string): string {
    const covers = BangumiApi.extractImageCandidates(html);
    for (let i = 0; i < covers.length; i++) {
      const cover = BangumiApi.normalizeCoverUrl(covers[i]);
      if (cover.length === 0) {
        continue;
      }
      logger.info('Bangumi web cover for %{public}s: %{public}s',
        keyword, cover.length > 60 ? cover.substring(0, 60) : cover);
      return cover;
    }

    logger.info('Bangumi web: no cover found for %{public}s', keyword);
    return '';
  }

  private static extractImageCandidates(html: string): string[] {
    const candidates: string[] = [];
    let pos = 0;
    while (pos < html.length) {
      const imgStart = html.indexOf('<img', pos);
      if (imgStart === -1) {
        break;
      }
      const imgEnd = html.indexOf('>', imgStart);
      if (imgEnd === -1) {
        break;
      }
      const tag = html.substring(imgStart, imgEnd + 1);
      pos = imgEnd + 1;
      if (!tag.includes('cover') && !tag.includes('thumb') && !tag.includes('pic/cover')) {
        continue;
      }
      const src = BangumiApi.extractAttr(tag, 'src');
      if (src.length > 0) {
        candidates.push(src);
      }
      const dataSrc = BangumiApi.extractAttr(tag, 'data-src');
      if (dataSrc.length > 0) {
        candidates.push(dataSrc);
      }
    }

    BangumiApi.collectCoverUrls(html, '//lain.bgm.tv/pic/cover/', candidates);
    BangumiApi.collectCoverUrls(html, 'https://lain.bgm.tv/pic/cover/', candidates);
    BangumiApi.collectCoverUrls(html, '//bgmimg.anibt.net/pic/cover/', candidates);
    BangumiApi.collectCoverUrls(html, 'https://bgmimg.anibt.net/pic/cover/', candidates);
    return candidates;
  }

  private static extractAttr(tag: string, attr: string): string {
    const marker = attr + '=';
    let pos = tag.indexOf(marker);
    if (pos === -1) {
      return '';
    }
    pos += marker.length;
    if (pos >= tag.length) {
      return '';
    }
    const quote = tag.charAt(pos);
    if (quote !== '"' && quote !== "'") {
      return '';
    }
    const valueStart = pos + 1;
    const valueEnd = tag.indexOf(quote, valueStart);
    if (valueEnd === -1 || valueEnd <= valueStart) {
      return '';
    }
    return tag.substring(valueStart, valueEnd);
  }

  private static collectCoverUrls(html: string, marker: string, candidates: string[]): void {
    let pos = 0;
    while (pos < html.length) {
      const idx = html.indexOf(marker, pos);
      if (idx === -1) {
        break;
      }
      const quote1 = html.indexOf('"', idx);
      const quote2 = html.indexOf("'", idx);
      let end = -1;
      if (quote1 !== -1 && quote2 !== -1) {
        end = quote1 < quote2 ? quote1 : quote2;
      } else {
        end = quote1 !== -1 ? quote1 : quote2;
      }
      if (end !== -1 && end > idx) {
        candidates.push(html.substring(idx, end));
      }
      pos = idx + marker.length;
    }
  }

  private static normalizeCoverUrl(raw: string): string {
    const normalized = BangumiConfig.normalizeImageUrl(raw);
    if (normalized.length === 0) {
      return '';
    }
    if (!normalized.includes('pic/cover') && !normalized.includes('.jpg') &&
        !normalized.includes('.png') && !normalized.includes('.webp')) {
      return '';
    }
    return normalized;
  }

  static resetProbe(): void {
    apiDomainIndex = -1;
    apiProbeCompleted = false;
    webSearchAvailable = true;
    webSearchFailedAt = 0;
  }

  private static canTryWebSearch(): boolean {
    if (webSearchAvailable) {
      return true;
    }
    const now = Date.now();
    if (now - webSearchFailedAt >= WEB_FAILURE_COOLDOWN_MS) {
      webSearchAvailable = true;
      webSearchFailedAt = 0;
      return true;
    }
    return false;
  }

  private static markWebUnavailable(): void {
    webSearchAvailable = false;
    webSearchFailedAt = Date.now();
  }

  static async getTrendsList(offset: number): Promise<AnimeItem[]> {
    const mirrorItems = await BangumiApi.fetchMirrorPopular('', offset);
    if (mirrorItems.length > 0) {
      return mirrorItems;
    }

    const items: AnimeItem[] = [];
    const domains: string[] = [
      'https://bgmapi.anibt.net',
      'https://next.bgm.tv'
    ];

    for (let d = 0; d < domains.length; d++) {
      const domain = domains[d];
      const url = `${domain}/p1/trending/subjects?type=2&limit=24&offset=${offset}`;
      const request = http.createHttp();
      try {
        logger.info('Trends request: %{public}s offset=%{public}d', domain, offset);
        const response = await request.request(url, {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING
        });

        const statusCode = response.responseCode as number;
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy();
          continue;
        }

        const bodyStr = response.result as string;
        if (bodyStr.length === 0) {
          request.destroy();
          continue;
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>;
        const dataList = json['data'] as Object[];
        if (dataList === null || dataList === undefined || dataList.length === 0) {
          request.destroy();
          continue;
        }

        for (let i = 0; i < dataList.length; i++) {
          const entry = dataList[i] as Record<string, Object>;
          const subject = entry['subject'] as Record<string, Object>;
          if (subject !== null && subject !== undefined) {
            const item = BangumiApi.parseAnimeItemFromApi(subject);
            if (item.name.length > 0) {
              items.push(item);
            }
          }
        }

        logger.info('Trends loaded %{public}d items from %{public}s', items.length, domain);
        request.destroy();
        return items;
      } catch (err) {
        const msg = extractErrorMsg(err as Object);
        logger.warn('Trends from %{public}s failed: %{public}s', domain, msg);
        request.destroy();
      }
    }

    if (items.length === 0) {
      logger.info('Trends API all failed, fallback to rank search');
      return await BangumiApi.getBangumiListByTag('', offset);
    }
    return items;
  }

  static async getBangumiListByTag(tag: string, offset: number): Promise<AnimeItem[]> {
    const mirrorItems = await BangumiApi.fetchMirrorPopular(tag, offset);
    if (mirrorItems.length > 0) {
      return mirrorItems;
    }

    return await BangumiApi.searchByTagFallback(tag, offset);
  }

  private static async fetchMirrorPopular(tag: string, offset: number): Promise<AnimeItem[]> {
    const items: AnimeItem[] = [];
    let url = `${BangumiConfig.KAZUMI_POPULAR_URL}?limit=24&offset=${offset}`;
    if (tag.length > 0) {
      url = url + '&tag=' + encodeURIComponent(tag);
    }

    const request = http.createHttp();
    try {
      logger.info('Mirror popular: tag=%{public}s offset=%{public}d', tag, offset);
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
        },
        readTimeout: MIRROR_CACHE_READ_TIMEOUT_MS,
        connectTimeout: MIRROR_CACHE_CONNECT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });

      const statusCode = response.responseCode as number;
      if (statusCode < 200 || statusCode >= 300) {
        logger.warn('Mirror popular HTTP %{public}d', statusCode);
        request.destroy();
        return items;
      }

      const bodyStr = response.result as string;
      if (bodyStr.length === 0) {
        request.destroy();
        return items;
      }

      const json = JSON.parse(bodyStr) as Record<string, Object>;
      const dataList = json['data'] as Object[];
      if (dataList !== null && dataList !== undefined && dataList.length > 0) {
        for (let i = 0; i < dataList.length; i++) {
          const subject = dataList[i] as Record<string, Object>;
          const item = BangumiApi.parseAnimeItemFromApi(subject);
          if (item.name.length > 0) {
            items.push(item);
          }
        }
      }

      logger.info('Mirror popular returned %{public}d items', items.length);
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Mirror popular failed: %{public}s', msg);
    } finally {
      request.destroy();
    }
    return items;
  }

  private static async searchByTagFallback(tag: string, offset: number): Promise<AnimeItem[]> {
    const items: AnimeItem[] = [];
    const bodyObj: Record<string, Object> = {};
    bodyObj['keyword'] = '';
    bodyObj['sort'] = 'rank';
    const filterObj: Record<string, Object> = {};
    filterObj['type'] = [2] as Object;
    if (tag.length > 0) {
      filterObj['tag'] = [tag] as Object;
    }
    filterObj['rank'] = ['>0', '<=99999'] as Object;
    filterObj['nsfw'] = false as Object;
    bodyObj['filter'] = filterObj as Object;
    const body = JSON.stringify(bodyObj);
    const path = '/v0/search/subjects?limit=24&offset=' + String(offset);

    for (let d = 0; d < BANGUMI_API_DOMAINS.length; d++) {
      const domain = BANGUMI_API_DOMAINS[d];
      const searchUrl = domain + path;
      const request = http.createHttp();
      try {
        logger.info('Tag search: tag=%{public}s offset=%{public}d via %{public}s', tag, offset, domain);
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        };

        const response = await request.request(searchUrl, options);
        const statusCode = response.responseCode as number;
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy();
          continue;
        }

        const bodyStr = response.result as string;
        if (bodyStr.length === 0) {
          request.destroy();
          continue;
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>;
        const dataList = json['data'] as Object[];
        if (dataList === null || dataList === undefined || dataList.length === 0) {
          request.destroy();
          continue;
        }

        for (let i = 0; i < dataList.length; i++) {
          const subject = dataList[i] as Record<string, Object>;
          const item = BangumiApi.parseAnimeItemFromApi(subject);
          if (item.name.length > 0) {
            items.push(item);
          }
        }

        logger.info('Tag search returned %{public}d items from %{public}s', items.length, domain);
        request.destroy();
        return items;
      } catch (err) {
        const msg = extractErrorMsg(err as Object);
        logger.warn('Tag search from %{public}s error: %{public}s', domain, msg);
        request.destroy();
      }
    }

    return items;
  }

  static async getSubject(bangumiId: number): Promise<AnimeItem | null> {
    const p1Path = `/p1/subjects/${bangumiId}`;
    const detailDomains: string[] = BangumiConfig.BANGUMI_SUBJECT_DETAIL_BASES;

    for (let d = 0; d < detailDomains.length; d++) {
      const domain = detailDomains[d];
      const url = domain + p1Path;
      const request = http.createHttp();
      try {
        logger.info('Get subject %{public}d /p1 from %{public}s', bangumiId, domain);
        const response = await request.request(url, {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING
        });

        const statusCode = response.responseCode as number;
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy();
          continue;
        }

        const bodyStr = response.result as string;
        if (bodyStr.length === 0) {
          request.destroy();
          continue;
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>;
        const item = BangumiApi.parseAnimeItemFromApi(json);
        logger.info('Subject %{public}d loaded from %{public}s: %{public}s eps=%{public}d airDate=%{public}s',
          bangumiId, domain, item.name, item.eps, item.airDate);
        request.destroy();
        if (item.eps <= 0 || item.airDate.length === 0) {
          const v0Item = await BangumiApi.fetchSubjectV0(bangumiId);
          if (v0Item !== null) {
            BangumiApi.mergeSubjectDetail(item, v0Item);
          }
        }
        return item;
      } catch (err) {
        const msg = extractErrorMsg(err as Object);
        logger.warn('Get subject /p1 from %{public}s failed: %{public}s', domain, msg);
        request.destroy();
      }
    }

    const fallback = await BangumiApi.fetchSubjectV0(bangumiId);
    if (fallback !== null) {
      return fallback;
    }

    logger.warn('All domains failed for subject %{public}d', bangumiId);
    return null;
  }

  private static async fetchSubjectV0(bangumiId: number): Promise<AnimeItem | null> {
    const v0Path = `/v0/subjects/${bangumiId}`;
    for (let d = 0; d < BANGUMI_API_DOMAINS.length; d++) {
      const domain = BANGUMI_API_DOMAINS[d];
      const url = domain + v0Path;
      const request = http.createHttp();
      try {
        logger.info('Get subject %{public}d /v0 from %{public}s', bangumiId, domain);
        const response = await request.request(url, {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING
        });

        const statusCode = response.responseCode as number;
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy();
          continue;
        }

        const bodyStr = response.result as string;
        if (bodyStr.length === 0) {
          request.destroy();
          continue;
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>;
        const item = BangumiApi.parseAnimeItemFromApi(json);
        logger.info('Subject %{public}d loaded from %{public}s: %{public}s eps=%{public}d airDate=%{public}s',
          bangumiId, domain, item.name, item.eps, item.airDate);
        request.destroy();
        return item;
      } catch (err) {
        const msg = extractErrorMsg(err as Object);
        logger.warn('Get subject /v0 from %{public}s failed: %{public}s', domain, msg);
        request.destroy();
      }
    }
    return null;
  }

  private static mergeSubjectDetail(target: AnimeItem, fallback: AnimeItem): void {
    if (target.name.length === 0) target.name = fallback.name;
    if (target.originalName.length === 0) target.originalName = fallback.originalName;
    if (target.desc.length === 0) target.desc = fallback.desc;
    if (target.airDate.length === 0) target.airDate = fallback.airDate;
    if (target.airWeekday <= 0) target.airWeekday = fallback.airWeekday;
    if (target.eps <= 0) target.eps = fallback.eps;
    if (target.ratingScore <= 0) target.ratingScore = fallback.ratingScore;
    if (target.rank <= 0) target.rank = fallback.rank;
    if (target.votes <= 0) target.votes = fallback.votes;
    if (target.votesCount.length === 0) target.votesCount = fallback.votesCount;
    if (target.tags.length === 0) target.tags = fallback.tags;
    if (target.aliases.length === 0) target.aliases = fallback.aliases;
    if (target.cover.length === 0) target.cover = fallback.cover;
    if (target.bangumiCover.length === 0) target.bangumiCover = fallback.bangumiCover;
    if (target.coverLarge.length === 0) target.coverLarge = fallback.coverLarge;
    if (target.coverCommon.length === 0) target.coverCommon = fallback.coverCommon;
    if (target.coverMedium.length === 0) target.coverMedium = fallback.coverMedium;
  }

  static async fetchCalendarBySeason(start: string, end: string): Promise<AnimeItem[][]> {
    const result: AnimeItem[][] = []
    for (let i = 0; i < 7; i++) {
      result.push([])
    }

    const url = `${BangumiConfig.KAZUMI_CALENDAR_URL}?start=${start}&end=${end}`
    const request = http.createHttp()
    try {
      logger.info('Mirror calendar season: %{public}s to %{public}s', start, end)
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
        },
        readTimeout: MIRROR_CACHE_READ_TIMEOUT_MS,
        connectTimeout: MIRROR_CACHE_CONNECT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      })

      const statusCode = response.responseCode as number
      if (statusCode < 200 || statusCode >= 300) {
        logger.warn('fetchCalendarBySeason HTTP %{public}d', statusCode)
        request.destroy()
        return result
      }

      const bodyStr = response.result as string
      if (bodyStr.length === 0) {
        request.destroy()
        return result
      }

      const json = JSON.parse(bodyStr) as Record<string, Object>
      BangumiApi.fillCalendarFromJson(json, result)
      const totalDays = result.filter((arr: AnimeItem[]) => arr.length > 0).length
      if (totalDays === 0) {
        request.destroy()
        return result
      }
      const totalItems = result.reduce((sum: number, arr: AnimeItem[]) => sum + arr.length, 0)
      logger.info('fetchCalendarBySeason loaded: %{public}d items across %{public}d days', totalItems, totalDays)
      request.destroy()
      return result
    } catch (err) {
      const msg = extractErrorMsg(err as Object)
      logger.warn('fetchCalendarBySeason failed: %{public}s', msg)
      request.destroy()
      return result
    }
  }

  static async searchByAirDateRange(start: string, end: string): Promise<AnimeItem[][]> {
    const result: AnimeItem[][] = []
    for (let i = 0; i < 7; i++) {
      result.push([])
    }

    const bodyObj: Record<string, Object> = {}
    bodyObj['keyword'] = ''
    bodyObj['sort'] = 'rank'
    const filterObj: Record<string, Object> = {}
    filterObj['type'] = [2] as Object
    filterObj['tag'] = ['日本'] as Object
    filterObj['air_date'] = [`>=${start}`, `<${end}`] as Object
    filterObj['rank'] = ['>0', '<=99999'] as Object
    filterObj['nsfw'] = true as Object
    bodyObj['filter'] = filterObj as Object
    const body = JSON.stringify(bodyObj)
    const path = '/v0/search/subjects?limit=50&offset=0'

    for (let d = 0; d < BANGUMI_API_DOMAINS.length; d++) {
      const domain = BANGUMI_API_DOMAINS[d]
      const searchUrl = domain + path
      const request = http.createHttp()
      try {
        logger.info('searchByAirDateRange: %{public}s to %{public}s via %{public}s', start, end, domain)
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        }

        const response = await request.request(searchUrl, options)
        const statusCode = response.responseCode as number
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy()
          continue
        }

        const bodyStr = response.result as string
        if (bodyStr.length === 0) {
          request.destroy()
          continue
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>
        const dataList = json['data'] as Object[]
        if (dataList === null || dataList === undefined || dataList.length === 0) {
          request.destroy()
          continue
        }

        for (let i = 0; i < dataList.length; i++) {
          const subject = dataList[i] as Record<string, Object>
          const item = BangumiApi.parseAnimeItemFromApi(subject)
          if (item.name.length > 0 && item.airWeekday >= 1 && item.airWeekday <= 7) {
            result[item.airWeekday - 1].push(item)
          }
        }

        const totalItems = result.reduce((sum: number, arr: AnimeItem[]) => sum + arr.length, 0)
        logger.info('searchByAirDateRange returned %{public}d items from %{public}s', totalItems, domain)
        request.destroy()
        return result
      } catch (err) {
        const msg = extractErrorMsg(err as Object)
        logger.warn('searchByAirDateRange from %{public}s error: %{public}s', domain, msg)
        request.destroy()
      }
    }

    return result
  }

  static async getCalendar(): Promise<AnimeItem[][]> {
    const result: AnimeItem[][] = [];
    for (let i = 0; i < 7; i++) {
      result.push([]);
    }

    const mirrorResult = await BangumiApi.fetchMirrorCalendarSeason();
    if (mirrorResult) {
      return mirrorResult;
    }

    const calendarDomains: string[] = [
      'https://bgmapi.anibt.net',
      'https://next.bgm.tv',
      'https://api.bgm.tv'
    ];
    const calendarPath = '/p1/calendar';

    for (let d = 0; d < calendarDomains.length; d++) {
      const domain = calendarDomains[d];
      const url = domain + calendarPath;
      const request = http.createHttp();
      try {
        logger.info('Fetching calendar from %{public}s', domain);
        const response = await request.request(url, {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: 15000,
          connectTimeout: 10000,
          expectDataType: http.HttpDataType.STRING
        });

        const statusCode = response.responseCode as number;
        logger.info('Calendar response from %{public}s: HTTP %{public}d', domain, statusCode);
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy();
          continue;
        }

        const bodyStr = response.result as string;
        if (bodyStr.length === 0) {
          request.destroy();
          continue;
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>;
        BangumiApi.fillCalendarFromJson(json, result);
        const totalDays = result.filter((arr: AnimeItem[]) => arr.length > 0).length;
        const totalItems = result.reduce((sum: number, arr: AnimeItem[]) => sum + arr.length, 0);
        logger.info('Calendar loaded from %{public}s: %{public}d items across %{public}d days',
          domain, totalItems, totalDays);
        request.destroy();
        return result;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.warn('Calendar fetch from %{public}s failed: %{public}s', domain, msg);
        request.destroy();
      }
    }

    logger.warn('All calendar domains failed, returning empty');
    return result;
  }

  private static async fetchMirrorCalendarSeason(): Promise<AnimeItem[][] | null> {
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth();
    const quarterStart = new Date(year, Math.floor(month / 3) * 3, 1);
    const quarterEnd = new Date(year, Math.floor(month / 3) * 3 + 3, 1);
    const startDate = BangumiApi.formatDate(quarterStart);
    const endDate = BangumiApi.formatDate(quarterEnd);

    const url = `${BangumiConfig.KAZUMI_CALENDAR_URL}?start=${startDate}&end=${endDate}`;
    const request = http.createHttp();
    try {
      logger.info('Mirror calendar season: %{public}s to %{public}s', startDate, endDate);
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
        },
        readTimeout: MIRROR_CACHE_READ_TIMEOUT_MS,
        connectTimeout: MIRROR_CACHE_CONNECT_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });

      const statusCode = response.responseCode as number;
      if (statusCode < 200 || statusCode >= 300) {
        logger.warn('Mirror calendar HTTP %{public}d', statusCode);
        request.destroy();
        return null;
      }

      const bodyStr = response.result as string;
      if (bodyStr.length === 0) {
        request.destroy();
        return null;
      }

      const json = JSON.parse(bodyStr) as Record<string, Object>;
      const result: AnimeItem[][] = [];
      for (let i = 0; i < 7; i++) {
        result.push([]);
      }
      BangumiApi.fillCalendarFromJson(json, result);
      const totalDays = result.filter((arr: AnimeItem[]) => arr.length > 0).length;
      if (totalDays === 0) {
        request.destroy();
        return null;
      }
      const totalItems = result.reduce((sum: number, arr: AnimeItem[]) => sum + arr.length, 0);
      logger.info('Mirror calendar loaded: %{public}d items across %{public}d days', totalItems, totalDays);
      request.destroy();
      return result;
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Mirror calendar failed: %{public}s', msg);
      request.destroy();
      return null;
    }
  }

  private static fillCalendarFromJson(json: Record<string, Object>, result: AnimeItem[][]): void {
    for (let weekday = 1; weekday <= 7; weekday++) {
      const dayKey = String(weekday);
      const dayList = json[dayKey] as Object[];
      if (dayList === null || dayList === undefined) {
        continue;
      }
      const items: AnimeItem[] = [];
      for (let j = 0; j < dayList.length; j++) {
        const entry = dayList[j] as Record<string, Object>;
        const subject = entry['subject'] as Record<string, Object>;
        if (subject === null || subject === undefined) {
          continue;
        }
        const item = BangumiApi.parseAnimeItemFromApi(subject);
        if (item.name.length > 0) {
          items.push(item);
        }
      }
      result[weekday - 1] = items;
    }
  }

  private static formatDate(d: Date): string {
    const y = d.getFullYear();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${day}`;
  }

  private static parseAnimeItemFromApi(item: Record<string, Object>): AnimeItem {
    const anime = new AnimeItem();
    const nameCn = (item['name_cn'] as string) ?? (item['nameCN'] as string) ?? '';
    const name = (item['name'] as string) ?? '';
    anime.name = nameCn.length > 0 ? nameCn : name;
    anime.originalName = name;
    anime.desc = (item['summary'] as string) ?? '';

    const dateStr = (item['date'] as string) ?? '';
    if (dateStr.length > 0) {
      anime.airDate = dateStr;
    } else {
      const airtimeObj = item['airtime'] as Record<string, Object>;
      if (airtimeObj !== null && airtimeObj !== undefined) {
        anime.airDate = (airtimeObj['date'] as string) ?? '';
        anime.airWeekday = (airtimeObj['weekday'] as number) ?? 0;
      }
    }

    anime.eps = BangumiApi.readNumber(item['eps']);
    if (anime.eps <= 0) {
      anime.eps = BangumiApi.readNumber(item['total_episodes']);
    }

    const imagesObj = item['images'] as Record<string, Object>;
    if (imagesObj !== null && imagesObj !== undefined) {
      const large = (imagesObj['large'] as string) ?? '';
      const common = (imagesObj['common'] as string) ?? '';
      const medium = (imagesObj['medium'] as string) ?? '';
      if (large.length > 0) anime.coverLarge = BangumiApi.normalizeCoverUrl(large);
      if (common.length > 0) anime.coverCommon = BangumiApi.normalizeCoverUrl(common);
      if (medium.length > 0) anime.coverMedium = BangumiApi.normalizeCoverUrl(medium);
      const coverUrl = large.length > 0 ? large :
        common.length > 0 ? common : medium;
      const normalizedCover = BangumiApi.normalizeCoverUrl(coverUrl);
      anime.bangumiCover = normalizedCover;
      anime.cover = normalizedCover;
    } else {
      const imageStr = (item['image'] as string) ?? '';
      if (imageStr.length > 0) {
        const normalizedCover = BangumiApi.normalizeCoverUrl(imageStr);
        anime.bangumiCover = normalizedCover;
        anime.cover = normalizedCover;
      }
    }

    const ratingObj = item['rating'] as Record<string, Object>;
    if (ratingObj !== null && ratingObj !== undefined) {
      anime.ratingScore = (ratingObj['score'] as number) ?? 0;
      anime.rank = (ratingObj['rank'] as number) ?? 0;
      anime.votes = (ratingObj['total'] as number) ?? 0;
      const countValue = ratingObj['count'];
      if (Array.isArray(countValue)) {
        const countObj = countValue as Object[];
        const counts: number[] = [];
        for (let i = 0; i < countObj.length; i++) {
          counts.push(countObj[i] as number);
        }
        anime.votesCount = counts;
      } else if (countValue !== null && countValue !== undefined) {
        const countObj = countValue as Record<string, Object>;
        const counts: number[] = [];
        for (let score = 1; score <= 10; score++) {
          const value = countObj[`${score}`] as number;
          counts.push(value !== null && value !== undefined ? value : 0);
        }
        anime.votesCount = counts;
      }
    }

    const tagList = item['tags'] as Object[];
    if (tagList !== null && tagList !== undefined) {
      const tags: string[] = [];
      for (let i = 0; i < tagList.length; i++) {
        const tagObj = tagList[i] as Record<string, Object>;
        const tagName = (tagObj['name'] as string) ?? '';
        if (tagName.length > 0) {
          tags.push(tagName);
        }
      }
      anime.tags = tags;
    }

    const infoboxList = item['infobox'] as Object[];
    if (infoboxList !== null && infoboxList !== undefined) {
      const aliases: string[] = [];
      for (let i = 0; i < infoboxList.length; i++) {
        const info = infoboxList[i] as Record<string, Object>;
        const key = (info['key'] as string) ?? '';
        const valueText = BangumiApi.readInfoboxValueText(info['value']);
        if (anime.eps <= 0 && (key === '话数' || key === '集数')) {
          anime.eps = BangumiApi.extractFirstNumber(valueText);
        } else if (anime.airDate.length === 0 && (key === '放送开始' || key === '开始')) {
          anime.airDate = BangumiApi.normalizeDateText(valueText);
        }
        if (key === '别名' || key === '别名2') {
          const values = info['value'] as Object[];
          if (values !== null && values !== undefined) {
            for (let v = 0; v < values.length; v++) {
              const valObj = values[v] as Record<string, Object>;
              const vStr = (valObj['v'] as string) ?? '';
              if (vStr.length > 0 && vStr !== anime.name && vStr !== anime.originalName) {
                aliases.push(vStr);
              }
            }
          } else {
            const vStr = (info['value'] as string) ?? '';
            if (vStr.length > 0 && vStr !== anime.name && vStr !== anime.originalName) {
              aliases.push(vStr);
            }
          }
        }
      }
      anime.aliases = aliases;
    }

    const rawInfo = (item['info'] as string) ?? '';
    if (rawInfo.length > 0) {
      BangumiApi.enrichAnimeItemFromRawInfo(anime, rawInfo);
    }

    const id = (item['id'] as number) ?? -1;
    anime.bangumiId = id;
    anime.url = id >= 0 ? `bangumi:subject:${id}` : '';
    anime.sourceId = -1;
    anime.sourceName = 'Bangumi';
    return anime;
  }

  private static enrichAnimeItemFromRawInfo(anime: AnimeItem, rawInfo: string): void {
    const lines = rawInfo.split('\n');
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      if (line.startsWith('|')) {
        line = line.substring(1).trim();
      }
      const splitIndex = line.indexOf('=');
      if (splitIndex <= 0) {
        continue;
      }

      const key = line.substring(0, splitIndex).trim();
      const value = line.substring(splitIndex + 1).trim();
      if (value.length === 0 || value === '{') {
        continue;
      }

      if (anime.eps <= 0 && (key === '话数' || key === '集数')) {
        anime.eps = BangumiApi.extractFirstNumber(value);
      } else if (anime.airDate.length === 0 && (key === '放送开始' || key === '开始')) {
        anime.airDate = BangumiApi.normalizeDateText(value);
      }

      if (anime.eps > 0 && anime.airDate.length > 0) {
        return;
      }
    }
  }

  private static readNumber(value: Object | undefined): number {
    if (value === null || value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value as number;
    }
    if (typeof value === 'string') {
      const parsed = Number(value as string);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private static readInfoboxValueText(value: Object | undefined): string {
    if (value === null || value === undefined) {
      return '';
    }
    if (typeof value === 'string') {
      return value as string;
    }
    if (Array.isArray(value)) {
      const arr = value as Object[];
      const parts: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        const obj = arr[i] as Record<string, Object>;
        const v = (obj['v'] as string) ?? '';
        if (v.length > 0) {
          parts.push(v);
        }
      }
      return parts.join(' / ');
    }
    return '';
  }

  private static extractFirstNumber(text: string): number {
    let digits = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch >= '0' && ch <= '9') {
        digits += ch;
      } else if (digits.length > 0) {
        break;
      }
    }
    if (digits.length === 0) {
      return 0;
    }
    const parsed = Number(digits);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private static normalizeDateText(text: string): string {
    if (text.length === 0) {
      return '';
    }
    const normalized = text.replace('年', '-').replace('月', '-').replace('日', '');
    const parts = normalized.split('-');
    if (parts.length >= 3) {
      const year = parts[0].trim();
      const month = parts[1].trim().padStart(2, '0');
      const day = parts[2].trim().padStart(2, '0');
      if (year.length === 4 && month.length === 2 && day.length === 2) {
        return `${year}-${month}-${day}`;
      }
    }
    return text;
  }

  static async searchHighScoreSubjects(limit: number, offset: number): Promise<AnimeItem[]> {
    const items: AnimeItem[] = []
    const bodyObj: Record<string, Object> = {}
    bodyObj['keyword'] = ''
    bodyObj['sort'] = 'rank'
    const filterObj: Record<string, Object> = {}
    filterObj['type'] = [2] as Object
    filterObj['rank'] = ['>0', '<=99999'] as Object
    filterObj['rating'] = ['>=7.5'] as Object
    filterObj['rating_count'] = ['>=500'] as Object
    filterObj['nsfw'] = false as Object
    bodyObj['filter'] = filterObj as Object
    const body = JSON.stringify(bodyObj)
    const path = '/v0/search/subjects?limit=' + String(limit) + '&offset=' + String(offset)

    for (let d = 0; d < BANGUMI_API_DOMAINS.length; d++) {
      const domain = BANGUMI_API_DOMAINS[d]
      const searchUrl = domain + path
      const request = http.createHttp()
      try {
        logger.info('searchHighScore: limit=%{public}d offset=%{public}d via %{public}s', limit, offset, domain)
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        }

        const response = await request.request(searchUrl, options)
        const statusCode = response.responseCode as number
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy()
          continue
        }

        const bodyStr = response.result as string
        if (bodyStr.length === 0) {
          request.destroy()
          continue
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>
        const dataList = json['data'] as Object[]
        if (dataList === null || dataList === undefined || dataList.length === 0) {
          request.destroy()
          continue
        }

        for (let i = 0; i < dataList.length; i++) {
          const subject = dataList[i] as Record<string, Object>
          const item = BangumiApi.parseAnimeItemFromApi(subject)
          if (item.name.length > 0) {
            items.push(item)
          }
        }

        logger.info('searchHighScore returned %{public}d items from %{public}s', items.length, domain)
        request.destroy()
        return items
      } catch (err) {
        const msg = extractErrorMsg(err as Object)
        logger.warn('searchHighScore from %{public}s error: %{public}s', domain, msg)
        request.destroy()
      }
    }

    const fallbackItems = await BangumiApi.fetchMirrorPopular('', offset)
    if (fallbackItems.length > 0) {
      const scoredItems: AnimeItem[] = []
      for (let i = 0; i < fallbackItems.length; i++) {
        const item = fallbackItems[i]
        if (item.ratingScore > 0) {
          scoredItems.push(item)
        }
      }
      scoredItems.sort((a: AnimeItem, b: AnimeItem): number => {
        if (a.rank > 0 && b.rank > 0 && a.rank !== b.rank) {
          return a.rank - b.rank
        }
        if (a.rank > 0 && b.rank <= 0) {
          return -1
        }
        if (a.rank <= 0 && b.rank > 0) {
          return 1
        }
        if (b.ratingScore !== a.ratingScore) {
          return b.ratingScore - a.ratingScore
        }
        return b.votes - a.votes
      })
      const limitedItems: AnimeItem[] = []
      for (let i = 0; i < scoredItems.length && i < limit; i++) {
        limitedItems.push(scoredItems[i])
      }
      logger.info('searchHighScore fallback returned %{public}d items', limitedItems.length)
      return limitedItems
    }

    return items
  }

  static async searchSeasonalSubjects(startDate: string, endDate: string, limit: number, offset: number): Promise<AnimeItem[]> {
    const items: AnimeItem[] = []
    const bodyObj: Record<string, Object> = {}
    bodyObj['keyword'] = ''
    bodyObj['sort'] = 'rank'
    const filterObj: Record<string, Object> = {}
    filterObj['type'] = [2] as Object
    filterObj['tag'] = ['日本'] as Object
    filterObj['air_date'] = ['>=' + startDate, '<' + endDate] as Object
    filterObj['nsfw'] = false as Object
    bodyObj['filter'] = filterObj as Object
    const body = JSON.stringify(bodyObj)
    const path = '/v0/search/subjects?limit=' + String(limit) + '&offset=' + String(offset)

    for (let d = 0; d < BANGUMI_API_DOMAINS.length; d++) {
      const domain = BANGUMI_API_DOMAINS[d]
      const searchUrl = domain + path
      const request = http.createHttp()
      try {
        logger.info('searchSeasonal: %{public}s to %{public}s via %{public}s', startDate, endDate, domain)
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        }

        const response = await request.request(searchUrl, options)
        const statusCode = response.responseCode as number
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy()
          continue
        }

        const bodyStr = response.result as string
        if (bodyStr.length === 0) {
          request.destroy()
          continue
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>
        const dataList = json['data'] as Object[]
        if (dataList === null || dataList === undefined || dataList.length === 0) {
          request.destroy()
          continue
        }

        for (let i = 0; i < dataList.length; i++) {
          const subject = dataList[i] as Record<string, Object>
          const item = BangumiApi.parseAnimeItemFromApi(subject)
          if (item.name.length > 0) {
            items.push(item)
          }
        }

        logger.info('searchSeasonal returned %{public}d items from %{public}s', items.length, domain)
        request.destroy()
        return items
      } catch (err) {
        const msg = extractErrorMsg(err as Object)
        logger.warn('searchSeasonal from %{public}s error: %{public}s', domain, msg)
        request.destroy()
      }
    }

    return items
  }

  static async searchByTagWithSort(tag: string, sort: string, limit: number, offset: number): Promise<AnimeItem[]> {
    if (sort === 'rank') {
      const mirrorItems = await BangumiApi.fetchMirrorPopular(tag, offset)
      if (mirrorItems.length > 0) {
        return mirrorItems
      }
    }

    const items: AnimeItem[] = []
    const bodyObj: Record<string, Object> = {}
    bodyObj['keyword'] = ''
    bodyObj['sort'] = sort
    const filterObj: Record<string, Object> = {}
    filterObj['type'] = [2] as Object
    if (tag.length > 0) {
      filterObj['tag'] = [tag] as Object
    }
    filterObj['rank'] = ['>0', '<=99999'] as Object
    filterObj['nsfw'] = false as Object
    bodyObj['filter'] = filterObj as Object
    const body = JSON.stringify(bodyObj)
    const path = '/v0/search/subjects?limit=' + String(limit) + '&offset=' + String(offset)

    for (let d = 0; d < BANGUMI_API_DOMAINS.length; d++) {
      const domain = BANGUMI_API_DOMAINS[d]
      const searchUrl = domain + path
      const request = http.createHttp()
      try {
        logger.info('searchByTagWithSort: tag=%{public}s sort=%{public}s via %{public}s', tag, sort, domain)
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
          },
          readTimeout: API_SEARCH_READ_TIMEOUT_MS,
          connectTimeout: API_SEARCH_CONNECT_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        }

        const response = await request.request(searchUrl, options)
        const statusCode = response.responseCode as number
        if (statusCode < 200 || statusCode >= 300) {
          request.destroy()
          continue
        }

        const bodyStr = response.result as string
        if (bodyStr.length === 0) {
          request.destroy()
          continue
        }

        const json = JSON.parse(bodyStr) as Record<string, Object>
        const dataList = json['data'] as Object[]
        if (dataList === null || dataList === undefined || dataList.length === 0) {
          request.destroy()
          continue
        }

        for (let i = 0; i < dataList.length; i++) {
          const subject = dataList[i] as Record<string, Object>
          const item = BangumiApi.parseAnimeItemFromApi(subject)
          if (item.name.length > 0) {
            items.push(item)
          }
        }

        logger.info('searchByTagWithSort returned %{public}d items from %{public}s', items.length, domain)
        request.destroy()
        return items
      } catch (err) {
        const msg = extractErrorMsg(err as Object)
        logger.warn('searchByTagWithSort from %{public}s error: %{public}s', domain, msg)
        request.destroy()
      }
    }

    return items
  }

  static getCurrentSeasonRange(): SeasonRange {
    const now = new Date()
    const year = now.getFullYear()
    const month = now.getMonth()
    const quarter = Math.floor(month / 3)
    const startMonth = quarter * 3
    const startDate = new Date(year, startMonth, 1)
    const endDate = new Date(year, startMonth + 3, 1)
    const range = new SeasonRange()
    range.start = BangumiApi.formatDate(startDate)
    range.end = BangumiApi.formatDate(endDate)
    return range
  }

  static getCurrentSeasonLabel(): string {
    const now = new Date()
    const year = now.getFullYear()
    const month = now.getMonth()
    const quarter = Math.floor(month / 3)
    const seasonNames: string[] = ['冬季', '春季', '夏季', '秋季']
    return year.toString() + seasonNames[quarter] + '新番'
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: Function) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
