import { connection, http } from '@kit.NetworkKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ImageProxyConfig, ImageProxyType } from '../models/ImageProxyConfig'

export const UNSUPPORTED_SOCKS5_PROXY: string = 'SOCKS5 requires HarmonyOS API 26.0.0'

export class ProxyRequestOptions {
  static apply(options: http.HttpRequestOptions, proxy: ImageProxyConfig | null,
    useSystemProxy: boolean = false): void {
    options.usingProxy = useSystemProxy
    options.usingSocks5Proxy = undefined
    if (proxy === null) {
      return
    }
    if (proxy.type === ImageProxyType.SOCKS5) {
      if (!deviceInfo.apiAvailable('26.0.0')) {
        throw new Error(UNSUPPORTED_SOCKS5_PROXY)
      }
      const socksProxy: connection.Socks5Proxy = {
        host: proxy.host,
        port: proxy.port,
        exclusionList: proxy.exclusionList,
        dnsStrategy: connection.Socks5DnsStrategy.PROXY_MODE
      }
      if (proxy.username.length > 0) {
        socksProxy.username = proxy.username
        socksProxy.password = proxy.password
      }
      options.usingSocks5Proxy = socksProxy
    } else {
      const httpProxy: connection.HttpProxy = {
        host: proxy.host,
        port: proxy.port,
        exclusionList: proxy.exclusionList
      }
      if (proxy.username.length > 0) {
        httpProxy.username = proxy.username
        httpProxy.password = proxy.password
      }
      options.usingProxy = httpProxy
    }
  }
}
