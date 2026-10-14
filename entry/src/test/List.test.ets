import localUnitTest from './LocalUnit.test';
import historySyncProtocolTest from './HistorySyncProtocol.test';

export default function testsuite() {
  localUnitTest();
  historySyncProtocolTest();
}
