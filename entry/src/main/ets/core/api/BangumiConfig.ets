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
  static readonly BANGUMI_IMAGE_BASE: string = 'https://lain.bangumi.pro';
  static readonly BANGUMI_WEB_BASE: string = 'https://bgmmi.anibt.net';
  static readonly BANGUMI_WEB_SEARCH_URLS: string[] = [
    'https://bgmmi.anibt.net/subject_search/',
    'https://bgm.tv/subject_search/'
  ];

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
    // Proxy detail responses may expose a subject image API instead of the
    // actual cover filename. It cannot be mapped to lain.bangumi.pro and is
    // unreliable as an Image source, so let the detail loader resolve the v0
    // metadata that contains the real /pic/cover/...jpg path.
    if (url.includes('/v0/subjects/') && url.includes('/image?')) {
      return '';
    }
    url = url.replace('https://lain.bgm.tv/pic/cover/', BangumiConfig.BANGUMI_IMAGE_BASE + '/pic/cover/');
    url = url.replace('http://lain.bgm.tv/pic/cover/', BangumiConfig.BANGUMI_IMAGE_BASE + '/pic/cover/');
    url = url.replace('https://lain.bgm.tv/pic/', BangumiConfig.BANGUMI_IMAGE_BASE + '/pic/');
    url = url.replace('http://lain.bgm.tv/pic/', BangumiConfig.BANGUMI_IMAGE_BASE + '/pic/');
    url = url.replace('https://lain.bgm.tv/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://lain.bgm.tv/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('https://lain.bangumi.lol/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://lain.bangumi.lol/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('https://img.bgm.tv/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('https://bgmimg.anibt.net/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    url = url.replace('http://bgmimg.anibt.net/', BangumiConfig.BANGUMI_IMAGE_BASE + '/');
    if (!url.startsWith('http')) {
      return '';
    }
    return url;
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
