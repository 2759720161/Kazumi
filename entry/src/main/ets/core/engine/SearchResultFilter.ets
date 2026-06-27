import { AnimeItem } from '../../models/AnimeItem';
import { Logger } from '../../utils/Logger';

const logger = new Logger('SearchResultFilter');

const ACTION_WORD_BLACKLIST: string[] = [
  '首页',
  '播放',
  '立即播放',
  '详情'
];

const CATEGORY_WORD_BLACKLIST: string[] = [
  '日漫',
  '国漫',
  '剧场',
  '剧场版',
  'OVA',
  'OAD',
  'TV',
  '电影',
  '连载',
  '完结',
  '国产动漫',
  '日本动漫',
  '欧美动漫',
  '海外动漫',
  '动漫电影'
];

const STATUS_WORD_PATTERNS: string[] = [
  '更新至\\d+集',
  '第\\d+集'
];

const INVALID_URL_PATTERNS: string[] = [
  '/vodplay/',
  'javascript:'
];

const ANCHOR_ONLY_PATTERN: string = '^#.*$';

const MAX_TITLE_LENGTH: number = 60;

export class SearchResultFilter {
  filterAndDeduplicate(items: AnimeItem[], ruleName: string): AnimeItem[] {
    const rawNodeCount = items.length;
    if (rawNodeCount === 0) {
      return items;
    }

    try {
      const filtered: AnimeItem[] = [];
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        const reason = this.getFilterReason(item);
        if (reason.length > 0) {
          logger.debug('Drop %{public}s item: name=%{public}s, url=%{public}s, reason=%{public}s',
            ruleName, item.name.length > 30 ? item.name.substring(0, 30) : item.name,
            item.url.length > 50 ? item.url.substring(0, 50) : item.url, reason);
          continue;
        }
        filtered.push(item);
      }

      const afterFilterCount = filtered.length;

      const deduplicated = this.deduplicateByUrl(filtered);

      const validUniqueCount = deduplicated.length;
      const droppedCount = rawNodeCount - validUniqueCount;

      logger.info('Search rule %{public}s produced %{public}d nodes, validUnique=%{public}d, dropped=%{public}d',
        ruleName, rawNodeCount, validUniqueCount, droppedCount);

      if (rawNodeCount > 10 && validUniqueCount < rawNodeCount * 0.3) {
        const retentionPercent = rawNodeCount > 0 ? Math.round(validUniqueCount * 100 / rawNodeCount) : 0;
        logger.warn('Rule %{public}s may be too wide: %{public}d nodes → %{public}d unique (%{public}d%% retention)',
          ruleName, rawNodeCount, validUniqueCount, retentionPercent);
      }

      return deduplicated;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warn('SearchResultFilter failed, returning original items: %{public}s', msg);
      return items;
    }
  }

  private getFilterReason(item: AnimeItem): string {
    if (item.name.length === 0) {
      return 'empty-name';
    }
    if (item.url.length === 0) {
      return 'empty-url';
    }
    const actionReason = this.getActionOrStatusReason(item.name);
    if (actionReason.length > 0) {
      return actionReason;
    }
    const urlReason = this.getInvalidUrlReason(item.url);
    if (urlReason.length > 0) {
      return urlReason;
    }
    if (item.name.trim().length > MAX_TITLE_LENGTH) {
      return 'title-too-long';
    }
    return '';
  }

  private getActionOrStatusReason(name: string): string {
    const trimmed = name.trim();
    for (let i = 0; i < ACTION_WORD_BLACKLIST.length; i++) {
      if (trimmed === ACTION_WORD_BLACKLIST[i]) {
        return 'action-word';
      }
    }
    for (let i = 0; i < CATEGORY_WORD_BLACKLIST.length; i++) {
      if (trimmed === CATEGORY_WORD_BLACKLIST[i]) {
        return 'category-word';
      }
    }
    for (let i = 0; i < STATUS_WORD_PATTERNS.length; i++) {
      try {
        const regex = new RegExp(STATUS_WORD_PATTERNS[i]);
        if (regex.test(trimmed)) {
          return 'status-word';
        }
      } catch (e) {
        continue;
      }
    }
    return '';
  }

  private getInvalidUrlReason(url: string): string {
    const trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'not-http-url';
    }
    for (let i = 0; i < INVALID_URL_PATTERNS.length; i++) {
      if (trimmed.includes(INVALID_URL_PATTERNS[i])) {
        return 'invalid-url-pattern';
      }
    }
    try {
      const anchorRegex = new RegExp(ANCHOR_ONLY_PATTERN);
      if (anchorRegex.test(trimmed)) {
        return 'anchor-only';
      }
    } catch (e) {
    }
    if (this.isRootPathUrl(trimmed)) {
      return 'root-path-url';
    }
    return '';
  }

  private isRootPathUrl(url: string): boolean {
    try {
      const schemeEnd = url.indexOf('://');
      if (schemeEnd === -1) {
        return false;
      }
      const afterScheme = url.substring(schemeEnd + 3);
      const firstSlash = afterScheme.indexOf('/');
      if (firstSlash === -1) {
        return true;
      }
      const path = afterScheme.substring(firstSlash);
      const cleanPath = path.split('?')[0].split('#')[0];
      if (cleanPath === '/' || cleanPath.length <= 1) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  private normalizeUrl(url: string): string {
    try {
      let normalized = url.trim();
      const hashIndex = normalized.indexOf('#');
      if (hashIndex !== -1) {
        normalized = normalized.substring(0, hashIndex);
      }
      const queryIndex = normalized.indexOf('?');
      if (queryIndex !== -1) {
        normalized = normalized.substring(0, queryIndex);
      }
      while (normalized.length > 1 && normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    } catch (e) {
      return url;
    }
  }

  private deduplicateByUrl(items: AnimeItem[]): AnimeItem[] {
    const groups: Map<string, AnimeItem[]> = new Map();

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const key = this.normalizeUrl(item.url);
      let group = groups.get(key);
      if (group === undefined) {
        group = [];
        groups.set(key, group);
      }
      group.push(item);
    }

    const result: AnimeItem[] = [];
    const keys = Array.from(groups.keys());
    for (let i = 0; i < keys.length; i++) {
      const group = groups.get(keys[i]);
      if (group === undefined || group.length === 0) {
        continue;
      }
      if (group.length === 1) {
        result.push(group[0]);
        continue;
      }
      group.sort((a: AnimeItem, b: AnimeItem): number => {
        const aHasCover = a.cover.length > 0 ? 1 : 0;
        const bHasCover = b.cover.length > 0 ? 1 : 0;
        if (aHasCover !== bHasCover) {
          return bHasCover - aHasCover;
        }
        const aIsDetail = a.url.includes('/voddetail/') || a.url.includes('/detail/') ? 1 : 0;
        const bIsDetail = b.url.includes('/voddetail/') || b.url.includes('/detail/') ? 1 : 0;
        if (aIsDetail !== bIsDetail) {
          return bIsDetail - aIsDetail;
        }
        const aNameLen = a.name.trim().length;
        const bNameLen = b.name.trim().length;
        if (aNameLen !== bNameLen && aNameLen <= MAX_TITLE_LENGTH && bNameLen <= MAX_TITLE_LENGTH) {
          return bNameLen - aNameLen;
        }
        return 0;
      });
      result.push(group[0]);
    }
    return result;
  }
}
