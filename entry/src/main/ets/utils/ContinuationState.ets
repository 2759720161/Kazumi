import { util } from '@kit.ArkTS'

export const CONTINUATION_PAYLOAD_KEY: string = 'kazumiContinuationPayload'
export const CONTINUATION_RESTORE_PAYLOAD_KEY: string = 'continuationRestorePayload'
export const CONTINUATION_RESTORE_TOKEN_KEY: string = 'continuationRestoreToken'
export const CONTINUATION_CURRENT_SECTION_KEY: string = 'continuationCurrentSection'
export const CONTINUATION_MAX_TRANSFER_BYTES: number = 80 * 1024

const CONTINUATION_PAYLOAD_PROTOCOL_VERSION: number = 2

export class ContinuationPayload {
  version: number = CONTINUATION_PAYLOAD_PROTOCOL_VERSION
  route: string = 'index'
  currentTab: number = 0
  currentSection: string = 'home'
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
  static markIndex(currentTab: number, currentSection: string = ''): void {
    if (currentSection.length > 0) {
      AppStorage.setOrCreate(CONTINUATION_CURRENT_SECTION_KEY, currentSection)
    }
    const payload = new ContinuationPayload()
    payload.route = 'index'
    payload.currentTab = currentTab
    payload.currentSection = ContinuationState.resolveCurrentSection(currentSection)
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

  static updatePlayerPosition(positionMs: number): void {
    const payloadJson = AppStorage.get<string>(CONTINUATION_PAYLOAD_KEY) ?? ''
    const payload = ContinuationState.parsePayload(payloadJson)
    if (payload === null || payload.route !== 'player') {
      return
    }
    payload.positionMs = Math.max(0, positionMs)
    payload.updatedAt = Date.now()
    AppStorage.setOrCreate(CONTINUATION_PAYLOAD_KEY, JSON.stringify(payload))
  }

  static getTransferPayloadJson(): string {
    const payloadJson = AppStorage.get<string>(CONTINUATION_PAYLOAD_KEY) ?? ''
    const payload = ContinuationState.parsePayload(payloadJson)
    if (payload === null) {
      return ''
    }
    return ContinuationState.fitPayloadForTransfer(payload)
  }

  static getPayloadSizeBytes(payloadJson: string): number {
    if (payloadJson.length === 0) {
      return 0
    }
    return util.TextEncoder.create('utf-8').encodeInto(payloadJson).byteLength
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
      if (raw['currentSection'] !== undefined) {
        payload.currentSection = raw['currentSection'] as string
      } else {
        // Protocol v1 transferred only the numeric tab index.
        payload.currentSection = ''
      }
      if (raw['paramsJson'] !== undefined) payload.paramsJson = raw['paramsJson'] as string
      if (raw['positionMs'] !== undefined) payload.positionMs = raw['positionMs'] as number
      if (raw['updatedAt'] !== undefined) payload.updatedAt = raw['updatedAt'] as number
      if (!ContinuationState.isSupportedRoute(payload.route)) {
        return null
      }
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
    payload.currentSection = ContinuationState.resolveCurrentSection('')
    payload.paramsJson = JSON.stringify(params)
    payload.updatedAt = Date.now()
    return payload
  }

  private static storePayload(payload: ContinuationPayload): void {
    let payloadJson = ContinuationState.fitPayloadForTransfer(payload)
    if (payloadJson.length === 0) {
      const fallback = new ContinuationPayload()
      fallback.route = 'index'
      fallback.currentTab = payload.currentTab
      fallback.currentSection = payload.currentSection
      fallback.updatedAt = Date.now()
      payloadJson = JSON.stringify(fallback)
    }
    AppStorage.setOrCreate(CONTINUATION_PAYLOAD_KEY, payloadJson)
  }

  private static resolveCurrentSection(currentSection: string): string {
    if (currentSection.length > 0) {
      return currentSection
    }
    return AppStorage.get<string>(CONTINUATION_CURRENT_SECTION_KEY) ?? 'home'
  }

  private static isSupportedRoute(route: string): boolean {
    return route === 'index' || route === 'detail' || route === 'player'
  }

  private static fitPayloadForTransfer(payload: ContinuationPayload): string {
    payload.version = CONTINUATION_PAYLOAD_PROTOCOL_VERSION
    let payloadJson = JSON.stringify(payload)
    if (ContinuationState.getPayloadSizeBytes(payloadJson) <= CONTINUATION_MAX_TRANSFER_BYTES) {
      return payloadJson
    }

    if (payload.route === 'player') {
      payloadJson = ContinuationState.compactPlayerPayload(payload)
    } else if (payload.route === 'detail') {
      payloadJson = ContinuationState.compactDetailPayload(payload)
    }
    if (ContinuationState.getPayloadSizeBytes(payloadJson) <= CONTINUATION_MAX_TRANSFER_BYTES) {
      return payloadJson
    }
    return ''
  }

  private static compactPlayerPayload(payload: ContinuationPayload): string {
    const params = ContinuationState.parsePlayerParams(payload.paramsJson)
    const originalEpisodesJson = params.episodesJson

    // roadsJson already contains the selected road's episodes, so this is normally duplicate data.
    params.episodesJson = ''
    payload.paramsJson = JSON.stringify(params)
    let payloadJson = JSON.stringify(payload)
    if (ContinuationState.getPayloadSizeBytes(payloadJson) <= CONTINUATION_MAX_TRANSFER_BYTES) {
      return payloadJson
    }

    const selectedRoadJson = ContinuationState.selectSingleRoad(params.roadsJson, params.selectedRoadIndex)
    if (selectedRoadJson.length > 0) {
      params.roadsJson = selectedRoadJson
      params.selectedRoadIndex = 0
      payload.paramsJson = JSON.stringify(params)
      payloadJson = JSON.stringify(payload)
      if (ContinuationState.getPayloadSizeBytes(payloadJson) <= CONTINUATION_MAX_TRANSFER_BYTES) {
        return payloadJson
      }
    }

    // Preserve a lightweight episode list when the full road graph is still too large.
    params.roadsJson = ''
    params.episodesJson = originalEpisodesJson
    params.selectedRoadIndex = 0
    payload.paramsJson = JSON.stringify(params)
    payloadJson = JSON.stringify(payload)
    if (ContinuationState.getPayloadSizeBytes(payloadJson) <= CONTINUATION_MAX_TRANSFER_BYTES) {
      return payloadJson
    }

    // The current media URL, episode identity and progress are the minimum viable continuation state.
    params.episodesJson = ''
    params.animeCover = ''
    params.bangumiCover = ''
    params.coverFallback = ''
    params.animeDesc = ''
    payload.paramsJson = JSON.stringify(params)
    return JSON.stringify(payload)
  }

  private static compactDetailPayload(payload: ContinuationPayload): string {
    try {
      const params = JSON.parse(payload.paramsJson) as Record<string, Object>
      params['animeDesc'] = ''
      params['animeTags'] = ''
      params['animeVotesCount'] = ''
      params['animeCover'] = ''
      params['animeCoverFallback'] = ''
      params['animeBangumiCover'] = ''
      payload.paramsJson = JSON.stringify(params)
    } catch (_) {
      payload.paramsJson = ''
    }
    return JSON.stringify(payload)
  }

  private static selectSingleRoad(roadsJson: string, selectedRoadIndex: number): string {
    if (roadsJson.length === 0) {
      return ''
    }
    try {
      const roads = JSON.parse(roadsJson) as Array<Object>
      if (selectedRoadIndex < 0 || selectedRoadIndex >= roads.length) {
        return ''
      }
      const selectedRoads: Array<Object> = []
      selectedRoads.push(roads[selectedRoadIndex])
      return JSON.stringify(selectedRoads)
    } catch (_) {
      return ''
    }
  }
}
