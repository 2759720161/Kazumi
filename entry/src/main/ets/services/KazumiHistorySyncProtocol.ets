const ONLINE_ENTRY_KIND: string = 'online'

export class KazumiHistoryProgress {
  episode: number = 1
  road: number = 0
  progressMs: number = 0
  updatedAtMs: number = 0

  static fromJSON(json: Record<string, Object>): KazumiHistoryProgress {
    const progress = new KazumiHistoryProgress()
    progress.episode = HistorySyncValue.number(json['episode'], 1)
    progress.road = HistorySyncValue.number(json['road'], 0)
    progress.progressMs = Math.max(0, HistorySyncValue.number(json['progressMs'], 0))
    progress.updatedAtMs = HistorySyncValue.number(json['updatedAtMs'], 0)
    return progress
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['episode'] = this.episode
    result['road'] = this.road
    result['progressMs'] = this.progressMs
    if (this.updatedAtMs > 0) {
      result['updatedAtMs'] = this.updatedAtMs
    }
    return result
  }
}

export class KazumiHistoryItem {
  bangumiItem: Record<string, Object> = {}
  lastWatchEpisode: number = 1
  adapterName: string = ''
  lastWatchTime: number = 0
  lastSrc: string = ''
  lastWatchEpisodeName: string = ''
  entryKind: string = ONLINE_ENTRY_KIND
  episodePageUrl: string = ''
  progresses: Map<number, KazumiHistoryProgress> = new Map()

  get bangumiId(): number {
    return HistorySyncValue.number(this.bangumiItem['id'], -1)
  }

  get entityKey(): string {
    return KazumiHistoryItem.scopedKey(this.adapterName, this.bangumiId, this.entryKind)
  }

  get legacyKey(): string {
    return KazumiHistoryItem.legacyEntityKey(this.adapterName, this.bangumiId)
  }

  static normalizeEntryKind(value: string): string {
    return value === 'offline' ? 'offline' : ONLINE_ENTRY_KIND
  }

  static legacyEntityKey(adapterName: string, bangumiId: number): string {
    return adapterName + String(bangumiId)
  }

  static scopedKey(adapterName: string, bangumiId: number, entryKind: string): string {
    return KazumiHistoryItem.legacyEntityKey(adapterName, bangumiId) + '::' +
      KazumiHistoryItem.normalizeEntryKind(entryKind)
  }

  static fromJSON(json: Record<string, Object>): KazumiHistoryItem | null {
    const bangumiObject = json['bangumiItem']
    if (bangumiObject === undefined || bangumiObject === null) {
      return null
    }
    const item = new KazumiHistoryItem()
    item.bangumiItem = bangumiObject as Record<string, Object>
    if (item.bangumiId <= 0) {
      return null
    }
    item.lastWatchEpisode = HistorySyncValue.number(json['lastWatchEpisode'], 1)
    item.adapterName = HistorySyncValue.string(json['adapterName'])
    item.lastWatchTime = HistorySyncValue.number(json['lastWatchTime'], Date.now())
    item.lastSrc = HistorySyncValue.string(json['lastSrc'])
    item.lastWatchEpisodeName = HistorySyncValue.string(json['lastWatchEpisodeName'])
    item.entryKind = KazumiHistoryItem.normalizeEntryKind(HistorySyncValue.string(json['entryKind']))
    item.episodePageUrl = HistorySyncValue.string(json['episodePageUrl'])
    const progressesObject = json['progresses']
    if (progressesObject !== undefined && progressesObject !== null) {
      const progresses = progressesObject as Record<string, Object>
      const keys = Object.keys(progresses)
      for (let i = 0; i < keys.length; i++) {
        const value = progresses[keys[i]]
        if (value === undefined || value === null) {
          continue
        }
        const progress = KazumiHistoryProgress.fromJSON(value as Record<string, Object>)
        const episode = Number(keys[i])
        item.progresses.set(Number.isFinite(episode) ? episode : progress.episode, progress)
      }
    }
    return item
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['bangumiItem'] = this.bangumiItem
    result['lastWatchEpisode'] = this.lastWatchEpisode
    result['adapterName'] = this.adapterName
    result['lastWatchTime'] = this.lastWatchTime
    result['lastSrc'] = this.lastSrc
    result['lastWatchEpisodeName'] = this.lastWatchEpisodeName
    result['entryKind'] = this.entryKind
    if (this.episodePageUrl.length > 0) {
      result['episodePageUrl'] = this.episodePageUrl
    }
    const progresses: Record<string, Object> = {}
    const episodes = Array.from(this.progresses.keys())
    episodes.sort((a: number, b: number) => a - b)
    for (let i = 0; i < episodes.length; i++) {
      const progress = this.progresses.get(episodes[i])
      if (progress !== undefined) {
        progresses[String(episodes[i])] = progress.toJSON()
      }
    }
    result['progresses'] = progresses
    return result
  }
}

export class KazumiHistorySyncEvent {
  eventId: string = ''
  deviceId: string = ''
  seq: number = 0
  op: string = ''
  updatedAt: number = 0
  entityKey: string = ''
  bangumiItem: Record<string, Object> | null = null
  adapterName: string = ''
  episode: number = 1
  road: number = 0
  progressMs: number = 0
  lastSrc: string = ''
  lastWatchEpisodeName: string = ''
  entryKind: string = ONLINE_ENTRY_KIND
  episodePageUrl: string = ''
  carriesWatchState: boolean = false

  get version(): string {
    return KazumiHistorySyncVersion.of(this.updatedAt, this.eventId)
  }

  static fromJSON(json: Record<string, Object>): KazumiHistorySyncEvent | null {
    if (!HistorySyncValue.isRequiredString(json['eventId']) ||
      !HistorySyncValue.isRequiredString(json['deviceId']) ||
      !HistorySyncValue.isFiniteNumber(json['seq']) ||
      !HistorySyncValue.isRequiredString(json['op']) ||
      !HistorySyncValue.isFiniteNumber(json['updatedAt']) ||
      !HistorySyncValue.isOptionalString(json['entityKey']) ||
      !HistorySyncValue.isOptionalString(json['adapterName']) ||
      !HistorySyncValue.isOptionalNumber(json['episode']) ||
      !HistorySyncValue.isOptionalNumber(json['road']) ||
      !HistorySyncValue.isOptionalNumber(json['progressMs']) ||
      !HistorySyncValue.isOptionalString(json['lastSrc']) ||
      !HistorySyncValue.isOptionalString(json['lastWatchEpisodeName']) ||
      !HistorySyncValue.isOptionalString(json['entryKind']) ||
      !HistorySyncValue.isOptionalString(json['episodePageUrl']) ||
      !HistorySyncValue.isOptionalBoolean(json['carriesWatchState'])) {
      return null
    }
    const event = new KazumiHistorySyncEvent()
    event.eventId = HistorySyncValue.string(json['eventId'])
    event.deviceId = HistorySyncValue.string(json['deviceId'])
    event.seq = HistorySyncValue.number(json['seq'], 0)
    event.op = HistorySyncValue.string(json['op'])
    event.updatedAt = HistorySyncValue.number(json['updatedAt'], 0)
    event.entityKey = HistorySyncValue.string(json['entityKey'])
    const bangumiItem = json['bangumiItem']
    if (bangumiItem !== undefined && bangumiItem !== null) {
      event.bangumiItem = bangumiItem as Record<string, Object>
    }
    event.adapterName = HistorySyncValue.string(json['adapterName'])
    event.episode = HistorySyncValue.number(json['episode'], 1)
    event.road = HistorySyncValue.number(json['road'], 0)
    event.progressMs = Math.max(0, HistorySyncValue.number(json['progressMs'], 0))
    event.lastSrc = HistorySyncValue.string(json['lastSrc'])
    event.lastWatchEpisodeName = HistorySyncValue.string(json['lastWatchEpisodeName'])
    event.entryKind = KazumiHistoryItem.normalizeEntryKind(HistorySyncValue.string(json['entryKind']))
    event.episodePageUrl = HistorySyncValue.string(json['episodePageUrl'])
    event.carriesWatchState = HistorySyncValue.boolean(json['carriesWatchState'], false) ||
      json['lastSrc'] !== undefined || json['lastWatchEpisodeName'] !== undefined
    if (event.eventId.length === 0 || event.updatedAt <= 0) {
      return null
    }
    if (event.op === 'upsertProgress') {
      if (!HistorySyncValue.isBangumiItem(event.bangumiItem) || event.adapterName.length === 0 ||
        !HistorySyncValue.isFiniteNumber(json['episode']) || !HistorySyncValue.isFiniteNumber(json['road']) ||
        !HistorySyncValue.isFiniteNumber(json['progressMs'])) {
        return null
      }
    } else if (event.op === 'upsertWatchState') {
      if (!HistorySyncValue.isBangumiItem(event.bangumiItem) || event.adapterName.length === 0 ||
        !HistorySyncValue.isFiniteNumber(json['episode'])) {
        return null
      }
    } else if (event.op === 'deleteHistory') {
      if (event.entityKey.length === 0) {
        return null
      }
    } else if (event.op !== 'clearAll') {
      return null
    }
    return event
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['eventId'] = this.eventId
    result['deviceId'] = this.deviceId
    result['seq'] = this.seq
    result['op'] = this.op
    result['updatedAt'] = this.updatedAt
    if (this.entityKey.length > 0) result['entityKey'] = this.entityKey
    if (this.bangumiItem !== null) result['bangumiItem'] = this.bangumiItem
    if (this.adapterName.length > 0) result['adapterName'] = this.adapterName
    if (this.op === 'upsertProgress' || this.op === 'upsertWatchState') result['episode'] = this.episode
    if (this.op === 'upsertProgress') {
      result['road'] = this.road
      result['progressMs'] = this.progressMs
    }
    if (this.lastSrc.length > 0) result['lastSrc'] = this.lastSrc
    if (this.lastWatchEpisodeName.length > 0) result['lastWatchEpisodeName'] = this.lastWatchEpisodeName
    if (this.op === 'upsertProgress' || this.op === 'upsertWatchState') result['entryKind'] = this.entryKind
    if (this.episodePageUrl.length > 0) result['episodePageUrl'] = this.episodePageUrl
    if (this.carriesWatchState) result['carriesWatchState'] = true
    return result
  }
}

export class KazumiHistorySyncSnapshot {
  generatedAt: number = Date.now()
  histories: KazumiHistoryItem[] = []
  itemVersions: Map<string, string> = new Map()
  progressVersions: Map<string, Map<number, string>> = new Map()
  deletedVersions: Map<string, string> = new Map()
  clearVersion: string = ''

  static empty(): KazumiHistorySyncSnapshot {
    return new KazumiHistorySyncSnapshot()
  }

  static fromText(text: string): KazumiHistorySyncSnapshot | null {
    try {
      const parsed = JSON.parse(text) as Object
      if (!HistorySyncValue.isRecord(parsed)) return null
      const json = parsed as Record<string, Object>
      const histories = json['histories']
      if (histories !== undefined && histories !== null && !(histories instanceof Array)) return null
       if (histories instanceof Array) {
         const historyItems = histories as Object[]
         for (let i = 0; i < historyItems.length; i++) {
           if (!HistorySyncValue.isRecord(historyItems[i])) return null
           const history = historyItems[i] as Record<string, Object>
           if (!HistorySyncValue.isBangumiItem(history['bangumiItem']) ||
             !HistorySyncValue.isFiniteNumber(history['lastWatchEpisode']) ||
             !HistorySyncValue.isRequiredString(history['adapterName']) ||
             !HistorySyncValue.isFiniteNumber(history['lastWatchTime']) ||
             !HistorySyncValue.isOptionalString(history['lastSrc']) ||
             !HistorySyncValue.isOptionalString(history['lastWatchEpisodeName']) ||
             !HistorySyncValue.isOptionalString(history['entryKind']) ||
             !HistorySyncValue.isOptionalString(history['episodePageUrl']) ||
             !HistorySyncValue.isProgressRecord(history['progresses'])) return null
         }
       }
      if (!HistorySyncValue.isOptionalStringRecord(json['itemVersions']) ||
        !HistorySyncValue.isOptionalProgressVersionRecord(json['progressVersions']) ||
        !HistorySyncValue.isOptionalStringRecord(json['deletedVersions'])) return null
      const clearVersion = json['clearVersion']
      if (clearVersion !== undefined && clearVersion !== null && typeof clearVersion !== 'string') return null
      return KazumiHistorySyncSnapshot.fromJSON(json)
    } catch (_err) {
      return null
    }
  }

  static fromJSON(json: Record<string, Object>): KazumiHistorySyncSnapshot {
    const snapshot = new KazumiHistorySyncSnapshot()
    snapshot.generatedAt = HistorySyncValue.number(json['generatedAt'], Date.now())
    const aliases: Map<string, string> = new Map()
    const historiesObject = json['histories']
    if (historiesObject instanceof Array) {
      const histories = historiesObject as Record<string, Object>[]
      for (let i = 0; i < histories.length; i++) {
        const history = KazumiHistoryItem.fromJSON(histories[i])
        if (history === null) {
          continue
        }
        snapshot.histories.push(history)
        aliases.set(history.entityKey, history.entityKey)
        if (history.entryKind === ONLINE_ENTRY_KIND) {
          aliases.set(history.legacyKey, history.entityKey)
        }
      }
    }
    snapshot.itemVersions = HistorySyncMaps.readVersionMap(json['itemVersions'], aliases)
    snapshot.progressVersions = HistorySyncMaps.readProgressVersionMap(json['progressVersions'], aliases)
    snapshot.deletedVersions = HistorySyncMaps.readVersionMap(json['deletedVersions'], aliases)
    snapshot.clearVersion = HistorySyncValue.string(json['clearVersion'])
    return snapshot
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['schemaVersion'] = 1
    result['generatedAt'] = this.generatedAt
    const histories: Record<string, Object>[] = []
    for (let i = 0; i < this.histories.length; i++) {
      histories.push(this.histories[i].toJSON())
    }
    result['histories'] = histories
    result['itemVersions'] = HistorySyncMaps.versionMapToJSON(this.itemVersions)
    result['progressVersions'] = HistorySyncMaps.progressVersionMapToJSON(this.progressVersions)
    result['deletedVersions'] = HistorySyncMaps.versionMapToJSON(this.deletedVersions)
    if (this.clearVersion.length > 0) result['clearVersion'] = this.clearVersion
    return result
  }
}

export class KazumiHistorySyncState {
  histories: Map<string, KazumiHistoryItem> = new Map()
  itemVersions: Map<string, string> = new Map()
  progressVersions: Map<string, Map<number, string>> = new Map()
  deletedVersions: Map<string, string> = new Map()
  clearVersion: string = ''

  static fromSnapshot(snapshot: KazumiHistorySyncSnapshot): KazumiHistorySyncState {
    const state = new KazumiHistorySyncState()
    for (let i = 0; i < snapshot.histories.length; i++) {
      const history = snapshot.histories[i]
      state.histories.set(history.entityKey, history)
    }
    state.itemVersions = HistorySyncMaps.copyVersionMap(snapshot.itemVersions)
    state.progressVersions = HistorySyncMaps.copyProgressVersionMap(snapshot.progressVersions)
    state.deletedVersions = HistorySyncMaps.copyVersionMap(snapshot.deletedVersions)
    state.clearVersion = snapshot.clearVersion
    return state
  }

  applyAll(events: KazumiHistorySyncEvent[]): void {
    events.sort((a: KazumiHistorySyncEvent, b: KazumiHistorySyncEvent) =>
      KazumiHistorySyncVersion.compare(a.version, b.version))
    for (let i = 0; i < events.length; i++) {
      this.apply(events[i])
    }
  }

  apply(event: KazumiHistorySyncEvent): void {
    if (event.op === 'upsertProgress') {
      this.applyProgress(event)
    } else if (event.op === 'upsertWatchState') {
      this.applyWatchState(event)
    } else if (event.op === 'deleteHistory') {
      this.applyDelete(event)
    } else if (event.op === 'clearAll') {
      this.applyClear(event)
    }
  }

  toSnapshot(): KazumiHistorySyncSnapshot {
    const snapshot = new KazumiHistorySyncSnapshot()
    snapshot.generatedAt = Date.now()
    snapshot.histories = Array.from(this.histories.values())
    snapshot.itemVersions = HistorySyncMaps.copyVersionMap(this.itemVersions)
    snapshot.progressVersions = HistorySyncMaps.copyProgressVersionMap(this.progressVersions)
    snapshot.deletedVersions = HistorySyncMaps.copyVersionMap(this.deletedVersions)
    snapshot.clearVersion = this.clearVersion
    return snapshot
  }

  private applyProgress(event: KazumiHistorySyncEvent): void {
    if (event.bangumiItem === null || !this.isNewerThanClear(event.version)) return
    const bangumiId = HistorySyncValue.number(event.bangumiItem['id'], -1)
    if (bangumiId <= 0) return
    const entityKey = KazumiHistoryItem.scopedKey(event.adapterName, bangumiId, event.entryKind)
    const legacyKey = KazumiHistoryItem.legacyEntityKey(event.adapterName, bangumiId)
    const deletedVersion = this.deletedVersionForUpsert(entityKey, legacyKey, event.entryKind)
    if (deletedVersion.length > 0 && KazumiHistorySyncVersion.compare(event.version, deletedVersion) <= 0) return
    let current = this.histories.get(entityKey)
    if (current === undefined) {
      current = this.newItemFromEvent(event)
    }
    let episodeVersions = this.progressVersions.get(entityKey)
    if (episodeVersions === undefined) {
      episodeVersions = new Map()
      this.progressVersions.set(entityKey, episodeVersions)
    }
    const previous = episodeVersions.get(event.episode)
    if (previous === undefined || KazumiHistorySyncVersion.compare(event.version, previous) >= 0) {
      const progress = new KazumiHistoryProgress()
      progress.episode = event.episode
      progress.road = event.road
      progress.progressMs = event.progressMs
      progress.updatedAtMs = event.updatedAt
      current.progresses.set(event.episode, progress)
      episodeVersions.set(event.episode, event.version)
    }
    this.histories.set(entityKey, current)
    this.deletedVersions.delete(entityKey)
    if (event.entryKind === ONLINE_ENTRY_KIND) this.deletedVersions.delete(legacyKey)
    if (event.carriesWatchState && !event.eventId.startsWith('local-state:')) {
      this.applyWatchState(event)
    }
  }

  private applyWatchState(event: KazumiHistorySyncEvent): void {
    if (event.bangumiItem === null || !this.isNewerThanClear(event.version)) return
    const bangumiId = HistorySyncValue.number(event.bangumiItem['id'], -1)
    if (bangumiId <= 0) return
    const entityKey = KazumiHistoryItem.scopedKey(event.adapterName, bangumiId, event.entryKind)
    const legacyKey = KazumiHistoryItem.legacyEntityKey(event.adapterName, bangumiId)
    const deletedVersion = this.deletedVersionForUpsert(entityKey, legacyKey, event.entryKind)
    if (deletedVersion.length > 0 && KazumiHistorySyncVersion.compare(event.version, deletedVersion) <= 0) return
    let current = this.histories.get(entityKey)
    if (current === undefined) current = this.newItemFromEvent(event)
    const previous = this.itemVersions.get(entityKey)
    if (previous === undefined || KazumiHistorySyncVersion.compare(event.version, previous) >= 0) {
      current.bangumiItem = event.bangumiItem
      current.adapterName = event.adapterName
      current.lastWatchEpisode = event.episode
      current.lastWatchTime = event.updatedAt
      if (event.lastSrc.length > 0) current.lastSrc = event.lastSrc
      if (event.lastWatchEpisodeName.length > 0) current.lastWatchEpisodeName = event.lastWatchEpisodeName
      current.entryKind = event.entryKind
      if (event.episodePageUrl.length > 0) current.episodePageUrl = event.episodePageUrl
      this.itemVersions.set(entityKey, event.version)
    }
    this.histories.set(entityKey, current)
    this.deletedVersions.delete(entityKey)
    if (event.entryKind === ONLINE_ENTRY_KIND) this.deletedVersions.delete(legacyKey)
  }

  private applyDelete(event: KazumiHistorySyncEvent): void {
    if (!this.isNewerThanClear(event.version)) return
    const entityKey = this.canonicalExistingKey(event.entityKey)
    const itemVersion = this.itemVersions.get(entityKey)
    const deleteVersion = this.deletedVersions.get(entityKey)
    const newerThanItem = itemVersion === undefined || KazumiHistorySyncVersion.compare(event.version, itemVersion) >= 0
    const newerThanDelete = deleteVersion === undefined || KazumiHistorySyncVersion.compare(event.version, deleteVersion) >= 0
    if (newerThanItem && newerThanDelete) {
      this.histories.delete(entityKey)
      this.itemVersions.delete(entityKey)
      this.progressVersions.delete(entityKey)
      this.deletedVersions.set(entityKey, event.version)
    }
  }

  private applyClear(event: KazumiHistorySyncEvent): void {
    if (!this.isNewerThanClear(event.version)) return
    this.histories.clear()
    this.itemVersions.clear()
    this.progressVersions.clear()
    this.deletedVersions.clear()
    this.clearVersion = event.version
  }

  private newItemFromEvent(event: KazumiHistorySyncEvent): KazumiHistoryItem {
    const item = new KazumiHistoryItem()
    item.bangumiItem = event.bangumiItem ?? {}
    item.lastWatchEpisode = event.episode
    item.adapterName = event.adapterName
    item.lastWatchTime = event.updatedAt
    item.lastSrc = event.lastSrc
    item.lastWatchEpisodeName = event.lastWatchEpisodeName
    item.entryKind = event.entryKind
    item.episodePageUrl = event.episodePageUrl
    return item
  }

  private isNewerThanClear(version: string): boolean {
    return this.clearVersion.length === 0 || KazumiHistorySyncVersion.compare(version, this.clearVersion) > 0
  }

  private canonicalExistingKey(key: string): string {
    if (this.histories.has(key) || this.itemVersions.has(key) || this.progressVersions.has(key)) return key
    const values = Array.from(this.histories.values())
    for (let i = 0; i < values.length; i++) {
      if (values[i].entryKind === ONLINE_ENTRY_KIND && values[i].legacyKey === key) return values[i].entityKey
    }
    return key
  }

  private deletedVersionForUpsert(entityKey: string, legacyKey: string, entryKind: string): string {
    const scoped = this.deletedVersions.get(entityKey) ?? ''
    if (entryKind !== ONLINE_ENTRY_KIND) return scoped
    const legacy = this.deletedVersions.get(legacyKey) ?? ''
    return KazumiHistorySyncVersion.compare(scoped, legacy) >= 0 ? scoped : legacy
  }
}

export class KazumiHistorySyncVersion {
  static of(updatedAt: number, eventId: string): string {
    return Math.floor(updatedAt).toString().padStart(16, '0') + '|' + eventId
  }

  static compare(a: string, b: string): number {
    if (a < b) return -1
    if (a > b) return 1
    return 0
  }
}

class HistorySyncMaps {
  static readVersionMap(value: Object | undefined, aliases: Map<string, string>): Map<string, string> {
    const result: Map<string, string> = new Map()
    if (value === undefined || value === null) return result
    const json = value as Record<string, Object>
    const keys = Object.keys(json)
    for (let i = 0; i < keys.length; i++) {
      const key = aliases.get(keys[i]) ?? keys[i]
      const version = HistorySyncValue.string(json[keys[i]])
      const existing = result.get(key)
      if (existing === undefined || KazumiHistorySyncVersion.compare(version, existing) > 0) result.set(key, version)
    }
    return result
  }

  static readProgressVersionMap(value: Object | undefined, aliases: Map<string, string>): Map<string, Map<number, string>> {
    const result: Map<string, Map<number, string>> = new Map()
    if (value === undefined || value === null) return result
    const json = value as Record<string, Object>
    const keys = Object.keys(json)
    for (let i = 0; i < keys.length; i++) {
      const key = aliases.get(keys[i]) ?? keys[i]
      let target = result.get(key)
      if (target === undefined) {
        target = new Map()
        result.set(key, target)
      }
      const episodeJson = json[keys[i]] as Record<string, Object>
      const episodes = Object.keys(episodeJson)
      for (let j = 0; j < episodes.length; j++) {
        const episode = Number(episodes[j])
        if (!Number.isFinite(episode)) continue
        const version = HistorySyncValue.string(episodeJson[episodes[j]])
        const existing = target.get(episode)
        if (existing === undefined || KazumiHistorySyncVersion.compare(version, existing) > 0) target.set(episode, version)
      }
    }
    return result
  }

  static versionMapToJSON(map: Map<string, string>): Record<string, Object> {
    const result: Record<string, Object> = {}
    const keys = Array.from(map.keys())
    for (let i = 0; i < keys.length; i++) result[keys[i]] = map.get(keys[i]) ?? ''
    return result
  }

  static progressVersionMapToJSON(map: Map<string, Map<number, string>>): Record<string, Object> {
    const result: Record<string, Object> = {}
    const keys = Array.from(map.keys())
    for (let i = 0; i < keys.length; i++) {
      const episodeResult: Record<string, Object> = {}
      const episodes = map.get(keys[i])
      if (episodes !== undefined) {
        const episodeKeys = Array.from(episodes.keys())
        for (let j = 0; j < episodeKeys.length; j++) {
          episodeResult[String(episodeKeys[j])] = episodes.get(episodeKeys[j]) ?? ''
        }
      }
      result[keys[i]] = episodeResult
    }
    return result
  }

  static copyVersionMap(source: Map<string, string>): Map<string, string> {
    const result: Map<string, string> = new Map()
    const keys = Array.from(source.keys())
    for (let i = 0; i < keys.length; i++) result.set(keys[i], source.get(keys[i]) ?? '')
    return result
  }

  static copyProgressVersionMap(source: Map<string, Map<number, string>>): Map<string, Map<number, string>> {
    const result: Map<string, Map<number, string>> = new Map()
    const keys = Array.from(source.keys())
    for (let i = 0; i < keys.length; i++) {
      const values = source.get(keys[i])
      if (values === undefined) continue
      const copied: Map<number, string> = new Map()
      const episodes = Array.from(values.keys())
      for (let j = 0; j < episodes.length; j++) copied.set(episodes[j], values.get(episodes[j]) ?? '')
      result.set(keys[i], copied)
    }
    return result
  }
}

class HistorySyncValue {
  static isRecord(value: Object | null | undefined): boolean {
    return value !== undefined && value !== null && typeof value === 'object' && !(value instanceof Array)
  }

  static isOptionalStringRecord(value: Object | undefined): boolean {
    if (value === undefined || value === null) return true
    if (!HistorySyncValue.isRecord(value)) return false
    const record = value as Record<string, Object>
    const keys = Object.keys(record)
    for (let i = 0; i < keys.length; i++) {
      if (typeof record[keys[i]] !== 'string') return false
    }
    return true
  }

  static isOptionalProgressVersionRecord(value: Object | undefined): boolean {
    if (value === undefined || value === null) return true
    if (!HistorySyncValue.isRecord(value)) return false
    const record = value as Record<string, Object>
    const keys = Object.keys(record)
    for (let i = 0; i < keys.length; i++) {
      if (!HistorySyncValue.isOptionalStringRecord(record[keys[i]])) return false
    }
    return true
  }

  static isRequiredString(value: Object | undefined): boolean {
    return typeof value === 'string' && value.length > 0
  }

  static isOptionalString(value: Object | undefined): boolean {
    return value === undefined || value === null || typeof value === 'string'
  }

  static isFiniteNumber(value: Object | undefined): boolean {
    return typeof value === 'number' && Number.isFinite(value)
  }

  static isOptionalNumber(value: Object | undefined): boolean {
    return value === undefined || value === null || HistorySyncValue.isFiniteNumber(value)
  }

  static isOptionalBoolean(value: Object | undefined): boolean {
    return value === undefined || value === null || typeof value === 'boolean'
  }

  static isBangumiItem(value: Object | null | undefined): boolean {
    if (!HistorySyncValue.isRecord(value)) return false
    const item = value as Record<string, Object>
    return HistorySyncValue.isFiniteNumber(item['id']) && HistorySyncValue.number(item['id'], -1) > 0 &&
      HistorySyncValue.isFiniteNumber(item['type'])
  }

  static isProgressRecord(value: Object | undefined): boolean {
    if (!HistorySyncValue.isRecord(value)) return false
    const progresses = value as Record<string, Object>
    const keys = Object.keys(progresses)
    for (let i = 0; i < keys.length; i++) {
      const episode = Number(keys[i])
      if (!Number.isInteger(episode) || episode <= 0 || !HistorySyncValue.isRecord(progresses[keys[i]])) return false
      const progress = progresses[keys[i]] as Record<string, Object>
      if (!HistorySyncValue.isFiniteNumber(progress['episode']) ||
        !HistorySyncValue.isFiniteNumber(progress['road']) ||
        !HistorySyncValue.isFiniteNumber(progress['progressMs']) ||
        !HistorySyncValue.isOptionalNumber(progress['updatedAtMs'])) return false
    }
    return true
  }

  static string(value: Object | undefined): string {
    if (value === undefined || value === null) return ''
    return String(value)
  }

  static number(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') return Number.isFinite(value) ? value : fallback
    if (typeof value === 'string') {
      const parsed = Number(value)
      return Number.isFinite(parsed) ? parsed : fallback
    }
    return fallback
  }

  static boolean(value: Object | undefined, fallback: boolean): boolean {
    return typeof value === 'boolean' ? value : fallback
  }
}
