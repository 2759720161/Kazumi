import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { RuleSource, AntiCrawlerConfig } from '../models/RuleSource';
import { Logger } from '../utils/Logger';

const logger = new Logger('RuleSourceStore');

export class RuleSourceStore {
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<RuleSource[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.orderByAsc(RdbConstants.COL_NAME);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async getEnabled(): Promise<RuleSource[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.equalTo(RdbConstants.COL_ENABLED, 1);
    predicates.orderByAsc(RdbConstants.COL_NAME);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async getById(id: number): Promise<RuleSource | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.equalTo(RdbConstants.COL_ID, id);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    return list.length > 0 ? list[0] : null;
  }

  async getByName(name: string): Promise<RuleSource | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.equalTo(RdbConstants.COL_NAME, name);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    return list.length > 0 ? list[0] : null;
  }

  async insert(rule: RuleSource): Promise<number> {
    const now = Date.now();
    const values: relationalStore.ValuesBucket = {
      api: rule.api,
      type: rule.type,
      name: rule.name,
      version: rule.version,
      base_url: rule.baseUrl,
      search_url: rule.searchURL,
      search_list: rule.searchList,
      search_name: rule.searchName,
      search_result: rule.searchResult,
      chapter_roads: rule.chapterRoads,
      chapter_result: rule.chapterResult,
      referer: rule.referer,
      user_agent: rule.userAgent,
      anti_crawler_config: JSON.stringify(rule.antiCrawlerConfig.toJSON()),
      use_webview: rule.useWebview ? 1 : 0,
      use_native_player: rule.useNativePlayer ? 1 : 0,
      use_post: rule.usePost ? 1 : 0,
      use_legacy_parser: rule.useLegacyParser ? 1 : 0,
      ad_blocker: rule.adBlocker ? 1 : 0,
      multi_sources: rule.multiSources ? 1 : 0,
      enabled: rule.enabled ? 1 : 0,
      raw_json: JSON.stringify(rule.toJSON()),
      created_at: now,
      updated_at: now
    };
    return await this.rdbManager.insert(RdbConstants.TABLE_RULE_SOURCE, values);
  }

  async update(rule: RuleSource): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.equalTo(RdbConstants.COL_ID, rule.id);
    const values: relationalStore.ValuesBucket = {
      api: rule.api,
      type: rule.type,
      name: rule.name,
      version: rule.version,
      base_url: rule.baseUrl,
      search_url: rule.searchURL,
      search_list: rule.searchList,
      search_name: rule.searchName,
      search_result: rule.searchResult,
      chapter_roads: rule.chapterRoads,
      chapter_result: rule.chapterResult,
      referer: rule.referer,
      user_agent: rule.userAgent,
      anti_crawler_config: JSON.stringify(rule.antiCrawlerConfig.toJSON()),
      use_webview: rule.useWebview ? 1 : 0,
      use_native_player: rule.useNativePlayer ? 1 : 0,
      use_post: rule.usePost ? 1 : 0,
      use_legacy_parser: rule.useLegacyParser ? 1 : 0,
      ad_blocker: rule.adBlocker ? 1 : 0,
      multi_sources: rule.multiSources ? 1 : 0,
      enabled: rule.enabled ? 1 : 0,
      raw_json: JSON.stringify(rule.toJSON()),
      updated_at: Date.now()
    };
    return await this.rdbManager.update(RdbConstants.TABLE_RULE_SOURCE, values, predicates);
  }

  async deleteById(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.equalTo(RdbConstants.COL_ID, id);
    return await this.rdbManager.delete(predicates);
  }

  async deleteLegacyGugu3Sources(): Promise<number> {
    const rules = await this.getAll();
    let deleted = 0;
    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      if (this.isLegacyGugu3Source(rule)) {
        deleted += await this.deleteById(rule.id);
      }
    }
    return deleted;
  }

  async setEnabled(id: number, enabled: boolean): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_RULE_SOURCE);
    predicates.equalTo(RdbConstants.COL_ID, id);
    const values: relationalStore.ValuesBucket = {
      enabled: enabled ? 1 : 0,
      updated_at: Date.now()
    };
    return await this.rdbManager.update(RdbConstants.TABLE_RULE_SOURCE, values, predicates);
  }

  async count(): Promise<number> {
    const sql = `SELECT COUNT(*) AS cnt FROM ${RdbConstants.TABLE_RULE_SOURCE}`;
    const resultSet = await this.rdbManager.querySql(sql);
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(0);
    }
    resultSet.close();
    return count;
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): RuleSource[] {
    const list: RuleSource[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const rule = new RuleSource();
          rule.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          rule.api = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_API));
          rule.type = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_TYPE));
          rule.name = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_NAME));
          rule.version = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_VERSION));
          rule.baseUrl = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_BASE_URL));
          rule.searchURL = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_SEARCH_URL));
          rule.searchList = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_SEARCH_LIST));
          rule.searchName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_SEARCH_NAME));
          rule.searchResult = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_SEARCH_RESULT));
          rule.chapterRoads = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_CHAPTER_ROADS));
          rule.chapterResult = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_CHAPTER_RESULT));
          rule.referer = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_REFERER));
          rule.userAgent = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_USER_AGENT));
          rule.useWebview = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_USE_WEBVIEW)) === 1;
          rule.useNativePlayer = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_USE_NATIVE_PLAYER)) === 1;
          rule.usePost = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_USE_POST)) === 1;
          rule.useLegacyParser = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_USE_LEGACY_PARSER)) === 1;
          rule.adBlocker = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_AD_BLOCKER)) === 1;
          rule.multiSources = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_MULTI_SOURCES)) === 1;
          rule.enabled = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ENABLED)) === 1;
          rule.createdAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_CREATED_AT));
          rule.updatedAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_UPDATED_AT));

          const antiCrawlJson = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANTI_CRAWLER_CONFIG));
          if (antiCrawlJson.length > 0) {
            try {
              const parsed = JSON.parse(antiCrawlJson) as Record<string, Object>;
              rule.antiCrawlerConfig = AntiCrawlerConfig.fromJSON(parsed);
            } catch (e) {
              rule.antiCrawlerConfig = new AntiCrawlerConfig();
            }
          }
          list.push(rule);
        } while (resultSet.goToNextRow());
      }
    } catch (err) {
      logger.error('parseResultSet error: %{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      resultSet.close();
    }
    return list;
  }

  private isLegacyGugu3Source(rule: RuleSource): boolean {
    const name = rule.name.toLowerCase();
    const baseUrl = rule.baseUrl.toLowerCase();
    const searchUrl = rule.searchURL.toLowerCase();
    return name.includes('gugu3') || baseUrl.includes('gugu3.com') || searchUrl.includes('gugu3.com');
  }
}
