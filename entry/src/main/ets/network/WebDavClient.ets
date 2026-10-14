import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
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

export class WebDavBinaryResponse {
  statusCode: number = 0
  body: Uint8Array = new Uint8Array(0)
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
    const response = await this.request('PROPFIND', this.buildUrl('/'), '', headers)
    if (response.statusCode === 207 || response.statusCode === 200 || response.statusCode === 301 ||
      response.statusCode === 302) {
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

  async downloadTextAtPath(remotePath: string): Promise<string | null> {
    const response = await this.request('GET', this.buildUrl(remotePath))
    if (response.statusCode === 200) {
      return response.body
    }
    if (response.statusCode === 404) {
      return null
    }
    throw new Error('下载远端文件失败: HTTP ' + String(response.statusCode))
  }

  async uploadTextAtPath(remotePath: string, content: string): Promise<void> {
    const response = await this.request('PUT', this.buildUrl(remotePath), content, {
      'Content-Type': 'application/json; charset=utf-8'
    })
    if (response.statusCode === 200 || response.statusCode === 201 || response.statusCode === 204) {
      return
    }
    throw new Error('上传远端文件失败: HTTP ' + String(response.statusCode))
  }

  async downloadBytesAtPath(remotePath: string): Promise<Uint8Array | null> {
    const response = await this.requestBinary('GET', this.buildUrl(remotePath))
    if (response.statusCode === 200) {
      return response.body
    }
    if (response.statusCode === 404) {
      return null
    }
    throw new Error('下载远端二进制文件失败: HTTP ' + String(response.statusCode))
  }

  async uploadBytesAtPath(remotePath: string, content: Uint8Array): Promise<void> {
    const response = await this.requestBinary('PUT', this.buildUrl(remotePath), content, {
      'Content-Type': 'application/octet-stream'
    })
    if (response.statusCode === 200 || response.statusCode === 201 || response.statusCode === 204) {
      return
    }
    throw new Error('上传远端二进制文件失败: HTTP ' + String(response.statusCode))
  }

  async replaceTextAtPath(destinationPath: string, temporaryPath: string, content: string): Promise<void> {
    await this.deleteAtPath(temporaryPath)
    await this.uploadTextAtPath(temporaryPath, content)
    try {
      await this.commitUploadedFile(temporaryPath, destinationPath)
    } catch (moveErr) {
      const moveMessage = moveErr instanceof Error ? moveErr.message : String(moveErr)
      logger.warn('WebDAV MOVE commit failed, falling back to direct PUT: %{public}s', moveMessage)
      try {
        await this.uploadTextAtPath(destinationPath, content)
      } catch (uploadErr) {
        await this.deleteIgnoringFailure(temporaryPath)
        const uploadMessage = uploadErr instanceof Error ? uploadErr.message : String(uploadErr)
        throw new Error(moveMessage + '; 直接写入回退失败: ' + uploadMessage)
      }
      await this.deleteIgnoringFailure(temporaryPath)
    }
  }

  async replaceBytesAtPath(destinationPath: string, temporaryPath: string, content: Uint8Array): Promise<void> {
    await this.deleteAtPath(temporaryPath)
    await this.uploadBytesAtPath(temporaryPath, content)
    try {
      await this.commitUploadedFile(temporaryPath, destinationPath)
    } catch (moveErr) {
      const moveMessage = moveErr instanceof Error ? moveErr.message : String(moveErr)
      logger.warn('WebDAV MOVE commit failed, falling back to direct binary PUT: %{public}s', moveMessage)
      try {
        await this.uploadBytesAtPath(destinationPath, content)
      } catch (uploadErr) {
        await this.deleteIgnoringFailure(temporaryPath)
        const uploadMessage = uploadErr instanceof Error ? uploadErr.message : String(uploadErr)
        throw new Error(moveMessage + '; 直接写入回退失败: ' + uploadMessage)
      }
      await this.deleteIgnoringFailure(temporaryPath)
    }
  }

  async moveAtPath(sourcePath: string, destinationPath: string): Promise<void> {
    const response = await this.requestMove(sourcePath, destinationPath)
    if (response.statusCode === 200 || response.statusCode === 201 || response.statusCode === 204) {
      return
    }
    throw new Error('提交远端文件失败: HTTP ' + String(response.statusCode))
  }

  private async commitUploadedFile(sourcePath: string, destinationPath: string): Promise<void> {
    let response = await this.requestMove(sourcePath, destinationPath)
    if (this.isMoveSuccessful(response.statusCode)) {
      return
    }
    if (response.statusCode === 409 || response.statusCode === 412) {
      logger.warn('WebDAV overwrite MOVE returned %{public}d; retrying after deleting destination',
        response.statusCode)
      await this.deleteAtPath(destinationPath)
      response = await this.requestMove(sourcePath, destinationPath)
      if (this.isMoveSuccessful(response.statusCode)) {
        return
      }
    }
    throw new Error('提交远端文件失败: HTTP ' + String(response.statusCode))
  }

  private async requestMove(sourcePath: string, destinationPath: string): Promise<WebDavResponse> {
    return await this.request('MOVE', this.buildUrl(sourcePath), '', {
      'Destination': this.buildUrl(destinationPath),
      'Overwrite': 'T'
    })
  }

  private isMoveSuccessful(statusCode: number): boolean {
    return statusCode === 200 || statusCode === 201 || statusCode === 204
  }

  private async deleteIgnoringFailure(remotePath: string): Promise<void> {
    try {
      await this.deleteAtPath(remotePath)
    } catch (err) {
      logger.warn('WebDAV temporary file cleanup failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  async deleteAtPath(remotePath: string): Promise<void> {
    const response = await this.request('DELETE', this.buildUrl(remotePath))
    if (response.statusCode === 200 || response.statusCode === 202 || response.statusCode === 204 ||
      response.statusCode === 404) {
      return
    }
    throw new Error('删除远端文件失败: HTTP ' + String(response.statusCode))
  }

  async ensureRemoteDirAtPath(remotePath: string): Promise<void> {
    const dirUrl = this.buildUrl(remotePath)
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

  async listFileNamesAtPath(remotePath: string): Promise<string[]> {
    const headers: Record<string, string> = {}
    headers['Depth'] = '1'
    const response = await this.request('PROPFIND', this.buildUrl(remotePath), '', headers)
    if (response.statusCode === 404) {
      return []
    }
    if (response.statusCode !== 207 && response.statusCode !== 200) {
      throw new Error('读取远端目录失败: HTTP ' + String(response.statusCode))
    }
    return WebDavClient.extractChildNames(response.body, remotePath)
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

  private async requestBinary(method: string, url: string, body?: Uint8Array,
    headers?: Record<string, string>): Promise<WebDavBinaryResponse> {
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
      const requestBody = body !== undefined && body.length > 0 ? WebDavClient.toExactArrayBuffer(body) : undefined
      const options: http.HttpRequestOptions = {
        method: this.resolveRequestMethod(method),
        customMethod: method,
        header: requestHeaders,
        readTimeout: 20000,
        connectTimeout: 20000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        extraData: requestBody
      }
      const result = await httpRequest.request(url, options)
      const response = new WebDavBinaryResponse()
      response.statusCode = result.responseCode as number
      response.headers = result.header as Record<string, Object>
      if (result.result instanceof ArrayBuffer) {
        response.body = new Uint8Array(result.result as ArrayBuffer)
      }
      logger.debug('WebDAV binary %{public}s %{public}s -> %{public}d', method, url, response.statusCode)
      return response
    } catch (err) {
      const msg = WebDavClient.errorMessage(err)
      logger.warn('WebDAV binary request failed: %{public}s %{public}s %{public}s', method, url, msg)
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

  private static extractChildNames(body: string, remotePath: string): string[] {
    const names: string[] = []
    const normalizedDir = WebDavClient.normalizeDirPath(remotePath)
    const hrefRegex = /<[^>]*href[^>]*>([^<]+)<\/[^>]*href>/g
    let match: RegExpExecArray | null = hrefRegex.exec(body)
    while (match !== null) {
      const rawHref = WebDavClient.decodeHref(match[1])
      let path = rawHref
      const queryIndex = path.indexOf('?')
      if (queryIndex >= 0) {
        path = path.substring(0, queryIndex)
      }
      const normalizedHref = WebDavClient.normalizeDirPath(path)
      const relative = WebDavClient.relativeChildPath(normalizedHref, normalizedDir)
      if (relative.length > 0) {
        const slashIndex = relative.indexOf('/')
        const name = slashIndex >= 0 ? relative.substring(0, slashIndex) : relative
        if (name.length > 0 && names.indexOf(name) < 0) {
          names.push(name)
        }
      }
      match = hrefRegex.exec(body)
    }
    return names
  }

  private static relativeChildPath(normalizedHref: string, normalizedDir: string): string {
    if (normalizedHref === normalizedDir) {
      return ''
    }
    if (normalizedHref.startsWith(normalizedDir)) {
      return normalizedHref.substring(normalizedDir.length)
    }
    const markerIndex = normalizedHref.indexOf(normalizedDir)
    if (markerIndex >= 0) {
      return normalizedHref.substring(markerIndex + normalizedDir.length)
    }
    const dirWithoutLeadingSlash = normalizedDir.startsWith('/') ? normalizedDir.substring(1) : normalizedDir
    const fallbackMarker = '/' + dirWithoutLeadingSlash
    const fallbackIndex = normalizedHref.indexOf(fallbackMarker)
    if (fallbackIndex >= 0) {
      return normalizedHref.substring(fallbackIndex + fallbackMarker.length)
    }
    return ''
  }

  private static normalizeDirPath(path: string): string {
    let value = path.trim()
    const schemeIndex = value.indexOf('://')
    if (schemeIndex >= 0) {
      const pathStart = value.indexOf('/', schemeIndex + 3)
      value = pathStart >= 0 ? value.substring(pathStart) : '/'
    }
    if (!value.startsWith('/')) {
      value = '/' + value
    }
    try {
      value = decodeURIComponent(value)
    } catch (_err) {
      // Keep the raw href if the server returns a partially encoded path.
    }
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1)
    }
    return value + '/'
  }

  private static decodeHref(input: string): string {
    return input.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
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

  private static toExactArrayBuffer(input: Uint8Array): ArrayBuffer {
    const buffer = new ArrayBuffer(input.length)
    const output = new Uint8Array(buffer)
    for (let i = 0; i < input.length; i++) {
      output[i] = input[i]
    }
    return buffer
  }

  private static errorMessage(err: Object): string {
    if (err instanceof Error) {
      return err.message
    }
    const businessError = err as BusinessError
    const message = businessError.message ?? ''
    const code = businessError.code ?? 0
    if (message.length > 0 || code !== 0) {
      return 'code=' + String(code) + ' message=' + message
    }
    try {
      const serialized = JSON.stringify(err)
      return serialized.length > 0 ? serialized : String(err)
    } catch (_serializeErr) {
      return String(err)
    }
  }
}
