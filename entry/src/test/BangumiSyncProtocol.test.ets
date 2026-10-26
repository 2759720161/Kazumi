import { describe, it, expect } from '@ohos/hypium'
import { BangumiSyncConfig, BangumiSyncProtocol } from '../main/ets/models/BangumiSync'
import { CollectedBangumi } from '../main/ets/models/CollectedBangumi'
import { CollectType } from '../main/ets/models/CollectType'

function collection(id: number, type: number, time: number = 1): CollectedBangumi {
  const item = new CollectedBangumi()
  item.bangumiId = id
  item.animeId = 'subject:' + id
  item.collectType = type
  item.createdAt = time
  return item
}

export default function bangumiSyncProtocolTest() {
  describe('bangumiSyncProtocol', () => {
    it('defaultsToDisabledAndLocalPriority', 0, () => {
      const config = new BangumiSyncConfig()
      expect(config.enabled).assertFalse()
      expect(config.token).assertEqual('')
      expect(config.priority).assertEqual(0)
      expect(config.immediateToast).assertTrue()
    })
    it('mapsAllFiveStatusesBothWays', 0, () => {
      const local = [CollectType.watching, CollectType.planToWatch, CollectType.onHold,
        CollectType.watched, CollectType.abandoned]
      const remote = [3, 1, 4, 2, 5]
      for (let i = 0; i < local.length; i++) {
        expect(BangumiSyncProtocol.toRemoteType(local[i])).assertEqual(remote[i])
        expect(BangumiSyncProtocol.toLocalType(remote[i])).assertEqual(local[i])
      }
    })
    it('rejectsUncollectedAndInvalidRemoteTypes', 0, () => {
      let errors = 0
      try { BangumiSyncProtocol.toRemoteType(0) } catch (err) { errors++ }
      try { BangumiSyncProtocol.toLocalType(0) } catch (err) { errors++ }
      try { BangumiSyncProtocol.toLocalType(6) } catch (err) { errors++ }
      expect(errors).assertEqual(3)
    })
    it('fillsBothSidesUnderEitherPriority', 0, () => {
      for (let priority = 0; priority <= 1; priority++) {
        const plan = BangumiSyncProtocol.plan([collection(1, 1)], [collection(2, 2)], priority)
        expect(plan.uploads.length).assertEqual(1)
        expect(plan.uploads[0].bangumiId).assertEqual(1)
        expect(plan.downloads.length).assertEqual(1)
        expect(plan.downloads[0].bangumiId).assertEqual(2)
      }
    })
    it('usesLocalStatusForConflictsByDefault', 0, () => {
      const plan = BangumiSyncProtocol.plan([collection(1, 1)], [collection(1, 4)], 0)
      expect(plan.uploads.length).assertEqual(1)
      expect(plan.uploads[0].collectType).assertEqual(1)
      expect(plan.downloads.length).assertEqual(0)
    })
    it('usesRemoteStatusWhenSelected', 0, () => {
      const plan = BangumiSyncProtocol.plan([collection(1, 1)], [collection(1, 4)], 1)
      expect(plan.uploads.length).assertEqual(0)
      expect(plan.downloads.length).assertEqual(1)
      expect(plan.downloads[0].collectType).assertEqual(4)
    })
    it('skipsMatchingStatuses', 0, () => {
      const plan = BangumiSyncProtocol.plan([collection(1, 1)], [collection(1, 1)], 0)
      expect(plan.uploads.length + plan.downloads.length).assertEqual(0)
    })
    it('ignoresUnmatchedIdsAndDeduplicatesNewestStatus', 0, () => {
      const local = [collection(-1, 1), collection(0, 1), collection(1, 0),
        collection(2, 1, 2), collection(2, 4, 3)]
      const plan = BangumiSyncProtocol.plan(local, [], 0)
      expect(plan.uploads.length).assertEqual(1)
      expect(plan.uploads[0].collectType).assertEqual(4)
    })
    it('preservesSourceAndDoesNotMutateInputs', 0, () => {
      const item = collection(1, 1)
      item.sourceId = 8
      item.animeUrl = 'https://example.com/anime'
      const plan = BangumiSyncProtocol.plan([item], [collection(1, 4)], 0)
      expect(plan.uploads[0].sourceId).assertEqual(8)
      expect(item.collectType).assertEqual(1)
      expect(item.animeUrl).assertEqual('https://example.com/anime')
    })
  })
}
