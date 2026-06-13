import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { FileStore } from './FileStore';
import { Logger, extractErrorMsg } from '../utils/Logger';

const logger = new Logger('ImageCacheStore');

export class ImageCacheStore {
  private static instance: ImageCacheStore | null = null;
  private readonly cacheDirName: string = 'image_cache';
  private readonly failedUrls: Map<string, number> = new Map();
  private readonly failureCooldownMs: number = 5 * 60 * 1000;

  private constructor() {}

  static getInstance(): ImageCacheStore {
    if (ImageCacheStore.instance === null) {
      ImageCacheStore.instance = new ImageCacheStore();
    }
    return ImageCacheStore.instance;
  }

  async getCachedImageUri(urls: string[]): Promise<string> {
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
          if (stat.size > 100) {
            return fileUri.getUriFromPath(path);
          }
          logger.warn('Invalid cache file (size=%{public}d), deleting: %{public}s',
            stat.size, this.shorten(url));
          fs.unlinkSync(path);
        }

        const data = await this.downloadImage(url);
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

  private async downloadImage(url: string): Promise<ArrayBuffer> {
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
