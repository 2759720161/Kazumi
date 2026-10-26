import localUnitTest from './LocalUnit.test';
import historySyncProtocolTest from './HistorySyncProtocol.test';
import bangumiSyncProtocolTest from './BangumiSyncProtocol.test';

export default function testsuite() {
  localUnitTest();
  historySyncProtocolTest();
  bangumiSyncProtocolTest();
}
