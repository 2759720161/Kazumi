import { util } from '@kit.ArkTS'

const KAZUMI_SCHEME = 'kazumi:'
const MAX_SHARE_TEXT_LENGTH = 512 * 1024

export class RuleShareCodec {
  static encodeRuleJson(jsonText: string): string {
    if (jsonText.trim().length === 0) {
      throw new Error('规则内容为空')
    }
    const encoder = util.TextEncoder.create('utf-8')
    const helper = new util.Base64Helper()
    return `kazumi://${helper.encodeToStringSync(encoder.encodeInto(jsonText))}`
  }

  static decodeRuleJson(shareText: string): string {
    let input = RuleShareCodec.unwrapShareText(shareText)
    if (input.length === 0) {
      throw new Error('剪贴板为空')
    }
    if (input.length > MAX_SHARE_TEXT_LENGTH) {
      throw new Error('规则分享内容过大')
    }

    const lower = input.toLowerCase()
    if (!lower.startsWith(KAZUMI_SCHEME)) {
      throw new Error('剪贴板中没有 Kazumi 规则分享链接')
    }
    input = input.substring(KAZUMI_SCHEME.length)
    if (input.startsWith('//')) {
      input = input.substring(2)
    }

    try {
      input = decodeURIComponent(input)
    } catch (_err) {
      throw new Error('规则分享链接包含无效编码')
    }
    let payload = input.replace(/\s/g, '').replace(/-/g, '+').replace(/_/g, '/')
    if (payload.length === 0) {
      throw new Error('规则分享链接内容为空')
    }
    if (payload.length % 4 === 1 || !/^[A-Za-z0-9+/]*={0,2}$/.test(payload)) {
      throw new Error('规则分享链接不是有效 Base64')
    }
    while (payload.length % 4 !== 0) {
      payload += '='
    }

    try {
      const helper = new util.Base64Helper()
      const decoded = helper.decodeSync(payload)
      return util.TextDecoder.create('utf-8').decodeToString(decoded)
    } catch (_err) {
      throw new Error('规则分享链接解码失败')
    }
  }

  private static unwrapShareText(value: string): string {
    let text = value.trim()
    const markdownStart = text.indexOf('](')
    if (text.startsWith('[') && markdownStart > 0 && text.endsWith(')')) {
      text = text.substring(markdownStart + 2, text.length - 1).trim()
    }
    if ((text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'")) ||
      (text.startsWith('<') && text.endsWith('>'))) {
      text = text.substring(1, text.length - 1).trim()
    }
    return text
  }
}
