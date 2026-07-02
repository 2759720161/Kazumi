import { picker, fileIo } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalFilePicker')

export class LocalFileResult {
  fileName: string = ''
  content: string = ''
}

export class LocalVideoResult {
  fileName: string = ''
  uri: string = ''
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
      const content = LocalFilePicker.readTextFile(uri)
      if (content.length === 0) {
        logger.warn('弹幕文件内容为空: %{public}s', fileName)
        return null
      }

      logger.info('选择弹幕文件: %{public}s, size=%{public}d', fileName, content.length)
      const result = new LocalFileResult()
      result.fileName = fileName
      result.content = content
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
      return result
    } catch (err) {
      logger.error('选择视频文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      return null
    }
  }

  private static readTextFile(uri: string): string {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const stat = fileIo.statSync(file.fd)
        const buf = new ArrayBuffer(stat.size)
        fileIo.readSync(file.fd, buf)
        const arr = new Uint8Array(buf)
        let result = ''
        for (let i = 0; i < arr.length; i++) {
          result += String.fromCharCode(arr[i])
        }
        return result
      } finally {
        fileIo.closeSync(file)
      }
    } catch (err) {
      logger.error('读取文件失败: %{public}s', err instanceof Error ? err.message : String(err))
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
