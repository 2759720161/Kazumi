import { describe, it, expect } from '@ohos/hypium'
import {
  KazumiHistorySyncEvent,
  KazumiHistorySyncSnapshot,
  KazumiHistorySyncState
} from '../main/ets/services/KazumiHistorySyncProtocol'
import { HistoryEpisodeProgress, HistoryRecord } from '../main/ets/models/HistoryRecord'

function bangumiItem(id: number): Record<string, Object> {
  const item: Record<string, Object> = {}
  item['id'] = id
  item['type'] = 2
  item['name'] = 'Test Anime'
  item['nameCn'] = '测试番剧'
  return item
}

function upsertEvent(op: string, seq: number, updatedAt: number): KazumiHistorySyncEvent {
  const event = new KazumiHistorySyncEvent()
  event.eventId = 'device:' + String(seq)
  event.deviceId = 'device'
  event.seq = seq
  event.op = op
  event.updatedAt = updatedAt
  event.entityKey = 'gugu3400602::online'
  event.bangumiItem = bangumiItem(400602)
  event.adapterName = 'gugu3'
  event.episode = 2
  event.road = 1
  event.progressMs = 123456
  event.lastSrc = 'https://example.com/anime/400602'
  event.lastWatchEpisodeName = '第02集'
  event.entryKind = 'online'
  event.episodePageUrl = 'https://example.com/anime/400602/2'
  event.carriesWatchState = op === 'upsertWatchState'
  return event
}

export default function historySyncProtocolTest() {
  describe('historySyncProtocol', () => {
    it('mergesSeparatedProgressAndWatchState', 0, () => {
      const state = KazumiHistorySyncState.fromSnapshot(KazumiHistorySyncSnapshot.empty())
      const progress = upsertEvent('upsertProgress', 1, 1000)
      progress.lastSrc = ''
      progress.lastWatchEpisodeName = ''
      const watchState = upsertEvent('upsertWatchState', 2, 1000)
      state.applyAll([watchState, progress])
      const snapshot = state.toSnapshot()
      expect(snapshot.histories.length).assertEqual(1)
      expect(snapshot.histories[0].lastSrc).assertEqual('https://example.com/anime/400602')
      expect(snapshot.histories[0].episodePageUrl).assertEqual('https://example.com/anime/400602/2')
      expect(snapshot.histories[0].progresses.get(2)?.progressMs).assertEqual(123456)
    })

    it('canonicalizesLegacyOnlineVersionKeys', 0, () => {
      const history: Record<string, Object> = {}
      history['bangumiItem'] = bangumiItem(400602)
      history['lastWatchEpisode'] = 1
      history['adapterName'] = 'gugu3'
      history['lastWatchTime'] = 1000
      history['lastSrc'] = 'https://example.com/anime/400602'
      history['lastWatchEpisodeName'] = '第01集'
      history['progresses'] = {}
      const versions: Record<string, Object> = {}
      versions['gugu3400602'] = '0000000000001000|legacy'
      const json: Record<string, Object> = {}
      json['histories'] = [history]
      json['itemVersions'] = versions
      json['progressVersions'] = {}
      json['deletedVersions'] = {}
      const snapshot = KazumiHistorySyncSnapshot.fromJSON(json)
      expect(snapshot.itemVersions.get('gugu3400602::online')).assertEqual('0000000000001000|legacy')
    })

    it('doesNotResurrectStateOlderThanClearAll', 0, () => {
      const state = KazumiHistorySyncState.fromSnapshot(KazumiHistorySyncSnapshot.empty())
      const progress = upsertEvent('upsertProgress', 1, 1000)
      const watchState = upsertEvent('upsertWatchState', 2, 1000)
      const clear = new KazumiHistorySyncEvent()
      clear.eventId = 'device:3'
      clear.deviceId = 'device'
      clear.seq = 3
      clear.op = 'clearAll'
      clear.updatedAt = 2000
      state.applyAll([clear, watchState, progress])
      expect(state.toSnapshot().histories.length).assertEqual(0)
    })

    it('doesNotReuseAnotherEpisodeProgressAfterClearAll', 0, () => {
      const state = KazumiHistorySyncState.fromSnapshot(KazumiHistorySyncSnapshot.empty())
      const oldProgress = upsertEvent('upsertProgress', 1, 1000)
      const clear = new KazumiHistorySyncEvent()
      clear.eventId = 'device:2'
      clear.deviceId = 'device'
      clear.seq = 2
      clear.op = 'clearAll'
      clear.updatedAt = 2000
      const newWatchState = upsertEvent('upsertWatchState', 3, 3000)
      newWatchState.episode = 8
      state.applyAll([oldProgress, clear, newWatchState])

      const snapshot = state.toSnapshot()
      expect(snapshot.histories.length).assertEqual(1)
      expect(snapshot.histories[0].lastWatchEpisode).assertEqual(8)
      expect(snapshot.histories[0].progresses.size).assertEqual(0)
    })

    it('rejectsMalformedSnapshotShapes', 0, () => {
      const malformedHistories = KazumiHistorySyncSnapshot.fromText('{"histories":{}}')
      const malformedVersions = KazumiHistorySyncSnapshot.fromText('{"histories":[],"itemVersions":[]}')
      const malformedVersionValue = KazumiHistorySyncSnapshot.fromText(
        '{"histories":[],"itemVersions":{"gugu3400602::online":1}}')
      const malformedProgressVersions = KazumiHistorySyncSnapshot.fromText(
        '{"histories":[],"progressVersions":{"gugu3400602::online":[]}}')
      const malformedProgress = KazumiHistorySyncSnapshot.fromText(
        '{"histories":[{"bangumiItem":{"id":400602,"type":2},"lastWatchEpisode":1,' +
        '"adapterName":"gugu3","lastWatchTime":1000,"progresses":{"1":{"episode":1}}}]}')
      expect(malformedHistories === null).assertTrue()
      expect(malformedVersions === null).assertTrue()
      expect(malformedVersionValue === null).assertTrue()
      expect(malformedProgressVersions === null).assertTrue()
      expect(malformedProgress === null).assertTrue()
    })

    it('rejectsMalformedProgressEvents', 0, () => {
      const json = upsertEvent('upsertProgress', 1, 1000).toJSON()
      json['road'] = 'invalid'
      expect(KazumiHistorySyncEvent.fromJSON(json) === null).assertTrue()
    })

    it('preservesAllEpisodeProgressesInLocalHistory', 0, () => {
      const record = new HistoryRecord()
      record.episodeIndex = 1
      record.roadIndex = 1
      record.positionMs = 123456
      record.updatedAt = 2000
      record.ensureCurrentProgress()
      const firstEpisode = new HistoryEpisodeProgress()
      firstEpisode.episode = 1
      firstEpisode.road = 0
      firstEpisode.progressMs = 65432
      firstEpisode.updatedAtMs = 1000
      record.progresses.set(1, firstEpisode)

      const restored = HistoryRecord.fromJSON(record.toJSON())
      expect(restored.progresses.size).assertEqual(2)
      expect(restored.progresses.get(1)?.progressMs).assertEqual(65432)
      expect(restored.progresses.get(2)?.progressMs).assertEqual(123456)
    })

    it('keepsOnlineAndOfflineEntitiesSeparate', 0, () => {
      const state = KazumiHistorySyncState.fromSnapshot(KazumiHistorySyncSnapshot.empty())
      const onlineProgress = upsertEvent('upsertProgress', 1, 1000)
      const onlineWatchState = upsertEvent('upsertWatchState', 2, 1000)
      const offlineProgress = upsertEvent('upsertProgress', 3, 1100)
      offlineProgress.entryKind = 'offline'
      offlineProgress.entityKey = 'gugu3400602::offline'
      const offlineWatchState = upsertEvent('upsertWatchState', 4, 1100)
      offlineWatchState.entryKind = 'offline'
      offlineWatchState.entityKey = 'gugu3400602::offline'

      state.applyAll([onlineProgress, onlineWatchState, offlineProgress, offlineWatchState])
      const snapshot = state.toSnapshot()
      expect(snapshot.histories.length).assertEqual(2)
      expect(snapshot.itemVersions.has('gugu3400602::online')).assertTrue()
      expect(snapshot.itemVersions.has('gugu3400602::offline')).assertTrue()
    })
  })
}
