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
    const urls = useProxy ? [requestUrl] : BangumiConfig.getDirectDataCandidates(requestUrl)
    const attempts = useProxy ? proxies.length : urls.length
    for (let attempt = 0; attempt < attempts; attempt++) {
      this.assertCurrent()
      const proxy = useProxy ? proxies[attempt] : null
      const currentUrl = useProxy ? requestUrl : urls[attempt]
      const request = http.createHttp()
      this.activeRequest = request
      try {
        const useSystemProxy = !useProxy && BangumiConfig.isOfficialDataUrl(currentUrl)
        if (!useProxy && attempt > 0) {
          BangumiRequest.removeMirrorSignature(options)
        }
        ProxyRequestOptions.apply(options, proxy, useSystemProxy)
        logger.info('Bangumi data %{public}s: %{public}s',
          proxy !== null ? proxy.type : useSystemProxy ? 'system' : 'direct', currentUrl)
        const response = await request.request(currentUrl, options)
        this.assertCurrent()
        const status = response.responseCode as number
        const emptyBody = response.result === '' || response.result === null || response.result === undefined
        if (attempt + 1 < attempts && (useProxy ? status === 407 || status >= 500 :
          status < 200 || status >= 300 || emptyBody)) {
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
        logger.warn('Bangumi request failed, trying next address or proxy: %{public}s', message)
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

  private static removeMirrorSignature(options: http.HttpRequestOptions): void {
    if (options.header === undefined || options.header === null) {
      return
    }
    const source = options.header as Record<string, Object>
    const headers: Record<string, Object> = {}
    const keys = Object.keys(source)
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].toLowerCase()
      if (key !== 'x-appid' && key !== 'x-timestamp' && key !== 'x-signature') {
        headers[keys[i]] = source[keys[i]]
      }
    }
    options.header = headers
  }
}
