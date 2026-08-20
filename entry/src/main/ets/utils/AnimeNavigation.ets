import { RecommendCardModel } from '../models/RecommendCardModel'
import { DetailNavigationParams } from './DetailNavigation'

export function buildRecommendDetailParams(item: RecommendCardModel, sharedCoverId: string = ''): DetailNavigationParams {
  const params = new DetailNavigationParams()
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
  params.sharedCoverId = sharedCoverId.length > 0 ? sharedCoverId : 'subject-cover-' + item.bangumiId.toString()
  params.transitionCover = item.getGridCover()
  return params
}
