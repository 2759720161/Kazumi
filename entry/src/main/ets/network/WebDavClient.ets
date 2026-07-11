import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../utils/Logger'

const logger = new Logger('WebDavClient')

export class WebDavConfig {
  enabled: boolean = false
  serverUrl: string = ''
  username: string = ''
  password: string = ''
  remoteDir: string = '/FanPlayer/'
  autoSync: boolean = false
}

export class WebDavResponse {
  statusCode: number = 0
  body: string = ''
  headers: Record<string, Object> = {}
}

export class WebDavClient {
  private config: WebDavConfig

  constructor(config: WebDavConfig) {
    this.config = config
  }

  async testConnection(): Promise<boolean> {
    const headers: Record<string, string> = {}
    headers['Depth'] = '0'
    const response = await this.request('PROPFIND', this.buildUrl(this.config.remoteDir), '', headers)
    if (response.statusCode === 207 || response.statusCode === 200 || response.statusCode === 301 ||
      response.statusCode === 302) {
      return true
    }
    if (response.statusCode === 404) {
      await this.ensureRemoteDir()
      return true
    }
    return false
  }

  async ensureRemoteDir(): Promise<void> {
    const dirUrl = this.buildUrl(this.config.remoteDir)
    const headers: Record<string, string> = {}
    headers['Depth'] = '0'
    const propfind = await this.request('PROPFIND', dirUrl, '', headers)
    if (propfind.statusCode === 207 || propfind.statusCode === 200) {
      return
    }
    const mkcol = await this.request('MKCOL', dirUrl)
    if (mkcol.statusCode === 201 || mkcol.statusCode === 405 || mkcol.statusCode === 301 ||
      mkcol.statusCode === 302) {
      return
    }
    throw new Error('创建远端目录失败: HTTP ' + String(mkcol.statusCode))
  }

  async downloadText(fileName: string): Promise<string | null> {
    const response = await this.request('GET', this.buildFileUrl(fileName))
    if (response.statusCode === 200) {
      return response.body
    }
    if (response.statusCode === 404) {
      return null
    }
    throw new Error('下载远端文件失败: HTTP ' + String(response.statusCode))
  }

  async uploadText(fileName: string, content: string): Promise<void> {
    await this.ensureRemoteDir()
    const response = await this.request('PUT', this.buildFileUrl(fileName), content, {
      'Content-Type': 'application/json; charset=utf-8'
    })
    if (response.statusCode === 200 || response.statusCode === 201 || response.statusCode === 204) {
      return
    }
    throw new Error('上传远端文件失败: HTTP ' + String(response.statusCode))
  }

  private async request(method: string, url: string, body: string = '',
    headers?: Record<string, string>): Promise<WebDavResponse> {
    const httpRequest = http.createHttp()
    const requestHeaders: Record<string, string> = {}
    if (headers !== undefined) {
      const keys = Object.keys(headers)
      for (let i = 0; i < keys.length; i++) {
        requestHeaders[keys[i]] = headers[keys[i]]
      }
    }
    requestHeaders['Authorization'] = this.buildAuthorization()
    requestHeaders['Accept'] = '*/*'

    try {
      const options: http.HttpRequestOptions = {
        method: this.resolveRequestMethod(method),
        customMethod: method,
        header: requestHeaders,
        readTimeout: 20000,
        connectTimeout: 20000,
        expectDataType: http.HttpDataType.STRING,
        extraData: body.length > 0 ? body : undefined
      }
      const result = await httpRequest.request(url, options)
      const response = new WebDavResponse()
      response.statusCode = result.responseCode as number
      response.headers = result.header as Record<string, Object>
      if (typeof result.result === 'string') {
        response.body = result.result
      } else {
        response.body = JSON.stringify(result.result)
      }
      logger.debug('WebDAV %{public}s %{public}s -> %{public}d', method, url, response.statusCode)
      return response
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('WebDAV request failed: %{public}s %{public}s %{public}s', method, url, msg)
      throw new Error(msg)
    } finally {
      httpRequest.destroy()
    }
  }

  private resolveRequestMethod(method: string): http.RequestMethod {
    if (method === 'PUT') {
      return http.RequestMethod.PUT
    }
    if (method === 'DELETE') {
      return http.RequestMethod.DELETE
    }
    if (method === 'POST') {
      return http.RequestMethod.POST
    }
    return http.RequestMethod.GET
  }

  private buildAuthorization(): string {
    const raw = this.config.username + ':' + this.config.password
    const base64Helper = new util.Base64Helper()
    return 'Basic ' + base64Helper.encodeToStringSync(WebDavClient.encodeUtf8(raw))
  }

  private buildFileUrl(fileName: string): string {
    return this.buildUrl(this.config.remoteDir + fileName)
  }

  private buildUrl(path: string): string {
    let base = this.config.serverUrl.trim()
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1)
    }
    let normalizedPath = path.trim()
    if (!normalizedPath.startsWith('/')) {
      normalizedPath = '/' + normalizedPath
    }
    return base + WebDavClient.encodePath(normalizedPath)
  }

  private static encodePath(path: string): string {
    const parts = path.split('/')
    const encoded: string[] = []
    for (let i = 0; i < parts.length; i++) {
      encoded.push(encodeURIComponent(parts[i]))
    }
    return encoded.join('/')
  }

  private static encodeUtf8(input: string): Uint8Array {
    const bytes: number[] = []
    for (let i = 0; i < input.length; i++) {
      let code = input.charCodeAt(i)
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < input.length) {
        const next = input.charCodeAt(i + 1)
        if (next >= 0xDC00 && next <= 0xDFFF) {
          code = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00)
          i++
        }
      }
      if (code <= 0x7F) {
        bytes.push(code)
      } else if (code <= 0x7FF) {
        bytes.push(0xC0 | (code >> 6))
        bytes.push(0x80 | (code & 0x3F))
      } else if (code <= 0xFFFF) {
        bytes.push(0xE0 | (code >> 12))
        bytes.push(0x80 | ((code >> 6) & 0x3F))
        bytes.push(0x80 | (code & 0x3F))
      } else {
        bytes.push(0xF0 | (code >> 18))
        bytes.push(0x80 | ((code >> 12) & 0x3F))
        bytes.push(0x80 | ((code >> 6) & 0x3F))
        bytes.push(0x80 | (code & 0x3F))
      }
    }
    return new Uint8Array(bytes)
  }
}
