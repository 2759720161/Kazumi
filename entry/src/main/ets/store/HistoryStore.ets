import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { HistoryRecord } from '../models/HistoryRecord';
import { Logger } from '../utils/Logger';

const logger = new Logger('HistoryStore');

export class HistoryStore {
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<HistoryRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.orderByDesc(RdbConstants.COL_UPDATED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async getByAnimeId(animeId: string): Promise<HistoryRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    return list.length > 0 ? list[0] : null;
  }

  async upsert(record: HistoryRecord): Promise<number> {
    const existing = await this.getByAnimeId(record.animeId);
    if (existing !== null) {
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
      predicates.equalTo(RdbConstants.COL_ANIME_ID, record.animeId);
      const values: relationalStore.ValuesBucket = {
        anime_name: record.animeName,
        anime_cover: record.animeCover,
        anime_url: record.animeUrl,
        source_id: record.sourceId,
        episode_name: record.episodeName,
        episode_url: record.episodeUrl,
        position_ms: record.positionMs,
        duration_ms: record.durationMs,
        updated_at: Date.now()
      };
      return await this.rdbManager.update(RdbConstants.TABLE_WATCH_HISTORY, values, predicates);
    } else {
      const values: relationalStore.ValuesBucket = {
        anime_id: record.animeId,
        anime_name: record.animeName,
        anime_cover: record.animeCover,
        anime_url: record.animeUrl,
        source_id: record.sourceId,
        episode_name: record.episodeName,
        episode_url: record.episodeUrl,
        position_ms: record.positionMs,
        duration_ms: record.durationMs,
        updated_at: Date.now()
      };
      return await this.rdbManager.insert(RdbConstants.TABLE_WATCH_HISTORY, values);
    }
  }

  async deleteByAnimeId(animeId: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    return await this.rdbManager.delete(predicates);
  }

  async clearAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    return await this.rdbManager.delete(predicates);
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): HistoryRecord[] {
    const list: HistoryRecord[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new HistoryRecord();
          record.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          record.animeId = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_ID));
          record.animeName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_NAME));
          record.animeCover = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_COVER));
          record.animeUrl = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_ANIME_URL));
          record.sourceId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_SOURCE_ID));
          record.episodeName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EPISODE_NAME));
          record.episodeUrl = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EPISODE_URL));
          record.positionMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS));
          record.durationMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS));
          record.updatedAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_UPDATED_AT));
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