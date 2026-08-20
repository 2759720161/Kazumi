import { picker, fileIo, fileShare, fileUri } from '@kit.CoreFileKit'
import { bundleManager, common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalFilePicker')
const DOWNLOAD_MODE_URI_PREFIX = 'file://docs/storage/Users/currentUser/Download/'
const FANPLAYER_DOWNLOAD_URI_PREFIX = DOWNLOAD_MODE_URI_PREFIX + 'FanPlayer/'

export class LocalFileResult {
  fileName: string = ''
  uri: string = ''
  content: string = ''
  fileSize: number = 0
}

export class LocalVideoResult {
  fileName: string = ''
  uri: string = ''
  fileSize: number = 0
}

export class TextFileReadResult {
  content: string = ''
  fileSize: number = 0
}

export class LocalFilePicker {
  static async pickDanmakuFile(context: common.UIAbilityContext): Promise<LocalFileResult | null> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      documentSelectOptions.fileSuffixFilters = ['弹幕文件(.xml, .json, .ass)|.xml,.json,.ass']
      const documentPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await documentPicker.select(documentSelectOptions)
      if (uris.length === 0) {
        return null
      }

      const uri = uris[0]
      await LocalFilePicker.persistUriPermission(uri)
      const fileName = LocalFilePicker.getFileNameFromUri(uri)
      const readResult = LocalFilePicker.readTextFile(uri)
      if (readResult.content.length === 0) {
        logger.warn('弹幕文件内容为空: %{public}s', fileName)
        return null
      }

      logger.info('选择弹幕文件: %{public}s, size=%{public}d', fileName, readResult.content.length)
      const result = new LocalFileResult()
      result.fileName = fileName
      result.uri = uri
      result.content = readResult.content
      result.fileSize = readResult.fileSize
      return result
    } catch (err) {
      logger.error('选择弹幕文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  static async pickVideoFile(context: common.UIAbilityContext): Promise<LocalVideoResult | null> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      documentSelectOptions.fileSuffixFilters = ['视频文件|.mp4,.mkv,.avi,.webm,.ts,.flv,.mov,.wmv,.3gp']
      const documentPicker = new picker.DocumentViewPicker(context)
      const uris: string[] = await documentPicker.select(documentSelectOptions)
      if (uris.length === 0) {
        return null
      }

      const uri = uris[0]
      const fileName = LocalFilePicker.getFileNameFromUri(uri)
      logger.info('选择视频文件: %{public}s, uri=%{public}s', fileName, uri.substring(0, 60))
      await LocalFilePicker.persistUriPermission(uri)
      const result = new LocalVideoResult()
      result.fileName = fileName
      result.uri = uri
      result.fileSize = LocalFilePicker.getFileSize(uri)
      return result
    } catch (err) {
      logger.error('选择视频文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  static canReadUri(uri: string): boolean {
    if (uri.length === 0) {
      return false
    }
    const path = LocalFilePicker.getFileAccessPath(uri)
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      fileIo.closeSync(file)
      return true
    } catch (_err) {
      return false
    }
  }

  /**
   * Converts an app-owned Download-mode URI to the real filesystem path used
   * by fileIo and AVPlayer. Other document URIs must remain unchanged so that
   * their persisted FileShare permissions continue to work.
   */
  static getFileAccessPath(uri: string): string {
    if (!LocalFilePicker.isOwnDownloadModeUri(uri)) {
      return uri
    }
    try {
      return new fileUri.FileUri(uri).path
    } catch (_err) {
      return uri
    }
  }

  static async authorizeExistingUri(context: common.UIAbilityContext, uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (await LocalFilePicker.ensureReadableUri(uri)) {
      return true
    }
    if (!LocalFilePicker.isDocumentFileUri(uri)) {
      logger.warn('持久化授权不可用且跳过批量授权：该URI不是文档文件URI: %{public}s',
        uri.substring(0, 60))
      return false
    }
    return LocalFilePicker.authorizeExistingUris(context, [uri])
  }

  static async ensureReadableUri(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (LocalFilePicker.canReadUri(uri)) {
      return true
    }
    if (LocalFilePicker.isOwnDownloadModeUri(uri)) {
      logger.warn('本应用Download模式文件不可读，跳过持久化激活: %{public}s', uri.substring(0, 60))
      return false
    }
    const activated = await LocalFilePicker.activatePersistedUriPermission(uri)
    if (!activated) {
      return false
    }
    return LocalFilePicker.canReadUri(uri)
  }

  static async persistUriPermission(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (LocalFilePicker.isOwnDownloadModeUri(uri) && LocalFilePicker.canReadUri(uri)) {
      logger.info('本应用Download模式文件已具备访问权限: %{public}s', uri.substring(0, 60))
      return true
    }
    if (!LocalFilePicker.canUsePersistentPermission()) {
      logger.warn('当前设备不支持文件持久化授权')
      return false
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [LocalFilePicker.buildReadPolicy(uri)]
      const checked = await fileShare.checkPersistentPermission(policies)
      if (checked.length > 0 && checked[0]) {
        await LocalFilePicker.activatePersistedUriPermission(uri)
        return true
      }
      await fileShare.persistPermission(policies)
      await LocalFilePicker.activatePersistedUriPermission(uri)
      logger.info('持久化本地文件授权成功: %{public}s', uri.substring(0, 60))
      return true
    } catch (err) {
      logger.warn('持久化本地文件授权失败: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  static async activatePersistedUriPermission(uri: string): Promise<boolean> {
    if (uri.length === 0) {
      return false
    }
    if (LocalFilePicker.isOwnDownloadModeUri(uri)) {
      return LocalFilePicker.canReadUri(uri)
    }
    if (!LocalFilePicker.canUsePersistentPermission()) {
      return false
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [LocalFilePicker.buildReadPolicy(uri)]
      await fileShare.activatePermission(policies)
      logger.info('激活本地文件持久化授权成功: %{public}s', uri.substring(0, 60))
      return true
    } catch (err) {
      logger.warn('激活本地文件持久化授权失败: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  static async revokeUriPermission(uri: string): Promise<void> {
    if (LocalFilePicker.isOwnDownloadModeUri(uri)) {
      return
    }
    if (uri.length === 0 || !LocalFilePicker.canUsePersistentPermission()) {
      return
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [LocalFilePicker.buildReadPolicy(uri)]
      await fileShare.revokePermission(policies)
      logger.info('撤销本地文件持久化授权成功: %{public}s', uri.substring(0, 60))
    } catch (err) {
      logger.warn('撤销本地文件持久化授权失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  static async authorizeExistingUris(context: common.UIAbilityContext, uris: string[]): Promise<boolean> {
    const targetUris: string[] = []
    for (let i = 0; i < uris.length; i++) {
      if (uris[i].length > 0 && LocalFilePicker.isDocumentFileUri(uris[i])) {
        targetUris.push(uris[i])
      } else if (uris[i].length > 0) {
        logger.warn('跳过批量授权URI：不是文档文件URI: %{public}s', uris[i].substring(0, 60))
      }
    }
    if (targetUris.length === 0) {
      return false
    }
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.multiAuthMode = true
      documentSelectOptions.multiUriArray = targetUris
      const documentPicker = new picker.DocumentViewPicker(context)
      const authorizedUris: string[] = await documentPicker.select(documentSelectOptions)
      logger.info('授权本地文件: requested=%{public}d, returned=%{public}d',
        targetUris.length, authorizedUris.length)
      for (let i = 0; i < targetUris.length; i++) {
        if (!LocalFilePicker.canReadUri(targetUris[i])) {
          logger.warn('授权后仍无法读取文件: %{public}s', targetUris[i].substring(0, 60))
          return false
        }
      }
      return true
    } catch (err) {
      logger.warn('本地文件授权失败: %{public}s', err instanceof Error ? err.message : String(err))
      return false
    }
  }

  private static readTextFile(uri: string): TextFileReadResult {
    const emptyResult = new TextFileReadResult()
    emptyResult.content = ''
    emptyResult.fileSize = 0
    try {
      const file = fileIo.openSync(LocalFilePicker.getFileAccessPath(uri), fileIo.OpenMode.READ_ONLY)
      try {
        const stat = fileIo.statSync(file.fd)
        if (stat.size > 20 * 1024 * 1024) {
          logger.warn('文件过大: %{public}d bytes', stat.size)
          const oversizedResult = new TextFileReadResult()
          oversizedResult.content = ''
          oversizedResult.fileSize = stat.size
          return oversizedResult
        }
        const buf = new ArrayBuffer(stat.size)
        fileIo.readSync(file.fd, buf)
        const decoder = util.TextDecoder.create('utf-8')
        const content = decoder.decodeToString(new Uint8Array(buf))
        const result = new TextFileReadResult()
        result.content = content
        result.fileSize = stat.size
        return result
      } finally {
        fileIo.closeSync(file)
      }
    } catch (err) {
      logger.error('读取文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      return emptyResult
    }
  }

  static readDanmakuFileByUri(uri: string, fileName: string): LocalFileResult | null {
    const readResult = LocalFilePicker.readTextFile(uri)
    if (readResult.content.length === 0) {
      return null
    }
    const result = new LocalFileResult()
    result.fileName = fileName.length > 0 ? fileName : LocalFilePicker.getFileNameFromUri(uri)
    result.uri = uri
    result.content = readResult.content
    result.fileSize = readResult.fileSize
    return result
  }

  private static getFileSize(uri: string): number {
    try {
      const file = fileIo.openSync(LocalFilePicker.getFileAccessPath(uri), fileIo.OpenMode.READ_ONLY)
      try {
        const stat = fileIo.statSync(file.fd)
        return stat.size
      } finally {
        fileIo.closeSync(file)
      }
    } catch (err) {
      logger.warn('读取文件大小失败: %{public}s', err instanceof Error ? err.message : String(err))
      return 0
    }
  }

  private static isDocumentFileUri(uri: string): boolean {
    const lowerUri = uri.toLowerCase()
    if (lowerUri.includes('/media') || lowerUri.includes('medialibrary') || lowerUri.includes('/photo/')) {
      return false
    }
    return lowerUri.startsWith('file://')
  }

  private static buildReadPolicy(uri: string): fileShare.PolicyInfo {
    return {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE
    }
  }

  private static canUsePersistentPermission(): boolean {
    try {
      return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')
    } catch (_err) {
      return false
    }
  }

  private static isOwnDownloadModeUri(uri: string): boolean {
    if (uri.startsWith(FANPLAYER_DOWNLOAD_URI_PREFIX) ||
      uri === DOWNLOAD_MODE_URI_PREFIX + 'FanPlayer') {
      return true
    }
    const bundleName = LocalFilePicker.getBundleName()
    if (bundleName.length === 0) {
      return false
    }
    const ownDownloadPrefix = DOWNLOAD_MODE_URI_PREFIX + bundleName + '/'
    return uri === DOWNLOAD_MODE_URI_PREFIX + bundleName || uri.startsWith(ownDownloadPrefix)
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

  private static getFileNameFromUri(uri: string): string {
    const lastSlash = uri.lastIndexOf('/')
    if (lastSlash >= 0 && lastSlash < uri.length - 1) {
      return decodeURIComponent(uri.substring(lastSlash + 1))
    }
    return uri
  }
}
