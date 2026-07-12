import { HistoryRecord } from '../models/HistoryRecord'
import { HistoryStore } from '../store/HistoryStore'
import { PreferencesStore } from '../store/PreferencesStore'
import { RuleSourceStore } from '../store/RuleSourceStore'
import { RuleSource } from '../models/RuleSource'
import { WebDavClient, WebDavConfig } from '../network/WebDavClient'
import { Logger } from '../utils/Logger'
import { ADVANCED_OPTIONS_UNLOCKED_KEY } from '../utils/AdvancedOptionsUnlock'
import { BangumiConfig } from '../core/api/BangumiConfig'
import { BangumiApi } from '../core/api/BangumiApi'
import { AnimeItem } from '../models/AnimeItem'

const logger = new Logger('HistorySyncService')

export const WEBDAV_SYNC_ENABLED_KEY: string = 'webdav_sync_enabled'
export const WEBDAV_SYNC_AUTO_KEY: string = 'webdav_sync_auto'
export const WEBDAV_SYNC_SERVER_URL_KEY: string = 'webdav_sync_server_url'
export const WEBDAV_SYNC_USERNAME_KEY: string = 'webdav_sync_username'
export const WEBDAV_SYNC_PASSWORD_KEY: string = 'webdav_sync_password'
export const WEBDAV_SYNC_REMOTE_DIR_KEY: string = 'webdav_sync_remote_dir'
export const WEBDAV_SYNC_LAST_TIME_KEY: string = 'webdav_sync_last_time'
const WEBDAV_SYNC_DELETED_KEY: string = 'webdav_sync_deleted_history'
const WEBDAV_SYNC_DEVICE_ID_KEY: string = 'webdav_sync_device_id'
const HISTORY_FILE_NAME: string = 'watch_history.json'
const UPSTREAM_SYNC_ROOT_PATH: string = '/kazumiSync'
const UPSTREAM_HISTORY_ROOT_PATH: string = '/kazumiSync/history'
const UPSTREAM_HISTORY_CHANGES_PATH: string = '/kazumiSync/history/changes'
const UPSTREAM_HISTORY_SNAPSHOT_PATH: string = '/kazumiSync/history/snapshot.json'
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

class UpstreamProgress {
  episode: number = 1
  road: number = 0
  progressMs: number = 0
}

export class HistorySyncService {
  private static sharedInstance: HistorySyncService = new HistorySyncService()
  private historyStore: HistoryStore = new HistoryStore()
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
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
    const legacyPayload = this.parsePayload(remoteText)
    const upstreamPayload = await this.readUpstreamHistoryPayload(client)
    const remotePayload = this.mergePayloads(legacyPayload, upstreamPayload)
    const mergedPayload = this.mergePayloads(localPayload, remotePayload)
    await this.enrichRuleSourceInfo(mergedPayload.records)
    await this.enrichMissingBangumiCovers(mergedPayload.records)
    logger.info('History sync merge counts local=%{public}d legacy=%{public}d upstream=%{public}d remote=%{public}d merged=%{public}d',
      localPayload.records.length, legacyPayload.records.length, upstreamPayload.records.length,
      remotePayload.records.length, mergedPayload.records.length)

    await this.applyMergedPayload(mergedPayload)
    mergedPayload.updatedAt = Date.now()
    await client.uploadText(HISTORY_FILE_NAME, JSON.stringify(this.payloadToJSON(mergedPayload)))
    await this.writeUpstreamHistoryPayload(client, mergedPayload)
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
        recordMap.delete(ids[i])
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
      const mergeKey = this.getHistoryMergeKey(record)
      const existing = recordMap.get(mergeKey)
      if (existing === undefined || record.updatedAt >= existing.updatedAt) {
        recordMap.set(mergeKey, this.combineHistoryRecords(record, existing))
      }
    }
  }

  private combineHistoryRecords(winner: HistoryRecord, existing: HistoryRecord | undefined): HistoryRecord {
    if (existing === undefined) {
      return winner
    }
    if (winner.bangumiId > 0 && existing.bangumiId === winner.bangumiId && winner.animeId !== existing.animeId) {
      const winnerCanonical = this.isCanonicalLocalHistoryId(winner)
      const existingCanonical = this.isCanonicalLocalHistoryId(existing)
      if (!winnerCanonical && existingCanonical) {
        winner.animeId = existing.animeId
      }
    }
    if (winner.animeUrl.length === 0) {
      winner.animeUrl = existing.animeUrl
    }
    if (winner.episodeUrl.length === 0) {
      winner.episodeUrl = existing.episodeUrl
    }
    if (winner.animeCover.length === 0) {
      winner.animeCover = existing.animeCover
    }
    if (winner.sourceId < 0) {
      winner.sourceId = existing.sourceId
    }
    if (winner.sourceName.length === 0) {
      winner.sourceName = existing.sourceName
    }
    return winner
  }

  private getHistoryMergeKey(record: HistoryRecord): string {
    if (record.bangumiId > 0) {
      const sourceKey = record.sourceName.length > 0 ? record.sourceName :
        (record.sourceId >= 0 ? 'source_' + String(record.sourceId) : '')
      if (sourceKey.length > 0) {
        return 'bangumi:' + sourceKey + ':' + String(record.bangumiId)
      }
      if (record.animeUrl.length > 0) {
        return 'bangumi-url:' + String(record.bangumiId) + ':' + record.animeUrl
      }
      return 'bangumi:' + String(record.bangumiId)
    }
    return record.animeId
  }

  private isCanonicalLocalHistoryId(record: HistoryRecord): boolean {
    if (record.sourceId < 0 || record.animeUrl.length === 0) {
      return false
    }
    return record.animeId === String(record.sourceId) + '_' + record.animeUrl
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
    await this.deleteMergedDuplicateLocalRecords(payload)
  }

  private async deleteMergedDuplicateLocalRecords(payload: HistorySyncPayload): Promise<void> {
    const keepAnimeIds: Set<string> = new Set()
    const keepMergeKeys: Set<string> = new Set()
    for (let i = 0; i < payload.records.length; i++) {
      keepAnimeIds.add(payload.records[i].animeId)
      keepMergeKeys.add(this.getHistoryMergeKey(payload.records[i]))
    }
    const localRecords = await this.historyStore.getAll()
    for (let i = 0; i < localRecords.length; i++) {
      const record = localRecords[i]
      if (keepAnimeIds.has(record.animeId)) {
        continue
      }
      if (keepMergeKeys.has(this.getHistoryMergeKey(record))) {
        await this.historyStore.deleteByAnimeId(record.animeId)
      }
    }
  }

  private async readUpstreamHistoryPayload(client: WebDavClient): Promise<HistorySyncPayload> {
    const payload = new HistorySyncPayload()
    try {
      const snapshotText = await client.downloadTextAtPath(UPSTREAM_HISTORY_SNAPSHOT_PATH)
      if (snapshotText !== null && snapshotText.trim().length > 0) {
        const snapshotPayload = this.parseUpstreamSnapshot(snapshotText)
        logger.info('Read upstream history snapshot records=%{public}d', snapshotPayload.records.length)
        this.mergeRecordsIntoMapFromPayload(payload, snapshotPayload)
      }
    } catch (err) {
      logger.warn('Read upstream history snapshot failed: %{public}s', err instanceof Error ? err.message : String(err))
    }

    try {
      const fileNames = await client.listFileNamesAtPath(UPSTREAM_HISTORY_CHANGES_PATH)
      const events: Record<string, Object>[] = []
      for (let i = 0; i < fileNames.length; i++) {
        const fileName = fileNames[i]
        if (!fileName.endsWith('.jsonl')) {
          continue
        }
        const text = await client.downloadTextAtPath(UPSTREAM_HISTORY_CHANGES_PATH + '/' + fileName)
        if (text !== null) {
          const parsedEvents = this.parseUpstreamEventLines(text)
          for (let j = 0; j < parsedEvents.length; j++) {
            events.push(parsedEvents[j])
          }
        }
      }
      logger.info('Read upstream history change files=%{public}d events=%{public}d', fileNames.length, events.length)
      this.applyUpstreamEvents(payload, events)
    } catch (err) {
      logger.warn('Read upstream history changes failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
    await this.enrichRuleSourceInfo(payload.records)
    payload.records.sort((a: HistoryRecord, b: HistoryRecord) => b.updatedAt - a.updatedAt)
    return payload
  }

  private mergeRecordsIntoMapFromPayload(target: HistorySyncPayload, source: HistorySyncPayload): void {
    const merged = this.mergePayloads(target, source)
    target.records = merged.records
    target.deleted = merged.deleted
    target.updatedAt = Math.max(target.updatedAt, source.updatedAt)
  }

  private async enrichRuleSourceInfo(records: HistoryRecord[]): Promise<void> {
    if (records.length === 0) {
      return
    }
    let rules: RuleSource[] = []
    try {
      rules = await this.ruleSourceStore.getAll()
    } catch (err) {
      logger.warn('Load rule sources for history sync failed: %{public}s',
        err instanceof Error ? err.message : String(err))
      return
    }
    if (rules.length === 0) {
      return
    }

    const ruleById: Map<number, RuleSource> = new Map()
    const ruleByName: Map<string, RuleSource> = new Map()
    for (let i = 0; i < rules.length; i++) {
      ruleById.set(rules[i].id, rules[i])
      ruleByName.set(this.normalizeRuleName(rules[i].name), rules[i])
    }

    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      if (record.sourceId >= 0) {
        const rule = ruleById.get(record.sourceId)
        if (rule !== undefined) {
          record.sourceName = rule.name
          this.canonicalizeLocalAnimeId(record)
          continue
        }
      }

      const sourceAliasId = this.parseSourceIdAlias(record.sourceName)
      if (sourceAliasId >= 0) {
        const rule = ruleById.get(sourceAliasId)
        if (rule !== undefined) {
          record.sourceId = rule.id
          record.sourceName = rule.name
          this.canonicalizeLocalAnimeId(record)
          continue
        }
      }

      const matched = ruleByName.get(this.normalizeRuleName(record.sourceName))
      if (matched !== undefined) {
        record.sourceId = matched.id
        record.sourceName = matched.name
        this.canonicalizeLocalAnimeId(record)
      }
    }
  }

  private async enrichMissingBangumiCovers(records: HistoryRecord[]): Promise<void> {
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      if ((record.animeCover.length > 0 && record.animeName.length > 0) || record.bangumiId <= 0) {
        continue
      }
      try {
        const subject: AnimeItem | null = await BangumiApi.getSubject(record.bangumiId)
        if (subject === null) {
          continue
        }
        if (record.animeCover.length === 0) {
          const cover = subject.getDetailCover()
          if (cover.length > 0) {
            record.animeCover = cover
          }
        }
        if (record.animeName.length === 0) {
          record.animeName = subject.name
        }
      } catch (err) {
        logger.warn('Enrich history cover failed: bangumiId=%{public}d, error=%{public}s',
          record.bangumiId, err instanceof Error ? err.message : String(err))
      }
    }
  }

  private canonicalizeLocalAnimeId(record: HistoryRecord): void {
    if (record.sourceId >= 0 && record.animeUrl.length > 0) {
      record.animeId = String(record.sourceId) + '_' + record.animeUrl
    }
  }

  private normalizeRuleName(name: string): string {
    return name.trim().toLowerCase()
  }

  private parseSourceIdAlias(name: string): number {
    const trimmed = name.trim()
    if (!trimmed.startsWith('source_')) {
      return -1
    }
    const parsed = Number(trimmed.substring('source_'.length))
    return Number.isInteger(parsed) && parsed >= 0 ? parsed : -1
  }

  private parseUpstreamSnapshot(text: string): HistorySyncPayload {
    const payload = new HistorySyncPayload()
    try {
      const parsed = JSON.parse(text) as Record<string, Object>
      const generatedAt = parsed['generatedAt']
      if (typeof generatedAt === 'number') {
        payload.updatedAt = generatedAt
      }
      const historiesObj = parsed['histories']
      if (historiesObj instanceof Array) {
        const histories = historiesObj as Record<string, Object>[]
        for (let i = 0; i < histories.length; i++) {
          const record = this.historyRecordFromUpstreamHistory(histories[i])
          if (record !== null) {
            payload.records.push(record)
          }
        }
      }
      const deletedVersionsObj = parsed['deletedVersions']
      if (deletedVersionsObj !== undefined) {
        this.parseUpstreamDeletedVersions(payload, deletedVersionsObj as Record<string, Object>)
      }
    } catch (err) {
      logger.warn('Parse upstream history snapshot failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return payload
  }

  private parseUpstreamDeletedVersions(payload: HistorySyncPayload, deletedVersions: Record<string, Object>): void {
    const keys = Object.keys(deletedVersions)
    for (let i = 0; i < keys.length; i++) {
      const item = new HistorySyncDeletedItem()
      item.animeId = keys[i]
      item.deletedAt = this.updatedAtFromVersion(String(deletedVersions[keys[i]]))
      payload.deleted.push(item)
    }
  }

  private parseUpstreamEventLines(text: string): Record<string, Object>[] {
    const events: Record<string, Object>[] = []
    const lines = text.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length === 0) {
        continue
      }
      try {
        events.push(JSON.parse(line) as Record<string, Object>)
      } catch (err) {
        logger.warn('Parse upstream history event line failed: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    events.sort((a: Record<string, Object>, b: Record<string, Object>) => {
      const aVersion = this.versionOfEvent(a)
      const bVersion = this.versionOfEvent(b)
      if (aVersion < bVersion) return -1
      if (aVersion > bVersion) return 1
      return 0
    })
    return events
  }

  private applyUpstreamEvents(payload: HistorySyncPayload, events: Record<string, Object>[]): void {
    const recordMap: Map<string, HistoryRecord> = new Map()
    this.mergeRecordsIntoMap(recordMap, payload.records)
    const deletedMap: Map<string, number> = new Map()
    this.mergeDeletedIntoMap(deletedMap, payload.deleted)
    let clearAt = 0

    for (let i = 0; i < events.length; i++) {
      const event = events[i]
      const op = String(event['op'] ?? '')
      const updatedAt = this.numberValue(event['updatedAt'], 0)
      if (op === 'clearAll') {
        if (updatedAt >= clearAt) {
          recordMap.clear()
          deletedMap.clear()
          clearAt = updatedAt
        }
        continue
      }
      const entityKey = String(event['entityKey'] ?? '')
      if (entityKey.length === 0 || updatedAt < clearAt) {
        continue
      }
      if (op === 'deleteHistory') {
        const existing = this.findRecordByUpstreamEntityKey(recordMap, entityKey)
        if (existing !== null && updatedAt >= existing.updatedAt) {
          recordMap.delete(this.getHistoryMergeKey(existing))
        }
        const deletedExisting = deletedMap.get(entityKey)
        if (deletedExisting === undefined || updatedAt > deletedExisting) {
          deletedMap.set(entityKey, updatedAt)
        }
        continue
      }
      if (op === 'upsertProgress') {
        const record = this.historyRecordFromUpstreamEvent(event)
        if (record === null) {
          continue
        }
        const deletedAt = deletedMap.get(entityKey)
        if (deletedAt !== undefined && deletedAt > record.updatedAt) {
          continue
        }
        this.mergeRecordsIntoMap(recordMap, [record])
        deletedMap.delete(entityKey)
      }
    }

    payload.records = Array.from(recordMap.values())
    payload.deleted = []
    const deletedKeys = Array.from(deletedMap.keys())
    for (let i = 0; i < deletedKeys.length; i++) {
      const item = new HistorySyncDeletedItem()
      item.animeId = deletedKeys[i]
      item.deletedAt = deletedMap.get(deletedKeys[i]) ?? 0
      payload.deleted.push(item)
    }
  }

  private findRecordByUpstreamEntityKey(recordMap: Map<string, HistoryRecord>, entityKey: string): HistoryRecord | null {
    const values = Array.from(recordMap.values())
    for (let i = 0; i < values.length; i++) {
      if (this.getUpstreamEntityKey(values[i]) === entityKey || values[i].animeId === entityKey) {
        return values[i]
      }
    }
    return null
  }

  private historyRecordFromUpstreamEvent(event: Record<string, Object>): HistoryRecord | null {
    const bangumiItem = event['bangumiItem']
    if (bangumiItem === undefined) {
      return null
    }
    const historyJson: Record<string, Object> = {}
    historyJson['bangumiItem'] = bangumiItem
    historyJson['adapterName'] = String(event['adapterName'] ?? '')
    historyJson['lastWatchEpisode'] = this.numberValue(event['episode'], 1)
    historyJson['lastWatchTime'] = this.numberValue(event['updatedAt'], Date.now())
    historyJson['lastSrc'] = String(event['lastSrc'] ?? '')
    historyJson['lastWatchEpisodeName'] = String(event['lastWatchEpisodeName'] ?? '')
    const progresses: Record<string, Object> = {}
    const progress: Record<string, Object> = {}
    progress['episode'] = this.numberValue(event['episode'], 1)
    progress['road'] = this.numberValue(event['road'], 0)
    progress['progressMs'] = this.numberValue(event['progressMs'], 0)
    progresses[String(progress['episode'])] = progress
    historyJson['progresses'] = progresses
    return this.historyRecordFromUpstreamHistory(historyJson)
  }

  private historyRecordFromUpstreamHistory(history: Record<string, Object>): HistoryRecord | null {
    const bangumiObject = history['bangumiItem']
    if (bangumiObject === undefined) {
      return null
    }
    const bangumiItem = bangumiObject as Record<string, Object>
    const bangumiId = this.numberValue(bangumiItem['id'], -1)
    if (bangumiId <= 0) {
      return null
    }
    const adapterName = String(history['adapterName'] ?? '')
    const lastWatchEpisode = this.numberValue(history['lastWatchEpisode'], 1)
    const record = new HistoryRecord()
    record.bangumiId = bangumiId
    record.sourceName = adapterName
    record.animeId = adapterName + String(bangumiId)
    record.animeName = this.resolveUpstreamAnimeName(bangumiItem)
    record.animeCover = this.resolveUpstreamCover(bangumiItem)
    const lastSrc = String(history['lastSrc'] ?? '')
    record.animeUrl = lastSrc
    record.episodeName = String(history['lastWatchEpisodeName'] ?? '')
    if (record.episodeName.length === 0) {
      record.episodeName = '第' + String(lastWatchEpisode) + '集'
    }
    record.episodeUrl = lastSrc
    record.updatedAt = this.numberValue(history['lastWatchTime'], Date.now())
    record.episodeIndex = Math.max(0, lastWatchEpisode - 1)
    const progress = this.resolveUpstreamProgress(history, lastWatchEpisode)
    record.roadIndex = progress.road
    record.positionMs = progress.progressMs
    return record
  }

  private resolveUpstreamProgress(history: Record<string, Object>, episode: number): UpstreamProgress {
    const fallback = new UpstreamProgress()
    const progressesObj = history['progresses']
    if (progressesObj === undefined) {
      return fallback
    }
    const progresses = progressesObj as Record<string, Object>
    const progressObj = progresses[String(episode)]
    if (progressObj === undefined) {
      const keys = Object.keys(progresses)
      if (keys.length === 0) {
        return fallback
      }
      return this.progressFromUpstreamJson(progresses[keys[0]] as Record<string, Object>)
    }
    return this.progressFromUpstreamJson(progressObj as Record<string, Object>)
  }

  private progressFromUpstreamJson(json: Record<string, Object>): UpstreamProgress {
    const progress = new UpstreamProgress()
    progress.episode = this.numberValue(json['episode'], 1)
    progress.road = this.numberValue(json['road'], 0)
    progress.progressMs = this.numberValue(json['progressMs'], 0)
    return progress
  }

  private resolveUpstreamAnimeName(bangumiItem: Record<string, Object>): string {
    const nameCn = String(bangumiItem['nameCn'] ?? '')
    if (nameCn.length > 0) {
      return nameCn
    }
    const snakeNameCn = String(bangumiItem['name_cn'] ?? '')
    if (snakeNameCn.length > 0) {
      return snakeNameCn
    }
    return String(bangumiItem['name'] ?? '')
  }

  private resolveUpstreamCover(bangumiItem: Record<string, Object>): string {
    const directImage = this.normalizeUpstreamCoverValue(bangumiItem['image'])
    if (directImage.length > 0) {
      return directImage
    }
    const coverImage = this.normalizeUpstreamCoverValue(bangumiItem['cover'])
    if (coverImage.length > 0) {
      return coverImage
    }
    const imagesObj = bangumiItem['images']
    if (imagesObj === undefined) {
      return ''
    }
    const images = imagesObj as Record<string, Object>
    const keys: string[] = ['large', 'common', 'medium', 'grid', 'small']
    for (let i = 0; i < keys.length; i++) {
      const cover = this.normalizeUpstreamCoverValue(images[keys[i]])
      if (cover.length > 0) {
        return cover
      }
    }
    return ''
  }

  private normalizeUpstreamCoverValue(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return ''
    }
    const raw = String(value)
    if (raw.length === 0) {
      return ''
    }
    return BangumiConfig.normalizeImageUrl(raw)
  }

  private async writeUpstreamHistoryPayload(client: WebDavClient, payload: HistorySyncPayload): Promise<void> {
    try {
      await client.ensureRemoteDirAtPath(UPSTREAM_SYNC_ROOT_PATH)
      await client.ensureRemoteDirAtPath(UPSTREAM_HISTORY_ROOT_PATH)
      await client.ensureRemoteDirAtPath(UPSTREAM_HISTORY_CHANGES_PATH)
      const snapshot = this.upstreamSnapshotToJSON(payload)
      await client.uploadTextAtPath(UPSTREAM_HISTORY_SNAPSHOT_PATH, JSON.stringify(snapshot))
      const deviceId = await this.getDeviceId()
      const events = this.upstreamEventsFromPayload(payload, deviceId)
      const eventLines = this.upstreamEventsToJsonLines(events)
      if (eventLines.length > 0) {
        await client.uploadTextAtPath(UPSTREAM_HISTORY_CHANGES_PATH + '/' + deviceId + '.jsonl', eventLines)
      }
    } catch (err) {
      logger.warn('Write upstream history payload failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private upstreamSnapshotToJSON(payload: HistorySyncPayload): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['schemaVersion'] = 1
    result['generatedAt'] = payload.updatedAt > 0 ? payload.updatedAt : Date.now()
    const histories: Record<string, Object>[] = []
    const itemVersions: Record<string, Object> = {}
    const progressVersions: Record<string, Object> = {}
    const deletedVersions: Record<string, Object> = {}

    for (let i = 0; i < payload.records.length; i++) {
      const record = payload.records[i]
      if (!this.isUpstreamExportable(record)) {
        continue
      }
      const historyJson = this.upstreamHistoryToJSON(record)
      const entityKey = this.getUpstreamEntityKey(record)
      const eventId = 'local-import:' + entityKey
      const version = this.versionOf(record.updatedAt, eventId)
      histories.push(historyJson)
      itemVersions[entityKey] = version
      const episodeVersions: Record<string, Object> = {}
      episodeVersions[String(this.getUpstreamEpisode(record))] = version
      progressVersions[entityKey] = episodeVersions
    }

    for (let i = 0; i < payload.deleted.length; i++) {
      const deleted = payload.deleted[i]
      if (deleted.animeId.length > 0) {
        deletedVersions[deleted.animeId] = this.versionOf(deleted.deletedAt, 'delete:' + deleted.animeId)
      }
    }
    result['histories'] = histories
    result['itemVersions'] = itemVersions
    result['progressVersions'] = progressVersions
    result['deletedVersions'] = deletedVersions
    return result
  }

  private upstreamHistoryToJSON(record: HistoryRecord): Record<string, Object> {
    const result: Record<string, Object> = {}
    const episode = this.getUpstreamEpisode(record)
    result['bangumiItem'] = this.upstreamBangumiItemToJSON(record)
    result['lastWatchEpisode'] = episode
    result['adapterName'] = this.getUpstreamAdapterName(record)
    result['lastWatchTime'] = record.updatedAt > 0 ? record.updatedAt : Date.now()
    result['lastSrc'] = this.getUpstreamLastSrc(record)
    result['lastWatchEpisodeName'] = record.episodeName
    const progresses: Record<string, Object> = {}
    const progress: Record<string, Object> = {}
    progress['episode'] = episode
    progress['road'] = record.roadIndex >= 0 ? record.roadIndex : 0
    progress['progressMs'] = Math.max(0, record.positionMs)
    progresses[String(episode)] = progress
    result['progresses'] = progresses
    return result
  }

  private upstreamBangumiItemToJSON(record: HistoryRecord): Record<string, Object> {
    const images: Record<string, Object> = {}
    images['large'] = record.animeCover
    images['common'] = record.animeCover
    images['medium'] = record.animeCover
    images['small'] = record.animeCover
    images['grid'] = record.animeCover
    const item: Record<string, Object> = {}
    item['id'] = record.bangumiId
    item['type'] = 2
    item['name'] = record.animeName
    item['nameCn'] = record.animeName
    item['summary'] = ''
    item['airDate'] = ''
    item['airWeekday'] = 0
    item['rank'] = 0
    item['images'] = images
    item['tags'] = []
    item['alias'] = []
    item['ratingScore'] = 0
    item['votes'] = 0
    item['votesCount'] = []
    item['info'] = ''
    return item
  }

  private upstreamEventsFromPayload(payload: HistorySyncPayload, deviceId: string): Record<string, Object>[] {
    const events: Record<string, Object>[] = []
    for (let i = 0; i < payload.records.length; i++) {
      const record = payload.records[i]
      if (!this.isUpstreamExportable(record)) {
        continue
      }
      const event: Record<string, Object> = {}
      event['eventId'] = deviceId + ':' + String(i + 1)
      event['deviceId'] = deviceId
      event['seq'] = i + 1
      event['op'] = 'upsertProgress'
      event['updatedAt'] = record.updatedAt > 0 ? record.updatedAt : Date.now()
      event['entityKey'] = this.getUpstreamEntityKey(record)
      event['bangumiItem'] = this.upstreamBangumiItemToJSON(record)
      event['adapterName'] = this.getUpstreamAdapterName(record)
      event['episode'] = this.getUpstreamEpisode(record)
      event['road'] = record.roadIndex >= 0 ? record.roadIndex : 0
      event['progressMs'] = Math.max(0, record.positionMs)
      event['lastSrc'] = this.getUpstreamLastSrc(record)
      event['lastWatchEpisodeName'] = record.episodeName
      events.push(event)
    }
    return events
  }

  private upstreamEventsToJsonLines(events: Record<string, Object>[]): string {
    const lines: string[] = []
    for (let i = 0; i < events.length; i++) {
      lines.push(JSON.stringify(events[i]))
    }
    return lines.length === 0 ? '' : lines.join('\n') + '\n'
  }

  private getUpstreamEntityKey(record: HistoryRecord): string {
    return this.getUpstreamAdapterName(record) + String(record.bangumiId)
  }

  private isUpstreamExportable(record: HistoryRecord): boolean {
    return record.bangumiId > 0 && this.isValidUpstreamAdapterName(record.sourceName) && record.animeUrl.length > 0
  }

  private getUpstreamLastSrc(record: HistoryRecord): string {
    return record.animeUrl
  }

  private isValidUpstreamAdapterName(name: string): boolean {
    const trimmed = name.trim()
    return trimmed.length > 0 && trimmed !== 'HarmonyOS' && this.parseSourceIdAlias(trimmed) < 0
  }

  private getUpstreamAdapterName(record: HistoryRecord): string {
    if (record.sourceName.length > 0) {
      return record.sourceName
    }
    if (record.sourceId >= 0) {
      return 'source_' + String(record.sourceId)
    }
    return 'HarmonyOS'
  }

  private getUpstreamEpisode(record: HistoryRecord): number {
    if (record.episodeIndex >= 0) {
      return record.episodeIndex + 1
    }
    return 1
  }

  private async getDeviceId(): Promise<string> {
    const prefs = PreferencesStore.getInstance()
    const existing = await prefs.getString(WEBDAV_SYNC_DEVICE_ID_KEY, '')
    if (existing.length > 0) {
      return existing
    }
    const generated = this.generateDeviceId()
    await prefs.setString(WEBDAV_SYNC_DEVICE_ID_KEY, generated)
    return generated
  }

  private generateDeviceId(): string {
    const hex: string[] = []
    for (let i = 0; i < 16; i++) {
      let value = Math.floor(Math.random() * 256)
      if (i === 6) {
        value = (value & 0x0f) | 0x40
      } else if (i === 8) {
        value = (value & 0x3f) | 0x80
      }
      hex.push(value.toString(16).padStart(2, '0'))
    }
    const joined = hex.join('')
    return joined.substring(0, 8) + '-' + joined.substring(8, 12) + '-' +
      joined.substring(12, 16) + '-' + joined.substring(16, 20) + '-' + joined.substring(20)
  }

  private numberValue(value: Object | undefined, defaultValue: number): number {
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'string') {
      const parsed = Number(value)
      return Number.isFinite(parsed) ? parsed : defaultValue
    }
    return defaultValue
  }

  private versionOfEvent(event: Record<string, Object>): string {
    return this.versionOf(this.numberValue(event['updatedAt'], 0), String(event['eventId'] ?? ''))
  }

  private versionOf(updatedAt: number, eventId: string): string {
    return Math.max(0, Math.floor(updatedAt)).toString().padStart(16, '0') + '|' + eventId
  }

  private updatedAtFromVersion(version: string): number {
    const delimiterIndex = version.indexOf('|')
    const timestamp = delimiterIndex >= 0 ? version.substring(0, delimiterIndex) : version
    const parsed = Number(timestamp)
    return Number.isFinite(parsed) ? parsed : 0
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
