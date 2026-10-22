import { http } from '@kit.NetworkKit'
import { ImageNetworkSettings } from '../../store/ImageNetworkSettings'
import { ImageNetworkConfig, ImageProxyConfig } from '../../models/ImageProxyConfig'
import { ProxyRequestOptions } from '../../network/ProxyRequestOptions'
import { BangumiConfig } from './BangumiConfig'
import { Logger, extractErrorMsg } from '../../utils/Logger'

const logger = new Logger('BangumiRequest')

export class BangumiRequest {
  private config: ImageNetworkConfig = ImageNetworkSettings.getConfig()
  private version: number = ImageNetworkSettings.getVersion()
  private activeRequest: http.HttpRequest | null = null
  private destroyed: boolean = false

  async request(url: string, options: http.HttpRequestOptions): Promise<http.HttpResponse> {
    this.assertCurrent()
    const useProxy = this.config.proxyEnabled && this.config.dataProxyEnabled
    const requestUrl = BangumiConfig.getDataRequestUrl(url, useProxy)
    const proxies: ImageProxyConfig[] = useProxy ? this.config.getProxyCandidates() : []
    if (useProxy && proxies.length === 0) {
      throw new Error('No Bangumi proxy selected')
    }
    const attempts = useProxy ? proxies.length : 1
    for (let attempt = 0; attempt < attempts; attempt++) {
      this.assertCurrent()
      const proxy = useProxy ? proxies[attempt] : null
      const request = http.createHttp()
      this.activeRequest = request
      try {
        ProxyRequestOptions.apply(options, proxy)
        logger.info('Bangumi data %{public}s: %{public}s', proxy === null ? 'direct' : proxy.type, requestUrl)
        const response = await request.request(requestUrl, options)
        this.assertCurrent()
        const status = response.responseCode as number
        if ((status === 407 || status >= 500) && attempt + 1 < attempts) {
          continue
        }
        if (status >= 200 && status < 300 && attempt > 0 && proxy !== null) {
          ImageNetworkSettings.activateAfterFailover(proxy.id, this.version)
        }
        return response
      } catch (err) {
        this.assertCurrent()
        const message = extractErrorMsg(err as Object)
        if (attempt + 1 >= attempts) {
          throw new Error(message)
        }
        logger.warn('Bangumi proxy attempt failed: %{public}s', message)
      } finally {
        if (this.activeRequest === request) {
          this.activeRequest = null
          request.destroy()
        }
      }
    }
    throw new Error('All Bangumi proxies failed')
  }

  destroy(): void {
    this.destroyed = true
    if (this.activeRequest !== null) {
      this.activeRequest.destroy()
      this.activeRequest = null
    }
  }

  private assertCurrent(): void {
    if (this.destroyed || this.version !== ImageNetworkSettings.getVersion()) {
      throw new Error('Bangumi network configuration changed')
    }
  }
}
