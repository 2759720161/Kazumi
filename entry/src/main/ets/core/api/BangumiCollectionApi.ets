import { http } from '@kit.NetworkKit'
import { BangumiRequest } from './BangumiRequest'
import { BangumiConfig } from './BangumiConfig'
import { BangumiSyncProtocol } from '../../models/BangumiSync'
import { CollectedBangumi } from '../../models/CollectedBangumi'
import { APP_VERSION } from '../../constants/AppVersion'

export type BangumiSyncProgress = (message: string, current: number, total: number) => void

export class BangumiCollectionApi {
  private token: string

  constructor(token: string) {
    this.token = token.trim()
  }

  async getUsername(): Promise<string> {
    const data = await this.request('/v0/me')
    if (typeof data['username'] !== 'string' || (data['username'] as string).length === 0) {
      throw new Error('Bangumi 用户信息无效')
    }
    return data['username'] as string
  }

  async getCollections(username: string, progress?: BangumiSyncProgress): Promise<CollectedBangumi[]> {
    const items: CollectedBangumi[] = []
    for (let type = 1; type <= 5; type++) {
      let offset = 0
      while (true) {
        const data = await this.request('/v0/users/' + encodeURIComponent(username) +
          '/collections?subject_type=2&type=' + type + '&limit=100&offset=' + offset)
        if (!Array.isArray(data['data']) || typeof data['total'] !== 'number') {
          throw new Error('Bangumi 收藏列表无效，已停止同步')
        }
        const page = data['data'] as Record<string, Object>[]
        const total = data['total'] as number
        if (!Number.isInteger(total) || total < 0 || (page.length === 0 && offset < total)) {
          throw new Error('Bangumi 收藏列表不完整，已停止同步')
        }
        for (let i = 0; i < page.length; i++) items.push(this.parseCollection(page[i]))
        offset += page.length
        progress?.('正在拉取 Bangumi 收藏（第 ' + type + '/5 类）', offset, total)
        if (offset >= total) break
        await this.pause()
      }
      await this.pause()
    }
    return items
  }

  async updateCollection(id: number, localType: number): Promise<void> {
    const payload: Record<string, Object> = {}
    payload['type'] = BangumiSyncProtocol.toRemoteType(localType)
    try {
      await this.request('/v0/users/-/collections/' + id, http.RequestMethod.POST, JSON.stringify(payload))
    } finally {
      await this.pause()
    }
  }

  private parseCollection(data: Record<string, Object>): CollectedBangumi {
    if (data === null || typeof data['subject_id'] !== 'number' ||
      !Number.isInteger(data['subject_id'] as number) || (data['subject_id'] as number) <= 0 ||
      typeof data['type'] !== 'number' || typeof data['subject'] !== 'object' || data['subject'] === null) {
      throw new Error('Bangumi 收藏条目无效，已停止同步')
    }
    const subject = data['subject'] as Record<string, Object>
    const item = new CollectedBangumi()
    item.bangumiId = data['subject_id'] as number
    item.animeId = 'bangumi:subject:' + item.bangumiId
    const nameCn = typeof subject['name_cn'] === 'string' ? subject['name_cn'] as string : ''
    item.animeName = nameCn.length > 0 ? nameCn :
      (typeof subject['name'] === 'string' ? subject['name'] as string : String(item.bangumiId))
    item.animeDesc = typeof subject['summary'] === 'string' ? subject['summary'] as string : ''
    if (subject['images'] !== null && typeof subject['images'] === 'object') {
      const images = subject['images'] as Record<string, Object>
      const image = typeof images['large'] === 'string' ? images['large'] as string :
        (typeof images['common'] === 'string' ? images['common'] as string : '')
      item.bangumiCover = BangumiConfig.normalizeImageUrl(image)
      item.animeCover = item.bangumiCover
    }
    item.collectType = BangumiSyncProtocol.toLocalType(data['type'] as number)
    const updatedAt = typeof data['updated_at'] === 'string' ? Date.parse(data['updated_at'] as string) : 0
    item.createdAt = Number.isFinite(updatedAt) && updatedAt > 0 ? updatedAt : Date.now()
    return item
  }

  private async request(path: string, method: http.RequestMethod = http.RequestMethod.GET,
    body: string = ''): Promise<Record<string, Object>> {
    if (this.token.length === 0) throw new Error('请先配置 Bangumi Access Token')
    const request = new BangumiRequest()
    try {
      // Authenticated traffic always targets the official API; the existing data proxy still applies.
      const options: http.HttpRequestOptions = {
        method: method,
        header: {
          'Authorization': 'Bearer ' + this.token,
          'User-Agent': 'FanPlayer/' + APP_VERSION + ' (HarmonyOS)',
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      }
      if (body.length > 0) options.extraData = body
      const response = await request.request('https://api.bgm.tv' + path, options)
      const status = response.responseCode as number
      if (status === 401) throw new Error('Bangumi Token 未授权或已过期，请重新配置')
      if (status === 403) throw new Error('Bangumi 拒绝访问，请检查 Token 权限')
      if (status === 429) throw new Error('Bangumi 请求过于频繁，请稍后重试')
      if (status < 200 || status >= 300) throw new Error('Bangumi 请求失败（HTTP ' + status + '）')
      if (status === 204 || String(response.result).length === 0) return {}
      return JSON.parse(response.result as string) as Record<string, Object>
    } finally {
      request.destroy()
    }
  }

  private async pause(): Promise<void> {
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 250))
  }
}
