import { relationalStore } from '@kit.ArkData'
import { RdbManager } from './RdbManager'
import { RdbConstants } from '../constants/RdbConstants'
import { CollectChangeRecord } from '../models/CollectChangeRecord'
import { Logger } from '../utils/Logger'

const logger = new Logger('CollectChangeStore')

export class CollectChangeStore {
  private rdbManager: RdbManager

  constructor() {
    this.rdbManager = RdbManager.getInstance()
  }

  async appendChange(bangumiId: number, action: number, type: number): Promise<CollectChangeRecord> {
    const existing = await this.getAllChanges()
    let maxId = 0
    for (let i = 0; i < existing.length; i++) {
      maxId = Math.max(maxId, existing[i].id)
    }
    const timestamp = Math.floor(Date.now() / 1000)
    const id = Math.max(timestamp, maxId + 1)
    const values: relationalStore.ValuesBucket = {
      id: id,
      bangumi_id: bangumiId,
      action: action,
      type: type,
      timestamp: timestamp
    }
    await this.rdbManager.insert(RdbConstants.TABLE_COLLECT_CHANGE, values)
    const record = new CollectChangeRecord()
    record.id = id
    record.bangumiId = bangumiId
    record.action = action
    record.type = type
    record.timestamp = timestamp
    return record
  }

  async getAllChanges(): Promise<CollectChangeRecord[]> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_COLLECT_CHANGE)
    predicates.orderByDesc(RdbConstants.COL_TIMESTAMP)
    const resultSet = await this.rdbManager.query(predicates)
    return this.parseResultSet(resultSet)
  }

  async clearChanges(): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_COLLECT_CHANGE)
    await this.rdbManager.delete(predicates)
  }

  async replaceAllChanges(records: CollectChangeRecord[]): Promise<void> {
    this.rdbManager.beginTransaction()
    try {
      const predicates = new relationalStore.RdbPredicates(RdbConstants.TABLE_COLLECT_CHANGE)
      await this.rdbManager.delete(predicates)
      for (let i = 0; i < records.length; i++) {
        const record = records[i]
        const values: relationalStore.ValuesBucket = {
          id: record.id,
          bangumi_id: record.bangumiId,
          action: record.action,
          type: record.type,
          timestamp: record.timestamp
        }
        await this.rdbManager.insert(RdbConstants.TABLE_COLLECT_CHANGE, values)
      }
      this.rdbManager.commit()
    } catch (err) {
      this.rdbManager.rollBack()
      throw new Error(err instanceof Error ? err.message : String(err))
    }
  }

  private parseResultSet(resultSet: relationalStore.ResultSet): CollectChangeRecord[] {
    const list: CollectChangeRecord[] = []
    if (resultSet.rowCount === 0) {
      resultSet.close()
      return list
    }
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const record = new CollectChangeRecord()
          record.id = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ID))
          record.bangumiId = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_BANGUMI_ID))
          record.action = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_ACTION))
          record.type = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_TYPE))
          record.timestamp = resultSet.getLong(resultSet.getColumnIndex(RdbConstants.COL_TIMESTAMP))
          list.push(record)
        } while (resultSet.goToNextRow())
      }
    } catch (err) {
      logger.error('parseResultSet error: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      resultSet.close()
    }
    return list
  }
}
