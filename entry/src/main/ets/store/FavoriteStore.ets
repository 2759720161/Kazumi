import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { FavoriteRecord } from '../models/FavoriteRecord';
import { CollectedBangumi } from '../models/CollectedBangumi';
import { CollectType } from '../models/CollectType';
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
    predicates.equalTo(RdbConstants.COL_COLLECT_TYPE, CollectType.normalize(collectType));
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
    const type = CollectType.normalize(resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_COLLECT_TYPE)));
    resultSet.close();
    return type;
  }

  async getCollectedByAnimeId(animeId: string): Promise<CollectedBangumi | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    const resultSet = await this.rdbManager.query(predicates);
    const items = this.parseCollectedResultSet(resultSet);
    return items.length > 0 ? items[0] : null;
  }

  async getCollectedByBangumiId(bangumiId: number): Promise<CollectedBangumi | null> {
    if (bangumiId <= 0) {
      return null;
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_BANGUMI_ID, bangumiId);
    predicates.orderByDesc(RdbConstants.COL_CREATED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    const items = this.parseCollectedResultSet(resultSet);
    return items.length > 0 ? items[0] : null;
  }

  async replaceSyncedCollectibles(incoming: CollectedBangumi[]): Promise<void> {
    const local = await this.getAllCollected();
    const incomingByBangumiId: Map<number, CollectedBangumi> = new Map<number, CollectedBangumi>();
    for (let i = 0; i < incoming.length; i++) {
      if (incoming[i].bangumiId > 0) {
        incomingByBangumiId.set(incoming[i].bangumiId, incoming[i]);
      }
    }
    const applied: Set<number> = new Set<number>();
    this.rdbManager.beginTransaction();
    try {
      for (let i = 0; i < local.length; i++) {
        const localItem = local[i];
        if (localItem.bangumiId <= 0) {
          continue;
        }
        const synced = incomingByBangumiId.get(localItem.bangumiId);
        if (synced === undefined || applied.has(localItem.bangumiId)) {
          await this.remove(localItem.animeId);
          continue;
        }
        const merged = this.mergeSyncedWithLocalSource(synced, localItem);
        await this.updateCollected(localItem.animeId, merged);
        applied.add(localItem.bangumiId);
      }

      const incomingIds: number[] = [];
      incomingByBangumiId.forEach((_item: CollectedBangumi, bangumiId: number) => {
        incomingIds.push(bangumiId);
      });
      for (let i = 0; i < incomingIds.length; i++) {
        const bangumiId = incomingIds[i];
        if (applied.has(bangumiId)) {
          continue;
        }
        const item = incomingByBangumiId.get(bangumiId);
        if (item !== undefined) {
          await this.addCollected(item);
          applied.add(bangumiId);
        }
      }
      this.rdbManager.commit();
    } catch (err) {
      this.rdbManager.rollBack();
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  private async updateCollected(animeId: string, item: CollectedBangumi): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      anime_name: item.animeName,
      anime_cover: item.animeCover,
      anime_desc: item.animeDesc,
      anime_url: item.animeUrl,
      name: item.sourceName,
      source_id: item.sourceId,
      collect_type: CollectType.normalize(item.collectType),
      bangumi_id: item.bangumiId,
      bangumi_cover: item.bangumiCover,
      cover_fallback: item.coverFallback,
      created_at: item.createdAt
    };
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_FAVORITE);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    return await this.rdbManager.update(RdbConstants.TABLE_FAVORITE, values, predicates);
  }

  private mergeSyncedWithLocalSource(synced: CollectedBangumi, local: CollectedBangumi): CollectedBangumi {
    const item = new CollectedBangumi();
    item.animeId = local.animeId.length > 0 ? local.animeId : synced.animeId;
    item.bangumiId = synced.bangumiId;
    item.animeName = synced.animeName.length > 0 ? synced.animeName : local.animeName;
    item.animeCover = synced.animeCover.length > 0 ? synced.animeCover : local.animeCover;
    item.bangumiCover = synced.bangumiCover.length > 0 ? synced.bangumiCover : local.bangumiCover;
    item.coverFallback = synced.coverFallback.length > 0 ? synced.coverFallback : local.coverFallback;
    item.animeDesc = synced.animeDesc.length > 0 ? synced.animeDesc : local.animeDesc;
    item.animeUrl = local.animeUrl.length > 0 ? local.animeUrl : synced.animeUrl;
    item.sourceName = local.sourceName;
    item.sourceId = local.sourceId;
    item.collectType = CollectType.normalize(synced.collectType);
    item.createdAt = synced.createdAt > 0 ? synced.createdAt : local.createdAt;
    return item;
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
          item.collectType = CollectType.normalize(resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_COLLECT_TYPE)));
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
            const ctype = CollectType.normalize(resultSet.getLong(1))
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
