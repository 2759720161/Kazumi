import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { media } from '@kit.MediaKit'
import { FileStore } from '../store/FileStore'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalVideoThumbnailStore')

export class LocalVideoThumbnailStore {
  private static instance: LocalVideoThumbnailStore | null = null
  private readonly cacheDirName: string = 'local_video_covers'

  private constructor() {}

  static getInstance(): LocalVideoThumbnailStore {
    if (LocalVideoThumbnailStore.instance === null) {
      LocalVideoThumbnailStore.instance = new LocalVideoThumbnailStore()
    }
    return LocalVideoThumbnailStore.instance
  }

  async ensureThumbnail(videoUri: string, fileName: string, fileSize: number): Promise<string> {
    if (videoUri.length === 0) {
      return ''
    }

    const path = this.getCachePath(videoUri, fileName, fileSize)
    if (this.isValidCacheFile(path)) {
      return fileUri.getUriFromPath(path)
    }

    let videoFile: fs.File | null = null
    let generator: media.AVImageGenerator | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      videoFile = fs.openSync(videoUri, fs.OpenMode.READ_ONLY)
      const avFileDescriptor: media.AVFileDescriptor = {
        fd: videoFile.fd
      }
      generator = await media.createAVImageGenerator()
      generator.fdSrc = avFileDescriptor
      pixelMap = await generator.fetchFrameByTime(
        1000000,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
        {
          width: 540,
          height: 304
        }
      )

      const packer = image.createImagePacker()
      try {
        const data = await packer.packToData(pixelMap, {
          format: 'image/jpeg',
          quality: 82
        })
        this.writeBinary(path, data)
      } finally {
        await packer.release()
      }

      logger.info('本地视频封面生成成功: %{public}s', this.shorten(fileName))
      return fileUri.getUriFromPath(path)
    } catch (err) {
      logger.warn('本地视频封面生成失败: %{public}s, err=%{public}s',
        this.shorten(fileName), err instanceof Error ? err.message : String(err))
      return ''
    } finally {
      if (pixelMap !== null) {
        try {
          await pixelMap.release()
        } catch (_err) {
        }
      }
      if (generator !== null) {
        try {
          await generator.release()
        } catch (_err) {
        }
      }
      if (videoFile !== null) {
        try {
          fs.closeSync(videoFile)
        } catch (_err) {
        }
      }
    }
  }

  private isValidCacheFile(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        return false
      }
      const stat = fs.statSync(path)
      return stat.size > 100
    } catch (_err) {
      return false
    }
  }

  private writeBinary(path: string, data: ArrayBuffer): void {
    const dirPath = path.substring(0, path.lastIndexOf('/'))
    if (!this.pathExists(dirPath)) {
      fs.mkdirSync(dirPath, true)
    }
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
    try {
      fs.writeSync(file.fd, data)
    } finally {
      fs.closeSync(file)
    }
  }

  private pathExists(path: string): boolean {
    try {
      return fs.accessSync(path)
    } catch (_err) {
      return false
    }
  }

  private getCachePath(videoUri: string, fileName: string, fileSize: number): string {
    const cacheDir = FileStore.getInstance().getCacheDir()
    const key = `${videoUri}|${fileName}|${fileSize}`
    return `${cacheDir}/${this.cacheDirName}/${this.hashKey(key)}.jpg`
  }

  private hashKey(value: string): string {
    let hash = 5381
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) & 0x7fffffff
    }
    return hash.toString(16)
  }

  private shorten(value: string): string {
    return value.length > 80 ? value.substring(0, 80) : value
  }
}
