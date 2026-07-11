import { HistoryRecord } from '../models/HistoryRecord'
import { HistoryStore } from '../store/HistoryStore'
import { PreferencesStore } from '../store/PreferencesStore'
import { WebDavClient, WebDavConfig } from '../network/WebDavClient'
import { Logger } from '../utils/Logger'
import { ADVANCED_OPTIONS_UNLOCKED_KEY } from '../utils/AdvancedOptionsUnlock'

const logger = new Logger('HistorySyncService')

export const WEBDAV_SYNC_ENABLED_KEY: string = 'webdav_sync_enabled'
export const WEBDAV_SYNC_AUTO_KEY: string = 'webdav_sync_auto'
export const WEBDAV_SYNC_SERVER_URL_KEY: string = 'webdav_sync_server_url'
export const WEBDAV_SYNC_USERNAME_KEY: string = 'webdav_sync_username'
export const WEBDAV_SYNC_PASSWORD_KEY: string = 'webdav_sync_password'
export const WEBDAV_SYNC_REMOTE_DIR_KEY: string = 'webdav_sync_remote_dir'
export const WEBDAV_SYNC_LAST_TIME_KEY: string = 'webdav_sync_last_time'
const WEBDAV_SYNC_DELETED_KEY: string = 'webdav_sync_deleted_history'
const HISTORY_FILE_NAME: string = 'watch_history.json'
const AUTO_UPLOAD_DELAY_MS: number = 15000

export class HistorySyncDeletedItem {
  animeId: string = ''
  deletedAt: number = 0
}

export class HistorySyncPayload {
  schemaVersion: number = 1
  app: string = 'FanPlayer-HarmonyOS'
  updatedAt: number = 0
  records: HistoryRecord[] = []
  deleted: HistorySyncDeletedItem[] = []
}

export class HistorySyncResult {
  success: boolean = false
  message: string = ''
  localCount: number = 0
  remoteCount: number = 0
  mergedCount: number = 0
}

export class HistorySyncService {
  private static sharedInstance: HistorySyncService = new HistorySyncService()
  private historyStore: HistoryStore = new HistoryStore()
  private autoUploadTimer: number = -1
  private autoUploadRunning: boolean = false
  private autoUploadPending: boolean = false

  static getInstance(): HistorySyncService {
    return HistorySyncService.sharedInstance
  }

  async getConfig(): Promise<WebDavConfig> {
    const prefs = PreferencesStore.getInstance()
    const config = new WebDavConfig()
    config.enabled = await prefs.getBoolean(WEBDAV_SYNC_ENABLED_KEY, false)
    config.autoSync = await prefs.getBoolean(WEBDAV_SYNC_AUTO_KEY, false)
    config.serverUrl = await prefs.getString(WEBDAV_SYNC_SERVER_URL_KEY, '')
    config.username = await prefs.getString(WEBDAV_SYNC_USERNAME_KEY, '')
    config.password = await prefs.getString(WEBDAV_SYNC_PASSWORD_KEY, '')
    config.remoteDir = await prefs.getString(WEBDAV_SYNC_REMOTE_DIR_KEY, '/FanPlayer/')
    if (config.remoteDir === '/kazumi/' || config.remoteDir === 'kazumi' || config.remoteDir === '/kazumi') {
      config.remoteDir = '/FanPlayer/'
      await prefs.setString(WEBDAV_SYNC_REMOTE_DIR_KEY, config.remoteDir)
    }
    return config
  }

  async saveConfig(config: WebDavConfig): Promise<void> {
    const prefs = PreferencesStore.getInstance()
    await prefs.setBoolean(WEBDAV_SYNC_ENABLED_KEY, config.enabled)
    await prefs.setBoolean(WEBDAV_SYNC_AUTO_KEY, config.autoSync)
    await prefs.setString(WEBDAV_SYNC_SERVER_URL_KEY, config.serverUrl.trim())
    await prefs.setString(WEBDAV_SYNC_USERNAME_KEY, config.username)
    await prefs.setString(WEBDAV_SYNC_PASSWORD_KEY, config.password)
    await prefs.setString(WEBDAV_SYNC_REMOTE_DIR_KEY, this.normalizeRemoteDir(config.remoteDir))
  }

  async testConnection(config?: WebDavConfig): Promise<void> {
    await this.ensureWebDavFeatureUnlocked()
    const actual = config !== undefined ? config : await this.getConfig()
    this.validateConfig(actual)
    const ok = await new WebDavClient(actual).testConnection()
    if (!ok) {
      throw new Error('WebDAV 连接失败，请检查地址和账号')
    }
  }

  async syncNow(): Promise<HistorySyncResult> {
    await this.ensureWebDavFeatureUnlocked()
    const config = await this.getConfig()
    this.validateConfig(config)
    const client = new WebDavClient(config)
    const localPayload = await this.buildLocalPayload()
    const remoteText = await client.downloadText(HISTORY_FILE_NAME)
    const remotePayload = this.parsePayload(remoteText)
    const mergedPayload = this.mergePayloads(localPayload, remotePayload)

    await this.applyMergedPayload(mergedPayload)
    mergedPayload.updatedAt = Date.now()
    await client.uploadText(HISTORY_FILE_NAME, JSON.stringify(this.payloadToJSON(mergedPayload)))
    await this.saveDeletedItems(mergedPayload.deleted)
    await PreferencesStore.getInstance().setNumber(WEBDAV_SYNC_LAST_TIME_KEY, mergedPayload.updatedAt)

    const result = new HistorySyncResult()
    result.success = true
    result.message = '同步完成'
    result.localCount = localPayload.records.length
    result.remoteCount = remotePayload.records.length
    result.mergedCount = mergedPayload.records.length
    return result
  }

  scheduleAutoUploadAfterLocalChange(delayMs: number = AUTO_UPLOAD_DELAY_MS): void {
    this.autoUploadPending = true
    if (this.autoUploadRunning) {
      return
    }
    if (this.autoUploadTimer >= 0) {
      clearTimeout(this.autoUploadTimer)
      this.autoUploadTimer = -1
    }
    this.autoUploadTimer = setTimeout(() => {
      this.autoUploadTimer = -1
      this.runScheduledAutoUpload()
    }, delayMs)
  }

  async recordDeleted(animeId: string): Promise<void> {
    if (!await this.isWebDavFeatureUnlocked()) {
      return
    }
    if (animeId.length === 0) {
      return
    }
    const deleted = await this.loadDeletedItems()
    let found = false
    const now = Date.now()
    for (let i = 0; i < deleted.length; i++) {
      if (deleted[i].animeId === animeId) {
        deleted[i].deletedAt = now
        found = true
        break
      }
    }
    if (!found) {
      const item = new HistorySyncDeletedItem()
      item.animeId = animeId
      item.deletedAt = now
      deleted.push(item)
    }
    await this.saveDeletedItems(deleted)
  }

  private async runScheduledAutoUpload(): Promise<void> {
    if (this.autoUploadRunning) {
      return
    }
    this.autoUploadPending = false
    this.autoUploadRunning = true
    try {
      if (!await this.isWebDavFeatureUnlocked()) {
        return
      }
      const config = await this.getConfig()
      if (!config.enabled || !config.autoSync) {
        return
      }
      await this.syncNow()
      logger.info('Auto upload watch history finished')
    } catch (err) {
      logger.warn('Auto upload watch history failed: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.autoUploadRunning = false
      if (this.autoUploadPending) {
        this.scheduleAutoUploadAfterLocalChange()
      }
    }
  }

  private async buildLocalPayload(): Promise<HistorySyncPayload> {
    const payload = new HistorySyncPayload()
    payload.updatedAt = Date.now()
    payload.records = await this.historyStore.getAll()
    payload.deleted = await this.loadDeletedItems()
    return payload
  }

  private async isWebDavFeatureUnlocked(): Promise<boolean> {
    return await PreferencesStore.getInstance().getBoolean(ADVANCED_OPTIONS_UNLOCKED_KEY, false)
  }

  private async ensureWebDavFeatureUnlocked(): Promise<void> {
    if (!await this.isWebDavFeatureUnlocked()) {
      throw new Error('WebDAV 同步属于隐藏功能，请先解锁后使用')
    }
  }

  private mergePayloads(local: HistorySyncPayload, remote: HistorySyncPayload): HistorySyncPayload {
    const result = new HistorySyncPayload()
    const recordMap: Map<string, HistoryRecord> = new Map()
    const deletedMap: Map<string, number> = new Map()

    this.mergeDeletedIntoMap(deletedMap, local.deleted)
    this.mergeDeletedIntoMap(deletedMap, remote.deleted)
    this.mergeRecordsIntoMap(recordMap, local.records)
    this.mergeRecordsIntoMap(recordMap, remote.records)

    const ids = Array.from(recordMap.keys())
    for (let i = 0; i < ids.length; i++) {
      const record = recordMap.get(ids[i])
      if (record === undefined) {
        continue
      }
      const deletedAt = deletedMap.get(record.animeId)
      if (deletedAt !== undefined && deletedAt > record.updatedAt) {
        recordMap.delete(record.animeId)
      }
    }

    const deletedIds = Array.from(deletedMap.keys())
    for (let i = 0; i < deletedIds.length; i++) {
      const item = new HistorySyncDeletedItem()
      item.animeId = deletedIds[i]
      item.deletedAt = deletedMap.get(deletedIds[i]) ?? 0
      result.deleted.push(item)
    }
    result.records = Array.from(recordMap.values())
    result.records.sort((a: HistoryRecord, b: HistoryRecord) => b.updatedAt - a.updatedAt)
    result.updatedAt = Math.max(local.updatedAt, remote.updatedAt, Date.now())
    return result
  }

  private mergeRecordsIntoMap(recordMap: Map<string, HistoryRecord>, records: HistoryRecord[]): void {
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      if (record.animeId.length === 0) {
        continue
      }
      const existing = recordMap.get(record.animeId)
      if (existing === undefined || record.updatedAt >= existing.updatedAt) {
        recordMap.set(record.animeId, record)
      }
    }
  }

  private mergeDeletedIntoMap(deletedMap: Map<string, number>, deleted: HistorySyncDeletedItem[]): void {
    for (let i = 0; i < deleted.length; i++) {
      const item = deleted[i]
      if (item.animeId.length === 0) {
        continue
      }
      const existing = deletedMap.get(item.animeId)
      if (existing === undefined || item.deletedAt > existing) {
        deletedMap.set(item.animeId, item.deletedAt)
      }
    }
  }

  private async applyMergedPayload(payload: HistorySyncPayload): Promise<void> {
    const deletedMap: Map<string, number> = new Map()
    this.mergeDeletedIntoMap(deletedMap, payload.deleted)
    for (let i = 0; i < payload.records.length; i++) {
      const record = payload.records[i]
      const deletedAt = deletedMap.get(record.animeId)
      if (deletedAt !== undefined && deletedAt > record.updatedAt) {
        await this.historyStore.deleteByAnimeId(record.animeId)
      } else {
        await this.historyStore.upsertPreservingUpdatedAt(record)
      }
    }
    const deletedIds = Array.from(deletedMap.keys())
    for (let i = 0; i < deletedIds.length; i++) {
      const local = await this.historyStore.getByAnimeId(deletedIds[i])
      const deletedAt = deletedMap.get(deletedIds[i]) ?? 0
      if (local !== null && deletedAt > local.updatedAt) {
        await this.historyStore.deleteByAnimeId(deletedIds[i])
      }
    }
  }

  private parsePayload(text: string | null): HistorySyncPayload {
    const payload = new HistorySyncPayload()
    if (text === null || text.trim().length === 0) {
      return payload
    }
    try {
      const parsed = JSON.parse(text) as Record<string, Object>
      const updatedAt = parsed['updatedAt']
      if (typeof updatedAt === 'number') {
        payload.updatedAt = updatedAt
      }
      const recordsObj = parsed['records']
      if (recordsObj instanceof Array) {
        const records = recordsObj as Record<string, Object>[]
        for (let i = 0; i < records.length; i++) {
          payload.records.push(HistoryRecord.fromJSON(records[i]))
        }
      }
      const deletedObj = parsed['deleted']
      if (deletedObj instanceof Array) {
        const deleted = deletedObj as Record<string, Object>[]
        for (let i = 0; i < deleted.length; i++) {
          const item = new HistorySyncDeletedItem()
          const animeId = deleted[i]['animeId']
          const deletedAt = deleted[i]['deletedAt']
          if (typeof animeId === 'string') {
            item.animeId = animeId
          }
          if (typeof deletedAt === 'number') {
            item.deletedAt = deletedAt
          }
          if (item.animeId.length > 0) {
            payload.deleted.push(item)
          }
        }
      }
    } catch (err) {
      logger.warn('Parse remote history payload failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return payload
  }

  private payloadToJSON(payload: HistorySyncPayload): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['schemaVersion'] = payload.schemaVersion
    result['app'] = payload.app
    result['updatedAt'] = payload.updatedAt
    const records: Record<string, Object>[] = []
    for (let i = 0; i < payload.records.length; i++) {
      records.push(payload.records[i].toJSON())
    }
    const deleted: Record<string, Object>[] = []
    for (let i = 0; i < payload.deleted.length; i++) {
      const item: Record<string, Object> = {}
      item['animeId'] = payload.deleted[i].animeId
      item['deletedAt'] = payload.deleted[i].deletedAt
      deleted.push(item)
    }
    result['records'] = records
    result['deleted'] = deleted
    return result
  }

  private async loadDeletedItems(): Promise<HistorySyncDeletedItem[]> {
    const raw = await PreferencesStore.getInstance().getString(WEBDAV_SYNC_DELETED_KEY, '[]')
    const payload = this.parsePayload('{"deleted":' + raw + '}')
    return payload.deleted
  }

  private async saveDeletedItems(items: HistorySyncDeletedItem[]): Promise<void> {
    const jsonItems: Record<string, Object>[] = []
    for (let i = 0; i < items.length; i++) {
      const item: Record<string, Object> = {}
      item['animeId'] = items[i].animeId
      item['deletedAt'] = items[i].deletedAt
      jsonItems.push(item)
    }
    await PreferencesStore.getInstance().setString(WEBDAV_SYNC_DELETED_KEY, JSON.stringify(jsonItems))
  }

  private validateConfig(config: WebDavConfig): void {
    if (!config.enabled) {
      throw new Error('请先开启 WebDAV 同步')
    }
    if (config.serverUrl.trim().length === 0) {
      throw new Error('请填写 WebDAV 地址')
    }
    if (!config.serverUrl.startsWith('https://') && !config.serverUrl.startsWith('http://')) {
      throw new Error('WebDAV 地址必须以 http:// 或 https:// 开头')
    }
    if (config.username.length === 0) {
      throw new Error('请填写用户名')
    }
    if (config.password.length === 0) {
      throw new Error('请填写密码或应用密码')
    }
  }

  private normalizeRemoteDir(dir: string): string {
    let value = dir.trim()
    if (value.length === 0) {
      value = '/FanPlayer/'
    }
    if (!value.startsWith('/')) {
      value = '/' + value
    }
    if (!value.endsWith('/')) {
      value = value + '/'
    }
    return value
  }
}
