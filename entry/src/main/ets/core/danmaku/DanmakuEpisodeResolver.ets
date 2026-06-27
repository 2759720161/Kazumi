import { DandanApiClient } from './DandanApiClient'
import { StringSimilarity } from './StringSimilarity'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuEpisodeResolver')

const SIMILARITY_THRESHOLD = 0.5

export class DanmakuEpisodeInfo {
  episodeId: number = 0
  episodeTitle: string = ''
}

export class DanmakuEpisodeResolver {
  private apiClient: DandanApiClient = DandanApiClient.getInstance()
  private cachedBangumiId: number = 0
  private cachedAnimeName: string = ''
  private cachedEpisodes: DanmakuEpisodeInfo[] = []
  private cachedBgmBangumiId: number = 0
  private cachedBgmAnimeId: number = 0
  private cachedBgmEpisodes: DanmakuEpisodeInfo[] = []

  async resolveEpisodeId(animeName: string, episodeIndex: number, bgmBangumiId: number = 0): Promise<number> {
    if (animeName.length === 0) {
      return 0
    }

    if (bgmBangumiId > 0) {
      logger.info('弹幕路径: Bangumi ID主路径, bgmBangumiId=%{public}d', bgmBangumiId)
      const episodeNo = episodeIndex + 1
      const mainResult = await this.resolveEpisodeIdByBgmBangumiId(bgmBangumiId, episodeNo)
      if (mainResult > 0) {
        return mainResult
      }
      logger.warn('Bangumi ID主路径失败, 降级到标题搜索路径')
    } else {
      logger.info('弹幕路径: 标题搜索路径, bgmBangumiId缺失或无效')
    }

    if (this.cachedAnimeName === animeName && this.cachedEpisodes.length > 0) {
      if (episodeIndex >= 0 && episodeIndex < this.cachedEpisodes.length) {
        const ep = this.cachedEpisodes[episodeIndex]
        logger.info('使用缓存的episodeId=%{public}d, title=%{public}s', ep.episodeId, ep.episodeTitle)
        return ep.episodeId
      }
      return 0
    }

    try {
      const bangumiId = await this.searchBangumiId(animeName)
      if (bangumiId === 0) {
        logger.warn('未找到番剧: %{public}s', animeName)
        return 0
      }

      const episodes = await this.fetchEpisodes(bangumiId)
      if (episodes.length === 0) {
        logger.warn('番剧无分集信息: bangumiId=%{public}d', bangumiId)
        return 0
      }

      this.cachedBangumiId = bangumiId
      this.cachedAnimeName = animeName
      this.cachedEpisodes = episodes

      if (episodeIndex >= 0 && episodeIndex < episodes.length) {
        const ep = episodes[episodeIndex]
        logger.info('episode匹配: index=%{public}d, title=%{public}s, episodeId=%{public}d',
          episodeIndex, ep.episodeTitle, ep.episodeId)
        return ep.episodeId
      }

      logger.warn('分集索引越界: episodeIndex=%{public}d, total=%{public}d',
        episodeIndex, episodes.length)
      return 0
    } catch (err) {
      logger.error('解析episodeId异常: %{public}s',
        err instanceof Error ? err.message : String(err))
      return 0
    }
  }

  private async resolveEpisodeIdByBgmBangumiId(bgmBangumiId: number, episodeNo: number): Promise<number> {
    try {
      if (this.cachedBgmBangumiId === bgmBangumiId && this.cachedBgmEpisodes.length > 0) {
        if (episodeNo >= 1 && episodeNo <= this.cachedBgmEpisodes.length) {
          const ep = this.cachedBgmEpisodes[episodeNo - 1]
          logger.info('Bangumi ID缓存命中: episodeNo=%{public}d, episodeId=%{public}d', episodeNo, ep.episodeId)
          return ep.episodeId
        }
        logger.warn('Bangumi ID缓存命中但episodeNo越界: episodeNo=%{public}d, total=%{public}d',
          episodeNo, this.cachedBgmEpisodes.length)
        return 0
      }

      const path = `/api/v2/bangumi/bgmtv/${bgmBangumiId}`
      logger.info('请求Bangumi ID映射: bgmBangumiId=%{public}d', bgmBangumiId)
      const result = await this.apiClient.get(path)
      if (!result.isSuccessful) {
        logger.warn('Bangumi ID映射请求失败: HTTP %{public}d', result.statusCode)
        return 0
      }

      const json = JSON.parse(result.body) as Record<string, Object>
      const bangumi = json['bangumi'] as Record<string, Object>
      if (bangumi === null || bangumi === undefined) {
        logger.warn('Bangumi ID映射响应无bangumi字段')
        return 0
      }

      const animeId = Number(bangumi['animeId'] ?? 0)
      if (animeId <= 0) {
        logger.warn('弹弹Play无对应记录: bgmBangumiId=%{public}d', bgmBangumiId)
        return 0
      }
      if (animeId >= 100000) {
        logger.warn('用户自建条目: animeId=%{public}d, 跳过', animeId)
        return 0
      }

      logger.info('Bangumi ID映射成功: bgmBangumiId=%{public}d -> animeId=%{public}d', bgmBangumiId, animeId)

      const episodes = await this.fetchEpisodes(animeId)
      if (episodes.length === 0) {
        logger.warn('番剧无分集信息: animeId=%{public}d', animeId)
        return 0
      }

      this.cachedBgmBangumiId = bgmBangumiId
      this.cachedBgmAnimeId = animeId
      this.cachedBgmEpisodes = episodes

      if (episodeNo >= 1 && episodeNo <= episodes.length) {
        const ep = episodes[episodeNo - 1]
        logger.info('Bangumi ID主路径成功: animeId=%{public}d, episodeNo=%{public}d, episodeId=%{public}d',
          animeId, episodeNo, ep.episodeId)
        return ep.episodeId
      }

      logger.warn('episodeNo越界: episodeNo=%{public}d, total=%{public}d', episodeNo, episodes.length)
      return 0
    } catch (err) {
      logger.error('Bangumi ID主路径异常: %{public}s',
        err instanceof Error ? err.message : String(err))
      return 0
    }
  }

  private async searchBangumiId(animeName: string): Promise<number> {
    const path = '/api/v2/search/anime'
    const queryParameters: Record<string, string> = {}
    queryParameters['keyword'] = animeName
    logger.info('搜索番剧: keyword=%{public}s', animeName)

    try {
      const result = await this.apiClient.get(path, queryParameters)
      if (!result.isSuccessful) {
        logger.warn('搜索番剧请求失败: HTTP %{public}d', result.statusCode)
        return 0
      }

      const json = JSON.parse(result.body) as Record<string, Object>
      const animes = json['animes'] as Object[]
      if (animes === null || animes === undefined || animes.length === 0) {
        return 0
      }

      logger.info('search返回%{public}d个anime', animes.length)

      let bestId: number = 0
      let bestSimilarity: number = 0
      let bestTitle: string = ''
      for (let i = 0; i < animes.length; i++) {
        const anime = animes[i] as Record<string, Object>
        const animeId = Number(anime['animeId'] ?? 0)
        const animeTitle = String(anime['animeTitle'] ?? '')

        if (animeId < 2) {
          continue
        }

        if (animeTitle === animeName) {
          logger.info('完全匹配: animeId=%{public}d, title=%{public}s', animeId, animeTitle)
          return animeId
        }

        const similarity = StringSimilarity.calculateNormalizedSimilarity(animeTitle, animeName)
        if (similarity > bestSimilarity) {
          bestSimilarity = similarity
          bestId = animeId
          bestTitle = animeTitle
        }
      }

      if (bestId > 0 && bestSimilarity >= SIMILARITY_THRESHOLD) {
        logger.info('最佳匹配: title=%{public}s, animeId=%{public}d, similarity=%{public}s',
          bestTitle, bestId, bestSimilarity.toFixed(3))
        return bestId
      }
      if (bestId > 0) {
        logger.warn('相似度过低: title=%{public}s, animeId=%{public}d, similarity=%{public}s < %{public}s',
          bestTitle, bestId, bestSimilarity.toFixed(3), SIMILARITY_THRESHOLD.toFixed(3))
      }
      return 0
    } catch (parseErr) {
      logger.error('搜索结果解析失败: %{public}s',
        parseErr instanceof Error ? parseErr.message : String(parseErr))
      return 0
    }
  }

  private async fetchEpisodes(bangumiId: number): Promise<DanmakuEpisodeInfo[]> {
    const path = `/api/v2/bangumi/${bangumiId}`
    logger.info('获取分集列表: bangumiId=%{public}d', bangumiId)

    try {
      const result = await this.apiClient.get(path)
      if (!result.isSuccessful) {
        logger.warn('获取分集列表请求失败: HTTP %{public}d', result.statusCode)
        return []
      }

      const json = JSON.parse(result.body) as Record<string, Object>
      const bangumi = json['bangumi'] as Record<string, Object>
      if (bangumi === null || bangumi === undefined) {
        return []
      }

      const episodeList = bangumi['episodes'] as Object[]
      if (episodeList === null || episodeList === undefined) {
        return []
      }

      const episodes: DanmakuEpisodeInfo[] = []
      for (let i = 0; i < episodeList.length; i++) {
        const ep = episodeList[i] as Record<string, Object>
        const info = new DanmakuEpisodeInfo()
        info.episodeId = Number(ep['episodeId'] ?? 0)
        info.episodeTitle = String(ep['episodeTitle'] ?? '')
        if (info.episodeId > 0) {
          episodes.push(info)
        }
      }

      logger.info('获取到%{public}d个分集', episodes.length)
      return episodes
    } catch (parseErr) {
      logger.error('分集列表解析失败: %{public}s',
        parseErr instanceof Error ? parseErr.message : String(parseErr))
      return []
    }
  }

  reset(): void {
    this.cachedBangumiId = 0
    this.cachedAnimeName = ''
    this.cachedEpisodes = []
    this.cachedBgmBangumiId = 0
    this.cachedBgmAnimeId = 0
    this.cachedBgmEpisodes = []
  }
}
