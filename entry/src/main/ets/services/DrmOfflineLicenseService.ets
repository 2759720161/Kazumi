import { drm } from '@kit.DrmKit'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../utils/Logger'

const logger = new Logger('DrmOfflineLicenseService')
const WIDEVINE_UUID = 'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed'
const PLAYREADY_UUID = '9a04f079-9840-4286-ab92-e65be0885f95'

export class DrmOfflineLicenseResult {
  pluginName: string = ''
  schemeUuid: string = ''
  mediaKeyIdBase64: string = ''
}

export class DrmOfflineLicenseService {
  getSupportedSchemes(): string[] {
    const result: string[] = []
    const systems = drm.getMediaKeySystems()
    for (let i = 0; i < systems.length; i++) result.push(this.normalizeUuid(systems[i].uuid))
    return result
  }

  async acquire(scheme: string, initData: Uint8Array, mimeType: string, licenseUrl: string,
    headers: Record<string, string>): Promise<DrmOfflineLicenseResult> {
    const uuid = this.resolveUuid(scheme)
    const systems = drm.getMediaKeySystems()
    let pluginName = ''
    for (let i = 0; i < systems.length; i++) {
      if (this.normalizeUuid(systems[i].uuid) === uuid) {
        pluginName = systems[i].name
        break
      }
    }
    if (pluginName.length === 0) {
      throw new Error('当前设备未安装 ' + this.schemeLabel(uuid) + ' DRM 插件')
    }
    const keySystem = drm.createMediaKeySystem(pluginName)
    try {
      if (keySystem.getCertificateStatus() !== drm.CertificateStatus.CERT_STATUS_PROVISIONED) {
        const provision = await keySystem.generateKeySystemRequest()
        const response = await this.postBinary(provision.defaultURL, provision.data, headers)
        await keySystem.processKeySystemResponse(response)
      }
      const session = keySystem.createMediaKeySession()
      try {
        const keyRequest = await session.generateMediaKeyRequest(mimeType, initData,
          drm.MediaKeyType.MEDIA_KEY_TYPE_OFFLINE)
        const endpoint = licenseUrl.length > 0 ? licenseUrl : keyRequest.defaultURL
        if (endpoint.length === 0) throw new Error('清单和下载请求均未提供 DRM 许可证地址')
        const response = await this.postBinary(endpoint, keyRequest.data, headers)
        const mediaKeyId = await session.processMediaKeyResponse(response)
        const result = new DrmOfflineLicenseResult()
        result.pluginName = pluginName
        result.schemeUuid = uuid
        result.mediaKeyIdBase64 = new util.Base64Helper().encodeToStringSync(mediaKeyId)
        logger.info('DRM离线许可证已持久化: scheme=%{public}s', this.schemeLabel(uuid))
        return result
      } finally {
        session.destroy()
      }
    } finally {
      keySystem.destroy()
    }
  }

  clear(pluginName: string, scheme: string, mediaKeyIdBase64: string): void {
    if (mediaKeyIdBase64.length === 0) return
    const uuid = this.resolveUuid(scheme)
    let resolvedPlugin = pluginName
    if (resolvedPlugin.length === 0) {
      const systems = drm.getMediaKeySystems()
      for (let i = 0; i < systems.length; i++) {
        if (this.normalizeUuid(systems[i].uuid) === uuid) {
          resolvedPlugin = systems[i].name
          break
        }
      }
    }
    if (resolvedPlugin.length === 0) throw new Error('无法找到待清理离线许可证的 DRM 插件')
    const keySystem = drm.createMediaKeySystem(resolvedPlugin)
    try {
      const mediaKeyId = new util.Base64Helper().decodeSync(mediaKeyIdBase64)
      keySystem.clearOfflineMediaKeys(mediaKeyId)
      logger.info('DRM离线许可证已清理: scheme=%{public}s', this.schemeLabel(uuid))
    } finally {
      keySystem.destroy()
    }
  }

  private async postBinary(url: string, payload: Uint8Array,
    headers: Record<string, string>): Promise<Uint8Array> {
    if (!url.startsWith('http://') && !url.startsWith('https://')) throw new Error('DRM 服务地址无效')
    const client = http.createHttp()
    try {
      const result = await client.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: payload.buffer,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
        maxLimit: 4 * 1024 * 1024
      })
      if (result.responseCode < 200 || result.responseCode >= 300) {
        throw new Error('DRM 许可证服务返回 HTTP ' + String(result.responseCode))
      }
      if (!(result.result instanceof ArrayBuffer)) throw new Error('DRM 许可证响应不是二进制数据')
      return new Uint8Array(result.result as ArrayBuffer)
    } finally {
      client.destroy()
    }
  }

  private resolveUuid(value: string): string {
    const normalized = this.normalizeUuid(value)
    if (normalized.indexOf('widevine') >= 0) return WIDEVINE_UUID
    if (normalized.indexOf('playready') >= 0) return PLAYREADY_UUID
    return normalized
  }

  private normalizeUuid(value: string): string {
    return value.toLowerCase().replace(/[{}]/g, '').replace(/^urn:uuid:/, '')
  }

  private schemeLabel(uuid: string): string {
    if (uuid === WIDEVINE_UUID) return 'Widevine'
    if (uuid === PLAYREADY_UUID) return 'PlayReady'
    return uuid
  }
}
