import { RuleSource } from '../../models/RuleSource';
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel';
import { AnimeItem } from '../../models/AnimeItem';
import { Episode } from '../../models/Episode';
import { RuleSourceStore } from '../../store/RuleSourceStore';
import { SearchExecutor } from './SearchExecutor';
import { RequestPolicyHandler } from './RequestPolicyHandler';
import { AntiCrawlHandler } from './AntiCrawlHandler';
import { Logger } from '../../utils/Logger';

const logger = new Logger('RuleEngine');

export class RuleEngine {
  private ruleStore: RuleSourceStore;
  private searchExecutor: SearchExecutor;
  private requestHandler: RequestPolicyHandler;
  private antiCrawlHandler: AntiCrawlHandler;

  constructor() {
    this.ruleStore = new RuleSourceStore();
    this.searchExecutor = new SearchExecutor();
    this.requestHandler = new RequestPolicyHandler();
    this.antiCrawlHandler = new AntiCrawlHandler();
  }

  async search(keyword: string): Promise<AnimeItem[]> {
    const enabledRules = await this.ruleStore.getEnabled();
    if (enabledRules.length === 0) {
      logger.warn('No enabled rule sources');
      return [];
    }

    logger.info('Searching %{public}s across %{public}d rules', keyword, enabledRules.length);

    const allResults: AnimeItem[] = [];
    const promises: Promise<AnimeItem[]>[] = [];

    for (let i = 0; i < enabledRules.length; i++) {
      const rule = enabledRules[i];
      promises.push(this.searchWithRule(rule, keyword));
    }

    const results = await Promise.all(promises);
    for (let i = 0; i < results.length; i++) {
      const ruleResults = results[i];
      for (let j = 0; j < ruleResults.length; j++) {
        allResults.push(ruleResults[j]);
      }
    }

    const deduped = this.dedupResults(allResults);
    logger.info('Search completed: %{public}d results (deduped from %{public}d)',
      deduped.length, allResults.length);

    return deduped;
  }

  async searchAll(keyword: string): Promise<AnimeItem[]> {
    const enabledRules = await this.ruleStore.getEnabled();
    if (enabledRules.length === 0) {
      logger.warn('No enabled rule sources');
      return [];
    }

    logger.info('Searching all playback sources for %{public}s across %{public}d rules',
      keyword, enabledRules.length);

    const allResults: AnimeItem[] = [];
    const promises: Promise<AnimeItem[]>[] = [];
    for (let i = 0; i < enabledRules.length; i++) {
      promises.push(this.searchWithRule(enabledRules[i], keyword));
    }

    const results = await Promise.all(promises);
    for (let i = 0; i < results.length; i++) {
      const ruleResults = results[i];
      for (let j = 0; j < ruleResults.length; j++) {
        allResults.push(ruleResults[j]);
      }
    }

    logger.info('Playback source search completed: %{public}d results', allResults.length);
    return allResults;
  }

  private async searchWithRule(rule: RuleSource, keyword: string): Promise<AnimeItem[]> {
    try {
      const runtime = new RuleRuntimeModel(rule);
      const html = await this.requestHandler.fetchWithRule(runtime, keyword);

      if (this.antiCrawlHandler.isCaptchaResponse(html)) {
        logger.warn('Captcha detected for rule %{public}s', rule.name);
        if (rule.antiCrawlerConfig.enabled) {
          const result = await this.antiCrawlHandler.handleAntiCrawl(rule.antiCrawlerConfig, runtime.fullSearchUrl);
          if (!result.success) {
            logger.warn('Anti-crawl handling failed for %{public}s: %{public}s', rule.name, result.message);
            return [];
          }
        }
      }

      return this.searchExecutor.parseSearchResults(html, runtime);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Search failed for rule %{public}s: %{public}s', rule.name, msg);
      return [];
    }
  }

  async parseDetail(rule: RuleSource, url: string): Promise<Record<string, string>> {
    try {
      const runtime = new RuleRuntimeModel(rule);
      const html = await this.requestHandler.fetchUrlWithRuleHeaders(runtime, url);
      return this.searchExecutor.parseDetail(html, runtime);
    } catch (err) {
      logger.error('Detail parsing failed: %{public}s', err instanceof Error ? err.message : String(err));
      return {};
    }
  }

  async parseEpisodes(rule: RuleSource, url: string): Promise<Episode[]> {
    try {
      const runtime = new RuleRuntimeModel(rule);
      const html = await this.requestHandler.fetchUrlWithRuleHeaders(runtime, url);
      return this.searchExecutor.parseEpisodes(html, runtime);
    } catch (err) {
      logger.error('Episode parsing failed: %{public}s', err instanceof Error ? err.message : String(err));
      return [];
    }
  }

  getRuleStore(): RuleSourceStore {
    return this.ruleStore;
  }

  private dedupResults(items: AnimeItem[]): AnimeItem[] {
    const seen: Set<string> = new Set();
    const result: AnimeItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const key = items[i].name;
      if (!seen.has(key)) {
        seen.add(key);
        result.push(items[i]);
      }
    }
    return result;
  }
}
