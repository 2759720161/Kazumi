import { common } from '@kit.AbilityKit'
import { fileIo, fileUri, picker, ListFileOptions } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LocalVideoRecord } from '../models/LocalVideoRecord'
import { Logger } from '../utils/Logger'

const logger = new Logger('UserDownloadFolder')
const OWN_FOLDER_URI_PREFIX = 'file://docs/storage/Users/currentUser/Download/'
const OWN_FOLDER_NAME = 'FanPlayer'
const DOWNLOAD_STAGING_SUFFIX = '.kazumi-download'
const HLS_DIRECTORY_MARKER = '.kazumi-hls'
const DASH_DIRECTORY_MARKER = '.kazumi-dash'
const DANMAKU_FOLDER_NAME = '弹幕'
const COVER_FOLDER_NAME = '封面'
const INFORMATION_FOLDER_NAME = '信息'

class LocalDanmakuCandidate {
  fileName: string = ''
  uri: string = ''
  format: string = ''
}

export class UserDownloadTarget {
  fileName: string = ''
  uri: string = ''
  path: string = ''
  finalPath: string = ''
}

export class UserDownloadFolder {
  private static ownFolderPath: string = ''
  private static folderActivated: boolean = false

  static async ensureOwnFolder(context: common.UIAbilityContext): Promise<string> {
    if (UserDownloadFolder.folderActivated && UserDownloadFolder.ownFolderPath.length > 0) {
      return UserDownloadFolder.ownFolderPath
    }

    const ownFolderUri = OWN_FOLDER_URI_PREFIX + OWN_FOLDER_NAME
    const ownPath = new fileUri.FileUri(ownFolderUri).path

    try {
      if (fileIo.accessSync(ownPath)) {
        UserDownloadFolder.ownFolderPath = ownPath
        UserDownloadFolder.folderActivated = true
        logger.info('Download/FanPlayer目录已存在: %{public}s', ownPath)
        return ownPath
      }
    } catch (_err) {
    }

    try {
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      const documentViewPicker = new picker.DocumentViewPicker(context)
      const saveResult: Array<string> = await documentViewPicker.save(documentSaveOptions)
      if (saveResult.length > 0) {
        const resultUri = saveResult[0]
        const resultPath = new fileUri.FileUri(resultUri).path
        UserDownloadFolder.ownFolderPath = resultPath
        UserDownloadFolder.folderActivated = true
        logger.info('Download/FanPlayer目录激活成功: %{public}s', resultPath)
        return resultPath
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Download/FanPlayer目录激活失败: %{public}s', msg)
    }

    return ''
  }

  static async createVideoTarget(context: common.UIAbilityContext, animeDirectoryName: string,
    fileName: string): Promise<UserDownloadTarget | null> {
    if (animeDirectoryName.length === 0 || fileName.length === 0) {
      return null
    }
    try {
      const animeFolderPath = await UserDownloadFolder.ensureAnimeFolder(context, animeDirectoryName)
      if (animeFolderPath.length === 0) {
        return null
      }

      const finalPath = UserDownloadFolder.buildAvailablePath(animeFolderPath, fileName)
      const stagingPath = finalPath + DOWNLOAD_STAGING_SUFFIX
      const targetFile = fileIo.openSync(stagingPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE)
      fileIo.closeSync(targetFile)

      const target = new UserDownloadTarget()
      target.path = stagingPath
      target.finalPath = finalPath
      target.uri = new fileUri.FileUri(stagingPath).toString()
      target.fileName = UserDownloadFolder.getFileName(finalPath)
      logger.info('已创建下载目标: %{public}s', target.fileName)
      return target
    } catch (err) {
      const businessError = err as BusinessError
      logger.warn('创建下载目标失败: code=%{public}d message=%{public}s',
        businessError.code, businessError.message)
      return null
    }
  }

  static async createHlsTarget(context: common.UIAbilityContext, animeDirectoryName: string,
    directoryName: string): Promise<UserDownloadTarget | null> {
    return await UserDownloadFolder.createAdaptiveTarget(context, animeDirectoryName,
      directoryName, HLS_DIRECTORY_MARKER, 'HLS')
  }

  static async createDashTarget(context: common.UIAbilityContext, animeDirectoryName: string,
    directoryName: string): Promise<UserDownloadTarget | null> {
    return await UserDownloadFolder.createAdaptiveTarget(context, animeDirectoryName,
      directoryName, DASH_DIRECTORY_MARKER, 'DASH')
  }

  private static async createAdaptiveTarget(context: common.UIAbilityContext, animeDirectoryName: string,
    directoryName: string, markerName: string, protocolName: string): Promise<UserDownloadTarget | null> {
    if (animeDirectoryName.length === 0 || directoryName.length === 0) {
      return null
    }
    try {
      const animeFolderPath = await UserDownloadFolder.ensureAnimeFolder(context, animeDirectoryName)
      if (animeFolderPath.length === 0) {
        return null
      }
      const targetPath = UserDownloadFolder.buildAvailableDirectoryPath(animeFolderPath, directoryName)
      fileIo.mkdirSync(targetPath)
      const marker = fileIo.openSync(targetPath + '/' + markerName,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.closeSync(marker)
      const target = new UserDownloadTarget()
      target.fileName = directoryName
      target.path = targetPath
      target.finalPath = targetPath
      target.uri = new fileUri.FileUri(targetPath).toString()
      logger.info('已创建%{public}s下载目录: %{public}s', protocolName, directoryName)
      return target
    } catch (err) {
      const businessError = err as BusinessError
      logger.warn('创建%{public}s下载目录失败: code=%{public}d message=%{public}s', protocolName,
        businessError.code, businessError.message)
      return null
    }
  }

  private static async ensureAnimeFolder(context: common.UIAbilityContext,
    animeDirectoryName: string): Promise<string> {
    const rootFolderPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootFolderPath.length === 0) {
      return ''
    }
    const animeFolderPath = rootFolderPath + '/' + animeDirectoryName
    try {
      if (!fileIo.accessSync(animeFolderPath)) {
        fileIo.mkdirSync(animeFolderPath)
      }
      return animeFolderPath
    } catch (err) {
      try {
        if (fileIo.accessSync(animeFolderPath)) {
          return animeFolderPath
        }
      } catch (_err) {
      }
      logger.warn('创建番剧下载目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return ''
    }
  }

  private static buildAvailablePath(folderPath: string, fileName: string): string {
    const extensionIndex = fileName.lastIndexOf('.')
    const baseName = extensionIndex > 0 ? fileName.substring(0, extensionIndex) : fileName
    const extension = extensionIndex > 0 ? fileName.substring(extensionIndex) : ''
    let candidate = folderPath + '/' + fileName
    let suffix = 2
    while (fileIo.accessSync(candidate) || fileIo.accessSync(candidate + DOWNLOAD_STAGING_SUFFIX)) {
      candidate = folderPath + '/' + baseName + ' (' + suffix + ')' + extension
      suffix++
    }
    return candidate
  }

  private static buildAvailableDirectoryPath(folderPath: string, directoryName: string): string {
    let candidate = folderPath + '/' + directoryName
    let suffix = 2
    while (fileIo.accessSync(candidate)) {
      candidate = folderPath + '/' + directoryName + ' (' + suffix + ')'
      suffix++
    }
    return candidate
  }

  static async scanOwnVideoFiles(context: common.UIAbilityContext): Promise<LocalVideoRecord[] | null> {
    const folderPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (folderPath.length === 0) {
      return null
    }

    const records: LocalVideoRecord[] = []
    const danmakuCandidates: Map<string, LocalDanmakuCandidate> = new Map()
    const coverCandidates: Map<string, string> = new Map()
    const videoMatchKeys: string[] = []
    try {
      const listFileOptions: ListFileOptions = {
        recursion: true
      }
      const filenames = fileIo.listFileSync(folderPath, listFileOptions)
      const hlsDirectories: string[] = []
      for (let i = 0; i < filenames.length; i++) {
        const relativePath = UserDownloadFolder.normalizeRelativePath(filenames[i])
        const fileName = UserDownloadFolder.getFileName(relativePath).toLowerCase()
        if (fileName !== 'playlist.m3u8' && fileName !== HLS_DIRECTORY_MARKER &&
          fileName !== DASH_DIRECTORY_MARKER) {
          continue
        }
        const directory = UserDownloadFolder.getDirName(relativePath)
        if (directory.length > 0 && hlsDirectories.indexOf(directory) < 0) {
          hlsDirectories.push(directory)
        }
      }
      const hlsSizes: Map<string, number> = new Map()
      const hlsRecordIndices: Map<string, number> = new Map()
      for (let i = 0; i < filenames.length; i++) {
        const relativePath = UserDownloadFolder.normalizeRelativePath(filenames[i])
        if (relativePath.length === 0) {
          continue
        }

        const filePath = folderPath + '/' + relativePath
        if (!fileIo.accessSync(filePath)) {
          continue
        }
        const stat = fileIo.statSync(filePath)
        if (!stat.isFile()) {
          continue
        }

        const hlsDirectory = UserDownloadFolder.findContainingHlsDirectory(relativePath, hlsDirectories)
        if (hlsDirectory.length > 0) {
          hlsSizes.set(hlsDirectory, (hlsSizes.get(hlsDirectory) || 0) + stat.size)
          const mp4RelativePath = hlsDirectory + '/video.mp4'
          const hasMp4 = fileIo.accessSync(folderPath + '/' + mp4RelativePath)
          if (relativePath === mp4RelativePath ||
            (!hasMp4 && relativePath === hlsDirectory + '/playlist.m3u8')) {
            const record = new LocalVideoRecord()
            record.fileUri = filePath
            record.fileName = UserDownloadFolder.getFileName(hlsDirectory) +
              (relativePath === mp4RelativePath ? '.mp4' : '.m3u8')
            const metadataPath = UserDownloadFolder.buildAdaptiveMetadataPath(folderPath, hlsDirectory)
            UserDownloadFolder.applyAdaptiveMetadata(record, metadataPath)
            records.push(record)
            videoMatchKeys.push(hlsDirectory.toLowerCase())
            hlsRecordIndices.set(hlsDirectory, records.length - 1)
          }
          continue
        }

        if (UserDownloadFolder.isVideoFile(relativePath)) {
          const record = new LocalVideoRecord()
          record.fileUri = filePath
          record.fileName = UserDownloadFolder.getFileName(relativePath)
          record.fileSize = stat.size
          record.fileKey = record.fileUri + '|' + record.fileSize + '|' + record.fileName
          records.push(record)
          const matchKey = UserDownloadFolder.buildMatchKey(relativePath)
          videoMatchKeys.push(matchKey)
        } else if (UserDownloadFolder.isDanmakuFile(relativePath)) {
          const candidate = new LocalDanmakuCandidate()
          candidate.fileName = UserDownloadFolder.getFileName(relativePath)
          candidate.uri = filePath
          candidate.format = UserDownloadFolder.getDanmakuFormatLabel(relativePath)
          const key = UserDownloadFolder.buildCompanionMatchKey(relativePath, DANMAKU_FOLDER_NAME)
          if (!danmakuCandidates.has(key)) {
            danmakuCandidates.set(key, candidate)
          }
        } else if (UserDownloadFolder.isCompanionCover(relativePath)) {
          const key = UserDownloadFolder.buildCoverMatchKey(relativePath)
          if (!coverCandidates.has(key)) {
            coverCandidates.set(key, new fileUri.FileUri(filePath).toString())
          }
        }
      }

      const hlsDirectoryKeys = Array.from(hlsRecordIndices.keys())
      for (let i = 0; i < hlsDirectoryKeys.length; i++) {
        const directory = hlsDirectoryKeys[i]
        const recordIndex = hlsRecordIndices.get(directory)
        if (recordIndex === undefined) {
          continue
        }
        records[recordIndex].fileSize = hlsSizes.get(directory) || 0
        records[recordIndex].fileKey = records[recordIndex].fileUri + '|' + records[recordIndex].fileSize + '|' +
          records[recordIndex].fileName
      }

      for (let i = 0; i < records.length; i++) {
        const candidate = danmakuCandidates.get(videoMatchKeys[i])
        if (candidate !== undefined) {
          records[i].danmakuFileName = candidate.fileName
          records[i].danmakuUri = candidate.uri
          records[i].danmakuFormat = candidate.format
        }
        const coverUri = coverCandidates.get(videoMatchKeys[i])
        if (coverUri !== undefined) {
          records[i].coverUri = coverUri
        }
      }
      logger.info('扫描Download/FanPlayer目录视频: %{public}d', records.length)
    } catch (err) {
      logger.warn('扫描Download/FanPlayer目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
    return records
  }

  /**
   * Lists only the immediate folders and playable videos of an app-owned
   * directory. Companion folders are implementation details and are hidden
   * from the local-library hierarchy.
   */
  static async listOwnDirectory(context: common.UIAbilityContext,
    relativeDirectory: string = ''): Promise<UserFolderEntry[] | null> {
    const rootPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (rootPath.length === 0) {
      return null
    }
    const normalizedDirectory = UserDownloadFolder.normalizeDirectory(relativeDirectory)
    const directoryPath = normalizedDirectory.length > 0 ? rootPath + '/' + normalizedDirectory : rootPath
    const entries: UserFolderEntry[] = []
    try {
      // HLS/DASH episode directories contain implementation files such as hundreds of
      // transport-stream fragments. Expose the directory as one logical video instead
      // of treating every fragment as an independent local video.
      const adaptivePlayablePath = UserDownloadFolder.findAdaptivePlayablePath(directoryPath)
      const isAdaptiveDirectory = UserDownloadFolder.isAdaptiveDirectory(directoryPath)
      const names = fileIo.listFileSync(directoryPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.normalizeRelativePath(names[i])
        if (name.length === 0 || UserDownloadFolder.isHiddenLibraryEntry(name)) {
          continue
        }

        const childPath = directoryPath + '/' + name
        if (!fileIo.accessSync(childPath)) {
          continue
        }
        const stat = fileIo.statSync(childPath)
        const relativePath = normalizedDirectory.length > 0 ? normalizedDirectory + '/' + name : name
        if (stat.isDirectory()) {
          const entry = new UserFolderEntry()
          entry.name = UserDownloadFolder.getFileName(name)
          entry.relativePath = relativePath
          entry.isDirectory = true
          entry.modifiedTime = stat.mtime
          entry.coverUri = UserDownloadFolder.findDirectoryCover(childPath)
          const summary = UserDownloadFolder.getDirectDirectorySummary(childPath)
          entry.childDirectoryCount = summary.directoryCount
          entry.childVideoCount = summary.videoCount
          entries.push(entry)
          continue
        }
        if (!stat.isFile() || !UserDownloadFolder.isVideoFile(name)) {
          if (!isAdaptiveDirectory || childPath !== adaptivePlayablePath ||
            !name.toLowerCase().endsWith('.m3u8')) {
            continue
          }
        }
        if (isAdaptiveDirectory && childPath !== adaptivePlayablePath) {
          continue
        }
        const entry = new UserFolderEntry()
        entry.name = isAdaptiveDirectory ?
          UserDownloadFolder.buildAdaptiveDisplayName(normalizedDirectory, name) :
          UserDownloadFolder.getFileName(name)
        entry.relativePath = relativePath
        entry.isDirectory = false
        entry.modifiedTime = stat.mtime
        entry.video.fileUri = childPath
        entry.video.fileName = entry.name
        entry.video.fileSize = stat.size
        entry.video.fileKey = entry.video.fileUri + '|' + entry.video.fileSize + '|' + entry.video.fileName
        entry.video.coverUri = UserDownloadFolder.findVideoCover(directoryPath, entry.name)
        entries.push(entry)
      }

      entries.sort((first: UserFolderEntry, second: UserFolderEntry): number => {
        if (first.isDirectory !== second.isDirectory) {
          return first.isDirectory ? -1 : 1
        }
        return UserDownloadFolder.compareVideoNames(first.name, second.name)
      })
      return entries
    } catch (err) {
      logger.warn('读取本地目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  private static normalizeRelativePath(path: string): string {
    let normalized = path
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1)
    }
    return normalized
  }

  private static normalizeDirectory(path: string): string {
    const segments = path.split('/')
    const clean: string[] = []
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].length > 0 && segments[i] !== '.' && segments[i] !== '..') {
        clean.push(segments[i])
      }
    }
    return clean.join('/')
  }

  private static isHiddenLibraryEntry(name: string): boolean {
    return name === DANMAKU_FOLDER_NAME || name === COVER_FOLDER_NAME ||
      name === INFORMATION_FOLDER_NAME || name === '.subtitles' ||
      name === HLS_DIRECTORY_MARKER || name === DASH_DIRECTORY_MARKER ||
      name.endsWith(DOWNLOAD_STAGING_SUFFIX)
  }

  private static isAdaptiveDirectory(directoryPath: string): boolean {
    return fileIo.accessSync(directoryPath + '/' + HLS_DIRECTORY_MARKER) ||
      fileIo.accessSync(directoryPath + '/' + DASH_DIRECTORY_MARKER)
  }

  /**
   * Returns the sole user-facing media file for a managed adaptive-download
   * directory. A successful native remux always wins over the HLS playlist.
   */
  private static findAdaptivePlayablePath(directoryPath: string): string {
    if (!UserDownloadFolder.isAdaptiveDirectory(directoryPath)) {
      return ''
    }
    const remuxedPath = directoryPath + '/video.mp4'
    if (fileIo.accessSync(remuxedPath)) {
      return remuxedPath
    }
    const playlistPath = directoryPath + '/playlist.m3u8'
    if (fileIo.accessSync(playlistPath)) {
      return playlistPath
    }
    return ''
  }

  private static buildAdaptiveDisplayName(relativeDirectory: string, playableName: string): string {
    const episodeName = UserDownloadFolder.getFileName(relativeDirectory)
    const extensionIndex = playableName.lastIndexOf('.')
    const extension = extensionIndex >= 0 ? playableName.substring(extensionIndex) : ''
    return (episodeName.length > 0 ? episodeName : UserDownloadFolder.removeExtension(playableName)) + extension
  }

  private static findDirectoryCover(directoryPath: string): string {
    const coverPath = directoryPath + '/' + COVER_FOLDER_NAME
    try {
      if (!fileIo.accessSync(coverPath)) {
        return ''
      }
      const names = fileIo.listFileSync(coverPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.normalizeRelativePath(names[i])
        if (UserDownloadFolder.isImageFile(name)) {
          const path = coverPath + '/' + name
          if (fileIo.accessSync(path) && fileIo.statSync(path).isFile()) {
            return new fileUri.FileUri(path).toString()
          }
        }
      }
    } catch (_err) {
    }
    return ''
  }

  private static findVideoCover(directoryPath: string, videoName: string): string {
    const coverPath = directoryPath + '/' + COVER_FOLDER_NAME
    const baseName = UserDownloadFolder.removeExtension(videoName).toLowerCase()
    try {
      if (!fileIo.accessSync(coverPath)) {
        return ''
      }
      const names = fileIo.listFileSync(coverPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.normalizeRelativePath(names[i])
        if (UserDownloadFolder.isImageFile(name) &&
          UserDownloadFolder.removeExtension(name).toLowerCase() === baseName) {
          const path = coverPath + '/' + name
          if (fileIo.accessSync(path) && fileIo.statSync(path).isFile()) {
            return new fileUri.FileUri(path).toString()
          }
        }
      }
    } catch (_err) {
    }
    return ''
  }

  private static isImageFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    return lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg') ||
      lowerPath.endsWith('.png') || lowerPath.endsWith('.webp')
  }

  private static getDirectDirectorySummary(directoryPath: string): UserDirectorySummary {
    const summary = new UserDirectorySummary()
    try {
      if (UserDownloadFolder.isAdaptiveDirectory(directoryPath)) {
        summary.videoCount = UserDownloadFolder.findAdaptivePlayablePath(directoryPath).length > 0 ? 1 : 0
        return summary
      }
      const names = fileIo.listFileSync(directoryPath)
      for (let i = 0; i < names.length; i++) {
        const name = UserDownloadFolder.normalizeRelativePath(names[i])
        if (name.length === 0 || UserDownloadFolder.isHiddenLibraryEntry(name)) {
          continue
        }
        const path = directoryPath + '/' + name
        if (!fileIo.accessSync(path)) {
          continue
        }
        const stat = fileIo.statSync(path)
        if (stat.isDirectory()) {
          summary.directoryCount++
        } else if (stat.isFile() && UserDownloadFolder.isVideoFile(name)) {
          summary.videoCount++
        }
      }
    } catch (_err) {
    }
    return summary
  }

  private static applyAdaptiveMetadata(record: LocalVideoRecord, metadataPath: string): void {
    try {
      if (metadataPath.length === 0 || !fileIo.accessSync(metadataPath)) return
      const raw = JSON.parse(fileIo.readTextSync(metadataPath)) as Record<string, Object>
      const scheme = raw['drmScheme']
      const pluginName = raw['drmPluginName']
      const keyId = raw['drmOfflineKeyId']
      if (typeof scheme === 'string') record.drmScheme = scheme
      if (typeof pluginName === 'string') record.drmPluginName = pluginName
      if (typeof keyId === 'string') record.drmOfflineKeyId = keyId
    } catch (err) {
      logger.warn('读取离线DRM元数据失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private static buildAdaptiveMetadataPath(folderPath: string, hlsDirectory: string): string {
    const animeDirectory = UserDownloadFolder.getDirName(hlsDirectory)
    if (animeDirectory.length === 0) {
      return ''
    }
    return folderPath + '/' + animeDirectory + '/' + INFORMATION_FOLDER_NAME + '/' +
      UserDownloadFolder.getFileName(hlsDirectory) + '.json'
  }

  static compareVideoNames(first: string, second: string): number {
    const firstNumber = UserDownloadFolder.extractFirstNumber(first)
    const secondNumber = UserDownloadFolder.extractFirstNumber(second)
    if (firstNumber >= 0 && secondNumber >= 0 && firstNumber !== secondNumber) {
      return firstNumber - secondNumber
    }
    return first.localeCompare(second)
  }

  private static extractFirstNumber(value: string): number {
    let digits = ''
    for (let i = 0; i < value.length; i++) {
      const char = value.charAt(i)
      if (char >= '0' && char <= '9') {
        digits += char
      } else if (digits.length > 0) {
        break
      }
    }
    return digits.length > 0 ? Number(digits) : -1
  }

  private static isVideoFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    return lowerPath.endsWith('.mp4') || lowerPath.endsWith('.mkv') || lowerPath.endsWith('.avi') ||
      lowerPath.endsWith('.webm') || lowerPath.endsWith('.ts') || lowerPath.endsWith('.flv') ||
      lowerPath.endsWith('.mov') || lowerPath.endsWith('.wmv') || lowerPath.endsWith('.3gp')
  }

  private static findContainingHlsDirectory(path: string, directories: string[]): string {
    let bestMatch = ''
    for (let i = 0; i < directories.length; i++) {
      const directory = directories[i]
      if ((path === directory || path.startsWith(directory + '/')) && directory.length > bestMatch.length) {
        bestMatch = directory
      }
    }
    return bestMatch
  }

  private static isDanmakuFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    const isDanmaku = lowerPath.endsWith('.xml') || lowerPath.endsWith('.json') || lowerPath.endsWith('.ass')
    return isDanmaku && UserDownloadFolder.isInCompanionFolder(path, DANMAKU_FOLDER_NAME)
  }

  private static isCompanionCover(path: string): boolean {
    const lowerPath = path.toLowerCase()
    const isImage = lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg') ||
      lowerPath.endsWith('.png') || lowerPath.endsWith('.webp')
    return isImage && UserDownloadFolder.isInCompanionFolder(path, COVER_FOLDER_NAME)
  }

  private static buildCoverMatchKey(path: string): string {
    return UserDownloadFolder.buildCompanionMatchKey(path, COVER_FOLDER_NAME)
  }

  private static buildMatchKey(path: string): string {
    const directory = UserDownloadFolder.getDirName(path).toLowerCase()
    const baseName = UserDownloadFolder.removeExtension(UserDownloadFolder.getFileName(path)).toLowerCase()
    return directory + '/' + baseName
  }

  private static buildCompanionMatchKey(path: string, folderName: string): string {
    const directory = UserDownloadFolder.getDirName(path).toLowerCase()
    const fileName = UserDownloadFolder.getFileName(path).toLowerCase()
    return UserDownloadFolder.getDirName(directory) + '/' + UserDownloadFolder.removeExtension(fileName)
  }

  private static isInCompanionFolder(path: string, folderName: string): boolean {
    return UserDownloadFolder.getFileName(UserDownloadFolder.getDirName(path)) === folderName
  }

  private static getDirName(path: string): string {
    const slashIndex = path.lastIndexOf('/')
    if (slashIndex > 0) {
      return path.substring(0, slashIndex)
    }
    return ''
  }

  private static getFileName(path: string): string {
    const slashIndex = path.lastIndexOf('/')
    if (slashIndex >= 0 && slashIndex < path.length - 1) {
      return path.substring(slashIndex + 1)
    }
    return path
  }

  private static removeExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex)
    }
    return fileName
  }

  private static getDanmakuFormatLabel(path: string): string {
    const lowerPath = path.toLowerCase()
    if (lowerPath.endsWith('.xml')) {
      return 'B站 XML'
    }
    if (lowerPath.endsWith('.json')) {
      return '弹弹 JSON'
    }
    if (lowerPath.endsWith('.ass')) {
      return 'ASS'
    }
    return '弹幕'
  }

}

export class UserFolderEntry {
  name: string = ''
  relativePath: string = ''
  isDirectory: boolean = false
  modifiedTime: number = 0
  coverUri: string = ''
  childDirectoryCount: number = 0
  childVideoCount: number = 0
  video: LocalVideoRecord = new LocalVideoRecord()
}

class UserDirectorySummary {
  directoryCount: number = 0
  videoCount: number = 0
}
