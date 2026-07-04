import { relationalStore } from '@kit.ArkData';
import { RdbManager } from './RdbManager';
import { RdbConstants } from '../constants/RdbConstants';
import { LocalVideoRecord } from '../models/LocalVideoRecord';
import { Logger } from '../utils/Logger';

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

  async getByFileName(fileName: string): Promise<LocalVideoRecord | null> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_FILE_NAME, fileName);
    const resultSet = await this.rdbManager.query(predicates);
    const list = this.parseResultSet(resultSet);
    if (list.length > 0) {
      return list[0];
    }
    return null;
  }

  async upsert(record: LocalVideoRecord): Promise<number> {
    const existing = await this.getByFileName(record.fileName);
    if (existing !== null) {
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
      predicates.equalTo(RdbConstants.COL_FILE_NAME, record.fileName);
      const values: relationalStore.ValuesBucket = {
        file_uri: record.fileUri,
        file_size: record.fileSize,
        duration_ms: record.durationMs,
        position_ms: record.positionMs,
        last_played_at: Date.now(),
        danmaku_file_name: record.danmakuFileName,
        danmaku_uri: record.danmakuUri,
        danmaku_offset_ms: record.danmakuOffsetMs,
        danmaku_format: record.danmakuFormat,
        danmaku_count: record.danmakuCount
      };
      return await this.rdbManager.update(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values, predicates);
    } else {
      const values: relationalStore.ValuesBucket = {
        file_uri: record.fileUri,
        file_name: record.fileName,
        file_size: record.fileSize,
        duration_ms: record.durationMs,
        position_ms: record.positionMs,
        last_played_at: Date.now(),
        danmaku_file_name: record.danmakuFileName,
        danmaku_uri: record.danmakuUri,
        danmaku_offset_ms: record.danmakuOffsetMs,
        danmaku_format: record.danmakuFormat,
        danmaku_count: record.danmakuCount,
        created_at: Date.now()
      };
      return await this.rdbManager.insert(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY, values);
    }
  }

  async deleteById(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    predicates.equalTo(RdbConstants.COL_ID, id);
    return await this.rdbManager.delete(predicates);
  }

  async clearAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_LOCAL_VIDEO_HISTORY);
    return await this.rdbManager.delete(predicates);
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
          record.fileUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_URI));
          record.fileName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_FILE_NAME));
          record.fileSize = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_FILE_SIZE));
          record.durationMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DURATION_MS));
          record.positionMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_POSITION_MS));
          record.lastPlayedAt = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_LAST_PLAYED_AT));
          record.danmakuFileName = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_FILE_NAME));
          record.danmakuUri = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_URI));
          record.danmakuOffsetMs = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_OFFSET_MS));
          record.danmakuFormat = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_FORMAT));
          record.danmakuCount = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_DANMAKU_COUNT));
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
