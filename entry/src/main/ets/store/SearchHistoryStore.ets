import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { SearchHistory } from '../models/SearchHistory';
import { Logger } from '../utils/Logger';

const logger = new Logger('SearchHistoryStore');

const MAX_SEARCH_HISTORY: number = 50;

export class SearchHistoryStore {
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<SearchHistory[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_SEARCH_HISTORY);
    predicates.orderByDesc(RdbConstants.COL_TIMESTAMP);
    predicates.limitAs(MAX_SEARCH_HISTORY);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async add(keyword: string): Promise<void> {
    const trimmed = keyword.trim();
    if (trimmed.length === 0) {
      return;
    }
    const existing = await this.getByKeyword(trimmed);
    if (existing !== null) {
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_SEARCH_HISTORY);
      predicates.equalTo(RdbConstants.COL_KEYWORD, trimmed);
      const values: relationalStore.ValuesBucket = {
        timestamp: Date.now()
      };
      await this.rdbManager.update(RdbConstants.TABLE_SEARCH_HISTORY, values, predicates);
    } else {
      const values: relationalStore.ValuesBucket = {
        keyword: trimmed,
        timestamp: Date.now()
      };
      await this.rdbManager.insert(RdbConstants.TABLE_SEARCH_HISTORY, values);
    }
  }

  async deleteByKeyword(keyword: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_SEARCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_KEYWORD, keyword);
    await this.rdbManager.delete(predicates);
  }

  async clearAll(): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_SEARCH_HISTORY);
    await this.rdbManager.delete(predicates);
  }

  private async getByKeyword(keyword: string): Promise<SearchHistory | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_SEARCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_KEYWORD, keyword);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    return list.length > 0 ? list[0] : null;
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): SearchHistory[] {
    const list: SearchHistory[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new SearchHistory();
          record.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          record.keyword = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_KEYWORD));
          record.timestamp = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_TIMESTAMP));
          list.push(record);
        } while (resultSet.goToNextRow());
      }
    } catch (err) {
      logger.error('parseResultSet error: %{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      resultSet.close();
    }
    return list;
  }
}