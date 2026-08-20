import { router } from '@kit.ArkUI'

export class DetailNavigationParams {
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
  sharedCoverId: string = ''
  transitionCover: string = ''
  autoOpenSourceSheet: boolean = false
}

export function navigateToDetail(params: DetailNavigationParams): void {
  router.pushUrl({
    url: 'pages/detail/DetailPage',
    params: params
  })
}
