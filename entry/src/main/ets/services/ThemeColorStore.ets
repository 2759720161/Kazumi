import { image } from '@kit.ImageKit'
import { ImageCacheStore } from '../store/ImageCacheStore'
import { Logger, extractErrorMsg } from '../utils/Logger'

const logger = new Logger('ThemeColorStore')
const SAMPLE_SIZE: number = 24

class ThemeRgb {
  r: number
  g: number
  b: number

  constructor(r: number, g: number, b: number) {
    this.r = r
    this.g = g
    this.b = b
  }
}

export class ThemeColorStore {
  private static instance: ThemeColorStore | null = null
  private readonly colorCache: Map<string, string> = new Map()
  private readonly pendingTasks: Map<string, Promise<string>> = new Map()

  private constructor() {}

  static getInstance(): ThemeColorStore {
    if (ThemeColorStore.instance === null) {
      ThemeColorStore.instance = new ThemeColorStore()
    }
    return ThemeColorStore.instance
  }

  async getThemeColor(urls: string[]): Promise<string> {
    const key = this.buildKey(urls)
    if (key.length === 0) {
      return ''
    }
    const cached = this.colorCache.get(key)
    if (cached !== undefined) {
      return cached
    }
    const pending = this.pendingTasks.get(key)
    if (pending !== undefined) {
      return pending
    }

    const task = this.extractThemeColor(urls)
      .then((color: string) => {
        this.colorCache.set(key, color)
        return color
      })
      .finally(() => {
        this.pendingTasks.delete(key)
      })
    this.pendingTasks.set(key, task)
    return task
  }

  private async extractThemeColor(urls: string[]): Promise<string> {
    const uri = await this.resolveImageUri(urls)
    if (uri.length === 0) {
      return ''
    }

    let source: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    try {
      source = image.createImageSource(uri)
      pixelMap = await source.createPixelMap({
        desiredSize: {
          width: SAMPLE_SIZE,
          height: SAMPLE_SIZE
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      })
      const pixels = new ArrayBuffer(SAMPLE_SIZE * SAMPLE_SIZE * 4)
      await pixelMap.readPixels({
        pixels: pixels,
        offset: 0,
        stride: SAMPLE_SIZE * 4,
        region: {
          size: {
            width: SAMPLE_SIZE,
            height: SAMPLE_SIZE
          },
          x: 0,
          y: 0
        }
      })
      return this.pickThemeColor(new Uint8Array(pixels))
    } catch (err) {
      logger.warn('Extract theme color failed: %{public}s', extractErrorMsg(err as Object))
      return ''
    } finally {
      if (pixelMap !== null) {
        try {
          await pixelMap.release()
        } catch (err) {
          logger.warn('Release theme pixelMap failed: %{public}s', extractErrorMsg(err as Object))
        }
      }
      if (source !== null) {
        try {
          source.release()
        } catch (err) {
          logger.warn('Release theme image source failed: %{public}s', extractErrorMsg(err as Object))
        }
      }
    }
  }

  private async resolveImageUri(urls: string[]): Promise<string> {
    const normalized: string[] = []
    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim()
      if (url.length === 0) {
        continue
      }
      if (url.startsWith('file://') || url.startsWith('/')) {
        return url
      }
      normalized.push(url)
    }
    if (normalized.length === 0) {
      return ''
    }
    return ImageCacheStore.getInstance().getCachedImageUri(normalized)
  }

  private pickThemeColor(pixels: Uint8Array): string {
    let weightedR = 0
    let weightedG = 0
    let weightedB = 0
    let totalWeight = 0
    let fallbackR = 0
    let fallbackG = 0
    let fallbackB = 0
    let fallbackCount = 0

    for (let i = 0; i + 3 < pixels.length; i += 4) {
      const b = pixels[i]
      const g = pixels[i + 1]
      const r = pixels[i + 2]
      const a = pixels[i + 3]
      if (a < 48) {
        continue
      }

      fallbackR += r
      fallbackG += g
      fallbackB += b
      fallbackCount++

      const max = Math.max(r, g, b)
      const min = Math.min(r, g, b)
      const saturation = max === 0 ? 0 : (max - min) / max
      const lightness = (max + min) / 510
      if (saturation < 0.08 || lightness < 0.12 || lightness > 0.90) {
        continue
      }

      const balance = 1 - Math.abs(lightness - 0.55)
      const weight = saturation * 0.72 + balance * 0.28
      weightedR += r * weight
      weightedG += g * weight
      weightedB += b * weight
      totalWeight += weight
    }

    if (totalWeight > 0) {
      return this.toHex(this.normalizeColor(new ThemeRgb(
        Math.round(weightedR / totalWeight),
        Math.round(weightedG / totalWeight),
        Math.round(weightedB / totalWeight)
      )))
    }
    if (fallbackCount > 0) {
      return this.toHex(this.normalizeColor(new ThemeRgb(
        Math.round(fallbackR / fallbackCount),
        Math.round(fallbackG / fallbackCount),
        Math.round(fallbackB / fallbackCount)
      )))
    }
    return ''
  }

  private normalizeColor(color: ThemeRgb): ThemeRgb {
    const max = Math.max(color.r, color.g, color.b)
    let r = color.r
    let g = color.g
    let b = color.b
    if (max < 96 && max > 0) {
      const scale = 96 / max
      r = Math.min(255, Math.round(r * scale))
      g = Math.min(255, Math.round(g * scale))
      b = Math.min(255, Math.round(b * scale))
    }
    return new ThemeRgb(r, g, b)
  }

  private toHex(color: ThemeRgb): string {
    return `#${this.hex(color.r)}${this.hex(color.g)}${this.hex(color.b)}`
  }

  private hex(value: number): string {
    const clamped = Math.max(0, Math.min(255, value))
    const text = clamped.toString(16).toUpperCase()
    return text.length === 1 ? `0${text}` : text
  }

  private buildKey(urls: string[]): string {
    const normalized: string[] = []
    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim()
      if (url.length > 0) {
        normalized.push(url)
      }
    }
    return normalized.join('|')
  }
}
