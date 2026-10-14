import { relationalStore } from '@kit.ArkData'
import { RdbConstants } from '../constants/RdbConstants'
import { KazumiHistorySyncEvent } from '../services/KazumiHistorySyncProtocol'
import { RdbManager } from './RdbManager'

export class HistorySyncEventStore {
  private static writeQueue: Promise<void> = Promise.resolve()
  private rdbManager: RdbManager = RdbManager.getInstance()

  async append(event: KazumiHistorySyncEvent): Promise<void> {
    await this.enqueueWrite(async (): Promise<void> => {
      await this.writeEvent(event)
    })
  }

  async appendAll(events: KazumiHistorySyncEvent[]): Promise<void> {
    if (events.length === 0) return
    await this.enqueueWrite(async (): Promise<void> => {
      for (let i = 0; i < events.length; i++) {
        await this.writeEvent(events[i])
      }
    })
  }

  private async writeEvent(event: KazumiHistorySyncEvent): Promise<void> {
    await this.rdbManager.executeSql(
      `INSERT OR REPLACE INTO ${RdbConstants.TABLE_HISTORY_SYNC_EVENT} (` +
      `${RdbConstants.COL_EVENT_ID}, ${RdbConstants.COL_PAYLOAD}, ${RdbConstants.COL_UPDATED_AT}) VALUES (?, ?, ?)`,
      [event.eventId, JSON.stringify(event.toJSON()), event.updatedAt]
    )
  }

  async getAll(): Promise<KazumiHistorySyncEvent[]> {
    await HistorySyncEventStore.writeQueue
    const result: KazumiHistorySyncEvent[] = []
    const invalidEventIds: string[] = []
    const resultSet = await this.rdbManager.querySql(
      `SELECT ${RdbConstants.COL_EVENT_ID}, ${RdbConstants.COL_PAYLOAD} FROM ${RdbConstants.TABLE_HISTORY_SYNC_EVENT} ` +
      `ORDER BY ${RdbConstants.COL_UPDATED_AT} ASC, ${RdbConstants.COL_EVENT_ID} ASC`
    )
    try {
      if (resultSet.goToFirstRow()) {
        do {
          const text = resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_PAYLOAD))
          try {
            const event = KazumiHistorySyncEvent.fromJSON(JSON.parse(text) as Record<string, Object>)
            if (event !== null) {
              result.push(event)
            } else {
              invalidEventIds.push(resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EVENT_ID)))
            }
          } catch (_err) {
            invalidEventIds.push(resultSet.getString(resultSet.getColumnIndex(RdbConstants.COL_EVENT_ID)))
          }
        } while (resultSet.goToNextRow())
      }
    } finally {
      resultSet.close()
    }
    await this.deleteByIds(invalidEventIds)
    return result
  }

  async deleteByIds(eventIds: string[]): Promise<void> {
    if (eventIds.length === 0) return
    await this.enqueueWrite(async (): Promise<void> => {
      const chunkSize = 500
      for (let offset = 0; offset < eventIds.length; offset += chunkSize) {
        const chunk = eventIds.slice(offset, Math.min(offset + chunkSize, eventIds.length))
        const placeholders: string[] = []
        const args: relationalStore.ValueType[] = []
        for (let i = 0; i < chunk.length; i++) {
          placeholders.push('?')
          args.push(chunk[i])
        }
        await this.rdbManager.executeSql(
          `DELETE FROM ${RdbConstants.TABLE_HISTORY_SYNC_EVENT} WHERE ` +
          `${RdbConstants.COL_EVENT_ID} IN (${placeholders.join(',')})`, args)
      }
    })
  }

  private enqueueWrite(operation: () => Promise<void>): Promise<void> {
    const queued = HistorySyncEventStore.writeQueue.then(async (): Promise<void> => {
      await operation()
    })
    HistorySyncEventStore.writeQueue = queued.catch((_err: Error): void => {})
    return queued
  }
}
