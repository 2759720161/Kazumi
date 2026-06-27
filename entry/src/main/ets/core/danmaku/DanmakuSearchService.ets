import { DandanApiClient } from './DandanApiClient'
import { DanmakuEpisodeInfo } from './DanmakuEpisodeResolver'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuSearchService')

export class DanmakuSearchResult {
  animeId: number = 0
  animeTitle: string = ''
  animeType: string = ''
}

export class DanmakuSearchService {
  private apiClient: DandanApiClient = DandanApiClient.getInstance()

  private static instance: DanmakuSearchService | null = null

  private constructor() {}

  static getInstance(): DanmakuSearchService {
    if (DanmakuSearchService.instance === null) {
      DanmakuSearchService.instance = new DanmakuSearchService()
    }
    return DanmakuSearchService.instance
  }

  async searchAnime(keyword: string): Promise<DanmakuSearchResult[]> {
    const trimmed: string = keyword.trim()
    if (trimmed.length === 0) {
      return []
    }

    try {
      const path: string = '/api/v2/search/anime'
      const queryParameters: Record<string, string> = {}
      queryParameters['keyword'] = trimmed
      logger.info('搜索番剧: keyword=%{public}s', trimmed)

      const result = await this.apiClient.get(path, queryParameters)
      if (!result.isSuccessful) {
        logger.warn('搜索番剧请求失败: HTTP %{public}d', result.statusCode)
        return []
      }

      const json: Record<string, Object> = JSON.parse(result.body) as Record<string, Object>
      const animes: Object[] = json['animes'] as Object[]
      if (animes === null || animes === undefined) {
        return []
      }

      const searchResults: DanmakuSearchResult[] = []
      for (let i = 0; i < animes.length; i++) {
        const anime: Record<string, Object> = animes[i] as Record<string, Object>
        const animeId: number = Number(anime['animeId'] ?? 0)
        if (animeId < 2 || animeId >= 100000) {
          continue
        }
        const item: DanmakuSearchResult = new DanmakuSearchResult()
        item.animeId = animeId
        item.animeTitle = String(anime['animeTitle'] ?? '')
        item.animeType = String(anime['animeType'] ?? '')
        searchResults.push(item)
      }

      logger.info('搜索返回%{public}d个有效结果', searchResults.length)
      return searchResults
    } catch (_err) {
      logger.warn('搜索番剧异常')
      return []
    }
  }

  async fetchEpisodes(animeId: number): Promise<DanmakuEpisodeInfo[]> {
    if (animeId <= 0) {
      return []
    }

    try {
      const path: string = `/api/v2/bangumi/${animeId}`
      logger.info('获取分集列表: animeId=%{public}d', animeId)

      const result = await this.apiClient.get(path)
      if (!result.isSuccessful) {
        logger.warn('获取分集列表请求失败: HTTP %{public}d', result.statusCode)
        return []
      }

      const json: Record<string, Object> = JSON.parse(result.body) as Record<string, Object>
      const bangumi: Record<string, Object> = json['bangumi'] as Record<string, Object>
      if (bangumi === null || bangumi === undefined) {
        return []
      }

      const episodeList: Object[] = bangumi['episodes'] as Object[]
      if (episodeList === null || episodeList === undefined) {
        return []
      }

      const episodes: DanmakuEpisodeInfo[] = []
      for (let i = 0; i < episodeList.length; i++) {
        const ep: Record<string, Object> = episodeList[i] as Record<string, Object>
        const info: DanmakuEpisodeInfo = new DanmakuEpisodeInfo()
        info.episodeId = Number(ep['episodeId'] ?? 0)
        info.episodeTitle = String(ep['episodeTitle'] ?? '')
        episodes.push(info)
      }

      logger.info('获取到%{public}d个分集', episodes.length)
      return episodes
    } catch (_err) {
      logger.warn('获取分集列表异常')
      return []
    }
  }
}