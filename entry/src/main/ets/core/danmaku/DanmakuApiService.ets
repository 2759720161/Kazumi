import { DandanApiClient } from './DandanApiClient'
import { DanmakuItem } from '../../models/DanmakuItem'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuApiService')

const DANMAKU_MAX_ITEMS = 5000

export class DanmakuApiResponse {
  items: DanmakuItem[] = []
  success: boolean = false
  errorMessage: string = ''
}

export class DanmakuApiService {
  private apiClient: DandanApiClient = DandanApiClient.getInstance()

  async fetchDanmaku(episodeId: number): Promise<DanmakuApiResponse> {
    const response = new DanmakuApiResponse()
    if (episodeId <= 0) {
      response.errorMessage = 'episodeId无效'
      return response
    }

    const path = `/api/v2/comment/${episodeId}`
    const queryParameters: Record<string, string> = {}
    queryParameters['withRelated'] = 'true'
    logger.info('请求弹幕: episodeId=%{public}d', episodeId)

    try {
      const result = await this.apiClient.get(path, queryParameters)
      if (!result.isSuccessful) {
        response.errorMessage = `弹幕API返回HTTP ${result.statusCode}`
        logger.warn('弹幕API请求失败: %{public}s', response.errorMessage)
        return response
      }

      const bodyStr = result.body
      if (bodyStr.length === 0) {
        response.success = true
        return response
      }

      const parsed = this.parseDanmakuResponse(bodyStr)
      response.items = parsed
      response.success = true
      logger.info('弹幕解析完成: %{public}d条', parsed.length)
      return response
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      response.errorMessage = `弹幕API请求异常: ${msg}`
      logger.error('弹幕API请求异常: %{public}s', msg)
      return response
    }
  }

  private parseDanmakuResponse(bodyStr: string): DanmakuItem[] {
    const items: DanmakuItem[] = []
    try {
      const json = JSON.parse(bodyStr) as Record<string, Object>
      const comments = json['comments'] as Object[]
      if (comments === null || comments === undefined) {
        return items
      }

      logger.info('comment返回%{public}d条', comments.length)

      const limit = Math.min(comments.length, DANMAKU_MAX_ITEMS)
      if (comments.length > DANMAKU_MAX_ITEMS) {
        logger.warn('弹幕数据量过大：截断至%{public}d条', DANMAKU_MAX_ITEMS)
      }

      for (let i = 0; i < limit; i++) {
        const comment = comments[i] as Record<string, Object>
        try {
          const parsed = this.parseComment(comment)
          if (parsed !== null) {
            items.push(parsed)
          }
        } catch (_itemErr) {
          logger.warn('弹幕数据格式异常：跳过第%{public}d条', i)
        }
      }
    } catch (parseErr) {
      logger.error('弹幕数据JSON解析失败: %{public}s',
        parseErr instanceof Error ? parseErr.message : String(parseErr))
    }

    items.sort((a: DanmakuItem, b: DanmakuItem) => a.timeMs - b.timeMs)
    logger.info('解析后%{public}d条items', items.length)
    return items
  }

  private parseComment(comment: Record<string, Object>): DanmakuItem | null {
    const messageValue = String(comment['m'] ?? '')
    if (messageValue.length === 0) {
      return null
    }

    const pValue = String(comment['p'] ?? '')
    if (pValue.length === 0) {
      return null
    }

    const parts = pValue.split(',')
    if (parts.length < 3) {
      return null
    }

    const timeSec = parseFloat(parts[0])
    if (isNaN(timeSec)) {
      return null
    }

    const typeValue = parseInt(parts[1], 10)
    if (isNaN(typeValue)) {
      return null
    }

    if (typeValue !== 1 && typeValue !== 4 && typeValue !== 5) {
      return null
    }

    const colorValue = parseInt(parts[2], 10)
    const color = this.normalizeColorFromInt(colorValue)

    const danmakuType = typeValue === 4 || typeValue === 5 ? typeValue : 0

    return new DanmakuItem(
      messageValue,
      Math.round(timeSec * 1000),
      color,
      25,
      danmakuType
    )
  }

  private normalizeColorFromInt(colorInt: number): string {
    if (isNaN(colorInt) || colorInt < 0 || colorInt > 0xFFFFFF) {
      return '#FFFFFF'
    }
    const hex = colorInt.toString(16).padStart(6, '0').toUpperCase()
    return `#${hex}`
  }
}
