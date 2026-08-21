import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { FileStore } from './FileStore';
import { Logger, extractErrorMsg } from '../utils/Logger';

const logger = new Logger('ImageCacheStore');
// Keep image bursts below the socket pressure that can trigger curl 55 on
// some HarmonyOS devices while still allowing the visible grid to fill quickly.
const MAX_CONCURRENT_IMAGE_DOWNLOADS = 3;
// Always leave one slot for visible/search images. Otherwise three slow home
// requests can make a newly opened page wait for their timeout before it gets
// its first cover.
const MAX_REGULAR_IMAGE_DOWNLOADS = 2;
const IMAGE_RETRY_DELAY_MS = 350;

export class ImageCacheStore {
  private static instance: ImageCacheStore | null = null;
  private readonly cacheDirName: string = 'image_cache';
  private readonly failedUrls: Map<string, number> = new Map();
  // Image failures are usually transient network errors. A long cooldown
  // leaves a card stuck on a placeholder after one interrupted response.
  private readonly failureCooldownMs: number = 15 * 1000;
  private readonly inFlightDownloads: Map<string, Promise<ArrayBuffer>> = new Map();
  private readonly downloadWaiters: Array<() => void> = [];
  private readonly priorityDownloadWaiters: Array<() => void> = [];
  private activeDownloadCount: number = 0;
  private activeRegularDownloadCount: number = 0;
  private activePriorityDownloadCount: number = 0;

  private constructor() {}

  static getInstance(): ImageCacheStore {
    if (ImageCacheStore.instance === null) {
      ImageCacheStore.instance = new ImageCacheStore();
    }
    return ImageCacheStore.instance;
  }

  async getCachedImageUri(urls: string[], priority: boolean = false): Promise<string> {
    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim();
      if (url.length === 0 || url.startsWith('file://')) {
        continue;
      }
      if (this.isFailedRecently(url)) {
        logger.info('Skip recently failed image: %{public}s', this.shorten(url));
        continue;
      }

      try {
        const path = this.getCachePath(url);
        if (fs.accessSync(path)) {
          const stat = fs.statSync(path);
          if (stat.size > 100 && this.isValidImageFile(path)) {
            return fileUri.getUriFromPath(path);
          }
          logger.warn('Invalid or truncated cache file (size=%{public}d), deleting: %{public}s',
            stat.size, this.shorten(url));
          fs.unlinkSync(path);
        }

        const data = await this.downloadImage(url, priority);
        this.writeBinary(path, data);
        return fileUri.getUriFromPath(path);
      } catch (err) {
        const msg = extractErrorMsg(err as Object);
        this.markFailed(url);
        logger.warn('Cache image failed: %{public}s, url=%{public}s', msg, this.shorten(url));
      }
    }
    return '';
  }

  /** Returns an existing cached file without starting a network request. */
  getExistingCachedImageUri(urls: string[]): string {
    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim();
      if (url.length === 0 || url.startsWith('file://') || this.isFailedRecently(url)) {
        continue;
      }
      try {
        const path = this.getCachePath(url);
        if (!fs.accessSync(path)) {
          continue;
        }
        const stat = fs.statSync(path);
        if (stat.size > 100 && this.isValidImageFile(path)) {
          return fileUri.getUriFromPath(path);
        }
        fs.unlinkSync(path);
      } catch (err) {
        logger.warn('Read cached image failed: %{public}s', extractErrorMsg(err as Object));
      }
    }
    return '';
  }

  private async downloadImage(url: string, priority: boolean): Promise<ArrayBuffer> {
    const inFlight = this.inFlightDownloads.get(url);
    if (inFlight !== undefined) {
      return await inFlight;
    }

    const task = this.downloadImageWithRetry(url, priority);
    this.inFlightDownloads.set(url, task);
    try {
      return await task;
    } finally {
      if (this.inFlightDownloads.get(url) === task) {
        this.inFlightDownloads.delete(url);
      }
    }
  }

  private async downloadImageWithRetry(url: string, priority: boolean): Promise<ArrayBuffer> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      await this.acquireDownloadSlot(priority);
      try {
        return await this.downloadImageOnce(url);
      } catch (err) {
        lastError = new Error(extractErrorMsg(err as Object));
        if (attempt < 2) {
          await new Promise<void>((resolve: () => void) => {
            setTimeout(resolve, IMAGE_RETRY_DELAY_MS * (attempt + 1));
          });
        }
      } finally {
        this.releaseDownloadSlot(priority);
      }
    }
    throw lastError === null ? new Error('Image download failed') : lastError;
  }

  private async acquireDownloadSlot(priority: boolean): Promise<void> {
    if (priority && this.activeDownloadCount < MAX_CONCURRENT_IMAGE_DOWNLOADS) {
      this.activeDownloadCount++;
      this.activePriorityDownloadCount++;
      return;
    }
    if (!priority && this.activeDownloadCount < MAX_CONCURRENT_IMAGE_DOWNLOADS &&
      this.activeRegularDownloadCount < MAX_REGULAR_IMAGE_DOWNLOADS) {
      this.activeDownloadCount++;
      this.activeRegularDownloadCount++;
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      if (priority) {
        this.priorityDownloadWaiters.push(resolve);
      } else {
        this.downloadWaiters.push(resolve);
      }
    });
    if (priority) {
      this.activePriorityDownloadCount++;
    } else {
      this.activeRegularDownloadCount++;
    }
  }

  private releaseDownloadSlot(priority: boolean): void {
    if (priority) {
      this.activePriorityDownloadCount = Math.max(0, this.activePriorityDownloadCount - 1);
    } else {
      this.activeRegularDownloadCount = Math.max(0, this.activeRegularDownloadCount - 1);
    }
    const next = this.priorityDownloadWaiters.length > 0
      ? this.priorityDownloadWaiters.shift()
      : this.downloadWaiters.shift();
    if (next !== undefined) {
      // Transfer the released slot directly to the next waiter. The resumed
      // waiter accounts for the slot before continuing its request.
      next();
      return;
    }
    this.activeDownloadCount = Math.max(0, this.activeDownloadCount - 1);
  }

  private async downloadImageOnce(url: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const isProxyUrl = url.includes('/img.php') || url.includes('/image.php') ||
        url.includes('/proxy?url') || url.includes('/pic?url');
      const isSlowCdn = url.includes('bgm.tv') || url.includes('bangumi') ||
        url.includes('imgdb.cn');
      let readTimeout = 15000;
      if (isProxyUrl) {
        readTimeout = 10000;
      } else if (isSlowCdn) {
        readTimeout = 20000;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36',
          'Referer': this.buildReferer(url),
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8'
        },
        readTimeout: readTimeout,
        connectTimeout: 12000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      const response = await request.request(url, options);
      const statusCode = response.responseCode as number;
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`HTTP ${statusCode}`);
      }
      const result = response.result;
      if (result === null || result === undefined) {
        throw new Error('Empty response body');
      }
      const data = result as ArrayBuffer;
      if (data.byteLength < 100) {
        throw new Error(`Image too small: ${data.byteLength} bytes`);
      }
      if (!this.isValidImageData(data)) {
        throw new Error(`Incomplete image data: ${data.byteLength} bytes`);
      }
      return data;
    } finally {
      request.destroy();
    }
  }

  private writeBinary(path: string, data: ArrayBuffer): void {
    const dirPath = path.substring(0, path.lastIndexOf('/'));
    if (!fs.accessSync(dirPath)) {
      fs.mkdirSync(dirPath, true);
    }
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * A timed-out HTTP request can still report status 200 and return a partial
   * ArrayBuffer. Check the container trailer before putting it in the cache.
   */
  private isValidImageFile(path: string): boolean {
    let file: fs.File | null = null;
    try {
      const stat = fs.statSync(path);
      if (stat.size <= 100) {
        return false;
      }
      const data = new ArrayBuffer(stat.size);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fs.readSync(file.fd, data);
      return this.isValidImageData(data);
    } catch (err) {
      return false;
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  private isValidImageData(data: ArrayBuffer): boolean {
    const bytes = new Uint8Array(data);
    if (bytes.length < 12) {
      return false;
    }

    // JPEG: SOI at the front and EOI near the end. Some image mirrors append
    // a small trailer after a complete JPEG; requiring EOI to be the final
    // two bytes incorrectly rejects those otherwise valid covers.
    if (bytes[0] === 0xFF && bytes[1] === 0xD8) {
      const searchStart = Math.max(2, bytes.length - 64);
      for (let i = searchStart; i <= bytes.length - 2; i++) {
        if (bytes[i] === 0xFF && bytes[i + 1] === 0xD9) {
          return true;
        }
      }
      return false;
    }

    // PNG: signature plus IEND near the end of the file.
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E &&
      bytes[3] === 0x47 && bytes[4] === 0x0D && bytes[5] === 0x0A &&
      bytes[6] === 0x1A && bytes[7] === 0x0A) {
      for (let i = Math.max(8, bytes.length - 32); i <= bytes.length - 4; i++) {
        if (bytes[i] === 0x49 && bytes[i + 1] === 0x45 &&
          bytes[i + 2] === 0x4E && bytes[i + 3] === 0x44) {
          return true;
        }
      }
      return false;
    }

    // WebP: RIFF container with WEBP form type. The RIFF length is allowed
    // to include padding, so only require the declared payload to be present.
    if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 &&
      bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 &&
      bytes[10] === 0x42 && bytes[11] === 0x50) {
      const declaredSize = bytes[4] + (bytes[5] << 8) + (bytes[6] << 16) + (bytes[7] << 24);
      return declaredSize <= bytes.length - 8;
    }

    // Keep compatibility with uncommon image formats returned by a rule
    // source. The known truncated formats above are the failure cases we can
    // identify without decoding the image on the UI thread.
    return true;
  }

  private getCachePath(url: string): string {
    const cacheDir = FileStore.getInstance().getCacheDir();
    return `${cacheDir}/${this.cacheDirName}/${this.hashUrl(url)}${this.getExtension(url)}`;
  }

  private hashUrl(url: string): string {
    let hash = 5381;
    for (let i = 0; i < url.length; i++) {
      hash = ((hash << 5) + hash + url.charCodeAt(i)) & 0x7fffffff;
    }
    return hash.toString(16);
  }

  private getExtension(url: string): string {
    const innerUrl = this.extractInnerUrl(url);
    const targetUrl = innerUrl.length > 0 ? innerUrl : url;
    const cleanUrl = targetUrl.split('?')[0].split('#')[0].toLowerCase();
    const extensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.svg'];
    for (let i = 0; i < extensions.length; i++) {
      if (cleanUrl.endsWith(extensions[i])) {
        return extensions[i];
      }
    }
    if (cleanUrl.includes('.jpg') || cleanUrl.includes('.jpeg')) {
      return '.jpg';
    }
    if (cleanUrl.includes('.png')) {
      return '.png';
    }
    if (cleanUrl.includes('.webp')) {
      return '.webp';
    }
    return '.jpg';
  }

  private extractInnerUrl(url: string): string {
    const proxyPatterns: string[] = [
      '/img.php?url=',
      '/image.php?url=',
      '/proxy?url=',
      '/pic?url='
    ];
    for (let i = 0; i < proxyPatterns.length; i++) {
      const idx = url.indexOf(proxyPatterns[i]);
      if (idx !== -1) {
        const rawUrl = url.substring(idx + proxyPatterns[i].length);
        if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          return decodeURIComponent(rawUrl.split('&')[0]);
        }
      }
    }
    return '';
  }

  private buildReferer(url: string): string {
    if (url.includes('doubanio.com')) {
      return 'https://movie.douban.com/';
    }
    if (url.includes('bgm.tv') || url.includes('bangumi')) {
      return 'https://bgm.tv/';
    }
    if (url.includes('imgdb.cn') || url.includes('imgdb')) {
      return 'https://www.imgdb.cn/';
    }


    const protocolEnd = url.indexOf('://');
    if (protocolEnd === -1) {
      return '';
    }
    const pathStart = url.indexOf('/', protocolEnd + 3);
    return pathStart === -1 ? `${url}/` : url.substring(0, pathStart + 1);
  }

  private shorten(url: string): string {
    return url.length > 120 ? url.substring(0, 120) : url;
  }

  private isFailedRecently(url: string): boolean {
    const failedAt = this.failedUrls.get(url);
    if (failedAt === undefined) {
      return false;
    }
    if (Date.now() - failedAt > this.failureCooldownMs) {
      this.failedUrls.delete(url);
      return false;
    }
    return true;
  }

  private markFailed(url: string): void {
    this.failedUrls.set(url, Date.now());
    if (this.failedUrls.size <= 300) {
      return;
    }
    const keys: string[] = [];
    this.failedUrls.forEach((value: number, key: string) => {
      keys.push(key);
    });
    if (keys.length > 0) {
      this.failedUrls.delete(keys[0]);
    }
  }
}
