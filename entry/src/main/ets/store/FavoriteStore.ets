import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { FavoriteRecord } from '../models/FavoriteRecord';
import { CollectedBangumi } from '../models/CollectedBangumi';
import { Logger } from '../utils/Logger';

const logger = new Logger('FavoriteStore');

export class FavoriteStore {
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<FavoriteRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.orderByDesc(RdbConstants.COL_CREATED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async isFavorite(animeId: string): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    const resultSet = await this.rdbManager.query(predicates);
    const count = resultSet.rowCount;
    resultSet.close();
    return count > 0;
  }

  /**
   * @deprecated 已被 FavoriteStore.addCollected() 替代。
   * 新代码应使用 CollectController.addCollect()，内部调用 addCollected()。
   * 保留此方法仅为兼容，不得在新功能中调用。
   */

  async add(record: FavoriteRecord): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      anime_id: record.animeId,
      anime_name: record.animeName,
      anime_cover: record.animeCover,
      anime_desc: record.animeDesc,
      anime_url: record.animeUrl,
      name: record.sourceName,
      source_id: record.sourceId,
      created_at: Date.now()
    };
    return await this.rdbManager.insert(RdbConstants.TABLE_FAVORITE, values);
  }

  async remove(animeId: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    return await this.rdbManager.delete(predicates);
  }

  async getAllCollected(): Promise<CollectedBangumi[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.orderByDesc(RdbConstants.COL_CREATED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseCollectedResultSet(resultSet);
  }

  async getByType(collectType: number): Promise<CollectedBangumi[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_COLLECT_TYPE, collectType);
    predicates.orderByDesc(RdbConstants.COL_CREATED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseCollectedResultSet(resultSet);
  }

  async addCollected(item: CollectedBangumi): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      anime_id: item.animeId,
      anime_name: item.animeName,
      anime_cover: item.animeCover,
      anime_desc: item.animeDesc,
      anime_url: item.animeUrl,
      name: item.sourceName,
      source_id: item.sourceId,
      collect_type: item.collectType,
      bangumi_id: item.bangumiId,
      bangumi_cover: item.bangumiCover,
      cover_fallback: item.coverFallback,
      created_at: item.createdAt > 0 ? item.createdAt : Date.now()
    };
    return await this.rdbManager.insert(RdbConstants.TABLE_FAVORITE, values);
  }

  async updateCollectType(animeId: string, collectType: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      collect_type: collectType,
      created_at: Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    return await this.rdbManager.update(RdbConstants.TABLE_FAVORITE, values, predicates);
  }

  async getCollectType(animeId: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    const resultSet = await this.rdbManager.query(predicates);
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return 0;
    }
    resultSet.goToFirstRow();
    const type = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_COLLECT_TYPE));
    resultSet.close();
    return type;
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): FavoriteRecord[] {
    const list: FavoriteRecord[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new FavoriteRecord();
          record.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          record.animeId = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_ID));
          record.animeName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_NAME));
          record.animeCover = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_COVER));
          record.animeDesc = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_DESC));
          record.animeUrl = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_URL));
          record.sourceName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_NAME));
          record.sourceId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_SOURCE_ID));
          record.createdAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_CREATED_AT));
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

  private parseCollectedResultSet(resultSet: relationalStore.ResultSet): CollectedBangumi[] {
    const list: CollectedBangumi[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const item = new CollectedBangumi();
          item.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          item.animeId = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_ID));
          item.animeName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_NAME));
          item.animeCover = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_COVER));
          item.animeDesc = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_DESC));
          item.animeUrl = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_URL));
          item.sourceName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_NAME));
          item.sourceId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_SOURCE_ID));
          item.collectType = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_COLLECT_TYPE));
          item.bangumiId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_BANGUMI_ID));
          item.bangumiCover = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_BANGUMI_COVER));
          item.coverFallback = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_COVER_FALLBACK));
          item.createdAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_CREATED_AT));
          list.push(item);
        } while (resultSet.goToNextRow());
      }
    } catch (err) {
      logger.error('parseCollectedResultSet error: %{public}s', err instanceof Error ? err.message : String(err));
    } finally {
      resultSet.close();
    }
    return list;
  }

  async getCollectTypeMap(animeIds: string[]): Promise<Map<string, number>> {
    const result = new Map<string, number>()
    if (animeIds.length === 0) return result

    const batchSize = 500
    for (let batchStart = 0; batchStart < animeIds.length; batchStart += batchSize) {
      const batchEnd = Math.min(batchStart + batchSize, animeIds.length)
      const placeholders: string[] = []
      const args: relationalStore.ValueType[] = []
      for (let i = batchStart; i < batchEnd; i++) {
        placeholders.push('?')
        args.push(animeIds[i])
      }
      const sql = `SELECT anime_id, collect_type FROM ${RdbConstants.TABLE_FAVORITE} WHERE anime_id IN (${placeholders.join(',')})`
      try {
        const store = this.rdbManager.getStore()
        const resultSet = await store.querySql(sql, args)
        if (resultSet.rowCount > 0 && resultSet.goToFirstRow()) {
          do {
            const aid = resultSet.getString(0)
            const ctype = resultSet.getLong(1)
            result.set(aid, ctype)
          } while (resultSet.goToNextRow())
        }
        resultSet.close()
      } catch (err) {
        logger.error('getCollectTypeMap batch query failed: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    return result
  }
}