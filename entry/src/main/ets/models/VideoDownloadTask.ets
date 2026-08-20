export enum VideoDownloadState {
  IDLE = 'idle',
  QUEUED = 'queued',
  PREPARING = 'preparing',
  RUNNING = 'running',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export enum VideoDownloadKind {
  DIRECT = 'direct',
  HLS = 'hls',
  DASH = 'dash'
}

export class VideoDownloadRequest {
  url: string = ''
  title: string = ''
  episodeTitle: string = ''
  mediaType: string = ''
  headers: Record<string, string> = {}
  animeCover: string = ''
  animeUrl: string = ''
  episodeUrl: string = ''
  sourceName: string = ''
  sourceId: number = -1
  bangumiId: number = 0
  roadIndex: number = -1
  episodeIndex: number = -1
  downloadDanmaku: boolean = true
  drmLicenseUrl: string = ''
  drmScheme: string = ''
  drmHeaders: Record<string, string> = {}
}

@Observed
export class VideoDownloadSnapshot {
  taskId: string = ''
  sourceUrl: string = ''
  targetUri: string = ''
  targetPath: string = ''
  fileName: string = ''
  title: string = ''
  kind: VideoDownloadKind = VideoDownloadKind.DIRECT
  mediaType: string = ''
  headers: Record<string, string> = {}
  state: VideoDownloadState = VideoDownloadState.PREPARING
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
  speedBytesPerSecond: number = 0
  estimatedRemainingSeconds: number = -1
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

  clone(): VideoDownloadSnapshot {
    const copy = new VideoDownloadSnapshot()
    copy.taskId = this.taskId
    copy.sourceUrl = this.sourceUrl
    copy.targetUri = this.targetUri
    copy.targetPath = this.targetPath
    copy.fileName = this.fileName
    copy.title = this.title
    copy.kind = this.kind
    copy.mediaType = this.mediaType
    copy.headers = {}
    const headerKeys = Object.keys(this.headers)
    for (let i = 0; i < headerKeys.length; i++) {
      copy.headers[headerKeys[i]] = this.headers[headerKeys[i]]
    }
    copy.state = this.state
    copy.processedBytes = this.processedBytes
    copy.totalBytes = this.totalBytes
    copy.progressPercent = this.progressPercent
    copy.errorMessage = this.errorMessage
    copy.createdAt = this.createdAt
    copy.completedAt = this.completedAt
    copy.targetDirectory = this.targetDirectory
    copy.localPlaylistUri = this.localPlaylistUri
    copy.completedSegments = this.completedSegments
    copy.totalSegments = this.totalSegments
    copy.audioTrackCount = this.audioTrackCount
    copy.subtitleTrackCount = this.subtitleTrackCount
    copy.queuePriority = this.queuePriority
    copy.queuedAt = this.queuedAt
    copy.speedBytesPerSecond = this.speedBytesPerSecond
    copy.estimatedRemainingSeconds = this.estimatedRemainingSeconds
    copy.animeCover = this.animeCover
    copy.animeUrl = this.animeUrl
    copy.episodeUrl = this.episodeUrl
    copy.sourceName = this.sourceName
    copy.sourceId = this.sourceId
    copy.bangumiId = this.bangumiId
    copy.roadIndex = this.roadIndex
    copy.episodeIndex = this.episodeIndex
    copy.downloadDanmaku = this.downloadDanmaku
    copy.coverPath = this.coverPath
    copy.coverUri = this.coverUri
    copy.metadataPath = this.metadataPath
    copy.danmakuPath = this.danmakuPath
    copy.danmakuUri = this.danmakuUri
    copy.danmakuCount = this.danmakuCount
    copy.isLive = this.isLive
    copy.videoTrackCount = this.videoTrackCount
    copy.iframeTrackCount = this.iframeTrackCount
    copy.remuxedPath = this.remuxedPath
    copy.remuxedUri = this.remuxedUri
    copy.drmScheme = this.drmScheme
    copy.drmLicenseUrl = this.drmLicenseUrl
    copy.drmHeaders = {}
    const drmHeaderKeys = Object.keys(this.drmHeaders)
    for (let i = 0; i < drmHeaderKeys.length; i++) {
      copy.drmHeaders[drmHeaderKeys[i]] = this.drmHeaders[drmHeaderKeys[i]]
    }
    copy.drmOfflineKeyId = this.drmOfflineKeyId
    copy.drmPluginName = this.drmPluginName
    return copy
  }

  updateFrom(source: VideoDownloadSnapshot): void {
    this.taskId = source.taskId
    this.sourceUrl = source.sourceUrl
    this.targetUri = source.targetUri
    this.targetPath = source.targetPath
    this.fileName = source.fileName
    this.title = source.title
    this.kind = source.kind
    this.mediaType = source.mediaType
    this.headers = source.headers
    this.state = source.state
    this.processedBytes = source.processedBytes
    this.totalBytes = source.totalBytes
    this.progressPercent = source.progressPercent
    this.errorMessage = source.errorMessage
    this.createdAt = source.createdAt
    this.completedAt = source.completedAt
    this.targetDirectory = source.targetDirectory
    this.localPlaylistUri = source.localPlaylistUri
    this.completedSegments = source.completedSegments
    this.totalSegments = source.totalSegments
    this.audioTrackCount = source.audioTrackCount
    this.subtitleTrackCount = source.subtitleTrackCount
    this.queuePriority = source.queuePriority
    this.queuedAt = source.queuedAt
    this.speedBytesPerSecond = source.speedBytesPerSecond
    this.estimatedRemainingSeconds = source.estimatedRemainingSeconds
    this.animeCover = source.animeCover
    this.animeUrl = source.animeUrl
    this.episodeUrl = source.episodeUrl
    this.sourceName = source.sourceName
    this.sourceId = source.sourceId
    this.bangumiId = source.bangumiId
    this.roadIndex = source.roadIndex
    this.episodeIndex = source.episodeIndex
    this.downloadDanmaku = source.downloadDanmaku
    this.coverPath = source.coverPath
    this.coverUri = source.coverUri
    this.metadataPath = source.metadataPath
    this.danmakuPath = source.danmakuPath
    this.danmakuUri = source.danmakuUri
    this.danmakuCount = source.danmakuCount
    this.isLive = source.isLive
    this.videoTrackCount = source.videoTrackCount
    this.iframeTrackCount = source.iframeTrackCount
    this.remuxedPath = source.remuxedPath
    this.remuxedUri = source.remuxedUri
    this.drmScheme = source.drmScheme
    this.drmLicenseUrl = source.drmLicenseUrl
    this.drmHeaders = source.drmHeaders
    this.drmOfflineKeyId = source.drmOfflineKeyId
    this.drmPluginName = source.drmPluginName
  }
}

export class DownloadStorageSummary {
  totalBytes: number = 0
  completedCount: number = 0
  activeCount: number = 0
  queuedCount: number = 0
  failedCount: number = 0
}

export type VideoDownloadListener = (snapshot: VideoDownloadSnapshot) => void
