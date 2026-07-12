import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { HistoryRecord } from '../models/HistoryRecord';
import { RuleSourceStore } from './RuleSourceStore';
import { DanmakuPlaybackBindingStore } from '../core/danmaku/DanmakuPlaybackBindingStore';
import { DanmakuCacheIndexStore } from '../core/danmaku/DanmakuCacheIndexStore';
import { Logger } from '../utils/Logger';

const logger = new Logger('HistoryStore');

export class HistoryStore {
  private rdbManager: RdbManager;
  private ruleSourceStore: RuleSourceStore;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
    this.ruleSourceStore = new RuleSourceStore();
  }

  async getAll(): Promise<HistoryRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.orderByDesc(RdbConstants.COL_UPDATED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    const records = this.parseResultSet(resultSet);
    await this.fillSourceNames(records);
    return records;
  }

  async getByAnimeId(animeId: string): Promise<HistoryRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    if (list.length > 0) {
      await this.fillSourceNames(list);
      return list[0];
    }
    return null;
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
        bangumi_id: record.bangumiId,
        source_id: record.sourceId,
        source_name: record.sourceName,
        episode_name: record.episodeName,
        episode_url: record.episodeUrl,
        position_ms: record.positionMs,
        duration_ms: record.durationMs,
        road_index: record.roadIndex,
        episode_index: record.episodeIndex,
        updated_at: Date.now()
      };
      return await this.rdbManager.update(RdbConstants.TABLE_WATCH_HISTORY, values, predicates);
    } else {
      const values: relationalStore.ValuesBucket = {
        anime_id: record.animeId,
        anime_name: record.animeName,
        anime_cover: record.animeCover,
        anime_url: record.animeUrl,
        bangumi_id: record.bangumiId,
        source_id: record.sourceId,
        source_name: record.sourceName,
        episode_name: record.episodeName,
        episode_url: record.episodeUrl,
        position_ms: record.positionMs,
        duration_ms: record.durationMs,
        road_index: record.roadIndex,
        episode_index: record.episodeIndex,
        updated_at: Date.now()
      };
      return await this.rdbManager.insert(RdbConstants.TABLE_WATCH_HISTORY, values);
    }
  }

  async upsertPreservingUpdatedAt(record: HistoryRecord): Promise<number> {
    const existing = await this.getByAnimeId(record.animeId);
    const updatedAt = record.updatedAt > 0 ? record.updatedAt : Date.now();
    if (existing !== null) {
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
      predicates.equalTo(RdbConstants.COL_ANIME_ID, record.animeId);
      const values: relationalStore.ValuesBucket = {
        anime_name: record.animeName,
        anime_cover: record.animeCover,
        anime_url: record.animeUrl,
        bangumi_id: record.bangumiId,
        source_id: record.sourceId,
        source_name: record.sourceName,
        episode_name: record.episodeName,
        episode_url: record.episodeUrl,
        position_ms: record.positionMs,
        duration_ms: record.durationMs,
        road_index: record.roadIndex,
        episode_index: record.episodeIndex,
        updated_at: updatedAt
      };
      return await this.rdbManager.update(RdbConstants.TABLE_WATCH_HISTORY, values, predicates);
    } else {
      const values: relationalStore.ValuesBucket = {
        anime_id: record.animeId,
        anime_name: record.animeName,
        anime_cover: record.animeCover,
        anime_url: record.animeUrl,
        bangumi_id: record.bangumiId,
        source_id: record.sourceId,
        source_name: record.sourceName,
        episode_name: record.episodeName,
        episode_url: record.episodeUrl,
        position_ms: record.positionMs,
        duration_ms: record.durationMs,
        road_index: record.roadIndex,
        episode_index: record.episodeIndex,
        updated_at: updatedAt
      };
      return await this.rdbManager.insert(RdbConstants.TABLE_WATCH_HISTORY, values);
    }
  }

  async replaceAnimeId(oldAnimeId: string, record: HistoryRecord): Promise<number> {
    if (oldAnimeId.length === 0 || oldAnimeId === record.animeId) {
      return await this.upsertPreservingUpdatedAt(record);
    }

    const existingNew: HistoryRecord | null = await this.getByAnimeId(record.animeId);
    if (existingNew !== null) {
      const merged: HistoryRecord = this.mergeDuplicateRecord(
        record.updatedAt >= existingNew.updatedAt ? record : existingNew,
        record.updatedAt >= existingNew.updatedAt ? existingNew : record
      );
      merged.animeId = record.animeId;
      const result = await this.upsertPreservingUpdatedAt(merged);
      await this.deleteByAnimeId(oldAnimeId);
      return result;
    }

    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, oldAnimeId);
    const values: relationalStore.ValuesBucket = {
      anime_id: record.animeId,
      anime_name: record.animeName,
      anime_cover: record.animeCover,
      anime_url: record.animeUrl,
      bangumi_id: record.bangumiId,
      source_id: record.sourceId,
      source_name: record.sourceName,
      episode_name: record.episodeName,
      episode_url: record.episodeUrl,
      position_ms: record.positionMs,
      duration_ms: record.durationMs,
      road_index: record.roadIndex,
      episode_index: record.episodeIndex,
      updated_at: record.updatedAt > 0 ? record.updatedAt : Date.now()
    };
    const updated = await this.rdbManager.update(RdbConstants.TABLE_WATCH_HISTORY, values, predicates);
    if (updated > 0) {
      return updated;
    }
    return await this.upsertPreservingUpdatedAt(record);
  }

  async deleteByAnimeId(animeId: string): Promise<number> {
    const record: HistoryRecord | null = await this.getByAnimeId(animeId)
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_WATCH_HISTORY);
    predicates.equalTo(RdbConstants.COL_ANIME_ID, animeId);
    const result = await this.rdbManager.delete(predicates);
    if (record !== null) {
      try {
        await DanmakuPlaybackBindingStore.getInstance().clearBindingByPlaybackRecord(record.sourceId, record.episodeUrl)
      } catch (_err) {
        logger.warn('清理弹幕绑定失败: animeId=%{public}s', animeId)
      }
      try {
        await DanmakuCacheIndexStore.getInstance().clearCacheIndexByPlaybackRecord(record.sourceId, record.episodeUrl)
      } catch (_err) {
        logger.warn('清理弹幕缓存索引失败: animeId=%{public}s', animeId)
      }
    }
    return result
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
          record.bangumiId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_BANGUMI_ID));
          record.sourceId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_SOURCE_ID));
          record.sourceName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_SOURCE_NAME));
          record.episodeName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EPISODE_NAME));
          record.episodeUrl = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EPISODE_URL));
          record.positionMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS));
          record.durationMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS));
          record.roadIndex = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ROAD_INDEX));
          record.episodeIndex = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_EPISODE_INDEX));
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

  private async fillSourceNames(records: HistoryRecord[]): Promise<void> {
    if (records.length === 0) {
      return;
    }
    const sourceIdSet: Set<number> = new Set();
    for (let i = 0; i < records.length; i++) {
      if (records[i].sourceId >= 0) {
        sourceIdSet.add(records[i].sourceId);
      }
    }
    if (sourceIdSet.size === 0) {
      return;
    }
    const nameMap: Map<number, string> = new Map();
    const ids = Array.from(sourceIdSet);
    for (let i = 0; i < ids.length; i++) {
      try {
        const rule = await this.ruleSourceStore.getById(ids[i]);
        if (rule !== null) {
          nameMap.set(ids[i], rule.name);
        }
      } catch (_err) {
        continue;
      }
    }
    for (let i = 0; i < records.length; i++) {
      const name = nameMap.get(records[i].sourceId);
      if (name !== undefined) {
        records[i].sourceName = name;
      }
    }
  }

  private mergeDuplicateRecord(primary: HistoryRecord, fallback: HistoryRecord): HistoryRecord {
    if (primary.animeName.length === 0) {
      primary.animeName = fallback.animeName;
    }
    if (primary.animeCover.length === 0) {
      primary.animeCover = fallback.animeCover;
    }
    if (primary.animeUrl.length === 0) {
      primary.animeUrl = fallback.animeUrl;
    }
    if (primary.bangumiId <= 0) {
      primary.bangumiId = fallback.bangumiId;
    }
    if (primary.sourceId < 0) {
      primary.sourceId = fallback.sourceId;
    }
    if (primary.sourceName.length === 0) {
      primary.sourceName = fallback.sourceName;
    }
    if (primary.episodeName.length === 0) {
      primary.episodeName = fallback.episodeName;
    }
    if (primary.episodeUrl.length === 0) {
      primary.episodeUrl = fallback.episodeUrl;
    }
    if (primary.positionMs <= 0) {
      primary.positionMs = fallback.positionMs;
    }
    if (primary.durationMs <= 0) {
      primary.durationMs = fallback.durationMs;
    }
    if (primary.roadIndex < 0) {
      primary.roadIndex = fallback.roadIndex;
    }
    if (primary.episodeIndex < 0) {
      primary.episodeIndex = fallback.episodeIndex;
    }
    return primary;
  }
}
