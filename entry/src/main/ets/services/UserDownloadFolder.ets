import { bundleManager, common } from '@kit.AbilityKit'
import { fileIo, fileUri, picker, ListFileOptions } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LocalVideoRecord } from '../models/LocalVideoRecord'
import { Logger } from '../utils/Logger'

const logger = new Logger('UserDownloadFolder')
const OWN_FOLDER_URI_PREFIX = 'file://docs/storage/Users/currentUser/Download/'

class LocalDanmakuCandidate {
  fileName: string = ''
  uri: string = ''
  format: string = ''
}

export class UserDownloadFolder {
  private static ownFolderPath: string = ''
  private static folderActivated: boolean = false

  static async ensureOwnFolder(context: common.UIAbilityContext): Promise<string> {
    if (UserDownloadFolder.folderActivated && UserDownloadFolder.ownFolderPath.length > 0) {
      return UserDownloadFolder.ownFolderPath
    }

    const bundleName = UserDownloadFolder.getBundleName()
    if (bundleName.length === 0) {
      return ''
    }

    const ownFolderUri = OWN_FOLDER_URI_PREFIX + bundleName
    const ownPath = new fileUri.FileUri(ownFolderUri).path

    try {
      if (fileIo.accessSync(ownPath)) {
        UserDownloadFolder.ownFolderPath = ownPath
        UserDownloadFolder.folderActivated = true
        logger.info('Download包名目录已存在: %{public}s', ownPath)
        return ownPath
      }
    } catch (_err) {
    }

    try {
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      documentSaveOptions.newFileNames = ['.placeholder']
      const documentViewPicker = new picker.DocumentViewPicker(context)
      const saveResult: Array<string> = await documentViewPicker.save(documentSaveOptions)
      if (saveResult.length > 0) {
        const resultUri = saveResult[0]
        const resultPath = new fileUri.FileUri(resultUri).path
        const parentDir = resultPath.substring(0, resultPath.lastIndexOf('/'))
        UserDownloadFolder.ownFolderPath = parentDir
        UserDownloadFolder.folderActivated = true

        try {
          const placeholderPath = resultPath
          if (fileIo.accessSync(placeholderPath)) {
            fileIo.unlinkSync(placeholderPath)
            logger.info('已清理占位文件')
          }
        } catch (_err) {
        }

        logger.info('Download包名目录激活成功: %{public}s', parentDir)
        return parentDir
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Download包名目录激活失败: %{public}s', msg)
    }

    return ''
  }

  static async scanOwnVideoFiles(context: common.UIAbilityContext): Promise<LocalVideoRecord[] | null> {
    const folderPath = await UserDownloadFolder.ensureOwnFolder(context)
    if (folderPath.length === 0) {
      return null
    }

    const records: LocalVideoRecord[] = []
    const danmakuCandidates: Map<string, LocalDanmakuCandidate> = new Map()
    const videoMatchKeys: string[] = []
    try {
      const listFileOptions: ListFileOptions = {
        recursion: true
      }
      const filenames = fileIo.listFileSync(folderPath, listFileOptions)
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

        if (UserDownloadFolder.isVideoFile(relativePath)) {
          const record = new LocalVideoRecord()
          record.fileUri = new fileUri.FileUri(filePath).toString()
          record.fileName = UserDownloadFolder.getFileName(relativePath)
          record.fileSize = stat.size
          record.fileKey = record.fileUri + '|' + record.fileSize + '|' + record.fileName
          records.push(record)
          videoMatchKeys.push(UserDownloadFolder.buildMatchKey(relativePath))
        } else if (UserDownloadFolder.isDanmakuFile(relativePath)) {
          const candidate = new LocalDanmakuCandidate()
          candidate.fileName = UserDownloadFolder.getFileName(relativePath)
          candidate.uri = new fileUri.FileUri(filePath).toString()
          candidate.format = UserDownloadFolder.getDanmakuFormatLabel(relativePath)
          const key = UserDownloadFolder.buildMatchKey(relativePath)
          if (!danmakuCandidates.has(key)) {
            danmakuCandidates.set(key, candidate)
          }
        }
      }

      for (let i = 0; i < records.length; i++) {
        const candidate = danmakuCandidates.get(videoMatchKeys[i])
        if (candidate === undefined) {
          continue
        }
        records[i].danmakuFileName = candidate.fileName
        records[i].danmakuUri = candidate.uri
        records[i].danmakuFormat = candidate.format
      }
      logger.info('扫描Download包名目录视频: %{public}d', records.length)
    } catch (err) {
      logger.warn('扫描Download包名目录失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
    return records
  }

  private static normalizeRelativePath(path: string): string {
    let normalized = path
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1)
    }
    return normalized
  }

  private static isVideoFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    return lowerPath.endsWith('.mp4') || lowerPath.endsWith('.mkv') || lowerPath.endsWith('.avi') ||
      lowerPath.endsWith('.webm') || lowerPath.endsWith('.ts') || lowerPath.endsWith('.flv') ||
      lowerPath.endsWith('.mov') || lowerPath.endsWith('.wmv') || lowerPath.endsWith('.3gp')
  }

  private static isDanmakuFile(path: string): boolean {
    const lowerPath = path.toLowerCase()
    return lowerPath.endsWith('.xml') || lowerPath.endsWith('.json') || lowerPath.endsWith('.ass')
  }

  private static buildMatchKey(path: string): string {
    const directory = UserDownloadFolder.getDirName(path).toLowerCase()
    const baseName = UserDownloadFolder.removeExtension(UserDownloadFolder.getFileName(path)).toLowerCase()
    return directory + '/' + baseName
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

  private static getBundleName(): string {
    try {
      const bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleFlags)
      return bundleInfo.name
    } catch (err) {
      logger.warn('获取应用包名失败: %{public}s', err instanceof Error ? err.message : String(err))
      return ''
    }
  }
}
