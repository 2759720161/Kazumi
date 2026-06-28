import { RecommendCardModel } from '../models/RecommendCardModel'

class RecommendDetailParams {
  animeName: string = ''
  animeCover: string = ''
  animeCoverFallback: string = ''
  animeBangumiCover: string = ''
  animeDesc: string = ''
  animeOriginalName: string = ''
  animeAirDate: string = ''
  animeRatingScore: number = 0
  animeRank: number = 0
  animeTags: string = ''
  animeVotes: number = 0
  animeVotesCount: string = ''
  animeAirWeekday: number = 0
  animeEps: number = 0
  animeUrl: string = ''
  sourceName: string = ''
  sourceId: number = -1
  bangumiId: number = -1
}

export function buildRecommendDetailParams(item: RecommendCardModel): RecommendDetailParams {
  const params = new RecommendDetailParams()
  params.animeName = item.title
  params.animeCover = item.cover
  params.animeCoverFallback = item.coverFallback
  params.animeBangumiCover = item.bangumiCover
  params.animeDesc = item.summary
  params.animeOriginalName = item.originalTitle
  params.animeAirDate = item.date
  params.animeRatingScore = item.score
  params.animeRank = item.rank
  params.animeTags = JSON.stringify(item.tags)
  params.animeVotes = item.votes
  params.animeVotesCount = JSON.stringify(item.votesCount)
  params.animeAirWeekday = item.airWeekday
  params.animeEps = item.eps
  params.animeUrl = item.url
  params.sourceName = item.sourceName
  params.sourceId = item.sourceId
  params.bangumiId = item.bangumiId
  return params
}
