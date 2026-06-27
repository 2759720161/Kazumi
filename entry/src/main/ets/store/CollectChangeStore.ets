import { relationalStore } from '@kit.ArkData'
import { RdbManager } from './RdbManager'
import { RdbConstants } from '../constants/RdbConstants'
import { CollectChangeRecord } from '../models/CollectChangeRecord'
import { Logger } from '../utils/Logger'

const logger = new Logger('CollectChangeStore')

/**
 * [FROZEN] 冻结声明：当前仅做本地追番、不做同步，collect_change 无业务价值。
 * 禁止围绕此 Store 开发新功能。保留此 Store 仅为数据完整性，不得新增调用点。
 */
export class CollectChangeStore {
  private rdbManager: RdbManager

  constructor() {
    this.rdbManager = RdbManager.getInstance()
  }

  async appendChange(bangumiId: number, action: number, type: number): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      id: Math.floor(Date.now() / 1000),
      bangumi_id: bangumiId,
      action: action,
      type: type,
      timestamp: Math.floor(Date.now() / 1000)
    }
    await this.rdbManager.insert(RdbConstants.TABLE_COLLECT_CHANGE, values)
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