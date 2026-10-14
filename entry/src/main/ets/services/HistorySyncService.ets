import { HistoryEpisodeProgress, HistoryRecord } from '../models/HistoryRecord'
import { HistoryStore } from '../store/HistoryStore'
import { PreferencesStore } from '../store/PreferencesStore'
import { RuleSourceStore } from '../store/RuleSourceStore'
import { RuleSource } from '../models/RuleSource'
import { WebDavClient, WebDavConfig } from '../network/WebDavClient'
import { Logger } from '../utils/Logger'
import { BangumiConfig } from '../core/api/BangumiConfig'
import { BangumiApi } from '../core/api/BangumiApi'
import { AnimeItem } from '../models/AnimeItem'
import { CollectSyncService, CollectSyncResult } from './CollectSyncService'
import { HistorySyncEventStore } from '../store/HistorySyncEventStore'
import { KazumiHiveCollectCodec } from './KazumiHiveCollectCodec'
import {
  KazumiHistoryItem,
  KazumiHistorySyncEvent,
  KazumiHistorySyncSnapshot,
  KazumiHistorySyncState
} from './KazumiHistorySyncProtocol'

const logger = new Logger('HistorySyncService')

export const WEBDAV_SYNC_ENABLED_KEY: string = 'webdav_sync_enabled'
export const WEBDAV_SYNC_AUTO_KEY: string = 'webdav_sync_auto'
export const WEBDAV_SYNC_SERVER_URL_KEY: string = 'webdav_sync_server_url'
export const WEBDAV_SYNC_USERNAME_KEY: string = 'webdav_sync_username'
export const WEBDAV_SYNC_PASSWORD_KEY: string = 'webdav_sync_password'
export const WEBDAV_SYNC_REMOTE_DIR_KEY: string = 'webdav_sync_remote_dir'
export const WEBDAV_SYNC_LAST_TIME_KEY: string = 'webdav_sync_last_time'
export const WEBDAV_SYNC_COLLECT_KEY: string = 'webdav_sync_collect'
const WEBDAV_SYNC_DEVICE_ID_KEY: string = 'webdav_sync_device_id'
const WEBDAV_SYNC_SEQUENCE_KEY: string = 'webdav_sync_sequence'
const WEBDAV_SYNC_HISTORY_SNAPSHOT_INITIALIZED_KEY: string = 'webdav_sync_history_snapshot_initialized'
const LEGACY_PRIVATE_HISTORY_FILE_NAME: string = 'watch_history.json'
const LEGACY_UPSTREAM_HISTORY_PATH: string = '/kazumiSync/histories.tmp'
const UPSTREAM_SYNC_ROOT_PATH: string = '/kazumiSync'
const UPSTREAM_HISTORY_ROOT_PATH: string = '/kazumiSync/history'
const UPSTREAM_HISTORY_CHANGES_PATH: string = '/kazumiSync/history/changes'
const UPSTREAM_HISTORY_SNAPSHOT_PATH: string = '/kazumiSync/history/snapshot.json'
const AUTO_UPLOAD_DELAY_MS: number = 15000
const HISTORY_CHECKPOINT_THRESHOLD: number = 1024 * 1024

export class HistorySyncResult {
  success: boolean = false
  message: string = ''
  localCount: number = 0
  remoteCount: number = 0
  mergedCount: number = 0
  collectLocalCount: number = 0
  collectRemoteCount: number = 0
  collectMergedCount: number = 0
}

class CanonicalHistoryReadResult {
  snapshot: KazumiHistorySyncSnapshot = KazumiHistorySyncSnapshot.empty()
  events: KazumiHistorySyncEvent[] = []
  ownEvents: KazumiHistorySyncEvent[] = []
  snapshotExists: boolean = false
  snapshotValid: boolean = true
  eventLogsValid: boolean = true
}

export class HistorySyncService {
  private static sharedInstance: HistorySyncService = new HistorySyncService()
  private historyStore: HistoryStore = new HistoryStore()
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private eventStore: HistorySyncEventStore = new HistorySyncEventStore()
  private autoUploadTimer: number = -1
  private autoUploadRunning: boolean = false
  private autoUploadPending: boolean = false
  private activeSync: Promise<HistorySyncResult> | null = null
  private sequenceQueue: Promise<number> = Promise.resolve(0)

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
    const previousServerUrl = await prefs.getString(WEBDAV_SYNC_SERVER_URL_KEY, '')
    const previousUsername = await prefs.getString(WEBDAV_SYNC_USERNAME_KEY, '')
    const previousRemoteDir = await prefs.getString(WEBDAV_SYNC_REMOTE_DIR_KEY, '/FanPlayer/')
    const normalizedServerUrl = config.serverUrl.trim()
    const normalizedRemoteDir = this.normalizeRemoteDir(config.remoteDir)
    await prefs.setBoolean(WEBDAV_SYNC_ENABLED_KEY, config.enabled)
    await prefs.setBoolean(WEBDAV_SYNC_AUTO_KEY, config.autoSync)
    await prefs.setString(WEBDAV_SYNC_SERVER_URL_KEY, normalizedServerUrl)
    await prefs.setString(WEBDAV_SYNC_USERNAME_KEY, config.username)
    await prefs.setString(WEBDAV_SYNC_PASSWORD_KEY, config.password)
    await prefs.setString(WEBDAV_SYNC_REMOTE_DIR_KEY, normalizedRemoteDir)
    if (previousServerUrl !== normalizedServerUrl || previousUsername !== config.username ||
      this.normalizeRemoteDir(previousRemoteDir) !== normalizedRemoteDir) {
      await prefs.setBoolean(WEBDAV_SYNC_HISTORY_SNAPSHOT_INITIALIZED_KEY, false)
    }
  }

  async testConnection(config?: WebDavConfig): Promise<void> {
    await this.ensureWebDavFeatureUnlocked()
    const actual = config !== undefined ? config : await this.getConfig()
    this.validateConfig(actual)
    const client = new WebDavClient(actual)
    const ok = await client.testConnection()
    if (!ok) {
      throw new Error('WebDAV 连接失败，请检查地址和账号')
    }
    await client.ensureRemoteDirAtPath(UPSTREAM_SYNC_ROOT_PATH)
  }

  async syncNow(): Promise<HistorySyncResult> {
    if (this.activeSync !== null) {
      return await this.activeSync
    }
    this.activeSync = this.performSync()
    try {
      return await this.activeSync
    } finally {
      this.activeSync = null
    }
  }

  private async performSync(): Promise<HistorySyncResult> {
    await this.ensureWebDavFeatureUnlocked()
    const config = await this.getConfig()
    this.validateConfig(config)
    const client = new WebDavClient(config)
    await client.ensureRemoteDirAtPath(UPSTREAM_SYNC_ROOT_PATH)
    await client.ensureRemoteDirAtPath(UPSTREAM_HISTORY_ROOT_PATH)
    await client.ensureRemoteDirAtPath(UPSTREAM_HISTORY_CHANGES_PATH)
    const deviceId = await this.getDeviceId()
    const localRecords = await this.historyStore.getAll()
    await this.enrichRuleSourceInfo(localRecords)
    const remoteRead = await this.readCanonicalHistory(client, deviceId)
    const state = KazumiHistorySyncState.fromSnapshot(remoteRead.snapshot)
    state.applyAll(remoteRead.events)

    const pendingEvents = await this.eventStore.getAll()
    state.applyAll(pendingEvents)
    const localStateEvents = this.buildLocalStateEvents(localRecords)
    state.applyAll(localStateEvents)

    let importedLegacyHistory = false
    const canonicalHistoryEmpty = this.isEmptyCanonicalHistory(remoteRead.snapshot) && remoteRead.events.length === 0
    if (canonicalHistoryEmpty) {
      const legacyUpstreamBytes = await client.downloadBytesAtPath(LEGACY_UPSTREAM_HISTORY_PATH)
      if (legacyUpstreamBytes !== null && legacyUpstreamBytes.length > 0) {
        try {
          const legacyHistories = KazumiHiveCollectCodec.decodeHistories(legacyUpstreamBytes)
          state.applyAll(this.buildImportedHistoryEvents(legacyHistories))
          importedLegacyHistory = legacyHistories.length > 0
        } catch (err) {
          logger.warn('Import Kazumi legacy histories.tmp failed: %{public}s',
            err instanceof Error ? err.message : String(err))
          try {
            await client.moveAtPath(LEGACY_UPSTREAM_HISTORY_PATH,
              '/kazumiSync/histories.invalid.' + String(Date.now()) + '.tmp')
          } catch (_moveErr) {
            logger.warn('Quarantine invalid Kazumi histories.tmp failed')
          }
        }
      }
    }
    if (!remoteRead.snapshotExists && remoteRead.events.length === 0 && !importedLegacyHistory) {
        const legacyText = await client.downloadText(LEGACY_PRIVATE_HISTORY_FILE_NAME)
        const legacyRecords = this.parseLegacyPrivateHistory(legacyText)
        if (legacyRecords.length > 0) {
          await this.enrichRuleSourceInfo(legacyRecords)
          state.applyAll(this.buildLocalStateEvents(legacyRecords))
          importedLegacyHistory = true
        }
    }

    const mergedSnapshot = state.toSnapshot()
    const projectedRecords = await this.applyCanonicalSnapshot(mergedSnapshot, localRecords)
    const uploadEvents = this.mergeEventLists(remoteRead.ownEvents, pendingEvents)
    if (remoteRead.ownEvents.length > 0) {
      // Keep the same durable active-log semantics as upstream. Events remain
      // local until a checkpoint has safely incorporated them into snapshot.json.
      await this.eventStore.appendAll(remoteRead.ownEvents)
    }
    const uploadText = this.eventsToJsonLines(uploadEvents)
    const snapshotInitialized = await PreferencesStore.getInstance().getBoolean(
      WEBDAV_SYNC_HISTORY_SNAPSHOT_INITIALIZED_KEY, false)
    const shouldCheckpoint = !snapshotInitialized || !remoteRead.snapshotExists || !remoteRead.snapshotValid ||
      !remoteRead.eventLogsValid || importedLegacyHistory || this.utf8Length(uploadText) > HISTORY_CHECKPOINT_THRESHOLD
    if (shouldCheckpoint) {
      await this.writeCanonicalSnapshot(client, mergedSnapshot, deviceId)
      await client.deleteAtPath(UPSTREAM_HISTORY_CHANGES_PATH + '/' + deviceId + '.jsonl')
      await PreferencesStore.getInstance().setBoolean(WEBDAV_SYNC_HISTORY_SNAPSHOT_INITIALIZED_KEY, true)
    } else if (uploadText.length > 0) {
      await this.writeDeviceEventLog(client, deviceId, uploadText)
    }
    if (shouldCheckpoint) {
      const checkpointedIds: string[] = []
      for (let i = 0; i < uploadEvents.length; i++) checkpointedIds.push(uploadEvents[i].eventId)
      await this.eventStore.deleteByIds(checkpointedIds)
    }
    logger.info('History sync protocol merged local=%{public}d upstream=%{public}d merged=%{public}d events=%{public}d checkpoint=%{public}s',
      localRecords.length, remoteRead.snapshot.histories.length, projectedRecords.length, remoteRead.events.length,
      String(shouldCheckpoint))
    let collectResult = new CollectSyncResult()
    const collectSyncEnabled = await PreferencesStore.getInstance().getBoolean(WEBDAV_SYNC_COLLECT_KEY, true)
    if (collectSyncEnabled) {
      collectResult = await new CollectSyncService().sync(client)
    }
    const completedAt = Date.now()
    await PreferencesStore.getInstance().setNumber(WEBDAV_SYNC_LAST_TIME_KEY, completedAt)

    const result = new HistorySyncResult()
    result.success = true
    result.message = collectSyncEnabled ? `同步完成：历史 ${projectedRecords.length}，收藏 ${collectResult.mergedCount}` :
      `同步完成：历史 ${projectedRecords.length}`
    result.localCount = localRecords.length
    result.remoteCount = remoteRead.snapshot.histories.length
    result.mergedCount = projectedRecords.length
    result.collectLocalCount = collectResult.localCount
    result.collectRemoteCount = collectResult.remoteCount
    result.collectMergedCount = collectResult.mergedCount
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

  async recordProgress(record: HistoryRecord): Promise<void> {
    if (!await this.isWebDavFeatureUnlocked()) {
      return
    }
    if (!this.isValidUpstreamAdapterName(record.sourceName) && record.sourceId >= 0) {
      const rule = await this.ruleSourceStore.getById(record.sourceId)
      if (rule !== null) {
        record.sourceName = rule.name
      }
    }
    if (!this.isUpstreamExportable(record)) {
      return
    }
    const updatedAt = record.updatedAt > 0 ? record.updatedAt : Date.now()
    const progress = await this.createRecordEvent(record, 'upsertProgress', updatedAt)
    const watchState = await this.createRecordEvent(record, 'upsertWatchState', updatedAt)
    await this.eventStore.appendAll([progress, watchState])
    this.scheduleAutoUploadAfterLocalChange()
  }

  async recordDeleted(record: HistoryRecord): Promise<void> {
    if (!await this.isWebDavFeatureUnlocked()) return
    if (record.bangumiId <= 0) return
    if (!this.isValidUpstreamAdapterName(record.sourceName) && record.sourceId >= 0) {
      const rule = await this.ruleSourceStore.getById(record.sourceId)
      if (rule !== null) record.sourceName = rule.name
    }
    if (!this.isValidUpstreamAdapterName(record.sourceName)) return
    const event = new KazumiHistorySyncEvent()
    event.deviceId = await this.getDeviceId()
    event.seq = await this.nextSequence()
    event.eventId = event.deviceId + ':' + String(event.seq)
    event.op = 'deleteHistory'
    event.updatedAt = Date.now()
    event.entityKey = this.getUpstreamEntityKey(record)
    await this.eventStore.append(event)
    this.scheduleAutoUploadAfterLocalChange()
  }

  async recordCleared(): Promise<void> {
    if (!await this.isWebDavFeatureUnlocked()) return
    const event = new KazumiHistorySyncEvent()
    event.deviceId = await this.getDeviceId()
    event.seq = await this.nextSequence()
    event.eventId = event.deviceId + ':' + String(event.seq)
    event.op = 'clearAll'
    event.updatedAt = Date.now()
    await this.eventStore.append(event)
    this.scheduleAutoUploadAfterLocalChange()
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

  private async readCanonicalHistory(client: WebDavClient, deviceId: string): Promise<CanonicalHistoryReadResult> {
    const result = new CanonicalHistoryReadResult()
    const snapshotText = await client.downloadTextAtPath(UPSTREAM_HISTORY_SNAPSHOT_PATH)
    if (snapshotText !== null) {
      result.snapshotExists = true
      const parsed = KazumiHistorySyncSnapshot.fromText(snapshotText)
      if (parsed === null) {
        result.snapshotValid = false
        logger.warn('Kazumi history snapshot is malformed; rebuilding from valid device logs')
      } else {
        result.snapshot = parsed
      }
    }
    const fileNames = await client.listFileNamesAtPath(UPSTREAM_HISTORY_CHANGES_PATH)
    for (let i = 0; i < fileNames.length; i++) {
      if (!fileNames[i].endsWith('.jsonl')) continue
      const text = await client.downloadTextAtPath(UPSTREAM_HISTORY_CHANGES_PATH + '/' + fileNames[i])
      if (text === null || text.trim().length === 0) continue
      const events = this.parseCanonicalEventLines(text)
      if (events === null) {
        result.eventLogsValid = false
        logger.warn('Ignore malformed Kazumi history device log: %{public}s', fileNames[i])
        try {
          const sourcePath = UPSTREAM_HISTORY_CHANGES_PATH + '/' + fileNames[i]
          await client.moveAtPath(sourcePath, sourcePath + '.invalid.' + String(Date.now()))
        } catch (_err) {
          logger.warn('Quarantine malformed Kazumi history device log failed: %{public}s', fileNames[i])
        }
        continue
      }
      for (let j = 0; j < events.length; j++) result.events.push(events[j])
      if (fileNames[i] === deviceId + '.jsonl') {
        for (let j = 0; j < events.length; j++) result.ownEvents.push(events[j])
      }
    }
    return result
  }

  private isEmptyCanonicalHistory(snapshot: KazumiHistorySyncSnapshot): boolean {
    return snapshot.histories.length === 0 && snapshot.itemVersions.size === 0 &&
      snapshot.progressVersions.size === 0 && snapshot.deletedVersions.size === 0 &&
      snapshot.clearVersion.length === 0
  }

  private parseCanonicalEventLines(text: string): KazumiHistorySyncEvent[] | null {
    const events: KazumiHistorySyncEvent[] = []
    const lines = text.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length === 0) continue
      try {
        const event = KazumiHistorySyncEvent.fromJSON(JSON.parse(line) as Record<string, Object>)
        if (event === null) return null
        events.push(event)
      } catch (_err) {
        return null
      }
    }
    return events
  }

  private buildLocalStateEvents(records: HistoryRecord[]): KazumiHistorySyncEvent[] {
    const events: KazumiHistorySyncEvent[] = []
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      if (!this.isUpstreamExportable(record)) continue
      const updatedAt = record.updatedAt > 0 ? record.updatedAt : Date.now()
      const entityKey = this.getUpstreamEntityKey(record)
      const episodes = Array.from(record.progresses.keys())
      for (let j = 0; j < episodes.length; j++) {
        const stored = record.progresses.get(episodes[j])
        if (stored === undefined) continue
        const progressUpdatedAt = stored.updatedAtMs > 0 ? stored.updatedAtMs : updatedAt
        const progress = this.createStateEvent(record, 'upsertProgress', progressUpdatedAt,
          'local-state:' + entityKey + ':' + String(stored.episode) + ':' + String(stored.road))
        progress.episode = stored.episode
        progress.road = stored.road
        progress.progressMs = stored.progressMs
        events.push(progress)
      }
      const watchState = this.createStateEvent(record, 'upsertWatchState', updatedAt,
        'local-state:' + entityKey + ':watch-state')
      events.push(watchState)
    }
    return events
  }

  private buildImportedHistoryEvents(histories: KazumiHistoryItem[]): KazumiHistorySyncEvent[] {
    const events: KazumiHistorySyncEvent[] = []
    for (let i = 0; i < histories.length; i++) {
      const history = histories[i]
      const episodes = Array.from(history.progresses.keys())
      for (let j = 0; j < episodes.length; j++) {
        const progress = history.progresses.get(episodes[j])
        if (progress === undefined) continue
        const event = new KazumiHistorySyncEvent()
        event.eventId = 'legacy-import:' + history.entityKey + ':' + String(progress.episode)
        event.deviceId = 'legacy-import'
        event.op = 'upsertProgress'
        event.updatedAt = progress.updatedAtMs > 0 ? progress.updatedAtMs : history.lastWatchTime
        event.entityKey = history.entityKey
        event.bangumiItem = history.bangumiItem
        event.adapterName = history.adapterName
        event.episode = progress.episode
        event.road = progress.road
        event.progressMs = progress.progressMs
        event.entryKind = history.entryKind
        event.episodePageUrl = history.episodePageUrl
        events.push(event)
      }
      const watchState = new KazumiHistorySyncEvent()
      watchState.eventId = 'legacy-import:' + history.entityKey + ':watch-state'
      watchState.deviceId = 'legacy-import'
      watchState.op = 'upsertWatchState'
      watchState.updatedAt = history.lastWatchTime
      watchState.entityKey = history.entityKey
      watchState.bangumiItem = history.bangumiItem
      watchState.adapterName = history.adapterName
      watchState.episode = history.lastWatchEpisode
      watchState.lastSrc = history.lastSrc
      watchState.lastWatchEpisodeName = history.lastWatchEpisodeName
      watchState.entryKind = history.entryKind
      watchState.episodePageUrl = history.episodePageUrl
      watchState.carriesWatchState = true
      events.push(watchState)
    }
    return events
  }

  private createStateEvent(record: HistoryRecord, op: string, updatedAt: number,
    eventId: string): KazumiHistorySyncEvent {
    const event = new KazumiHistorySyncEvent()
    event.eventId = eventId
    event.deviceId = 'local-state'
    event.seq = 0
    event.op = op
    event.updatedAt = updatedAt
    event.entityKey = this.getUpstreamEntityKey(record)
    event.bangumiItem = this.upstreamBangumiItemToJSON(record)
    event.adapterName = this.getUpstreamAdapterName(record)
    event.episode = this.getUpstreamEpisode(record)
    event.road = record.roadIndex >= 0 ? record.roadIndex : 0
    event.progressMs = Math.max(0, record.positionMs)
    event.lastSrc = record.animeUrl
    event.lastWatchEpisodeName = record.episodeName
    event.entryKind = HistoryRecord.normalizeEntryKind(record.entryKind)
    event.episodePageUrl = record.episodePageUrl.length > 0 ? record.episodePageUrl : record.episodeUrl
    event.carriesWatchState = op === 'upsertWatchState'
    return event
  }

  private async createRecordEvent(record: HistoryRecord, op: string,
    updatedAt: number): Promise<KazumiHistorySyncEvent> {
    const deviceId = await this.getDeviceId()
    const seq = await this.nextSequence()
    return this.createDeviceEvent(record, op, updatedAt, deviceId, seq)
  }

  private createDeviceEvent(record: HistoryRecord, op: string, updatedAt: number,
    deviceId: string, seq: number): KazumiHistorySyncEvent {
    const event = this.createStateEvent(record, op, updatedAt, deviceId + ':' + String(seq))
    event.deviceId = deviceId
    event.seq = seq
    event.carriesWatchState = op === 'upsertWatchState'
    if (op === 'upsertProgress') {
      event.lastSrc = ''
      event.lastWatchEpisodeName = ''
    }
    return event
  }

  private async nextSequence(): Promise<number> {
    const operation = this.sequenceQueue.then(async (_previous: number): Promise<number> => {
      const prefs = PreferencesStore.getInstance()
      const current = await prefs.getNumber(WEBDAV_SYNC_SEQUENCE_KEY, 0)
      const next = Math.floor(current) + 1
      await prefs.setNumber(WEBDAV_SYNC_SEQUENCE_KEY, next)
      return next
    })
    this.sequenceQueue = operation.catch((_err: Error): number => 0)
    return await operation
  }

  private mergeEventLists(first: KazumiHistorySyncEvent[], second: KazumiHistorySyncEvent[]): KazumiHistorySyncEvent[] {
    const eventMap: Map<string, KazumiHistorySyncEvent> = new Map()
    this.putEvents(eventMap, first)
    this.putEvents(eventMap, second)
    const result = Array.from(eventMap.values())
    result.sort((a: KazumiHistorySyncEvent, b: KazumiHistorySyncEvent) => {
      if (a.version < b.version) return -1
      if (a.version > b.version) return 1
      return 0
    })
    return result
  }

  private putEvents(target: Map<string, KazumiHistorySyncEvent>, events: KazumiHistorySyncEvent[]): void {
    for (let i = 0; i < events.length; i++) target.set(events[i].eventId, events[i])
  }

  private eventsToJsonLines(events: KazumiHistorySyncEvent[]): string {
    if (events.length === 0) return ''
    const lines: string[] = []
    for (let i = 0; i < events.length; i++) lines.push(JSON.stringify(events[i].toJSON()))
    return lines.join('\n') + '\n'
  }

  private utf8Length(value: string): number {
    let byteLength = 0
    for (let i = 0; i < value.length; i++) {
      const codeUnit = value.charCodeAt(i)
      if (codeUnit <= 0x7F) {
        byteLength += 1
      } else if (codeUnit <= 0x7FF) {
        byteLength += 2
      } else if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < value.length) {
        const nextCodeUnit = value.charCodeAt(i + 1)
        if (nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF) {
          byteLength += 4
          i += 1
        } else {
          byteLength += 3
        }
      } else {
        byteLength += 3
      }
    }
    return byteLength
  }

  private async writeDeviceEventLog(client: WebDavClient, deviceId: string, content: string): Promise<void> {
    const target = UPSTREAM_HISTORY_CHANGES_PATH + '/' + deviceId + '.jsonl'
    const temporary = target + '.cache'
    await client.replaceTextAtPath(target, temporary, content)
  }

  private async writeCanonicalSnapshot(client: WebDavClient, snapshot: KazumiHistorySyncSnapshot,
    deviceId: string): Promise<void> {
    const temporary = UPSTREAM_HISTORY_SNAPSHOT_PATH + '.' + deviceId + '.cache'
    await client.replaceTextAtPath(UPSTREAM_HISTORY_SNAPSHOT_PATH, temporary, JSON.stringify(snapshot.toJSON()))
  }

  private async applyCanonicalSnapshot(snapshot: KazumiHistorySyncSnapshot,
    localRecords: HistoryRecord[]): Promise<HistoryRecord[]> {
    const localByEntity: Map<string, HistoryRecord> = new Map()
    for (let i = 0; i < localRecords.length; i++) {
      if (localRecords[i].bangumiId > 0 && this.isValidUpstreamAdapterName(localRecords[i].sourceName)) {
        const entityKey = this.getUpstreamEntityKey(localRecords[i])
        if (!localByEntity.has(entityKey)) localByEntity.set(entityKey, localRecords[i])
      }
    }
    const projected: HistoryRecord[] = []
    const keepEntities: Set<string> = new Set()
    for (let i = 0; i < snapshot.histories.length; i++) {
      const item = snapshot.histories[i]
      const record = this.historyRecordFromUpstreamHistory(item.toJSON())
      if (record === null) continue
      const existing = localByEntity.get(item.entityKey)
      if (existing !== undefined) this.combineHistoryRecords(record, existing)
      projected.push(record)
      keepEntities.add(item.entityKey)
    }
    await this.enrichRuleSourceInfo(projected)
    await this.enrichMissingBangumiCovers(projected)
    for (let i = 0; i < projected.length; i++) {
      await this.historyStore.upsertPreservingUpdatedAt(projected[i], false)
    }
    for (let i = 0; i < localRecords.length; i++) {
      const record = localRecords[i]
      if (record.bangumiId <= 0 || !this.isValidUpstreamAdapterName(record.sourceName)) continue
      if (!keepEntities.has(this.getUpstreamEntityKey(record))) {
        await this.historyStore.deleteByAnimeId(record.animeId)
      }
    }
    await this.deleteMergedDuplicateLocalRecords(projected)
    projected.sort((a: HistoryRecord, b: HistoryRecord) => b.updatedAt - a.updatedAt)
    return projected
  }

  private async isWebDavFeatureUnlocked(): Promise<boolean> {
    return true
  }

  private async ensureWebDavFeatureUnlocked(): Promise<void> {
    if (!await this.isWebDavFeatureUnlocked()) {
      throw new Error('WebDAV 同步属于隐藏功能，请先解锁后使用')
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
    if (winner.animeCover.length === 0) {
      winner.animeCover = existing.animeCover
    }
    if (winner.animeName.length === 0) {
      winner.animeName = existing.animeName
    }
    if (winner.sourceId < 0) {
      winner.sourceId = existing.sourceId
    }
    if (winner.durationMs <= 0 && winner.episodeIndex === existing.episodeIndex &&
      winner.roadIndex === existing.roadIndex) {
      winner.durationMs = existing.durationMs
    }
    return winner
  }

  private getHistoryMergeKey(record: HistoryRecord): string {
    if (record.bangumiId > 0) {
      const sourceKey = record.sourceName.length > 0 ? record.sourceName :
        (record.sourceId >= 0 ? 'source_' + String(record.sourceId) : '')
      if (sourceKey.length > 0) {
        return 'bangumi:' + sourceKey + ':' + String(record.bangumiId) + ':' +
          HistoryRecord.normalizeEntryKind(record.entryKind)
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

  private async deleteMergedDuplicateLocalRecords(records: HistoryRecord[]): Promise<void> {
    const keepAnimeIds: Set<string> = new Set()
    const keepMergeKeys: Set<string> = new Set()
    for (let i = 0; i < records.length; i++) {
      keepAnimeIds.add(records[i].animeId)
      keepMergeKeys.add(this.getHistoryMergeKey(records[i]))
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
      this.normalizeHistoryRecordCover(record)
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
    if (HistoryRecord.normalizeEntryKind(record.entryKind) === 'online' &&
      record.sourceId >= 0 && record.animeUrl.length > 0) {
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
    record.entryKind = HistoryRecord.normalizeEntryKind(String(history['entryKind'] ?? 'online'))
    record.animeId = adapterName + String(bangumiId) + '::' + record.entryKind
    record.bangumiItemJSON = JSON.stringify(bangumiItem)
    record.animeName = this.resolveUpstreamAnimeName(bangumiItem)
    record.animeCover = this.resolveUpstreamCover(bangumiItem)
    const lastSrc = String(history['lastSrc'] ?? '')
    record.animeUrl = lastSrc
    record.episodeName = String(history['lastWatchEpisodeName'] ?? '')
    if (record.episodeName.length === 0) {
      record.episodeName = '第' + String(lastWatchEpisode) + '集'
    }
    const episodePageUrl = String(history['episodePageUrl'] ?? '')
    record.episodePageUrl = episodePageUrl
    record.episodeUrl = episodePageUrl.length > 0 ? episodePageUrl : lastSrc
    record.updatedAt = this.numberValue(history['lastWatchTime'], Date.now())
    record.episodeIndex = Math.max(0, lastWatchEpisode - 1)
    const progressesObj = history['progresses']
    if (progressesObj !== undefined && progressesObj !== null) {
      const progresses = progressesObj as Record<string, Object>
      const episodes = Object.keys(progresses)
      for (let i = 0; i < episodes.length; i++) {
        const progress = this.progressFromUpstreamJson(progresses[episodes[i]] as Record<string, Object>)
        const episodeFromKey = Number(episodes[i])
        if (Number.isFinite(episodeFromKey)) progress.episode = episodeFromKey
        if (progress.episode > 0) record.progresses.set(progress.episode, progress)
      }
    }
    const progress = this.resolveUpstreamProgress(history, lastWatchEpisode)
    record.roadIndex = progress.road
    record.positionMs = progress.progressMs
    return record
  }

  private resolveUpstreamProgress(history: Record<string, Object>, episode: number): HistoryEpisodeProgress {
    const fallback = new HistoryEpisodeProgress()
    const progressesObj = history['progresses']
    if (progressesObj === undefined) {
      return fallback
    }
    const progresses = progressesObj as Record<string, Object>
    const progressObj = progresses[String(episode)]
    if (progressObj === undefined) {
      return fallback
    }
    return this.progressFromUpstreamJson(progressObj as Record<string, Object>)
  }

  private progressFromUpstreamJson(json: Record<string, Object>): HistoryEpisodeProgress {
    const progress = new HistoryEpisodeProgress()
    progress.episode = this.numberValue(json['episode'], 1)
    progress.road = this.numberValue(json['road'], 0)
    progress.progressMs = this.numberValue(json['progressMs'], 0)
    progress.updatedAtMs = this.numberValue(json['updatedAtMs'], 0)
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
    if (typeof value === 'object') {
      const objectValue = value as Record<string, Object>
      const keys: string[] = ['url', 'large', 'common', 'medium', 'grid', 'small']
      for (let i = 0; i < keys.length; i++) {
        const nested = this.normalizeUpstreamCoverValue(objectValue[keys[i]])
        if (nested.length > 0) {
          return nested
        }
      }
      return ''
    }
    const raw = String(value).trim()
    return raw.length > 0 ? BangumiConfig.normalizeImageUrl(raw) : ''
  }

  private normalizeHistoryRecordCover(record: HistoryRecord): void {
    const raw = record.animeCover.trim()
    if (raw.length === 0 || raw.startsWith('file://') || raw.startsWith('/')) {
      return
    }
    const normalized = BangumiConfig.normalizeImageUrl(raw)
    if (normalized.length > 0) {
      record.animeCover = normalized
    } else {
      // Old sync payloads may contain a serialized image object or an invalid
      // host. Treat it as missing so the subject-image fallback can repair it.
      record.animeCover = ''
    }
  }

  private upstreamBangumiItemToJSON(record: HistoryRecord): Record<string, Object> {
    if (record.bangumiItemJSON.length > 0) {
      try {
        return JSON.parse(record.bangumiItemJSON) as Record<string, Object>
      } catch (_err) {
        logger.warn('Ignore malformed local Bangumi history payload')
      }
    }
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

  private getUpstreamEntityKey(record: HistoryRecord): string {
    return KazumiHistoryItem.scopedKey(this.getUpstreamAdapterName(record), record.bangumiId,
      HistoryRecord.normalizeEntryKind(record.entryKind))
  }

  private isUpstreamExportable(record: HistoryRecord): boolean {
    return record.bangumiId > 0 && this.isValidUpstreamAdapterName(record.sourceName)
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

  private parseLegacyPrivateHistory(text: string | null): HistoryRecord[] {
    const result: HistoryRecord[] = []
    if (text === null || text.trim().length === 0) {
      return result
    }
    try {
      const parsed = JSON.parse(text) as Record<string, Object>
      const recordsObj = parsed['records']
      if (recordsObj instanceof Array) {
        const records = recordsObj as Record<string, Object>[]
        for (let i = 0; i < records.length; i++) {
          const record = HistoryRecord.fromJSON(records[i])
          this.normalizeHistoryRecordCover(record)
          result.push(record)
        }
      }
    } catch (err) {
      logger.warn('Parse remote history payload failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return result
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
