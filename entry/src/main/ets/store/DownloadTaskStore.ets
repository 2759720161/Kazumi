import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  VideoDownloadKind,
  VideoDownloadSnapshot,
  VideoDownloadState
} from '../models/VideoDownloadTask'
import { Logger } from '../utils/Logger'

const logger = new Logger('DownloadTaskStore')
const STORE_FILE_NAME = 'video_download_tasks.json'

class DownloadTaskStoreRecord {
  taskId: string = ''
  sourceUrl: string = ''
  targetUri: string = ''
  targetPath: string = ''
  fileName: string = ''
  title: string = ''
  kind: VideoDownloadKind = VideoDownloadKind.DIRECT
  mediaType: string = ''
  headers: Record<string, string> = {}
  state: VideoDownloadState = VideoDownloadState.IDLE
  processedBytes: number = 0
  totalBytes: number = -1
  progressPercent: number = 0
  errorMessage: string = ''
  createdAt: number = 0
  completedAt: number = 0
  targetDirectory: string = ''
  localPlaylistUri: string = ''
  completedSegments: number = 0
  totalSegments: number = 0
  audioTrackCount: number = 0
  subtitleTrackCount: number = 0
  queuePriority: number = 0
  queuedAt: number = 0
  animeCover: string = ''
  animeUrl: string = ''
  episodeUrl: string = ''
  sourceName: string = ''
  sourceId: number = -1
  bangumiId: number = 0
  roadIndex: number = -1
  episodeIndex: number = -1
  downloadDanmaku: boolean = true
  coverPath: string = ''
  coverUri: string = ''
  metadataPath: string = ''
  danmakuPath: string = ''
  danmakuUri: string = ''
  danmakuCount: number = 0
  isLive: boolean = false
  videoTrackCount: number = 0
  iframeTrackCount: number = 0
  remuxedPath: string = ''
  remuxedUri: string = ''
  drmScheme: string = ''
  drmLicenseUrl: string = ''
  drmHeaders: Record<string, string> = {}
  drmOfflineKeyId: string = ''
  drmPluginName: string = ''
}

class DownloadTaskStoreRoot {
  version: number = 1
  tasks: DownloadTaskStoreRecord[] = []
}

export class DownloadTaskStore {
  private path: string = ''

  init(context: common.UIAbilityContext): void {
    this.path = context.filesDir + '/' + STORE_FILE_NAME
  }

  load(): VideoDownloadSnapshot[] {
    if (this.path.length === 0 || !fileIo.accessSync(this.path)) {
      return []
    }
    try {
      const parsed = JSON.parse(fileIo.readTextSync(this.path)) as Record<string, Object>
      const rawItems = parsed['tasks']
      if (!(rawItems instanceof Array)) {
        return []
      }
      const items = rawItems as Array<Record<string, Object>>
      const snapshots: VideoDownloadSnapshot[] = []
      for (let i = 0; i < items.length; i++) {
        const snapshot = this.fromRecord(items[i])
        if (snapshot.taskId.length > 0 && snapshot.sourceUrl.length > 0) {
          snapshots.push(snapshot)
        }
      }
      return snapshots
    } catch (err) {
      logger.warn('读取下载任务失败: %{public}s', err instanceof Error ? err.message : String(err))
      return []
    }
  }

  save(snapshots: VideoDownloadSnapshot[]): void {
    if (this.path.length === 0) {
      return
    }
    const records: DownloadTaskStoreRecord[] = []
    for (let i = 0; i < snapshots.length; i++) {
      records.push(this.toRecord(snapshots[i]))
    }
    const root = new DownloadTaskStoreRoot()
    root.tasks = records
    const tempPath = this.path + '.tmp'
    try {
      const file = fileIo.openSync(tempPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, JSON.stringify(root))
      } finally {
        fileIo.closeSync(file)
      }
      if (fileIo.accessSync(this.path)) {
        fileIo.unlinkSync(this.path)
      }
      fileIo.renameSync(tempPath, this.path)
    } catch (err) {
      logger.warn('保存下载任务失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private toRecord(snapshot: VideoDownloadSnapshot): DownloadTaskStoreRecord {
    const record = new DownloadTaskStoreRecord()
    record.taskId = snapshot.taskId
    record.sourceUrl = snapshot.sourceUrl
    record.targetUri = snapshot.targetUri
    record.targetPath = snapshot.targetPath
    record.fileName = snapshot.fileName
    record.title = snapshot.title
    record.kind = snapshot.kind
    record.mediaType = snapshot.mediaType
    record.headers = snapshot.headers
    record.state = snapshot.state
    record.processedBytes = snapshot.processedBytes
    record.totalBytes = snapshot.totalBytes
    record.progressPercent = snapshot.progressPercent
    record.errorMessage = snapshot.errorMessage
    record.createdAt = snapshot.createdAt
    record.completedAt = snapshot.completedAt
    record.targetDirectory = snapshot.targetDirectory
    record.localPlaylistUri = snapshot.localPlaylistUri
    record.completedSegments = snapshot.completedSegments
    record.totalSegments = snapshot.totalSegments
    record.audioTrackCount = snapshot.audioTrackCount
    record.subtitleTrackCount = snapshot.subtitleTrackCount
    record.queuePriority = snapshot.queuePriority
    record.queuedAt = snapshot.queuedAt
    record.animeCover = snapshot.animeCover
    record.animeUrl = snapshot.animeUrl
    record.episodeUrl = snapshot.episodeUrl
    record.sourceName = snapshot.sourceName
    record.sourceId = snapshot.sourceId
    record.bangumiId = snapshot.bangumiId
    record.roadIndex = snapshot.roadIndex
    record.episodeIndex = snapshot.episodeIndex
    record.downloadDanmaku = snapshot.downloadDanmaku
    record.coverPath = snapshot.coverPath
    record.coverUri = snapshot.coverUri
    record.metadataPath = snapshot.metadataPath
    record.danmakuPath = snapshot.danmakuPath
    record.danmakuUri = snapshot.danmakuUri
    record.danmakuCount = snapshot.danmakuCount
    record.isLive = snapshot.isLive
    record.videoTrackCount = snapshot.videoTrackCount
    record.iframeTrackCount = snapshot.iframeTrackCount
    record.remuxedPath = snapshot.remuxedPath
    record.remuxedUri = snapshot.remuxedUri
    record.drmScheme = snapshot.drmScheme
    record.drmLicenseUrl = snapshot.drmLicenseUrl
    record.drmHeaders = snapshot.drmHeaders
    record.drmOfflineKeyId = snapshot.drmOfflineKeyId
    record.drmPluginName = snapshot.drmPluginName
    return record
  }

  private fromRecord(raw: Record<string, Object>): VideoDownloadSnapshot {
    const snapshot = new VideoDownloadSnapshot()
    snapshot.taskId = this.stringValue(raw['taskId'])
    snapshot.sourceUrl = this.stringValue(raw['sourceUrl'])
    snapshot.targetUri = this.stringValue(raw['targetUri'])
    snapshot.targetPath = this.stringValue(raw['targetPath'])
    snapshot.fileName = this.stringValue(raw['fileName'])
    snapshot.title = this.stringValue(raw['title'])
    const kind = this.stringValue(raw['kind'])
    snapshot.kind = kind === VideoDownloadKind.HLS ? VideoDownloadKind.HLS :
      (kind === VideoDownloadKind.DASH ? VideoDownloadKind.DASH : VideoDownloadKind.DIRECT)
    snapshot.mediaType = this.stringValue(raw['mediaType'])
    snapshot.headers = this.headerValue(raw['headers'])
    snapshot.state = this.stateValue(this.stringValue(raw['state']))
    snapshot.processedBytes = this.numberValue(raw['processedBytes'], 0)
    snapshot.totalBytes = this.numberValue(raw['totalBytes'], -1)
    snapshot.progressPercent = this.numberValue(raw['progressPercent'], 0)
    snapshot.errorMessage = this.stringValue(raw['errorMessage'])
    snapshot.createdAt = this.numberValue(raw['createdAt'], 0)
    snapshot.completedAt = this.numberValue(raw['completedAt'], 0)
    snapshot.targetDirectory = this.stringValue(raw['targetDirectory'])
    snapshot.localPlaylistUri = this.stringValue(raw['localPlaylistUri'])
    snapshot.completedSegments = this.numberValue(raw['completedSegments'], 0)
    snapshot.totalSegments = this.numberValue(raw['totalSegments'], 0)
    snapshot.audioTrackCount = this.numberValue(raw['audioTrackCount'], 0)
    snapshot.subtitleTrackCount = this.numberValue(raw['subtitleTrackCount'], 0)
    snapshot.queuePriority = this.numberValue(raw['queuePriority'], 0)
    snapshot.queuedAt = this.numberValue(raw['queuedAt'], snapshot.createdAt)
    snapshot.animeCover = this.stringValue(raw['animeCover'])
    snapshot.animeUrl = this.stringValue(raw['animeUrl'])
    snapshot.episodeUrl = this.stringValue(raw['episodeUrl'])
    snapshot.sourceName = this.stringValue(raw['sourceName'])
    snapshot.sourceId = this.numberValue(raw['sourceId'], -1)
    snapshot.bangumiId = this.numberValue(raw['bangumiId'], 0)
    snapshot.roadIndex = this.numberValue(raw['roadIndex'], -1)
    snapshot.episodeIndex = this.numberValue(raw['episodeIndex'], -1)
    snapshot.downloadDanmaku = this.booleanValue(raw['downloadDanmaku'], true)
    snapshot.coverPath = this.stringValue(raw['coverPath'])
    snapshot.coverUri = this.stringValue(raw['coverUri'])
    snapshot.metadataPath = this.stringValue(raw['metadataPath'])
    snapshot.danmakuPath = this.stringValue(raw['danmakuPath'])
    snapshot.danmakuUri = this.stringValue(raw['danmakuUri'])
    snapshot.danmakuCount = this.numberValue(raw['danmakuCount'], 0)
    snapshot.isLive = this.booleanValue(raw['isLive'], false)
    snapshot.videoTrackCount = this.numberValue(raw['videoTrackCount'], 0)
    snapshot.iframeTrackCount = this.numberValue(raw['iframeTrackCount'], 0)
    snapshot.remuxedPath = this.stringValue(raw['remuxedPath'])
    snapshot.remuxedUri = this.stringValue(raw['remuxedUri'])
    snapshot.drmScheme = this.stringValue(raw['drmScheme'])
    snapshot.drmLicenseUrl = this.stringValue(raw['drmLicenseUrl'])
    snapshot.drmHeaders = this.headerValue(raw['drmHeaders'])
    snapshot.drmOfflineKeyId = this.stringValue(raw['drmOfflineKeyId'])
    snapshot.drmPluginName = this.stringValue(raw['drmPluginName'])
    return snapshot
  }

  private headerValue(value: Object | undefined): Record<string, string> {
    const headers: Record<string, string> = {}
    if (value === undefined || value === null || value instanceof Array || typeof value !== 'object') {
      return headers
    }
    const record = value as Record<string, Object>
    const keys = Object.keys(record)
    for (let i = 0; i < keys.length; i++) {
      if (typeof record[keys[i]] === 'string') {
        headers[keys[i]] = record[keys[i]] as string
      }
    }
    return headers
  }

  private stateValue(value: string): VideoDownloadState {
    if (value === VideoDownloadState.QUEUED) return VideoDownloadState.QUEUED
    if (value === VideoDownloadState.PREPARING) return VideoDownloadState.PREPARING
    if (value === VideoDownloadState.RUNNING) return VideoDownloadState.RUNNING
    if (value === VideoDownloadState.PAUSED) return VideoDownloadState.PAUSED
    if (value === VideoDownloadState.COMPLETED) return VideoDownloadState.COMPLETED
    if (value === VideoDownloadState.FAILED) return VideoDownloadState.FAILED
    if (value === VideoDownloadState.CANCELLED) return VideoDownloadState.CANCELLED
    return VideoDownloadState.IDLE
  }

  private stringValue(value: Object | undefined): string {
    return typeof value === 'string' ? value : ''
  }

  private numberValue(value: Object | undefined, fallback: number): number {
    return typeof value === 'number' ? value : fallback
  }

  private booleanValue(value: Object | undefined, fallback: boolean): boolean {
    return typeof value === 'boolean' ? value : fallback
  }
}
