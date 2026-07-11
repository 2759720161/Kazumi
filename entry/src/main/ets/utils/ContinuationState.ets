export const CONTINUATION_PAYLOAD_KEY: string = 'kazumiContinuationPayload'
export const CONTINUATION_RESTORE_PAYLOAD_KEY: string = 'continuationRestorePayload'
export const CONTINUATION_RESTORE_TOKEN_KEY: string = 'continuationRestoreToken'
export const CONTINUATION_SUPPORT_PAGE_STACK_KEY: string = 'ohos.extra.param.key.supportContinuePageStack'

export class ContinuationPayload {
  version: number = 1
  route: string = 'index'
  currentTab: number = 0
  paramsJson: string = ''
  positionMs: number = 0
  updatedAt: number = 0
}

export class ContinuationDetailParams {
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

export class ContinuationPlayerParams {
  videoUrl: string = ''
  episodeUrl: string = ''
  ruleSourceId: number = -1
  animeName: string = ''
  episodeName: string = ''
  animeId: string = ''
  animeCover: string = ''
  animeUrl: string = ''
  sourceId: number = -1
  episodesJson: string = ''
  currentEpisodeIndex: number = -1
  roadsJson: string = ''
  selectedRoadIndex: number = 0
  bangumiId: number = 0
  bangumiCover: string = ''
  coverFallback: string = ''
  animeDesc: string = ''
  sourceName: string = ''
  historyPositionMs: number = 0
}

export class ContinuationState {
  static markIndex(currentTab: number): void {
    const payload = new ContinuationPayload()
    payload.route = 'index'
    payload.currentTab = currentTab
    payload.updatedAt = Date.now()
    ContinuationState.storePayload(payload)
  }

  static markDetail(params: Object): void {
    const payload = ContinuationState.createPagePayload('detail', params)
    ContinuationState.storePayload(payload)
  }

  static markPlayer(params: Object, positionMs: number): void {
    const payload = ContinuationState.createPagePayload('player', params)
    payload.positionMs = Math.max(0, positionMs)
    ContinuationState.storePayload(payload)
  }

  static getPayloadJson(): string {
    return AppStorage.get<string>(CONTINUATION_PAYLOAD_KEY) ?? ''
  }

  static publishRestorePayload(payloadJson: string): void {
    if (payloadJson.length === 0) {
      return
    }
    AppStorage.setOrCreate(CONTINUATION_RESTORE_PAYLOAD_KEY, payloadJson)
    const token = AppStorage.get<number>(CONTINUATION_RESTORE_TOKEN_KEY) ?? 0
    AppStorage.setOrCreate(CONTINUATION_RESTORE_TOKEN_KEY, token + 1)
  }

  static parsePayload(payloadJson: string): ContinuationPayload | null {
    if (payloadJson.length === 0) {
      return null
    }
    try {
      const raw = JSON.parse(payloadJson) as Record<string, Object>
      const payload = new ContinuationPayload()
      if (raw['version'] !== undefined) payload.version = raw['version'] as number
      if (raw['route'] !== undefined) payload.route = raw['route'] as string
      if (raw['currentTab'] !== undefined) payload.currentTab = raw['currentTab'] as number
      if (raw['paramsJson'] !== undefined) payload.paramsJson = raw['paramsJson'] as string
      if (raw['positionMs'] !== undefined) payload.positionMs = raw['positionMs'] as number
      if (raw['updatedAt'] !== undefined) payload.updatedAt = raw['updatedAt'] as number
      return payload
    } catch (_) {
      return null
    }
  }

  static parseParams(paramsJson: string): Object {
    if (paramsJson.length === 0) {
      return new Object()
    }
    try {
      return JSON.parse(paramsJson) as Object
    } catch (_) {
      return new Object()
    }
  }

  static parsePlayerParams(paramsJson: string): ContinuationPlayerParams {
    const params = new ContinuationPlayerParams()
    if (paramsJson.length === 0) {
      return params
    }
    try {
      const raw = JSON.parse(paramsJson) as Record<string, Object>
      if (raw['videoUrl'] !== undefined) params.videoUrl = raw['videoUrl'] as string
      if (raw['episodeUrl'] !== undefined) params.episodeUrl = raw['episodeUrl'] as string
      if (raw['ruleSourceId'] !== undefined) params.ruleSourceId = raw['ruleSourceId'] as number
      if (raw['animeName'] !== undefined) params.animeName = raw['animeName'] as string
      if (raw['episodeName'] !== undefined) params.episodeName = raw['episodeName'] as string
      if (raw['animeId'] !== undefined) params.animeId = raw['animeId'] as string
      if (raw['animeCover'] !== undefined) params.animeCover = raw['animeCover'] as string
      if (raw['animeUrl'] !== undefined) params.animeUrl = raw['animeUrl'] as string
      if (raw['sourceId'] !== undefined) params.sourceId = raw['sourceId'] as number
      if (raw['episodesJson'] !== undefined) params.episodesJson = raw['episodesJson'] as string
      if (raw['currentEpisodeIndex'] !== undefined) params.currentEpisodeIndex = raw['currentEpisodeIndex'] as number
      if (raw['roadsJson'] !== undefined) params.roadsJson = raw['roadsJson'] as string
      if (raw['selectedRoadIndex'] !== undefined) params.selectedRoadIndex = raw['selectedRoadIndex'] as number
      if (raw['bangumiId'] !== undefined) params.bangumiId = raw['bangumiId'] as number
      if (raw['bangumiCover'] !== undefined) params.bangumiCover = raw['bangumiCover'] as string
      if (raw['coverFallback'] !== undefined) params.coverFallback = raw['coverFallback'] as string
      if (raw['animeDesc'] !== undefined) params.animeDesc = raw['animeDesc'] as string
      if (raw['sourceName'] !== undefined) params.sourceName = raw['sourceName'] as string
      if (raw['historyPositionMs'] !== undefined) params.historyPositionMs = raw['historyPositionMs'] as number
    } catch (_) {
      return params
    }
    return params
  }

  private static createPagePayload(route: string, params: Object): ContinuationPayload {
    const payload = new ContinuationPayload()
    payload.route = route
    payload.currentTab = AppStorage.get<number>('currentTab') ?? 0
    payload.paramsJson = JSON.stringify(params)
    payload.updatedAt = Date.now()
    return payload
  }

  private static storePayload(payload: ContinuationPayload): void {
    AppStorage.setOrCreate(CONTINUATION_PAYLOAD_KEY, JSON.stringify(payload))
  }
}
