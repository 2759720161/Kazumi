export enum ImageProxyType {
  HTTP = 'HTTP',
  SOCKS5 = 'SOCKS5'
}

export class ImageProxyConfig {
  id: string = ''
  type: ImageProxyType = ImageProxyType.HTTP
  name: string = ''
  host: string = ''
  port: number = 8080
  username: string = ''
  password: string = ''
  exclusionList: string[] = []

  static copy(value: ImageProxyConfig): ImageProxyConfig {
    const result = new ImageProxyConfig()
    result.id = value.id
    // Configurations saved before protocol selection was added are HTTP proxies.
    result.type = value.type === ImageProxyType.SOCKS5 ? ImageProxyType.SOCKS5 : ImageProxyType.HTTP
    result.name = value.name
    result.host = value.host
    result.port = value.port
    result.username = value.username
    result.password = value.password
    result.exclusionList = value.exclusionList.slice()
    return result
  }

  static normalizeHost(value: string, type: ImageProxyType = ImageProxyType.HTTP): string {
    let host = value.trim().toLowerCase()
    if (type === ImageProxyType.HTTP && host.startsWith('http://')) {
      host = host.substring(7)
    } else if (type === ImageProxyType.SOCKS5 && host.startsWith('socks5://')) {
      host = host.substring(9)
    } else if (type === ImageProxyType.SOCKS5 && host.startsWith('socks5h://')) {
      host = host.substring(10)
    }
    if (host.endsWith('/')) {
      host = host.substring(0, host.length - 1)
    }
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1)
    }
    return host
  }

  static isValidHost(host: string): boolean {
    if (host.length === 0 || host.length > 253) {
      return false
    }
    if (host.includes(':')) {
      if (host.indexOf('::') !== host.lastIndexOf('::') ||
        (host.startsWith(':') && !host.startsWith('::')) ||
        (host.endsWith(':') && !host.endsWith('::'))) {
        return false
      }
      const segments = host.split(':').filter((segment: string) => segment.length > 0)
      return segments.every((segment: string) => /^[0-9a-f]{1,4}$/i.test(segment)) &&
        (host.includes('::') ? segments.length < 8 : segments.length === 8)
    }
    if (/^[0-9.]+$/.test(host)) {
      const parts = host.split('.')
      return parts.length === 4 && parts.every((part: string) =>
        /^\d{1,3}$/.test(part) && Number(part) <= 255)
    }
    return host.split('.').every((label: string) =>
      /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label))
  }

  static isValid(value: ImageProxyConfig): boolean {
    return (value.type === undefined || value.type === ImageProxyType.HTTP || value.type === ImageProxyType.SOCKS5) &&
      ImageProxyConfig.isValidHost(value.host) && Number.isInteger(value.port) &&
      value.port >= 1 && value.port <= 65535 &&
      !value.exclusionList.some((host: string) => host !== '*' && !ImageProxyConfig.isValidHost(host)) &&
      (!value.exclusionList.includes('*') || value.exclusionList.length === 1) &&
      ((value.username.length === 0 && value.password.length === 0) ||
        (value.username.length > 0 && value.password.length > 0))
  }

  static getDefaultPort(type: ImageProxyType): number {
    return type === ImageProxyType.SOCKS5 ? 1080 : 8080
  }

  static parseExclusions(value: string): string[] {
    const result: string[] = []
    const entries = value.replace(/，/g, ',').split(',')
    for (let i = 0; i < entries.length; i++) {
      const host = entries[i].trim().toLowerCase()
      if (host.length > 0 && result.indexOf(host) < 0) {
        result.push(host)
      }
    }
    return result
  }
}

export class ImageNetworkConfig {
  proxyEnabled: boolean = false
  imageProxyEnabled: boolean = true
  dataProxyEnabled: boolean = true
  autoFailover: boolean = true
  selectedProxyId: string = ''
  proxies: ImageProxyConfig[] = []

  static copy(value: ImageNetworkConfig): ImageNetworkConfig {
    const result = new ImageNetworkConfig()
    result.proxyEnabled = value.proxyEnabled
    result.imageProxyEnabled = typeof value.imageProxyEnabled === 'boolean' ?
      value.imageProxyEnabled : true
    result.dataProxyEnabled = typeof value.dataProxyEnabled === 'boolean' ?
      value.dataProxyEnabled : true
    result.autoFailover = value.autoFailover
    result.selectedProxyId = value.selectedProxyId
    result.proxies = value.proxies.map((proxy: ImageProxyConfig) => ImageProxyConfig.copy(proxy))
    return result
  }

  getProxyCandidates(): ImageProxyConfig[] {
    if (!this.proxyEnabled) {
      return []
    }
    const selectedIndex = this.proxies.findIndex((proxy: ImageProxyConfig) => proxy.id === this.selectedProxyId)
    if (selectedIndex < 0) {
      return []
    }
    const result: ImageProxyConfig[] = []
    const count = this.autoFailover ? this.proxies.length : 1
    for (let i = 0; i < count; i++) {
      result.push(ImageProxyConfig.copy(this.proxies[(selectedIndex + i) % this.proxies.length]))
    }
    return result
  }
}
