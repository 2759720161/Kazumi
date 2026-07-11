import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { BangumiConfig } from './BangumiConfig'

export class BangumiMirrorSignature {
  static hasCredentials(): boolean {
    return BangumiConfig.BANGUMI_MIRROR_APP_ID.length > 0 && BangumiConfig.BANGUMI_MIRROR_APP_KEY.length > 0
  }

  static isProtectedSearchUrl(url: string): boolean {
    return url.startsWith(BangumiConfig.KAZUMI_BANGUMI_PROXY_BASE) &&
      BangumiMirrorSignature.extractPath(url) === '/v0/search/subjects'
  }

  static async buildSearchHeaders(url: string, body: string): Promise<Record<string, string>> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'KazumiOHOS/1.0 (HarmonyOS)'
    }

    if (!BangumiMirrorSignature.isProtectedSearchUrl(url) || !BangumiMirrorSignature.hasCredentials()) {
      return headers
    }

    const method = 'POST'
    const path = BangumiMirrorSignature.extractPath(url)
    const timestamp = Math.floor(Date.now() / 1000)
    const signature = await BangumiMirrorSignature.generateSearchSignature(method, path, body, timestamp)
    headers['X-AppId'] = BangumiConfig.BANGUMI_MIRROR_APP_ID
    headers['X-Timestamp'] = String(timestamp)
    headers['X-Signature'] = signature
    return headers
  }

  private static async generateSearchSignature(method: string, path: string, body: string, timestamp: number): Promise<string> {
    const bodyDigest = await BangumiMirrorSignature.sha256Hex(body)
    const data = BangumiConfig.BANGUMI_MIRROR_APP_ID + String(timestamp) + method + path +
      bodyDigest + BangumiConfig.BANGUMI_MIRROR_APP_KEY
    const digest = await BangumiMirrorSignature.sha256Bytes(data)
    const base64Helper = new util.Base64Helper()
    return base64Helper.encodeToStringSync(digest)
  }

  private static async sha256Hex(input: string): Promise<string> {
    const digest = await BangumiMirrorSignature.sha256Bytes(input)
    const parts: string[] = []
    for (let i = 0; i < digest.length; i++) {
      parts.push(digest[i].toString(16).padStart(2, '0'))
    }
    return parts.join('')
  }

  private static async sha256Bytes(input: string): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA256')
    await md.update({ data: BangumiMirrorSignature.encodeUtf8(input) })
    const result = await md.digest()
    return result.data
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

  private static extractPath(url: string): string {
    try {
      let value = url
      const schemeIndex = value.indexOf('://')
      if (schemeIndex >= 0) {
        value = value.substring(schemeIndex + 3)
      }
      const slashIndex = value.indexOf('/')
      if (slashIndex < 0) {
        return '/'
      }
      value = value.substring(slashIndex)
      const queryIndex = value.indexOf('?')
      if (queryIndex >= 0) {
        value = value.substring(0, queryIndex)
      }
      const fragmentIndex = value.indexOf('#')
      if (fragmentIndex >= 0) {
        value = value.substring(0, fragmentIndex)
      }
      return value.length > 0 ? value : '/'
    } catch (_err) {
      return '/'
    }
  }
}
