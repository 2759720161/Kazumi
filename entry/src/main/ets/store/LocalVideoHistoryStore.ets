import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { LocalVideoRecord } from '../models/LocalVideoRecord';
import { Logger } from '../utils/Logger';
import { LocalVideoHistoryChangeSignal } from './LocalVideoHistoryChangeSignal';

const logger = new Logger('LocalVideoHistoryStore');

export class LocalVideoHistoryStore {
  private rdbManager: RdbManager;

  constructor() {
    this.rdbManager = RdbManager.getInstance();
  }

  async getAll(): Promise<LocalVideoRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.orderByDesc(RdbConstants.COL_LAST_PLAYED_AT);
    const resultSet = await this.rdbManager.query(predicates);
    return this.parseResultSet(resultSet);
  }

  async getByFileKey(fileKey: string): Promise<LocalVideoRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, fileKey);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    if (list.length > 0) {
      return list[0];
    }
    return null;
  }

  async upsert(record: LocalVideoRecord): Promise<number> {
    const fileKey = this.buildFileKey(record);
    record.fileKey = fileKey;
    const existing = await this.getByFileKey(fileKey);
    if (existing !== null) {
      if (record.positionMs <= 0 && existing.positionMs > 0) {
        record.positionMs = existing.positionMs;
      }
      if (record.durationMs <= 0 && existing.durationMs > 0) {
        record.durationMs = existing.durationMs;
      }
      if (record.coverUri.length === 0 && existing.coverUri.length > 0) {
        record.coverUri = existing.coverUri;
      }
      if (record.danmakuFileName.length === 0 && record.danmakuUri.length === 0 && existing.danmakuUri.length > 0) {
        record.danmakuFileName = existing.danmakuFileName;
        record.danmakuUri = existing.danmakuUri;
        record.danmakuOffsetMs = existing.danmakuOffsetMs;
        record.danmakuFormat = existing.danmakuFormat;
        record.danmakuCount = existing.danmakuCount;
      }
      if (record.drmOfflineKeyId.length === 0 && existing.drmOfflineKeyId.length > 0) {
        record.drmScheme = existing.drmScheme;
        record.drmPluginName = existing.drmPluginName;
        record.drmOfflineKeyId = existing.drmOfflineKeyId;
      }
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
      predicates.equalTo(RdbConstants.COL_FILE_KEY, fileKey);
      const values: relationalStore.ValuesBucket = {
        file_key: fileKey,
        file_uri: record.fileUri,
        file_name: record.fileName,
        file_size: record.fileSize,
        cover_uri: record.coverUri,
        duration_ms: record.durationMs,
        position_ms: record.positionMs,
        last_played_at: Date.now(),
        danmaku_file_name: record.danmakuFileName,
        danmaku_uri: record.danmakuUri,
        danmaku_offset_ms: record.danmakuOffsetMs,
        danmaku_format: record.danmakuFormat,
        danmaku_count: record.danmakuCount,
        drm_scheme: record.drmScheme,
        drm_plugin_name: record.drmPluginName,
        drm_offline_key_id: record.drmOfflineKeyId
      };
      const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
      LocalVideoHistoryChangeSignal.notifyChanged();
      return rows;
    } else {
      const values: relationalStore.ValuesBucket = {
        file_key: fileKey,
        file_uri: record.fileUri,
        file_name: record.fileName,
        file_size: record.fileSize,
        cover_uri: record.coverUri,
        duration_ms: record.durationMs,
        position_ms: record.positionMs,
        last_played_at: Date.now(),
        danmaku_file_name: record.danmakuFileName,
        danmaku_uri: record.danmakuUri,
        danmaku_offset_ms: record.danmakuOffsetMs,
        danmaku_format: record.danmakuFormat,
        danmaku_count: record.danmakuCount,
        drm_scheme: record.drmScheme,
        drm_plugin_name: record.drmPluginName,
        drm_offline_key_id: record.drmOfflineKeyId,
        created_at: Date.now()
      };
      const id = await this.rdbManager.insert(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values);
      LocalVideoHistoryChangeSignal.notifyChanged();
      return id;
    }
  }

  async deleteById(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_ID, id);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async deleteByIds(ids: number[]): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.in(RdbConstants.COL_ID, ids);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async updateCoverUri(fileKey: string, coverUri: string): Promise<number> {
    if (fileKey.length === 0 || coverUri.length === 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_KEY, fileKey);
    const values: relationalStore.ValuesBucket = {
      cover_uri: coverUri
    };
    const rows = await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  async clearAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    const rows = await this.rdbManager.delete(predicates);
    if (rows > 0) {
      LocalVideoHistoryChangeSignal.notifyChanged();
    }
    return rows;
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): LocalVideoRecord[] {
    const list: LocalVideoRecord[] = [];
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return list;
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new LocalVideoRecord();
          record.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID));
          record.fileKey = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_KEY));
          record.fileUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_URI));
          record.fileName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_NAME));
          record.fileSize = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_FILE_SIZE));
          record.coverUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_COVER_URI));
          record.durationMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS));
          record.positionMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS));
          record.lastPlayedAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_LAST_PLAYED_AT));
          record.danmakuFileName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_FILE_NAME));
          record.danmakuUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_URI));
          record.danmakuOffsetMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_OFFSET_MS));
          record.danmakuFormat = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_FORMAT));
          record.danmakuCount = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_COUNT));
          record.drmScheme = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DRM_SCHEME));
          record.drmPluginName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DRM_PLUGIN_NAME));
          record.drmOfflineKeyId = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DRM_OFFLINE_KEY_ID));
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

  private buildFileKey(record: LocalVideoRecord): string {
    if (record.fileKey.length > 0) {
      return record.fileKey;
    }
    if (record.fileUri.length > 0) {
      return `${record.fileUri}|${record.fileSize}|${record.fileName}`;
    }
    return `${record.fileName}|${record.fileSize}|${record.durationMs}`;
  }
}
