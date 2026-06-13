import { Logger } from '../../utils/Logger'

const logger = new Logger('EpisodeNumberExtractor')

const SPECIAL_MARKERS: string[] = ['ova', 'oad', 'sp', 'special', 'movie', '剧场版']

export class EpisodeNumberExtractor {
  static extractEpisodeNumber(episodeTitle: string, fallbackIndex: number): number {
    if (episodeTitle.length === 0) {
      logger.info('集数提取: episodeTitle为空, 使用索引兜底: episodeNo=%{public}d', fallbackIndex)
      return fallbackIndex
    }

    const lowerTitle = episodeTitle.toLowerCase()
    for (let i = 0; i < SPECIAL_MARKERS.length; i++) {
      if (lowerTitle.indexOf(SPECIAL_MARKERS[i]) >= 0) {
        logger.info('集数提取: episodeTitle=%{public}s, 方法=特殊标记, episodeNo=0', episodeTitle)
        return 0
      }
    }

    const patterns: RegExp[] = [
      /第(\d+)[话集]/,
      /[Ee][Pp]\.?\s*(\d+)/,
      /[Ee]pisode\s*(\d+)/,
      /[Ee](\d+)/,
      /(\d+)/,
    ]
    const patternNames: string[] = ['中文格式', '英文EP格式', '英文Episode格式', '英文E格式', '纯数字格式']

    for (let i = 0; i < patterns.length; i++) {
      const match = episodeTitle.match(patterns[i])
      if (match !== null && match.length >= 2) {
        const num = parseInt(match[1], 10)
        if (!isNaN(num) && num > 0) {
          logger.info('集数提取: episodeTitle=%{public}s, 方法=正则提取: %{public}s, episodeNo=%{public}d',
            episodeTitle, patternNames[i], num)
          return num
        }
      }
    }

    logger.info('集数提取: episodeTitle=%{public}s, 方法=索引兜底, episodeNo=%{public}d',
      episodeTitle, fallbackIndex)
    return fallbackIndex
  }
}