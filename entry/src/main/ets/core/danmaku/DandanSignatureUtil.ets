import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DandanSignatureUtil')

export class DandanSignatureUtil {
  static async generateSignature(appId: string, appSecret: string, timestamp: number, path: string): Promise<string> {
    const data = appId + String(timestamp) + path + appSecret

    const md = cryptoFramework.createMd('SHA256')
    const charCodes: number[] = []
    for (let i = 0; i < data.length; i++) {
      charCodes.push(data.charCodeAt(i))
    }
    const inputData: cryptoFramework.DataBlob = {
      data: new Uint8Array(charCodes)
    }
    await md.update(inputData)
    const digestResult = await md.digest()

    const base64Helper = new util.Base64Helper()
    const encoded = base64Helper.encodeToStringSync(digestResult.data)

    return encoded
  }

  static extractPath(url: string): string {
    try {
      let pathPart = url

      const schemeIndex = pathPart.indexOf('://')
      if (schemeIndex >= 0) {
        pathPart = pathPart.substring(schemeIndex + 3)
      }

      const slashIndex = pathPart.indexOf('/')
      if (slashIndex >= 0) {
        pathPart = pathPart.substring(slashIndex)
      } else {
        return '/'
      }

      const queryIndex = pathPart.indexOf('?')
      if (queryIndex >= 0) {
        pathPart = pathPart.substring(0, queryIndex)
      }

      const fragmentIndex = pathPart.indexOf('#')
      if (fragmentIndex >= 0) {
        pathPart = pathPart.substring(0, fragmentIndex)
      }

      return pathPart.length > 0 ? pathPart : '/'
    } catch (_err) {
      return '/'
    }
  }
}
