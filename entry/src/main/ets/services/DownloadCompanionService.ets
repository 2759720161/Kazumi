import { fileIo, fileUri } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { DanmakuApiResponse, DanmakuApiService } from '../core/danmaku/DanmakuApiService'
import { DandanCredentialStore } from '../core/danmaku/DandanCredentialStore'
import { DanmakuEpisodeResolver } from '../core/danmaku/DanmakuEpisodeResolver'
import { DanmakuItem } from '../models/DanmakuItem'
import { VideoDownloadKind, VideoDownloadSnapshot } from '../models/VideoDownloadTask'
import { Logger } from '../utils/Logger'

const logger = new Logger('DownloadCompanionService')
const DANMAKU_FOLDER_NAME = '弹幕'
const COVER_FOLDER_NAME = '封面'
const INFORMATION_FOLDER_NAME = '信息'

class OfflineDanmakuComment {
  m: string = ''
  p: string = ''
}

class OfflineDanmakuPayload {
  comments: OfflineDanmakuComment[] = []
}

class OfflineVideoMetadata {
  version: number = 2
  title: string = ''
  sourceUrl: string = ''
  animeCover: string = ''
  animeUrl: string = ''
  episodeUrl: string = ''
  sourceName: string = ''
  sourceId: number = -1
  bangumiId: number = 0
  roadIndex: number = -1
  episodeIndex: number = -1
  coverUri: string = ''
  danmakuUri: string = ''
  danmakuCount: number = 0
  completedAt: number = 0
  drmScheme: string = ''
  drmPluginName: string = ''
  drmOfflineKeyId: string = ''
}

export class DownloadCompanionService {
  private readonly danmakuResolver: DanmakuEpisodeResolver = new DanmakuEpisodeResolver()
  private readonly danmakuApi: DanmakuApiService = new DanmakuApiService()

  async complete(snapshot: VideoDownloadSnapshot): Promise<void> {
    try {
      await this.downloadCover(snapshot)
    } catch (err) {
      logger.warn('下载离线封面失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
    if (snapshot.downloadDanmaku) {
      try {
        await this.downloadDanmaku(snapshot)
      } catch (err) {
        logger.warn('下载离线弹幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    try {
      this.writeMetadata(snapshot)
    } catch (err) {
      logger.warn('写入离线元数据失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  removeCompanions(snapshot: VideoDownloadSnapshot): void {
    this.removeFile(snapshot.coverPath)
    this.removeFile(snapshot.danmakuPath)
    this.removeFile(snapshot.metadataPath)
  }

  private async downloadCover(snapshot: VideoDownloadSnapshot): Promise<void> {
    if (!this.isHttpUrl(snapshot.animeCover)) {
      return
    }
    const extension = this.extractImageExtension(snapshot.animeCover)
    const path = this.getCompanionPath(snapshot, COVER_FOLDER_NAME, extension)
    if (!this.isCompleteFile(path)) {
      await this.downloadFile(snapshot.animeCover, path, snapshot.headers)
    }
    snapshot.coverPath = path
    snapshot.coverUri = new fileUri.FileUri(path).toString()
  }

  private async downloadDanmaku(snapshot: VideoDownloadSnapshot): Promise<void> {
    if (snapshot.episodeIndex < 0 || snapshot.title.length === 0) {
      return
    }
    await DandanCredentialStore.getInstance().init()
    const animeName = this.getAnimeName(snapshot)
    const episodeId = await this.danmakuResolver.resolveEpisodeId(animeName, snapshot.episodeIndex,
      snapshot.bangumiId)
    if (episodeId <= 0) {
      return
    }
    const response: DanmakuApiResponse = await this.danmakuApi.fetchDanmaku(episodeId)
    if (!response.success || response.items.length === 0) {
      return
    }
    const payload = new OfflineDanmakuPayload()
    payload.comments = this.toDanmakuComments(response.items)
    const path = this.getCompanionPath(snapshot, DANMAKU_FOLDER_NAME, '.json')
    this.writeTextFile(path, JSON.stringify(payload))
    snapshot.danmakuPath = path
    snapshot.danmakuUri = new fileUri.FileUri(path).toString()
    snapshot.danmakuCount = payload.comments.length
  }

  private writeMetadata(snapshot: VideoDownloadSnapshot): void {
    const metadata = new OfflineVideoMetadata()
    metadata.title = snapshot.title
    metadata.sourceUrl = snapshot.sourceUrl
    metadata.animeCover = snapshot.animeCover
    metadata.animeUrl = snapshot.animeUrl
    metadata.episodeUrl = snapshot.episodeUrl
    metadata.sourceName = snapshot.sourceName
    metadata.sourceId = snapshot.sourceId
    metadata.bangumiId = snapshot.bangumiId
    metadata.roadIndex = snapshot.roadIndex
    metadata.episodeIndex = snapshot.episodeIndex
    metadata.coverUri = snapshot.coverUri
    metadata.danmakuUri = snapshot.danmakuUri
    metadata.danmakuCount = snapshot.danmakuCount
    metadata.completedAt = snapshot.completedAt > 0 ? snapshot.completedAt : Date.now()
    metadata.drmScheme = snapshot.drmScheme
    metadata.drmPluginName = snapshot.drmPluginName
    metadata.drmOfflineKeyId = snapshot.drmOfflineKeyId
    const path = this.getCompanionPath(snapshot, INFORMATION_FOLDER_NAME, '.json')
    this.writeTextFile(path, JSON.stringify(metadata))
    snapshot.metadataPath = path
  }

  private async downloadFile(url: string, path: string, sourceHeaders: Record<string, string>): Promise<void> {
    const tempPath = path + '.tmp'
    this.removeFile(tempPath)
    const target = fileIo.openSync(tempPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    const request = http.createHttp()
    let offset = 0
    const receive = (data: ArrayBuffer): void => {
      fileIo.writeSync(target.fd, data, { offset: offset })
      offset += data.byteLength
    }
    request.on('dataReceive', receive)
    try {
      const status = await request.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: sourceHeaders,
        connectTimeout: 15000,
        readTimeout: 60000
      })
      if (status < 200 || status >= 300) {
        throw new Error('HTTP ' + String(status))
      }
    } finally {
      request.off('dataReceive', receive)
      request.destroy()
      fileIo.closeSync(target)
    }
    if (offset <= 0) {
      this.removeFile(tempPath)
      throw new Error('服务器返回空文件')
    }
    fileIo.renameSync(tempPath, path)
  }

  private toDanmakuComments(items: DanmakuItem[]): OfflineDanmakuComment[] {
    const comments: OfflineDanmakuComment[] = []
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      const comment = new OfflineDanmakuComment()
      comment.m = item.content
      const type = item.type === 4 || item.type === 5 ? item.type : 1
      comment.p = (item.timeMs / 1000).toFixed(3) + ',' + String(type) + ',' +
        String(this.colorToInt(item.color)) + ',' + item.source
      comments.push(comment)
    }
    return comments
  }

  private colorToInt(color: string): number {
    const value = color.startsWith('#') ? color.substring(1) : color
    const parsed = parseInt(value, 16)
    return isNaN(parsed) ? 0xFFFFFF : parsed
  }

  private getAnimeName(snapshot: VideoDownloadSnapshot): string {
    const separator = snapshot.title.indexOf(' - ')
    return separator > 0 ? snapshot.title.substring(0, separator) : snapshot.title
  }

  private getCompanionPath(snapshot: VideoDownloadSnapshot, folderName: string, extension: string): string {
    const animeFolder = this.getAnimeFolderPath(snapshot)
    const companionFolder = animeFolder + '/' + folderName
    this.ensureFolder(companionFolder)
    return companionFolder + '/' + this.getEpisodeBaseName(snapshot) + extension
  }

  private getAnimeFolderPath(snapshot: VideoDownloadSnapshot): string {
    if (snapshot.kind === VideoDownloadKind.HLS || snapshot.kind === VideoDownloadKind.DASH) {
      return this.getDirName(snapshot.targetDirectory)
    }
    return this.getDirName(snapshot.targetPath)
  }

  private getEpisodeBaseName(snapshot: VideoDownloadSnapshot): string {
    if (snapshot.kind === VideoDownloadKind.HLS || snapshot.kind === VideoDownloadKind.DASH) {
      return this.getFileName(snapshot.targetDirectory)
    }
    return this.removeExtension(this.getFileName(snapshot.targetPath))
  }

  private ensureFolder(path: string): void {
    if (!fileIo.accessSync(path)) {
      fileIo.mkdirSync(path)
    }
  }

  private getFileName(path: string): string {
    const slash = path.lastIndexOf('/')
    return slash >= 0 ? path.substring(slash + 1) : path
  }

  private getDirName(path: string): string {
    const slash = path.lastIndexOf('/')
    return slash > 0 ? path.substring(0, slash) : ''
  }

  private removeExtension(fileName: string): string {
    const dot = fileName.lastIndexOf('.')
    return dot > 0 ? fileName.substring(0, dot) : fileName
  }

  private extractImageExtension(url: string): string {
    const clean = url.split('?')[0].split('#')[0].toLowerCase()
    const extensions = ['.jpg', '.jpeg', '.png', '.webp']
    for (let i = 0; i < extensions.length; i++) {
      if (clean.endsWith(extensions[i])) {
        return extensions[i]
      }
    }
    return '.jpg'
  }

  private isHttpUrl(value: string): boolean {
    return value.startsWith('http://') || value.startsWith('https://')
  }

  private isCompleteFile(path: string): boolean {
    try {
      return fileIo.accessSync(path) && fileIo.statSync(path).size > 0
    } catch (_err) {
      return false
    }
  }

  private writeTextFile(path: string, content: string): void {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, content)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private removeFile(path: string): void {
    try {
      if (path.length > 0 && fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_err) {
    }
  }
}
