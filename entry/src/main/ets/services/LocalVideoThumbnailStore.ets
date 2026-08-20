import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { media } from '@kit.MediaKit'
import { FileStore } from '../store/FileStore'
import { LocalFilePicker } from './LocalFilePicker'
import { Logger } from '../utils/Logger'

const logger = new Logger('LocalVideoThumbnailStore')

export class LocalVideoThumbnailStore {
  private static instance: LocalVideoThumbnailStore | null = null
  /** 目录/文件夹封面默认使用视频首帧。 */
  static readonly FIRST_FRAME_TIME_MS: number = 0
  private readonly cacheDirName: string = 'local_video_covers'
  private randomFrameTimes: Map<string, number> = new Map()

  private constructor() {}

  static getInstance(): LocalVideoThumbnailStore {
    if (LocalVideoThumbnailStore.instance === null) {
      LocalVideoThumbnailStore.instance = new LocalVideoThumbnailStore()
    }
    return LocalVideoThumbnailStore.instance
  }

  /** 按指定播放位置生成视频封面；目录扫描不传参时使用首帧。 */
  async ensureThumbnail(videoUri: string, fileName: string, fileSize: number,
    frameTimeMs: number = LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS): Promise<string> {
    if (videoUri.length === 0) {
      return ''
    }

    const safeFrameTimeMs = Math.max(0, Math.floor(frameTimeMs))
    const path = this.getCachePath(videoUri, fileName, fileSize, safeFrameTimeMs)
    if (this.isValidCacheFile(path)) {
      return fileUri.getUriFromPath(path)
    }

    let videoFile: fs.File | null = null
    let generator: media.AVImageGenerator | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      videoFile = fs.openSync(LocalFilePicker.getFileAccessPath(videoUri), fs.OpenMode.READ_ONLY)
      const avFileDescriptor: media.AVFileDescriptor = {
        fd: videoFile.fd
      }
      generator = await media.createAVImageGenerator()
      generator.fdSrc = avFileDescriptor
      pixelMap = await this.fetchPreviewFrame(generator, safeFrameTimeMs)

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

      logger.info('本地视频封面生成成功: %{public}s position=%{public}d',
        this.shorten(fileName), safeFrameTimeMs)
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

  /**
   * 为本地目录生成稳定的随机视频帧。
   *
   * 随机时间点按文件身份缓存，避免页面每次刷新都重新抽帧或导致封面闪烁。
   */
  async ensureRandomThumbnail(videoUri: string, fileName: string, fileSize: number): Promise<string> {
    if (videoUri.length === 0) {
      return ''
    }

    const key = `${videoUri}|${fileName}|${fileSize}`
    let frameTimeMs = this.randomFrameTimes.get(key)
    if (frameTimeMs === undefined) {
      const durationMs = await this.getDurationMs(videoUri)
      frameTimeMs = this.selectRandomFrameTime(key, durationMs)
      this.randomFrameTimes.set(key, frameTimeMs)
    }

    const randomFrameUri = await this.ensureThumbnail(videoUri, fileName, fileSize, frameTimeMs)
    if (randomFrameUri.length > 0) {
      return randomFrameUri
    }

    // 部分容器无法在随机时间点定位，首帧作为可靠回退。
    this.randomFrameTimes.set(key, LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS)
    return await this.ensureThumbnail(videoUri, fileName, fileSize,
      LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS)
  }

  /** 某些容器在 0 时刻没有可用同步帧，首帧封面退回到首秒。 */
  private async fetchPreviewFrame(generator: media.AVImageGenerator,
    frameTimeMs: number): Promise<image.PixelMap> {
    try {
      return await generator.fetchFrameByTime(
        frameTimeMs * 1000,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
        { width: 540, height: 304 }
      )
    } catch (err) {
      if (frameTimeMs !== LocalVideoThumbnailStore.FIRST_FRAME_TIME_MS) {
        throw new Error(err instanceof Error ? err.message : String(err))
      }
      logger.warn('零时刻视频首帧不可用，改用首秒预览: %{public}s',
        err instanceof Error ? err.message : String(err))
      return await generator.fetchFrameByTime(
        1000 * 1000,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
        { width: 540, height: 304 }
      )
    }
  }

  private async getDurationMs(videoUri: string): Promise<number> {
    let videoFile: fs.File | null = null
    let extractor: media.AVMetadataExtractor | null = null
    try {
      videoFile = fs.openSync(LocalFilePicker.getFileAccessPath(videoUri), fs.OpenMode.READ_ONLY)
      extractor = await media.createAVMetadataExtractor()
      extractor.fdSrc = { fd: videoFile.fd }
      const metadata = await extractor.fetchMetadata()
      const durationText = metadata.duration
      if (durationText === undefined) {
        return 0
      }
      const durationMs = parseFloat(durationText)
      return Number.isFinite(durationMs) && durationMs > 0 ? Math.floor(durationMs) : 0
    } catch (err) {
      logger.warn('读取本地视频时长失败: %{public}s, err=%{public}s',
        this.shorten(videoUri), err instanceof Error ? err.message : String(err))
      return 0
    } finally {
      if (extractor !== null) {
        try {
          await extractor.release()
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

  private selectRandomFrameTime(key: string, durationMs: number): number {
    if (durationMs <= 4000) {
      return Math.max(0, Math.floor(durationMs / 2))
    }

    // 避开片头和片尾，使用文件身份生成稳定的伪随机位置。
    const lowerBound = Math.floor(durationMs * 0.12)
    const upperBound = Math.max(lowerBound + 1, Math.floor(durationMs * 0.88))
    const range = upperBound - lowerBound
    const hashValue = parseInt(this.hashKey(key + '|random-frame'), 16)
    const offset = (Number.isFinite(hashValue) ? hashValue : 0) % range
    return lowerBound + offset
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

  private getCachePath(videoUri: string, fileName: string, fileSize: number, frameTimeMs: number): string {
    const cacheDir = FileStore.getInstance().getCacheDir()
    const key = `${videoUri}|${fileName}|${fileSize}|${frameTimeMs}`
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
