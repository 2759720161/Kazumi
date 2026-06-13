import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { FavoriteRecord } from '../models/FavoriteRecord';
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
}