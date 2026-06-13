import { BangumiApi } from './BangumiApi';
import { AnimeItem } from '../../models/AnimeItem';
import { Logger, extractErrorMsg } from '../../utils/Logger';

const logger: Logger = new Logger('BangumiCoverResolver');

const coverCache: Map<string, string> = new Map();
const MAX_CACHE_SIZE: number = 200;

export class BangumiCoverResolver {
  static async resolveCovers(items: AnimeItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }

    const grouped: Map<string, AnimeItem[]> = new Map();
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.name.length === 0) {
        continue;
      }
      if (item.cover.length > 0 || item.coverFallback.length > 0) {
        continue;
      }
      const cleanName = cleanSearchName(item.name);
      let group = grouped.get(cleanName);
      if (group === undefined) {
        group = [];
        grouped.set(cleanName, group);
      }
      group.push(item);
    }

    try {
      const cleanNames: string[] = [];
      grouped.forEach((value: AnimeItem[], key: string) => {
        cleanNames.push(key);
      });
      if (cleanNames.length === 0) {
        logger.info('Skip Bangumi cover resolve: all %{public}d items already have source covers', items.length);
        return;
      }
      logger.info('Resolving %{public}d unique Bangumi covers for %{public}d items',
        cleanNames.length, items.length);
      for (let i = 0; i < cleanNames.length; i++) {
        const cleanName = cleanNames[i];
        const group = grouped.get(cleanName);
        if (group !== undefined) {
          await BangumiCoverResolver.resolveGroup(cleanName, group);
        }
      }
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Batch resolve failed: %{public}s', msg);
    }
  }

  private static async resolveGroup(cleanName: string, items: AnimeItem[]): Promise<void> {
    const cached = coverCache.get(cleanName);
    if (cached !== undefined) {
      if (cached.length > 0) {
        BangumiCoverResolver.applyCover(items, cached);
      }
      return;
    }

    try {
      const cover = await BangumiApi.searchCover(cleanName);
      addToCache(cleanName, cover);
      if (cover.length > 0) {
        BangumiCoverResolver.applyCover(items, cover);
        logger.info('Resolved Bangumi cover for %{public}s', cleanName.substring(0, 30));
      }
    } catch (err) {
      const msg = extractErrorMsg(err as Object);
      logger.warn('Resolve cover failed for %{public}s: %{public}s', cleanName.substring(0, 30), msg);
      addToCache(cleanName, '');
    }
  }

  static clearCache(): void {
    coverCache.clear();
  }

  private static applyCover(items: AnimeItem[], cover: string): void {
    for (let i = 0; i < items.length; i++) {
      items[i].bangumiCover = cover;
    }
  }
}

function cleanSearchName(name: string): string {
  let cleaned = name.trim();
  const suffixes: string[] = [
    ' \u7B2C\u4E8C\u5B63', ' \u7B2C\u4E09\u5B63', ' \u7B2C\u56DB\u5B63',
    ' \u7B2C\u4E8C\u671F', ' \u7B2C\u4E09\u671F',
    ' OVA', ' ova', ' \u5287\u573A\u7248', ' Movie', ' SP',
    ' \u7279\u522B\u7BC7', ' \u5916\u4F20'
  ];
  for (let i = 0; i < suffixes.length; i++) {
    if (cleaned.endsWith(suffixes[i])) {
      cleaned = cleaned.substring(0, cleaned.length - suffixes[i].length);
      break;
    }
  }
  return cleaned;
}

function addToCache(key: string, value: string): void {
  if (coverCache.size >= MAX_CACHE_SIZE) {
    const cacheKeys: string[] = [];
    coverCache.forEach((v: string, k: string) => {
      cacheKeys.push(k);
    });
    if (cacheKeys.length > 0) {
      coverCache.delete(cacheKeys[0]);
    }
  }
  coverCache.set(key, value);
}
