import { ImageNetworkSettings } from '../../store/ImageNetworkSettings';

export class BangumiConfig {
  static readonly KAZUMI_POPULAR_URL: string = 'https://api.kazumi.fyi/kazumi/v1/popular/subjects';
  static readonly KAZUMI_CALENDAR_URL: string = 'https://api.kazumi.fyi/kazumi/v1/calendar/season';
  static readonly KAZUMI_BANGUMI_PROXY_BASE: string = 'https://api.kazumi.fyi';
  static readonly BANGUMI_MIRROR_APP_ID: string = '';
  static readonly BANGUMI_MIRROR_APP_KEY: string = '';
  static readonly BANGUMI_SUBJECT_DETAIL_BASES: string[] = [
    'https://api.kazumi.fyi',
    'https://bgmapi.anibt.net',
    'https://next.bgm.tv'
  ];
  static readonly BANGUMI_API_BASES: string[] = [
    'https://api.kazumi.fyi',
    'https://bgmapi.anibt.net',
    'https://api.bgm.tv',
    'https://next.bgm.tv'
  ];
  static readonly BANGUMI_SUBJECT_V0_BASES: string[] = [
    'https://bgmapi.anibt.net',
    'https://api.bgm.tv'
  ];
  static readonly BANGUMI_SEARCH_BASES: string[] = [
    'https://api.bangumi.lol',
    'https://api.kazumi.fyi',
    'https://bgmapi.anibt.net',
    'https://api.bgm.tv',
    'https://next.bgm.tv'
  ];
  static readonly BANGUMI_NEXT_BASES: string[] = [
    'https://bgmapi.anibt.net',
    'https://next.bgm.tv'
  ];
  // Keep canonical URLs in the model. Proxied images use the original URL;
  // images outside the active proxy scope use the wsrv.nl relay.
  static readonly BANGUMI_IMAGE_BASE: string = 'https://lain.bgm.tv';
  // Legacy mirror URLs are normalized to the canonical host, not requested as a fallback.
  static readonly BANGUMI_IMAGE_MIRROR: string = 'https://bgmimg.anibt.net';
  static readonly BANGUMI_WEB_BASE: string = 'https://bgmmi.anibt.net';
  static readonly BANGUMI_WEB_SEARCH_URLS: string[] = [
    'https://bgmmi.anibt.net/subject_search/',
    'https://bgm.tv/subject_search/'
  ];

  static getApiBases(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://api.bgm.tv'] : BangumiConfig.BANGUMI_API_BASES;
  }

  static getSubjectV0Bases(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://api.bgm.tv'] : BangumiConfig.BANGUMI_SUBJECT_V0_BASES;
  }

  static getSearchBases(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://api.bgm.tv'] : BangumiConfig.BANGUMI_SEARCH_BASES;
  }

  static getNextBases(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://next.bgm.tv'] : BangumiConfig.BANGUMI_NEXT_BASES;
  }

  static getSubjectDetailBases(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://next.bgm.tv'] : BangumiConfig.BANGUMI_SUBJECT_DETAIL_BASES;
  }

  static getWebSearchUrls(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://bgm.tv/subject_search/'] : BangumiConfig.BANGUMI_WEB_SEARCH_URLS;
  }

  static getCalendarBases(): string[] {
    return ImageNetworkSettings.isDataProxyEnabled() ? ['https://next.bgm.tv'] :
      ['https://api.kazumi.fyi', 'https://bgmapi.anibt.net', 'https://next.bgm.tv', 'https://api.bgm.tv'];
  }

  // Only metadata included in the enabled proxy scope uses official endpoints.
  static getDataRequestUrl(url: string, dataProxyEnabled: boolean): string {
    if (!dataProxyEnabled) {
      return url;
    }
    const protocolEnd = url.indexOf('://');
    const pathStart = url.indexOf('/', protocolEnd + 3);
    if (protocolEnd < 0 || pathStart < 0) {
      throw new Error('Invalid Bangumi data URL');
    }
    const path = url.substring(pathStart);
    if (path.startsWith('/p1/')) {
      return 'https://next.bgm.tv' + path;
    }
    if (path.startsWith('/v0/')) {
      return 'https://api.bgm.tv' + path;
    }
    if (path.startsWith('/subject_search/')) {
      return 'https://bgm.tv' + path;
    }
    throw new Error('Mirror-only Bangumi endpoint is unavailable in data proxy mode');
  }

  static normalizeImageUrl(raw: string): string {
    let url = raw.trim();
    if (url.length === 0 || url.includes('no_icon')) {
      return '';
    }
    if (url.startsWith('//')) {
      url = 'https:' + url;
    } else if (url.startsWith('/')) {
      url = 'https://bgm.tv' + url;
    }
    // Keep Bangumi API image endpoints. The upstream proxy can fetch these
    // synthetic URLs directly, while converting them to an image filename is
    // impossible without another metadata request.
    if (url.startsWith('https://api.bgm.tv/') || url.startsWith('http://api.bgm.tv/')) {
      return url;
    }
    url = url.replace('https://lain.bgm.tv/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://lain.bgm.tv/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('https://lain.bangumi.lol/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://lain.bangumi.lol/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    // Migrate URLs persisted while the previous image hosts were configured.
    url = url.replace('https://lain.bangumi.pro/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://lain.bangumi.pro/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('https://img.bgm.tv/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('https://bgmimg.anibt.net/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://bgmimg.anibt.net/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    if (!url.startsWith('http')) {
      return '';
    }
    return url;
  }

  /** Builds the same image proxy URL used by the upstream Flutter client. */
  static getImageProxyUrl(raw: string): string {
    const normalized = BangumiConfig.normalizeImageUrl(raw);
    if (!BangumiConfig.isProxyableImageUrl(normalized)) {
      return '';
    }
    const protocolEnd = normalized.indexOf('://');
    if (protocolEnd < 0) {
      return '';
    }
    const source = normalized.substring(protocolEnd + 3);
    const encoded = encodeURIComponent(source);
    const animated = normalized.toLowerCase().split('?')[0].endsWith('.gif') ? '&n=-1' : '';
    return `https://wsrv.nl/?url=${encoded}${animated}`;
  }

  /**
   * Builds the ordered image candidates used by every cover consumer.
   *
   * Only Bangumi's own image hosts and image API endpoints are rewritten.
   * The master proxy switch and image scope must both be enabled to use the original URL.
   */
  static getImageCandidates(raw: string,
    imageProxyEnabled: boolean = ImageNetworkSettings.isImageProxyEnabled()): string[] {
    const candidates: string[] = []
    const normalized = BangumiConfig.normalizeImageUrl(raw)
    if (normalized.length === 0) {
      return candidates
    }
    const proxyUrl = imageProxyEnabled ? '' : BangumiConfig.getImageProxyUrl(normalized)
    candidates.push(proxyUrl.length > 0 ? proxyUrl : normalized)
    return candidates
  }

  private static isProxyableImageUrl(url: string): boolean {
    if (url.length === 0 || url.startsWith('file://') || url.startsWith('/')) {
      return false
    }
    const protocolEnd = url.indexOf('://')
    if (protocolEnd < 0) {
      return false
    }
    const authorityAndPath = url.substring(protocolEnd + 3)
    const slashIndex = authorityAndPath.indexOf('/')
    const host = slashIndex >= 0 ? authorityAndPath.substring(0, slashIndex) : authorityAndPath
    if (host === 'lain.bgm.tv') {
      return true
    }
    if (host !== 'api.bgm.tv') {
      return false
    }
    const pathStart = slashIndex >= 0 ? slashIndex : authorityAndPath.length
    const pathAndQuery = authorityAndPath.substring(pathStart)
    const queryIndex = pathAndQuery.indexOf('?')
    const path = queryIndex >= 0 ? pathAndQuery.substring(0, queryIndex) : pathAndQuery
    const segments = path.split('/').filter((segment: string) => segment.length > 0)
    if (segments.length !== 4 || segments[0] !== 'v0' || segments[3] !== 'image') {
      return false
    }
    const imageKinds: string[] = ['subjects', 'characters', 'persons']
    if (imageKinds.indexOf(segments[1]) < 0) {
      return false
    }
    const id = Number(segments[2])
    return Number.isInteger(id) && id > 0
  }

  /** Returns the known direct mirror candidate for a Bangumi cover URL. */
  static getImageMirrorUrl(raw: string): string {
    const normalized = BangumiConfig.normalizeImageUrl(raw);
    if (!normalized.startsWith(BangumiConfig.BANGUMI_IMAGE_BASE + '/')) {
      return '';
    }
    return normalized.replace(BangumiConfig.BANGUMI_IMAGE_BASE + '/',
      BangumiConfig.BANGUMI_IMAGE_MIRROR + '/');
  }

  static getSubjectImageUrls(subjectId: number): string[] {
    // A subject id is insufficient to construct lain.bangumi.pro's JPG path;
    // the filename hash must come from the metadata response. Do not synthesize
    // the old api.bangumi.lol image endpoint here, because it blocks real cover
    // candidates behind repeated connection timeouts.
    return [];
  }

  static getSubjectWebUrl(bangumiId: number): string {
    return `${BangumiConfig.BANGUMI_WEB_BASE}/subject/${bangumiId}`;
  }
}
