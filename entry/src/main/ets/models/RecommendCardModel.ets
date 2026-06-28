import { AnimeItem } from './AnimeItem'

export class RecommendCardModel {
  id: number = -1
  title: string = ''
  originalTitle: string = ''
  cover: string = ''
  coverLarge: string = ''
  backdrop: string = ''
  summary: string = ''
  score: number = 0
  rank: number = 0
  votes: number = 0
  date: string = ''
  year: string = ''
  tags: string[] = []
  eps: number = 0

  bangumiId: number = -1
  sourceId: number = -1
  sourceName: string = ''
  url: string = ''
  coverFallback: string = ''
  coverCommon: string = ''
  coverMedium: string = ''
  bangumiCover: string = ''
  aliases: string[] = []
  airWeekday: number = 0
  votesCount: number[] = []

  static fromAnimeItem(item: AnimeItem): RecommendCardModel {
    const model = new RecommendCardModel()
    model.id = item.bangumiId
    model.title = item.name
    model.originalTitle = item.originalName
    model.cover = item.getGridCover()
    model.coverLarge = item.coverLarge
    model.backdrop = item.coverLarge.length > 0 ? item.coverLarge : item.bangumiCover
    model.summary = item.desc
    model.score = item.ratingScore
    model.rank = item.rank
    model.votes = item.votes
    model.date = item.airDate
    model.year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : ''
    model.tags = [...item.tags]
    model.eps = item.eps
    model.bangumiId = item.bangumiId
    model.sourceId = item.sourceId
    model.sourceName = item.sourceName
    model.url = item.url
    model.coverFallback = item.coverFallback
    model.coverCommon = item.coverCommon
    model.coverMedium = item.coverMedium
    model.bangumiCover = item.bangumiCover
    model.aliases = [...item.aliases]
    model.airWeekday = item.airWeekday
    model.votesCount = [...item.votesCount]
    return model
  }

  getGridCover(): string {
    if (this.coverCommon.length > 0) return this.coverCommon
    if (this.coverMedium.length > 0) return this.coverMedium
    if (this.bangumiCover.length > 0) return this.bangumiCover
    if (this.cover.length > 0) return this.cover
    return this.coverFallback
  }

  getHeroBackdrop(): string {
    if (this.backdrop.length > 0) return this.backdrop
    if (this.coverLarge.length > 0) return this.coverLarge
    return this.bangumiCover
  }

  getScoreText(): string {
    if (this.score <= 0) return ''
    return this.score.toFixed(1)
  }

  getRankText(): string {
    if (this.rank <= 0) return ''
    return '#' + this.rank.toString()
  }

  getMetaText(): string {
    const parts: string[] = []
    if (this.year.length > 0) {
      parts.push(this.year)
    }
    if (this.eps > 0) {
      parts.push(this.eps.toString() + '集')
    }
    return parts.join(' \u00B7 ')
  }

  getTagText(): string {
    return this.tags.join(' / ')
  }
}
