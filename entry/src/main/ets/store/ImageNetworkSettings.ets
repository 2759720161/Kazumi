import { ImageNetworkConfig, ImageProxyConfig } from '../models/ImageProxyConfig'
import { PreferencesStore } from './PreferencesStore'
import { Logger, extractErrorMsg } from '../utils/Logger'
import { deviceInfo } from '@kit.BasicServicesKit'

export const IMAGE_NETWORK_VERSION_KEY: string = 'imageNetworkVersion'
export const IMAGE_ACTIVE_PROXY_KEY: string = 'imageActiveProxyId'
const PREFS_KEY: string = 'imageNetworkConfig'
const logger = new Logger('ImageNetworkSettings')

export class ImageNetworkSettings {
  private static config: ImageNetworkConfig = new ImageNetworkConfig()
  private static version: number = 0
  private static saveQueue: Promise<void> = Promise.resolve()

  static async init(): Promise<void> {
    const raw = await PreferencesStore.getInstance().getString(PREFS_KEY)
    if (raw.length > 0) {
      try {
        const value = JSON.parse(raw) as ImageNetworkConfig
        const config = new ImageNetworkConfig()
        config.autoFailover = value.autoFailover !== false
        if (Array.isArray(value.proxies)) {
          for (let i = 0; i < value.proxies.length; i++) {
            const proxy = value.proxies[i]
            if (proxy !== null && typeof proxy.id === 'string' && proxy.id.length > 0 && typeof proxy.name === 'string' &&
              typeof proxy.host === 'string' && typeof proxy.port === 'number' &&
              typeof proxy.username === 'string' && typeof proxy.password === 'string' &&
              Array.isArray(proxy.exclusionList) &&
              proxy.exclusionList.every((host: string) => typeof host === 'string') &&
              ImageProxyConfig.isValid(proxy) &&
              !config.proxies.some((saved: ImageProxyConfig) => saved.id === proxy.id)) {
              config.proxies.push(ImageProxyConfig.copy(proxy))
            }
          }
        }
        config.selectedProxyId = typeof value.selectedProxyId === 'string' ? value.selectedProxyId : ''
        if (!config.proxies.some((proxy: ImageProxyConfig) => proxy.id === config.selectedProxyId)) {
          config.selectedProxyId = config.proxies.length > 0 ? config.proxies[0].id : ''
        }
        config.proxyEnabled = value.proxyEnabled === true && config.proxies.length > 0
        // Versions without scope flags applied the proxy to both images and metadata.
        config.imageProxyEnabled = typeof value.imageProxyEnabled === 'boolean' ?
          value.imageProxyEnabled : true
        config.dataProxyEnabled = typeof value.dataProxyEnabled === 'boolean' ?
          value.dataProxyEnabled : true
        ImageNetworkSettings.config = config
      } catch (_) {
        logger.warn('Invalid saved image network configuration; using image relay mode')
      }
    }
    ImageNetworkSettings.notifyChanged()
  }

  static getConfig(): ImageNetworkConfig {
    return ImageNetworkConfig.copy(ImageNetworkSettings.config)
  }

  static isProxyEnabled(): boolean {
    return ImageNetworkSettings.config.proxyEnabled
  }

  static isImageProxyEnabled(): boolean {
    return ImageNetworkSettings.config.proxyEnabled && ImageNetworkSettings.config.imageProxyEnabled
  }

  static isDataProxyEnabled(): boolean {
    return ImageNetworkSettings.config.proxyEnabled && ImageNetworkSettings.config.dataProxyEnabled
  }

  static async setImageProxyEnabled(enabled: boolean): Promise<void> {
    if (enabled === ImageNetworkSettings.config.imageProxyEnabled) {
      return
    }
    const config = ImageNetworkSettings.getConfig()
    config.imageProxyEnabled = enabled
    await ImageNetworkSettings.commit(config)
    logger.info('Image proxy scope enabled=%{public}s', String(enabled))
  }

  static async setDataProxyEnabled(enabled: boolean): Promise<void> {
    if (enabled === ImageNetworkSettings.config.dataProxyEnabled) {
      return
    }
    const config = ImageNetworkSettings.getConfig()
    config.dataProxyEnabled = enabled
    await ImageNetworkSettings.commit(config)
    logger.info('Bangumi data proxy scope enabled=%{public}s', String(enabled))
  }

  static isSocks5Supported(): boolean {
    try {
      return deviceInfo.apiAvailable('26.0.0')
    } catch (_) {
      return false
    }
  }

  static getVersion(): number {
    return ImageNetworkSettings.version
  }

  static async setProxyEnabled(enabled: boolean): Promise<boolean> {
    if (enabled && ImageNetworkSettings.config.proxies.length === 0) {
      return false
    }
    if (enabled === ImageNetworkSettings.config.proxyEnabled) {
      return true
    }
    const config = ImageNetworkSettings.getConfig()
    config.proxyEnabled = enabled
    await ImageNetworkSettings.commit(config)
    logger.info('Image proxy enabled=%{public}s selected=%{public}s',
      String(config.proxyEnabled), config.selectedProxyId)
    return true
  }

  static async setAutoFailover(enabled: boolean): Promise<void> {
    if (enabled === ImageNetworkSettings.config.autoFailover) {
      return
    }
    const config = ImageNetworkSettings.getConfig()
    config.autoFailover = enabled
    await ImageNetworkSettings.commit(config)
    logger.info('Image proxy autoFailover=%{public}s', String(config.autoFailover))
  }

  static async saveProxy(proxy: ImageProxyConfig): Promise<void> {
    if (proxy.id.length === 0 || !ImageProxyConfig.isValid(proxy)) {
      throw new Error('Invalid image proxy configuration')
    }
    const config = ImageNetworkSettings.getConfig()
    const index = config.proxies.findIndex((saved: ImageProxyConfig) => saved.id === proxy.id)
    if (index >= 0) {
      config.proxies[index] = ImageProxyConfig.copy(proxy)
    } else {
      config.proxies.push(ImageProxyConfig.copy(proxy))
    }
    if (config.selectedProxyId.length === 0) {
      config.selectedProxyId = proxy.id
    }
    await ImageNetworkSettings.commit(config)
  }

  static async selectProxy(id: string): Promise<void> {
    const config = ImageNetworkSettings.getConfig()
    if (!config.proxies.some((proxy: ImageProxyConfig) => proxy.id === id)) {
      return
    }
    config.selectedProxyId = id
    await ImageNetworkSettings.commit(config)
  }

  static async deleteProxy(id: string): Promise<void> {
    const config = ImageNetworkSettings.getConfig()
    config.proxies = config.proxies.filter((proxy: ImageProxyConfig) => proxy.id !== id)
    if (config.selectedProxyId === id) {
      config.selectedProxyId = config.proxies.length > 0 ? config.proxies[0].id : ''
    }
    if (config.proxies.length === 0) {
      config.proxyEnabled = false
    }
    await ImageNetworkSettings.commit(config)
  }

  // A successful failover changes the selected server without invalidating
  // downloads already using the same configuration. User edits do invalidate them.
  static activateAfterFailover(id: string, expectedVersion: number): void {
    if (expectedVersion !== ImageNetworkSettings.version || !ImageNetworkSettings.config.proxyEnabled ||
      ImageNetworkSettings.config.selectedProxyId === id ||
      !ImageNetworkSettings.config.proxies.some((proxy: ImageProxyConfig) => proxy.id === id)) {
      return
    }
    const config = ImageNetworkSettings.getConfig()
    config.selectedProxyId = id
    ImageNetworkSettings.config = config
    AppStorage.setOrCreate<string>(IMAGE_ACTIVE_PROXY_KEY, id)
    ImageNetworkSettings.persist().catch(() => {
      logger.warn('Could not persist the proxy selected after image failover')
    })
  }

  private static notifyChanged(): void {
    ImageNetworkSettings.version++
    AppStorage.setOrCreate<number>(IMAGE_NETWORK_VERSION_KEY, ImageNetworkSettings.version)
    AppStorage.setOrCreate<string>(IMAGE_ACTIVE_PROXY_KEY, ImageNetworkSettings.config.selectedProxyId)
  }

  private static async commit(config: ImageNetworkConfig): Promise<void> {
    const previous = ImageNetworkSettings.getConfig()
    ImageNetworkSettings.config = config
    ImageNetworkSettings.notifyChanged()
    const version = ImageNetworkSettings.version
    try {
      await ImageNetworkSettings.persist()
    } catch (err) {
      if (ImageNetworkSettings.version === version) {
        ImageNetworkSettings.config = previous
        ImageNetworkSettings.notifyChanged()
      }
      throw new Error(extractErrorMsg(err as Object))
    }
  }

  private static persist(): Promise<void> {
    const raw = JSON.stringify(ImageNetworkSettings.config)
    ImageNetworkSettings.saveQueue = ImageNetworkSettings.saveQueue.catch(() => {}).then(async () => {
      await PreferencesStore.getInstance().setStringOrThrow(PREFS_KEY, raw)
    })
    return ImageNetworkSettings.saveQueue
  }
}
