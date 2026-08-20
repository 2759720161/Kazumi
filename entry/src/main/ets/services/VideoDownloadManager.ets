import { common } from '@kit.AbilityKit'
import { BusinessError, request } from '@kit.BasicServicesKit'
import { fileIo, fileUri, ListFileOptions } from '@kit.CoreFileKit'
import {
  VideoDownloadKind,
  VideoDownloadListener,
  VideoDownloadRequest,
  VideoDownloadSnapshot,
  VideoDownloadState,
  DownloadStorageSummary
} from '../models/VideoDownloadTask'
import { DownloadTaskStore } from '../store/DownloadTaskStore'
import { Logger } from '../utils/Logger'
import { BackgroundDownloadService } from './BackgroundDownloadService'
import { DownloadCompanionService } from './DownloadCompanionService'
import { HlsDownloadService } from './HlsDownloadService'
import { DashDownloadService } from './DashDownloadService'
import { NativeRemuxService } from './NativeRemuxService'
import { NativeDirectDownloadService } from './NativeDirectDownloadService'
import { DrmOfflineLicenseService } from './DrmOfflineLicenseService'
import { UserDownloadFolder, UserDownloadTarget } from './UserDownloadFolder'

const logger = new Logger('VideoDownloadManager')
const DIRECT_STAGING_SUFFIX = '.kazumi-download'
const MAX_ACTIVE_DOWNLOADS = 2
const PROGRESS_EMIT_INTERVAL_MS = 200
const PERSIST_INTERVAL_MS = 1500
const STORAGE_SUMMARY_CACHE_MS = 1000

class DownloadSpeedSample {
  startedAt: number = 0
  lastAt: number = 0
  lastBytes: number = 0
  speed: number = 0
}

export class VideoDownloadManager {
  private static instance: VideoDownloadManager | null = null
  private readonly tasks: Map<string, request.agent.Task> = new Map()
  private readonly targets: Map<string, UserDownloadTarget> = new Map()
  private readonly snapshots: Map<string, VideoDownloadSnapshot> = new Map()
  private readonly hlsRuns: Map<string, Promise<void>> = new Map()
  private readonly dashRuns: Map<string, Promise<void>> = new Map()
  private readonly directRuns: Map<string, Promise<void>> = new Map()
  private readonly removingTaskIds: Set<string> = new Set()
  private readonly progressEmitAt: Map<string, number> = new Map()
  private readonly progressEmitPercent: Map<string, number> = new Map()
  private readonly activeTaskIds: Set<string> = new Set()
  private readonly directResumeTaskIds: Set<string> = new Set()
  private readonly speedSamples: Map<string, DownloadSpeedSample> = new Map()
  private readonly listeners: VideoDownloadListener[] = []
  private readonly backgroundDownloadService: BackgroundDownloadService = BackgroundDownloadService.getInstance()
  private readonly hlsService: HlsDownloadService = new HlsDownloadService()
  private readonly dashService: DashDownloadService = new DashDownloadService()
  private readonly remuxService: NativeRemuxService = new NativeRemuxService()
  private readonly directService: NativeDirectDownloadService = new NativeDirectDownloadService()
  private readonly drmLicenseService: DrmOfflineLicenseService = new DrmOfflineLicenseService()
  private readonly companionService: DownloadCompanionService = new DownloadCompanionService()
  private readonly taskStore: DownloadTaskStore = new DownloadTaskStore()
  private context: common.UIAbilityContext | null = null
  private initialized: boolean = false
  private initializePromise: Promise<void> | null = null
  private persistTimer: number = -1
  private queueScheduling: boolean = false
  private prioritySequence: number = 0
  private storageSummaryCache: DownloadStorageSummary | null = null
  private storageSummaryCacheAt: number = 0

  static getInstance(): VideoDownloadManager {
    if (VideoDownloadManager.instance === null) {
      VideoDownloadManager.instance = new VideoDownloadManager()
    }
    return VideoDownloadManager.instance
  }

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context
    if (this.initialized) {
      return
    }
    if (this.initializePromise !== null) {
      await this.initializePromise
      return
    }
    this.initializePromise = this.performInitialize(context)
    try {
      await this.initializePromise
      this.initialized = true
    } finally {
      this.initializePromise = null
    }
  }

  private async performInitialize(context: common.UIAbilityContext): Promise<void> {
    this.backgroundDownloadService.setCancellationHandler((): void => {
      this.handleBackgroundTaskCancelled()
    })
    this.taskStore.init(context)
    const restored = this.taskStore.load()
    for (let i = 0; i < restored.length; i++) {
      const snapshot = restored[i]
      const persistedState = snapshot.state
      this.snapshots.set(snapshot.taskId, snapshot)
      if (this.isAdaptiveKind(snapshot.kind)) {
        this.hlsService.ensureManagedDirectory(snapshot.targetDirectory)
        if (snapshot.state === VideoDownloadState.RUNNING || snapshot.state === VideoDownloadState.PREPARING) {
          snapshot.state = VideoDownloadState.PAUSED
          snapshot.errorMessage = '应用重新启动，点击继续下载'
        }
      } else {
        await this.restoreDirectTask(context, snapshot)
        if (persistedState === VideoDownloadState.QUEUED && this.tasks.has(snapshot.taskId)) {
          snapshot.state = VideoDownloadState.QUEUED
        }
        if (snapshot.state === VideoDownloadState.RUNNING || snapshot.state === VideoDownloadState.PREPARING) {
          this.activeTaskIds.add(snapshot.taskId)
        }
      }
    }
    this.persistNow()
    this.scheduleQueue()
    logger.info('下载任务恢复完成: %{public}d', restored.length)
  }

  addListener(listener: VideoDownloadListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  removeListener(listener: VideoDownloadListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }

  async startDownload(context: common.UIAbilityContext,
    input: VideoDownloadRequest): Promise<VideoDownloadSnapshot> {
    await this.initialize(context)
    this.validateHttpUrl(input.url)
    const reusable = this.findReusableDownload(input)
    if (reusable !== null) {
      return reusable
    }
    if (this.isHlsRequest(input)) {
      return await this.startHlsDownload(context, input)
    }
    if (this.isDashRequest(input)) {
      return await this.startDashDownload(context, input)
    }
    return await this.startDirectDownload(context, input)
  }

  async startDirectDownload(context: common.UIAbilityContext,
    input: VideoDownloadRequest): Promise<VideoDownloadSnapshot> {
    await this.initialize(context)
    this.validateHttpUrl(input.url)
    const animeDirectoryName = this.buildAnimeDirectoryName(input)
    const fileName = this.buildFileName(input)
    const target = await UserDownloadFolder.createVideoTarget(context, animeDirectoryName, fileName)
    if (target === null) {
      throw new Error('无法创建下载目标')
    }
    const taskId = 'direct_' + String(Date.now()) + '_' + String(Math.floor(Math.random() * 1000000))
    const snapshot = this.createSnapshot(taskId, input, target, VideoDownloadKind.DIRECT)
    this.targets.set(taskId, target)
    this.snapshots.set(taskId, snapshot)
    this.emit(snapshot)

    snapshot.state = VideoDownloadState.QUEUED
    snapshot.queuedAt = Date.now()
    this.emit(snapshot)
    this.scheduleQueue()
    return snapshot.clone()
  }

  async pause(taskId: string): Promise<void> {
    const snapshot = this.requireSnapshot(taskId)
    if (snapshot.state === VideoDownloadState.QUEUED) {
      snapshot.state = VideoDownloadState.PAUSED
      snapshot.speedBytesPerSecond = 0
      snapshot.estimatedRemainingSeconds = -1
      this.emit(snapshot)
      this.scheduleQueue()
      return
    }
    if (this.isAdaptiveKind(snapshot.kind)) {
      snapshot.state = VideoDownloadState.PAUSED
      snapshot.errorMessage = ''
      if (snapshot.kind === VideoDownloadKind.HLS) {
        this.hlsService.pause(taskId)
        this.remuxService.pause(taskId)
      } else {
        this.dashService.pause(taskId)
      }
      this.emit(snapshot)
      this.backgroundDownloadService.publishPaused(taskId, snapshot.title, snapshot.progressPercent)
      return
    }
    const task = this.tasks.get(taskId)
    if (task !== undefined) {
      await task.pause()
      this.directResumeTaskIds.add(taskId)
    } else {
      this.directService.pause(taskId)
      snapshot.state = VideoDownloadState.PAUSED
      snapshot.speedBytesPerSecond = 0
      snapshot.estimatedRemainingSeconds = -1
      snapshot.errorMessage = ''
      this.emit(snapshot)
      this.backgroundDownloadService.publishPaused(taskId, snapshot.title, snapshot.progressPercent)
    }
    this.releaseActiveTask(taskId)
  }

  async resume(taskId: string): Promise<void> {
    const snapshot = this.requireSnapshot(taskId)
    if (snapshot.state === VideoDownloadState.COMPLETED) {
      return
    }
    if (snapshot.state === VideoDownloadState.CANCELLED) {
      throw new Error('已取消的下载任务无法继续')
    }
    if (this.isAdaptiveKind(snapshot.kind)) {
      if ((snapshot.kind === VideoDownloadKind.HLS && this.remuxService.isRunning(taskId)) ||
        (snapshot.kind === VideoDownloadKind.DASH && this.dashService.isRunning(taskId))) {
        if (snapshot.kind === VideoDownloadKind.HLS) this.remuxService.resume(taskId)
        else this.dashService.resume(taskId)
        snapshot.state = VideoDownloadState.RUNNING
        snapshot.errorMessage = ''
        this.emit(snapshot)
        return
      }
      this.backgroundDownloadService.cancelTaskNotification(taskId)
      const previousRun = snapshot.kind === VideoDownloadKind.HLS ?
        this.hlsRuns.get(taskId) : this.dashRuns.get(taskId)
      if (previousRun !== undefined) {
        await previousRun
      }
      this.backgroundDownloadService.cancelTaskNotification(taskId)
      snapshot.state = VideoDownloadState.QUEUED
      snapshot.queuedAt = Date.now()
      snapshot.errorMessage = ''
      this.emit(snapshot)
      this.scheduleQueue()
      return
    }
    const task = this.tasks.get(taskId)
    if (task !== undefined) {
      this.directResumeTaskIds.add(taskId)
    } else {
      const previousRun = this.directRuns.get(taskId)
      if (previousRun !== undefined) {
        await previousRun
      }
    }
    snapshot.state = VideoDownloadState.QUEUED
    snapshot.queuedAt = Date.now()
    snapshot.errorMessage = ''
    this.emit(snapshot)
    this.scheduleQueue()
  }

  async cancel(taskId: string): Promise<void> {
    const snapshot = this.snapshots.get(taskId)
    if (snapshot !== undefined && this.isAdaptiveKind(snapshot.kind)) {
      this.backgroundDownloadService.cancelTaskNotification(taskId)
      snapshot.state = VideoDownloadState.CANCELLED
      snapshot.errorMessage = ''
      if (snapshot.kind === VideoDownloadKind.HLS) {
        this.hlsService.cancel(taskId)
        this.remuxService.cancel(taskId)
      } else {
        this.dashService.cancel(taskId)
      }
      this.emit(snapshot)
      const running = snapshot.kind === VideoDownloadKind.HLS ? this.hlsRuns.get(taskId) : this.dashRuns.get(taskId)
      if (running !== undefined) {
        await running
      }
      this.hlsService.removeDirectory(snapshot.targetDirectory)
      this.clearOfflineLicense(snapshot)
      this.releaseActiveTask(taskId)
      return
    }

    const task = this.tasks.get(taskId)
    if (task !== undefined) {
      try {
        await task.stop()
      } catch (err) {
        logger.warn('停止下载任务失败: %{public}s', this.getErrorMessage(err))
      }
    } else {
      this.directService.cancel(taskId)
      this.backgroundDownloadService.cancelTaskNotification(taskId)
    }
    if (snapshot !== undefined) {
      snapshot.state = VideoDownloadState.CANCELLED
      snapshot.errorMessage = ''
      this.emit(snapshot)
    }
    this.tasks.delete(taskId)
    this.directResumeTaskIds.delete(taskId)
    const target = this.targets.get(taskId)
    if (target !== undefined) {
      this.removeTarget(target)
      this.targets.delete(taskId)
    }
    this.removeSystemTask(taskId)
    this.releaseActiveTask(taskId)
  }

  finishLive(taskId: string): void {
    const snapshot = this.requireSnapshot(taskId)
    if (!snapshot.isLive || !this.isAdaptiveKind(snapshot.kind)) throw new Error('该任务不是直播录制')
    if (snapshot.state !== VideoDownloadState.RUNNING && snapshot.state !== VideoDownloadState.PREPARING) {
      throw new Error('请先继续任务，再结束直播录制')
    }
    snapshot.state = VideoDownloadState.PREPARING
    snapshot.errorMessage = '正在结束录制并生成 MP4'
    if (snapshot.kind === VideoDownloadKind.HLS) this.hlsService.finish(taskId)
    else this.dashService.finish(taskId)
    this.emit(snapshot)
  }

  async remove(taskId: string, deleteFiles: boolean = true): Promise<void> {
    if (this.removingTaskIds.has(taskId)) {
      return
    }
    const snapshot = this.snapshots.get(taskId)
    if (snapshot === undefined) {
      return
    }
    this.removingTaskIds.add(taskId)
    try {
      if (snapshot.state === VideoDownloadState.RUNNING || snapshot.state === VideoDownloadState.PAUSED ||
        snapshot.state === VideoDownloadState.PREPARING || snapshot.state === VideoDownloadState.QUEUED) {
        await this.cancel(taskId)
      }
      if (deleteFiles) {
        if (this.isAdaptiveKind(snapshot.kind)) {
          this.hlsService.removeDirectory(snapshot.targetDirectory)
          this.companionService.removeCompanions(snapshot)
        } else {
          this.removeFile(snapshot.targetPath)
          this.removeFile(snapshot.targetPath + '.resume')
          this.companionService.removeCompanions(snapshot)
        }
        this.clearOfflineLicense(snapshot)
      }
      this.snapshots.delete(taskId)
      this.persistNow()
    } finally {
      this.removingTaskIds.delete(taskId)
    }
  }

  getSnapshot(taskId: string): VideoDownloadSnapshot | null {
    const snapshot = this.snapshots.get(taskId)
    return snapshot === undefined ? null : snapshot.clone()
  }

  getAllSnapshots(): VideoDownloadSnapshot[] {
    const values = Array.from(this.snapshots.values())
    values.sort((a: VideoDownloadSnapshot, b: VideoDownloadSnapshot): number => b.createdAt - a.createdAt)
    const copies: VideoDownloadSnapshot[] = []
    for (let i = 0; i < values.length; i++) {
      copies.push(values[i].clone())
    }
    return copies
  }

  /** Flush the latest task states before the UI ability is backgrounded or destroyed. */
  flushPersistence(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer)
      this.persistTimer = -1
    }
    if (this.initialized) {
      this.persistNow()
    }
  }

  async prioritize(taskId: string): Promise<void> {
    const snapshot = this.requireSnapshot(taskId)
    if (snapshot.state !== VideoDownloadState.QUEUED) {
      return
    }
    this.prioritySequence++
    snapshot.queuePriority = this.prioritySequence
    snapshot.queuedAt = Date.now()
    this.emit(snapshot)
    this.scheduleQueue()
  }

  async pauseAll(): Promise<void> {
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      const snapshot = values[i]
      if (snapshot.state === VideoDownloadState.QUEUED || snapshot.state === VideoDownloadState.RUNNING ||
        snapshot.state === VideoDownloadState.PREPARING) {
        await this.pause(snapshot.taskId)
      }
    }
  }

  async resumeAll(): Promise<void> {
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      if (values[i].state === VideoDownloadState.PAUSED) {
        await this.resume(values[i].taskId)
      }
    }
  }

  async clearFinished(): Promise<void> {
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      const state = values[i].state
      if (state === VideoDownloadState.COMPLETED || state === VideoDownloadState.FAILED ||
        state === VideoDownloadState.CANCELLED) {
        await this.remove(values[i].taskId, true)
      }
    }
  }

  async retry(taskId: string): Promise<VideoDownloadSnapshot> {
    const snapshot = this.requireSnapshot(taskId)
    if (this.isAdaptiveKind(snapshot.kind)) {
      await this.resume(taskId)
      return this.requireSnapshot(taskId).clone()
    }
    if (this.context === null) {
      throw new Error('下载服务尚未初始化')
    }
    const input = this.requestFromSnapshot(snapshot)
    await this.remove(taskId, true)
    return await this.startDownload(this.context, input)
  }

  getStorageSummary(): DownloadStorageSummary {
    const now = Date.now()
    if (this.storageSummaryCache !== null && now - this.storageSummaryCacheAt < STORAGE_SUMMARY_CACHE_MS) {
      return this.copyStorageSummary(this.storageSummaryCache)
    }
    const summary = new DownloadStorageSummary()
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      const snapshot = values[i]
      if (snapshot.state === VideoDownloadState.COMPLETED) {
        summary.completedCount++
      } else if (snapshot.state === VideoDownloadState.QUEUED) {
        summary.queuedCount++
      } else if (snapshot.state === VideoDownloadState.RUNNING || snapshot.state === VideoDownloadState.PREPARING) {
        summary.activeCount++
      } else if (snapshot.state === VideoDownloadState.FAILED) {
        summary.failedCount++
      }
      summary.totalBytes += this.getSnapshotStorageBytes(snapshot)
    }
    this.storageSummaryCache = summary
    this.storageSummaryCacheAt = now
    return this.copyStorageSummary(summary)
  }

  findLatestBySourceUrl(sourceUrl: string): VideoDownloadSnapshot | null {
    const values = Array.from(this.snapshots.values())
    let latest: VideoDownloadSnapshot | null = null
    for (let i = 0; i < values.length; i++) {
      const snapshot = values[i]
      if (snapshot.sourceUrl !== sourceUrl || snapshot.state === VideoDownloadState.CANCELLED) {
        continue
      }
      if (latest === null || snapshot.createdAt > latest.createdAt) {
        latest = snapshot
      }
    }
    return latest === null ? null : latest.clone()
  }

  private async startHlsDownload(context: common.UIAbilityContext,
    input: VideoDownloadRequest): Promise<VideoDownloadSnapshot> {
    const animeDirectoryName = this.buildAnimeDirectoryName(input)
    const directoryName = this.buildEpisodeBaseName(input)
    const target = await UserDownloadFolder.createHlsTarget(context, animeDirectoryName, directoryName)
    if (target === null) {
      throw new Error('无法创建 HLS 下载目录')
    }
    const taskId = 'hls_' + String(Date.now()) + '_' + String(Math.floor(Math.random() * 1000000))
    const snapshot = this.createSnapshot(taskId, input, target, VideoDownloadKind.HLS)
    snapshot.targetDirectory = target.path
    snapshot.targetPath = target.path + '/playlist.m3u8'
    snapshot.mediaType = 'm3u8'
    this.snapshots.set(taskId, snapshot)
    snapshot.state = VideoDownloadState.QUEUED
    snapshot.queuedAt = Date.now()
    this.emit(snapshot)
    this.scheduleQueue()
    return snapshot.clone()
  }

  private async startDashDownload(context: common.UIAbilityContext,
    input: VideoDownloadRequest): Promise<VideoDownloadSnapshot> {
    const animeDirectoryName = this.buildAnimeDirectoryName(input)
    const directoryName = this.buildEpisodeBaseName(input)
    const target = await UserDownloadFolder.createDashTarget(context, animeDirectoryName, directoryName)
    if (target === null) throw new Error('无法创建 DASH 下载目录')
    const taskId = 'dash_' + String(Date.now()) + '_' + String(Math.floor(Math.random() * 1000000))
    const snapshot = this.createSnapshot(taskId, input, target, VideoDownloadKind.DASH)
    snapshot.targetDirectory = target.path
    snapshot.targetPath = target.path + '/video.mp4'
    snapshot.mediaType = 'mpd'
    this.snapshots.set(taskId, snapshot)
    snapshot.state = VideoDownloadState.QUEUED
    snapshot.queuedAt = Date.now()
    this.emit(snapshot)
    this.scheduleQueue()
    return snapshot.clone()
  }

  private launchHls(snapshot: VideoDownloadSnapshot): void {
    if (this.hlsRuns.has(snapshot.taskId)) {
      return
    }
    const running = this.executeHls(snapshot)
    this.hlsRuns.set(snapshot.taskId, running)
    running.finally(() => {
      if (this.hlsRuns.get(snapshot.taskId) === running) {
        this.hlsRuns.delete(snapshot.taskId)
      }
    })
  }

  private launchDash(snapshot: VideoDownloadSnapshot): void {
    if (this.dashRuns.has(snapshot.taskId)) return
    const running = this.executeDash(snapshot)
    this.dashRuns.set(snapshot.taskId, running)
    running.finally((): void => {
      if (this.dashRuns.get(snapshot.taskId) === running) this.dashRuns.delete(snapshot.taskId)
    })
  }

  private launchDirect(snapshot: VideoDownloadSnapshot): void {
    if (this.directRuns.has(snapshot.taskId)) return
    const running = this.executeDirect(snapshot)
    this.directRuns.set(snapshot.taskId, running)
    running.finally((): void => {
      if (this.directRuns.get(snapshot.taskId) === running) this.directRuns.delete(snapshot.taskId)
    })
  }

  private async executeDirect(snapshot: VideoDownloadSnapshot): Promise<void> {
    try {
      const target = this.targets.get(snapshot.taskId) || this.targetFromSnapshot(snapshot)
      const downloadedBytes = await this.directService.start(snapshot.taskId, snapshot.sourceUrl, target.path,
        snapshot.headers, (processedBytes: number, totalBytes: number): void => {
          if (snapshot.state !== VideoDownloadState.RUNNING && snapshot.state !== VideoDownloadState.PREPARING) {
            return
          }
          snapshot.processedBytes = processedBytes
          snapshot.totalBytes = totalBytes
          snapshot.progressPercent = totalBytes > 0 ? Math.min(99, Math.floor(processedBytes * 100 / totalBytes)) : 0
          snapshot.state = VideoDownloadState.RUNNING
          this.updateTransferMetrics(snapshot, processedBytes)
          this.emitProgress(snapshot)
        })
      snapshot.processedBytes = downloadedBytes
      if (snapshot.totalBytes > 0) snapshot.progressPercent = 100
      this.finalizeTarget(target, snapshot)
      snapshot.progressPercent = 100
      snapshot.completedAt = Date.now()
      snapshot.errorMessage = ''
      snapshot.state = VideoDownloadState.PREPARING
      this.emit(snapshot)
      await this.companionService.complete(snapshot)
      snapshot.state = VideoDownloadState.COMPLETED
      snapshot.speedBytesPerSecond = 0
      snapshot.estimatedRemainingSeconds = 0
      this.emit(snapshot)
      this.targets.delete(snapshot.taskId)
    } catch (err) {
      const message = this.getErrorMessage(err)
      if (snapshot.state === VideoDownloadState.PAUSED || snapshot.state === VideoDownloadState.CANCELLED ||
        message === 'PAUSED' || message === 'CANCELLED') {
        return
      }
      snapshot.state = VideoDownloadState.FAILED
      snapshot.errorMessage = message
      this.emit(snapshot)
      logger.warn('直链下载失败: task=%{public}s error=%{public}s', snapshot.taskId, message)
    } finally {
      this.directService.release(snapshot.taskId)
      await this.backgroundDownloadService.release(snapshot.taskId)
      this.releaseActiveTask(snapshot.taskId)
    }
  }

  private async executeHls(snapshot: VideoDownloadSnapshot): Promise<void> {
    try {
      const playlistUri = await this.hlsService.start(snapshot,
        (completedSegments: number, totalSegments: number, totalBytes: number): void => {
          if (snapshot.state !== VideoDownloadState.RUNNING &&
            snapshot.state !== VideoDownloadState.PREPARING) {
            return
          }
          snapshot.completedSegments = completedSegments
          snapshot.totalSegments = totalSegments
          snapshot.processedBytes = totalBytes
          snapshot.totalBytes = -1
          snapshot.progressPercent = totalSegments > 0 ?
            Math.min(99, Math.floor(completedSegments * 100 / totalSegments)) : 0
          snapshot.state = VideoDownloadState.RUNNING
          this.updateTransferMetrics(snapshot, totalBytes)
          if (this.emitProgress(snapshot)) {
            this.backgroundDownloadService.updateProgress(snapshot.taskId, snapshot.title, snapshot.progressPercent)
          }
        })
      snapshot.localPlaylistUri = playlistUri
      snapshot.state = VideoDownloadState.PREPARING
      snapshot.errorMessage = '正在合并并转封装为 MP4'
      this.emit(snapshot)
      const mp4Path = snapshot.targetDirectory + '/video.mp4'
      const mp4Uri = await this.remuxService.remux(snapshot.taskId, playlistUri, mp4Path)
      snapshot.remuxedPath = mp4Path
      snapshot.remuxedUri = mp4Uri
      snapshot.targetPath = mp4Path
      snapshot.targetUri = mp4Uri
      snapshot.progressPercent = 100
      snapshot.completedAt = Date.now()
      snapshot.errorMessage = ''
      snapshot.state = VideoDownloadState.PREPARING
      this.emit(snapshot)
      await this.companionService.complete(snapshot)
      snapshot.state = VideoDownloadState.COMPLETED
      snapshot.speedBytesPerSecond = 0
      snapshot.estimatedRemainingSeconds = 0
      this.backgroundDownloadService.updateProgress(snapshot.taskId, snapshot.title, 100)
      this.backgroundDownloadService.cancelTaskNotification(snapshot.taskId)
      this.emit(snapshot)
    } catch (err) {
      if (snapshot.state === VideoDownloadState.PAUSED || snapshot.state === VideoDownloadState.CANCELLED) {
        return
      }
      snapshot.state = VideoDownloadState.FAILED
      snapshot.errorMessage = this.getErrorMessage(err)
      this.emit(snapshot)
      this.backgroundDownloadService.cancelTaskNotification(snapshot.taskId)
      logger.warn('HLS下载失败: task=%{public}s error=%{public}s', snapshot.taskId, snapshot.errorMessage)
    } finally {
      this.hlsService.release(snapshot.taskId)
      await this.backgroundDownloadService.release(snapshot.taskId)
      this.releaseActiveTask(snapshot.taskId)
    }
  }

  private async executeDash(snapshot: VideoDownloadSnapshot): Promise<void> {
    try {
      const outputUri = await this.dashService.start(snapshot,
        (isLive: boolean, videoTracks: number, audioTracks: number, subtitleTracks: number): void => {
          snapshot.isLive = isLive
          snapshot.videoTrackCount = videoTracks
          snapshot.audioTrackCount = audioTracks
          snapshot.subtitleTrackCount = subtitleTracks
          snapshot.state = VideoDownloadState.RUNNING
          snapshot.progressPercent = isLive ? 0 : Math.max(1, snapshot.progressPercent)
          this.emit(snapshot)
        })
      snapshot.targetUri = outputUri
      snapshot.remuxedUri = outputUri
      snapshot.remuxedPath = snapshot.targetDirectory + '/video.mp4'
      snapshot.targetPath = snapshot.remuxedPath
      snapshot.progressPercent = 100
      snapshot.completedAt = Date.now()
      snapshot.errorMessage = ''
      snapshot.state = VideoDownloadState.PREPARING
      this.emit(snapshot)
      await this.companionService.complete(snapshot)
      snapshot.state = VideoDownloadState.COMPLETED
      snapshot.speedBytesPerSecond = 0
      snapshot.estimatedRemainingSeconds = 0
      this.backgroundDownloadService.updateProgress(snapshot.taskId, snapshot.title, 100)
      this.backgroundDownloadService.cancelTaskNotification(snapshot.taskId)
      this.emit(snapshot)
    } catch (err) {
      if (snapshot.state === VideoDownloadState.PAUSED || snapshot.state === VideoDownloadState.CANCELLED) return
      snapshot.state = VideoDownloadState.FAILED
      snapshot.errorMessage = this.getErrorMessage(err)
      this.emit(snapshot)
      this.backgroundDownloadService.cancelTaskNotification(snapshot.taskId)
      logger.warn('DASH下载失败: task=%{public}s error=%{public}s', snapshot.taskId, snapshot.errorMessage)
    } finally {
      await this.backgroundDownloadService.release(snapshot.taskId)
      this.releaseActiveTask(snapshot.taskId)
    }
  }

  private handleBackgroundTaskCancelled(): void {
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      const snapshot = values[i]
      if (!this.isAdaptiveKind(snapshot.kind) ||
        (snapshot.state !== VideoDownloadState.RUNNING && snapshot.state !== VideoDownloadState.PREPARING)) {
        continue
      }
      snapshot.state = VideoDownloadState.PAUSED
      snapshot.errorMessage = '后台下载已停止，点击继续下载'
      if (snapshot.kind === VideoDownloadKind.HLS) {
        this.hlsService.pause(snapshot.taskId)
        this.remuxService.pause(snapshot.taskId)
      } else {
        this.dashService.pause(snapshot.taskId)
      }
      this.emit(snapshot)
      this.backgroundDownloadService.publishPaused(snapshot.taskId, snapshot.title, snapshot.progressPercent)
    }
  }

  private async restoreDirectTask(_context: common.UIAbilityContext,
    snapshot: VideoDownloadSnapshot): Promise<void> {
    if (snapshot.state === VideoDownloadState.COMPLETED || snapshot.state === VideoDownloadState.CANCELLED) {
      return
    }
    try {
      const targetPath = snapshot.targetPath
      if (targetPath.length === 0) {
        throw new Error('直链下载目标路径为空')
      }
      if (!fileIo.accessSync(targetPath) && !fileIo.accessSync(targetPath + '.resume')) {
        snapshot.state = VideoDownloadState.QUEUED
        snapshot.progressPercent = 0
        snapshot.processedBytes = 0
        snapshot.errorMessage = ''
        return
      }
      // A direct task is resumed by the app-owned HTTP downloader. This avoids
      // request.agent.getTask(), which cannot reattach to Download-mode paths.
      if (snapshot.state !== VideoDownloadState.PAUSED ||
        snapshot.errorMessage.indexOf('系统任务') >= 0 ||
        snapshot.errorMessage.indexOf('系统下载') >= 0) {
        snapshot.state = VideoDownloadState.QUEUED
        snapshot.errorMessage = ''
      }
    } catch (err) {
      logger.warn('准备直链下载任务恢复失败: task=%{public}s error=%{public}s',
        snapshot.taskId, this.getErrorMessage(err))
      snapshot.state = VideoDownloadState.QUEUED
      snapshot.errorMessage = ''
    }
  }

  private targetFromSnapshot(snapshot: VideoDownloadSnapshot): UserDownloadTarget {
    const target = new UserDownloadTarget()
    target.fileName = snapshot.fileName
    target.path = snapshot.targetPath
    target.uri = snapshot.targetUri
    target.finalPath = snapshot.targetPath.endsWith(DIRECT_STAGING_SUFFIX) ?
      snapshot.targetPath.substring(0, snapshot.targetPath.length - DIRECT_STAGING_SUFFIX.length) : snapshot.targetPath
    return target
  }

  private validateHttpUrl(url: string): void {
    const lowerUrl = url.toLowerCase()
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      throw new Error('仅支持 HTTP 或 HTTPS 视频地址')
    }
  }

  private findReusableDownload(input: VideoDownloadRequest): VideoDownloadSnapshot | null {
    const expectedTitle = this.buildTaskTitle(input)
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      const snapshot = values[i]
      if (snapshot.sourceUrl !== input.url || snapshot.title !== expectedTitle) {
        continue
      }
      if (snapshot.state === VideoDownloadState.RUNNING || snapshot.state === VideoDownloadState.PREPARING ||
        snapshot.state === VideoDownloadState.PAUSED || snapshot.state === VideoDownloadState.QUEUED) {
        return snapshot.clone()
      }
      if (snapshot.state === VideoDownloadState.COMPLETED) {
        if (this.isDownloadedFileAvailable(snapshot)) {
          return snapshot.clone()
        }
        snapshot.state = VideoDownloadState.FAILED
        snapshot.errorMessage = '下载文件已被移除'
        this.emit(snapshot)
      }
    }
    return null
  }

  private isDownloadedFileAvailable(snapshot: VideoDownloadSnapshot): boolean {
    try {
      return snapshot.targetPath.length > 0 && fileIo.accessSync(snapshot.targetPath) &&
        fileIo.statSync(snapshot.targetPath).size > 0
    } catch (_err) {
      return false
    }
  }

  private isHlsRequest(input: VideoDownloadRequest): boolean {
    const mediaType = input.mediaType.toLowerCase()
    const lowerUrl = input.url.toLowerCase().split('?')[0].split('#')[0]
    return mediaType === 'm3u8' || mediaType === 'hls' || lowerUrl.endsWith('.m3u8')
  }

  private isDashRequest(input: VideoDownloadRequest): boolean {
    const mediaType = input.mediaType.toLowerCase()
    const lowerUrl = input.url.toLowerCase().split('?')[0].split('#')[0]
    return mediaType === 'mpd' || mediaType === 'dash' ||
      mediaType === 'application/dash+xml' || lowerUrl.endsWith('.mpd')
  }

  private isAdaptiveKind(kind: VideoDownloadKind): boolean {
    return kind === VideoDownloadKind.HLS || kind === VideoDownloadKind.DASH
  }

  private createSnapshot(taskId: string, input: VideoDownloadRequest,
    target: UserDownloadTarget, kind: VideoDownloadKind): VideoDownloadSnapshot {
    const snapshot = new VideoDownloadSnapshot()
    snapshot.taskId = taskId
    snapshot.sourceUrl = input.url
    snapshot.targetUri = target.uri
    snapshot.targetPath = target.path
    snapshot.fileName = target.fileName
    snapshot.title = this.buildTaskTitle(input)
    snapshot.kind = kind
    snapshot.mediaType = input.mediaType
    snapshot.headers = this.buildHeaders(input.headers)
    snapshot.createdAt = Date.now()
    snapshot.queuedAt = snapshot.createdAt
    snapshot.animeCover = input.animeCover
    snapshot.animeUrl = input.animeUrl
    snapshot.episodeUrl = input.episodeUrl
    snapshot.sourceName = input.sourceName
    snapshot.sourceId = input.sourceId
    snapshot.bangumiId = input.bangumiId
    snapshot.roadIndex = input.roadIndex
    snapshot.episodeIndex = input.episodeIndex
    snapshot.downloadDanmaku = input.downloadDanmaku
    snapshot.drmScheme = input.drmScheme
    snapshot.drmLicenseUrl = input.drmLicenseUrl
    snapshot.drmHeaders = this.buildHeaders(input.drmHeaders)
    return snapshot
  }

  private bindTaskEvents(task: request.agent.Task, snapshot: VideoDownloadSnapshot): void {
    task.on('progress', (progress: request.agent.Progress) => {
      this.applyProgress(snapshot, progress)
      snapshot.state = VideoDownloadState.RUNNING
      this.emitProgress(snapshot)
    })
    task.on('pause', (progress: request.agent.Progress) => {
      this.applyProgress(snapshot, progress)
      snapshot.state = VideoDownloadState.PAUSED
      snapshot.speedBytesPerSecond = 0
      snapshot.estimatedRemainingSeconds = -1
      this.directResumeTaskIds.add(task.tid)
      this.emit(snapshot)
      this.releaseActiveTask(task.tid)
    })
    task.on('resume', (progress: request.agent.Progress) => {
      this.applyProgress(snapshot, progress)
      snapshot.state = VideoDownloadState.RUNNING
      this.emit(snapshot)
    })
    task.on('completed', (progress: request.agent.Progress) => {
      this.handleDirectCompleted(task, snapshot, progress)
    })
    task.on('failed', (progress: request.agent.Progress) => {
      this.applyProgress(snapshot, progress)
      snapshot.state = VideoDownloadState.FAILED
      snapshot.errorMessage = '下载失败，请检查网络、资源地址或访问凭据'
      this.emit(snapshot)
      this.tasks.delete(task.tid)
      this.directResumeTaskIds.delete(task.tid)
      const target = this.targets.get(task.tid)
      if (target !== undefined) {
        this.removeTarget(target)
        this.targets.delete(task.tid)
      }
      this.removeSystemTask(task.tid)
      this.releaseActiveTask(task.tid)
    })
  }

  private applyProgress(snapshot: VideoDownloadSnapshot, progress: request.agent.Progress): void {
    snapshot.processedBytes = Math.max(0, progress.processed)
    this.updateTransferMetrics(snapshot, snapshot.processedBytes)
    let total = -1
    if (progress.index >= 0 && progress.index < progress.sizes.length) {
      total = progress.sizes[progress.index]
    } else if (progress.sizes.length > 0) {
      total = progress.sizes[0]
    }
    snapshot.totalBytes = total
    if (total > 0) {
      snapshot.progressPercent = Math.max(0, Math.min(99,
        Math.floor(snapshot.processedBytes * 100 / total)))
    }
  }

  private scheduleQueue(): void {
    if (this.queueScheduling) {
      return
    }
    this.queueScheduling = true
    this.processQueue().finally((): void => {
      this.queueScheduling = false
      if (this.activeTaskIds.size < MAX_ACTIVE_DOWNLOADS && this.findNextQueued() !== null) {
        this.scheduleQueue()
      }
    })
  }

  private async processQueue(): Promise<void> {
    while (this.activeTaskIds.size < MAX_ACTIVE_DOWNLOADS) {
      const snapshot = this.findNextQueued()
      if (snapshot === null) {
        return
      }
      this.activeTaskIds.add(snapshot.taskId)
      snapshot.state = VideoDownloadState.PREPARING
      snapshot.errorMessage = ''
      this.resetTransferMetrics(snapshot)
      this.emit(snapshot)
      try {
        if (this.isAdaptiveKind(snapshot.kind)) {
          if (this.context === null) {
            throw new Error('下载服务尚未初始化')
          }
          await this.backgroundDownloadService.acquire(this.context, snapshot.taskId, snapshot.title)
          if (snapshot.state !== VideoDownloadState.PREPARING ||
            !this.activeTaskIds.has(snapshot.taskId)) {
            await this.backgroundDownloadService.release(snapshot.taskId)
            this.releaseActiveTask(snapshot.taskId)
            continue
          }
          snapshot.state = VideoDownloadState.RUNNING
          this.emit(snapshot)
          if (snapshot.kind === VideoDownloadKind.HLS) this.launchHls(snapshot)
          else this.launchDash(snapshot)
        } else {
          const task = this.tasks.get(snapshot.taskId)
          if (task === undefined) {
            if (this.context === null) {
              throw new Error('下载服务尚未初始化')
            }
            await this.backgroundDownloadService.acquire(this.context, snapshot.taskId, snapshot.title)
            if (snapshot.state !== VideoDownloadState.PREPARING ||
              !this.activeTaskIds.has(snapshot.taskId)) {
              await this.backgroundDownloadService.release(snapshot.taskId)
              this.releaseActiveTask(snapshot.taskId)
              continue
            }
            snapshot.state = VideoDownloadState.RUNNING
            this.emit(snapshot)
            this.launchDirect(snapshot)
          } else {
            if (this.directResumeTaskIds.has(snapshot.taskId)) {
              this.directResumeTaskIds.delete(snapshot.taskId)
              await task.resume()
            } else {
              await task.start()
            }
            if (this.isTaskStopped(snapshot) || !this.activeTaskIds.has(snapshot.taskId)) {
              this.releaseActiveTask(snapshot.taskId)
              continue
            }
            snapshot.state = VideoDownloadState.RUNNING
            this.emit(snapshot)
          }
        }
      } catch (err) {
        snapshot.state = VideoDownloadState.FAILED
        snapshot.errorMessage = this.getErrorMessage(err)
        this.emit(snapshot)
        if (this.isAdaptiveKind(snapshot.kind)) {
          await this.backgroundDownloadService.release(snapshot.taskId)
        } else {
          this.tasks.delete(snapshot.taskId)
          this.directResumeTaskIds.delete(snapshot.taskId)
          this.directService.release(snapshot.taskId)
          const target = this.targets.get(snapshot.taskId)
          if (target !== undefined) {
            this.removeTarget(target)
            this.targets.delete(snapshot.taskId)
          }
          this.removeSystemTask(snapshot.taskId)
        }
        this.releaseActiveTask(snapshot.taskId)
      }
    }
  }

  private findNextQueued(): VideoDownloadSnapshot | null {
    const queued: VideoDownloadSnapshot[] = []
    const values = Array.from(this.snapshots.values())
    for (let i = 0; i < values.length; i++) {
      if (values[i].state === VideoDownloadState.QUEUED && !this.activeTaskIds.has(values[i].taskId)) {
        queued.push(values[i])
      }
    }
    queued.sort((a: VideoDownloadSnapshot, b: VideoDownloadSnapshot): number => {
      if (a.queuePriority !== b.queuePriority) {
        return b.queuePriority - a.queuePriority
      }
      return a.queuedAt - b.queuedAt
    })
    return queued.length > 0 ? queued[0] : null
  }

  private isTaskStopped(snapshot: VideoDownloadSnapshot): boolean {
    return snapshot.state === VideoDownloadState.PAUSED || snapshot.state === VideoDownloadState.CANCELLED
  }

  private releaseActiveTask(taskId: string): void {
    this.activeTaskIds.delete(taskId)
    this.speedSamples.delete(taskId)
    this.progressEmitAt.delete(taskId)
    this.progressEmitPercent.delete(taskId)
    this.scheduleQueue()
  }

  private resetTransferMetrics(snapshot: VideoDownloadSnapshot): void {
    const now = Date.now()
    const sample = new DownloadSpeedSample()
    sample.startedAt = now
    sample.lastAt = now
    sample.lastBytes = snapshot.processedBytes
    this.speedSamples.set(snapshot.taskId, sample)
    snapshot.speedBytesPerSecond = 0
    snapshot.estimatedRemainingSeconds = -1
  }

  private updateTransferMetrics(snapshot: VideoDownloadSnapshot, currentBytes: number): void {
    const sample = this.speedSamples.get(snapshot.taskId)
    if (sample === undefined) {
      this.resetTransferMetrics(snapshot)
      return
    }
    const now = Date.now()
    const elapsed = now - sample.lastAt
    const delta = currentBytes - sample.lastBytes
    if (elapsed >= 500 && delta >= 0) {
      const instantSpeed = delta * 1000 / elapsed
      sample.speed = sample.speed > 0 ? sample.speed * 0.65 + instantSpeed * 0.35 : instantSpeed
      sample.lastAt = now
      sample.lastBytes = currentBytes
      snapshot.speedBytesPerSecond = Math.max(0, Math.floor(sample.speed))
    }
    if (snapshot.totalBytes > currentBytes && snapshot.speedBytesPerSecond > 0) {
      snapshot.estimatedRemainingSeconds = Math.ceil(
        (snapshot.totalBytes - currentBytes) / snapshot.speedBytesPerSecond)
    } else if (this.isAdaptiveKind(snapshot.kind) && snapshot.progressPercent > 0 &&
      snapshot.progressPercent < 100) {
      const totalElapsed = Math.max(1, now - sample.startedAt)
      snapshot.estimatedRemainingSeconds = Math.ceil(
        totalElapsed * (100 - snapshot.progressPercent) / snapshot.progressPercent / 1000)
    }
  }

  private handleDirectCompleted(task: request.agent.Task, snapshot: VideoDownloadSnapshot,
    progress: request.agent.Progress): void {
    this.completeDirect(task, snapshot, progress).catch((err: Object): void => {
      snapshot.state = VideoDownloadState.FAILED
      snapshot.errorMessage = '下载完成，但保存离线信息失败：' + this.getErrorMessage(err)
      this.emit(snapshot)
      this.tasks.delete(task.tid)
      this.directResumeTaskIds.delete(task.tid)
      this.targets.delete(task.tid)
      this.removeSystemTask(task.tid)
      this.releaseActiveTask(task.tid)
    })
  }

  private async completeDirect(task: request.agent.Task, snapshot: VideoDownloadSnapshot,
    progress: request.agent.Progress): Promise<void> {
    this.applyProgress(snapshot, progress)
    const target = this.targets.get(task.tid)
    if (target === undefined) {
      throw new Error('下载目标不存在')
    }
    this.finalizeTarget(target, snapshot)
    snapshot.progressPercent = 100
    snapshot.completedAt = Date.now()
    snapshot.errorMessage = ''
    snapshot.state = VideoDownloadState.PREPARING
    this.emit(snapshot)
    await this.companionService.complete(snapshot)
    snapshot.state = VideoDownloadState.COMPLETED
    snapshot.speedBytesPerSecond = 0
    snapshot.estimatedRemainingSeconds = 0
    this.emit(snapshot)
    this.tasks.delete(task.tid)
    this.directResumeTaskIds.delete(task.tid)
    this.targets.delete(task.tid)
    this.removeSystemTask(task.tid)
    this.releaseActiveTask(task.tid)
  }

  private requestFromSnapshot(snapshot: VideoDownloadSnapshot): VideoDownloadRequest {
    const input = new VideoDownloadRequest()
    input.url = snapshot.sourceUrl
    const separator = snapshot.title.indexOf(' - ')
    input.title = separator > 0 ? snapshot.title.substring(0, separator) : snapshot.title
    input.episodeTitle = separator > 0 ? snapshot.title.substring(separator + 3) : ''
    input.mediaType = snapshot.mediaType
    input.headers = snapshot.headers
    input.animeCover = snapshot.animeCover
    input.animeUrl = snapshot.animeUrl
    input.episodeUrl = snapshot.episodeUrl
    input.sourceName = snapshot.sourceName
    input.sourceId = snapshot.sourceId
    input.bangumiId = snapshot.bangumiId
    input.roadIndex = snapshot.roadIndex
    input.episodeIndex = snapshot.episodeIndex
    input.downloadDanmaku = snapshot.downloadDanmaku
    input.drmScheme = snapshot.drmScheme
    input.drmLicenseUrl = snapshot.drmLicenseUrl
    input.drmHeaders = snapshot.drmHeaders
    return input
  }

  private clearOfflineLicense(snapshot: VideoDownloadSnapshot): void {
    if (snapshot.drmOfflineKeyId.length === 0) return
    try {
      this.drmLicenseService.clear(snapshot.drmPluginName, snapshot.drmScheme, snapshot.drmOfflineKeyId)
      snapshot.drmOfflineKeyId = ''
    } catch (err) {
      logger.warn('清理DRM离线许可证失败: %{public}s', this.getErrorMessage(err))
    }
  }

  private getSnapshotStorageBytes(snapshot: VideoDownloadSnapshot): number {
    try {
      // Progress callbacks can arrive many times per second. For unfinished
      // tasks, the in-memory byte counter is sufficient and avoids synchronous
      // access/stat/listFile calls on the UI thread. Exact disk usage is still
      // calculated for completed tasks and by the cached summary path.
      if (snapshot.state !== VideoDownloadState.COMPLETED) {
        return Math.max(0, snapshot.processedBytes)
      }
      let bytes = 0
      if (this.isAdaptiveKind(snapshot.kind)) {
        bytes = this.getDirectoryStorageBytes(snapshot.targetDirectory)
      } else {
        bytes = this.getFileStorageBytes(snapshot.targetPath)
      }
      bytes += this.getFileStorageBytes(snapshot.coverPath)
      bytes += this.getFileStorageBytes(snapshot.danmakuPath)
      bytes += this.getFileStorageBytes(snapshot.metadataPath)
      return bytes
    } catch (_err) {
      return 0
    }
  }

  private getDirectoryStorageBytes(directory: string): number {
    if (directory.length === 0 || !fileIo.accessSync(directory)) {
      return 0
    }
    let bytes = 0
    const options: ListFileOptions = { recursion: true }
    const names = fileIo.listFileSync(directory, options)
    for (let i = 0; i < names.length; i++) {
      bytes += this.getFileStorageBytes(directory + '/' + names[i].replace(/\\/g, '/'))
    }
    return bytes
  }

  private getFileStorageBytes(path: string): number {
    if (path.length === 0 || !fileIo.accessSync(path)) {
      return 0
    }
    const stat = fileIo.statSync(path)
    return stat.isFile() ? stat.size : 0
  }

  private emit(snapshot: VideoDownloadSnapshot): void {
    if (snapshot.state !== VideoDownloadState.RUNNING && snapshot.state !== VideoDownloadState.PREPARING) {
      this.storageSummaryCache = null
      this.storageSummaryCacheAt = 0
    }
    this.schedulePersist()
    const copy = snapshot.clone()
    const currentListeners = this.listeners.slice()
    for (let i = 0; i < currentListeners.length; i++) {
      try {
        currentListeners[i](copy)
      } catch (err) {
        logger.warn('下载状态监听器执行失败: %{public}s', this.getErrorMessage(err))
      }
    }
  }

  private schedulePersist(): void {
    if (!this.initialized || this.persistTimer >= 0) {
      return
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1
      this.persistNow()
    }, PERSIST_INTERVAL_MS)
  }

  private persistNow(): void {
    this.taskStore.save(this.getAllSnapshots())
  }

  /**
   * Coalesce high-frequency transfer callbacks before notifying ArkUI.
   * File writes and speed calculation still happen for every network chunk,
   * but page reconstruction is limited to a stable UI cadence.
   */
  private emitProgress(snapshot: VideoDownloadSnapshot, force: boolean = false): boolean {
    const now = Date.now()
    const previousAt = this.progressEmitAt.get(snapshot.taskId)
    const previousPercent = this.progressEmitPercent.get(snapshot.taskId)
    if (!force && previousAt !== undefined) {
      if (now - previousAt < PROGRESS_EMIT_INTERVAL_MS) {
        return false
      }
      if (previousPercent === snapshot.progressPercent) {
        return false
      }
    }
    this.progressEmitAt.set(snapshot.taskId, now)
    this.progressEmitPercent.set(snapshot.taskId, snapshot.progressPercent)
    this.emit(snapshot)
    return true
  }

  private copyStorageSummary(source: DownloadStorageSummary): DownloadStorageSummary {
    const copy = new DownloadStorageSummary()
    copy.totalBytes = source.totalBytes
    copy.completedCount = source.completedCount
    copy.activeCount = source.activeCount
    copy.queuedCount = source.queuedCount
    copy.failedCount = source.failedCount
    return copy
  }

  private requireSnapshot(taskId: string): VideoDownloadSnapshot {
    const snapshot = this.snapshots.get(taskId)
    if (snapshot === undefined) {
      throw new Error('下载任务不存在')
    }
    return snapshot
  }

  private buildHeaders(source: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {}
    const keys = Object.keys(source)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim()
      const value = source[keys[i]].trim()
      const lowerKey = key.toLowerCase()
      if (key.length === 0 || value.length === 0 || lowerKey === 'host' ||
        lowerKey === 'content-length' || lowerKey === 'range' || lowerKey === 'accept-encoding') {
        continue
      }
      headers[key] = value
    }
    return headers
  }

  private buildTaskTitle(input: VideoDownloadRequest): string {
    let title = input.title.trim()
    if (input.episodeTitle.trim().length > 0) {
      title += title.length > 0 ? ' - ' + input.episodeTitle.trim() : input.episodeTitle.trim()
    }
    return title.length > 0 ? title.substring(0, Math.min(200, title.length)) : 'Kazumi 视频'
  }

  private buildAnimeDirectoryName(input: VideoDownloadRequest): string {
    return this.sanitizePathSegment(input.title, 'Kazumi视频', 80)
  }

  private buildEpisodeBaseName(input: VideoDownloadRequest): string {
    let episodeTitle = input.episodeTitle.trim()
    if (episodeTitle.length === 0 && input.episodeIndex >= 0) {
      episodeTitle = '第' + String(input.episodeIndex + 1) + '集'
    }
    return this.sanitizePathSegment(episodeTitle, '视频', 96)
  }

  private sanitizePathSegment(value: string, fallback: string, maxLength: number): string {
    let sanitized = value
      .replace(/[\\\/:*?"<>|\r\n]+/g, '_')
      .replace(/\s+/g, ' ')
      .trim()
    if (sanitized.length === 0) {
      sanitized = fallback
    }
    return sanitized.length > maxLength ? sanitized.substring(0, maxLength).trim() : sanitized
  }

  private buildFileName(input: VideoDownloadRequest): string {
    return this.buildEpisodeBaseName(input) + this.extractVideoExtension(input.url, input.mediaType)
  }

  private extractVideoExtension(url: string, mediaType: string): string {
    const cleanUrl = url.split('?')[0].split('#')[0].toLowerCase()
    const extensions = ['.mp4', '.mkv', '.webm', '.ts', '.flv', '.mov']
    for (let i = 0; i < extensions.length; i++) {
      if (cleanUrl.endsWith(extensions[i])) {
        return extensions[i]
      }
    }
    const normalizedType = mediaType.toLowerCase()
    if (normalizedType === 'flv' || normalizedType === 'ts' || normalizedType === 'webm' || normalizedType === 'mkv') {
      return '.' + normalizedType
    }
    return '.mp4'
  }

  private finalizeTarget(target: UserDownloadTarget, snapshot: VideoDownloadSnapshot): void {
    if (target.path !== target.finalPath) {
      fileIo.renameSync(target.path, target.finalPath)
    }
    snapshot.targetPath = target.finalPath
    snapshot.targetUri = new fileUri.FileUri(target.finalPath).toString()
  }

  private removeTarget(target: UserDownloadTarget): void {
    this.removeFile(target.path)
    this.removeFile(target.path + '.resume')
  }

  private removeFile(path: string): void {
    try {
      if (path.length > 0 && fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (err) {
      logger.warn('清理下载文件失败: %{public}s', this.getErrorMessage(err))
    }
  }

  private removeSystemTask(taskId: string): void {
    if (!taskId.startsWith('hls_') && this.tasks.has(taskId)) {
      request.agent.remove(taskId).catch((err: BusinessError) => {
        logger.warn('释放系统下载任务失败: code=%{public}d message=%{public}s', err.code, err.message)
      })
    }
  }

  private toDownloadError(prefix: string, err: Object): Error {
    return new Error(prefix + ': ' + this.getErrorMessage(err))
  }

  private getErrorMessage(err: Object): string {
    if (err instanceof Error) {
      return err.message
    }
    const businessError = err as BusinessError
    if (businessError.message !== undefined && businessError.message.length > 0) {
      return businessError.message
    }
    return String(err)
  }
}
