import { picker, fileIo } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalFilePicker')

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

  private static readTextFile(uri: string): TextFileReadResult {
    const emptyResult = new TextFileReadResult()
    emptyResult.content = ''
    emptyResult.fileSize = 0
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
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
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
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

  private static getFileNameFromUri(uri: string): string {
    const lastSlash = uri.lastIndexOf('/')
    if (lastSlash >= 0 && lastSlash < uri.length - 1) {
      return decodeURIComponent(uri.substring(lastSlash + 1))
    }
    return uri
  }
}
