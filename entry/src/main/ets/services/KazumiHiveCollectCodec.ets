import { util } from '@kit.ArkTS'
import { CollectedBangumi } from '../models/CollectedBangumi'
import { CollectChangeRecord } from '../models/CollectChangeRecord'
import { CollectType } from '../models/CollectType'
import { KazumiHistoryItem, KazumiHistoryProgress } from './KazumiHistorySyncProtocol'

const HIVE_TYPE_NULL: number = 0
const HIVE_TYPE_INT: number = 1
const HIVE_TYPE_DOUBLE: number = 2
const HIVE_TYPE_BOOL: number = 3
const HIVE_TYPE_STRING: number = 4
const HIVE_TYPE_BYTE_LIST: number = 5
const HIVE_TYPE_INT_LIST: number = 6
const HIVE_TYPE_DOUBLE_LIST: number = 7
const HIVE_TYPE_BOOL_LIST: number = 8
const HIVE_TYPE_STRING_LIST: number = 9
const HIVE_TYPE_LIST: number = 10
const HIVE_TYPE_MAP: number = 11
const HIVE_TYPE_DATE_TIME: number = 16
const HIVE_TYPE_DATE_TIME_WITH_TIMEZONE: number = 18
const HIVE_TYPE_EXTENSION: number = 21

// Hive CE reserves 0-31 for built-ins and offsets application type IDs by 32.
const HIVE_TYPE_BANGUMI_ITEM: number = 32
const HIVE_TYPE_HISTORY: number = 33
const HIVE_TYPE_PROGRESS: number = 34
const HIVE_TYPE_COLLECTED_BANGUMI: number = 35
const HIVE_TYPE_BANGUMI_TAG: number = 36
const HIVE_TYPE_COLLECT_CHANGE: number = 37

class HiveNullValue {}

class HiveBangumiTag {
  name: string = ''
  count: number = 0
  totalCount: number = 0
}

class HiveBangumiItem {
  id: number = -1
  type: number = 2
  name: string = ''
  nameCn: string = ''
  summary: string = ''
  airDate: string = ''
  airWeekday: number = 0
  rank: number = 0
  images: Map<string, string> = new Map<string, string>()
  tags: HiveBangumiTag[] = []
  aliases: string[] = []
  ratingScore: number = 0
  votes: number = 0
  votesCount: number[] = []
  info: string = ''
}

class HiveCollectedBangumi {
  bangumiItem: HiveBangumiItem = new HiveBangumiItem()
  timeMs: number = 0
  type: number = CollectType.watching
}

class HiveCollectChange {
  id: number = -1
  bangumiId: number = -1
  action: number = 0
  type: number = 0
  timestamp: number = 0
}

class HiveHistoryProgress {
  episode: number = 1
  road: number = 0
  progressMs: number = 0
  updatedAtMs: number = 0
}

class HiveHistory {
  progresses: Map<number, HiveHistoryProgress> = new Map<number, HiveHistoryProgress>()
  lastWatchEpisode: number = 1
  adapterName: string = ''
  bangumiItem: HiveBangumiItem = new HiveBangumiItem()
  lastWatchTime: number = 0
  lastSrc: string = ''
  lastWatchEpisodeName: string = ''
  entryKind: string = 'online'
  episodePageUrl: string = ''
}

class HiveBinaryReader {
  private bytes: Uint8Array
  offset: number = 0

  constructor(bytes: Uint8Array) {
    this.bytes = bytes
  }

  get length(): number {
    return this.bytes.length
  }

  readByte(): number {
    this.requireBytes(1)
    return this.bytes[this.offset++]
  }

  readWord(): number {
    this.requireBytes(2)
    const value = this.bytes[this.offset] | (this.bytes[this.offset + 1] << 8)
    this.offset += 2
    return value
  }

  readUint32(): number {
    this.requireBytes(4)
    const value = (this.bytes[this.offset] |
      (this.bytes[this.offset + 1] << 8) |
      (this.bytes[this.offset + 2] << 16) |
      (this.bytes[this.offset + 3] << 24)) >>> 0
    this.offset += 4
    return value
  }

  readDouble(): number {
    this.requireBytes(8)
    const data = new ArrayBuffer(8)
    const target = new Uint8Array(data)
    for (let i = 0; i < 8; i++) {
      target[i] = this.bytes[this.offset + i]
    }
    this.offset += 8
    return new DataView(data).getFloat64(0, true)
  }

  readString(): string {
    const count = this.readUint32()
    const value = this.readBytes(count)
    return util.TextDecoder.create('utf-8').decodeToString(value)
  }

  readBytes(count: number): Uint8Array {
    this.requireBytes(count)
    const value = this.bytes.slice(this.offset, this.offset + count)
    this.offset += count
    return value
  }

  peekUint32(offset: number): number {
    if (offset < 0 || offset + 4 > this.bytes.length) {
      throw new Error('Hive frame CRC 越界')
    }
    return (this.bytes[offset] |
      (this.bytes[offset + 1] << 8) |
      (this.bytes[offset + 2] << 16) |
      (this.bytes[offset + 3] << 24)) >>> 0
  }

  private requireBytes(count: number): void {
    if (count < 0 || this.offset + count > this.bytes.length) {
      throw new Error('Hive 数据不完整')
    }
  }
}

class HiveBinaryWriter {
  private bytes: number[] = []

  get length(): number {
    return this.bytes.length
  }

  writeByte(value: number): void {
    this.bytes.push(value & 0xFF)
  }

  writeUint32(value: number): void {
    const normalized = value >>> 0
    this.bytes.push(normalized & 0xFF)
    this.bytes.push((normalized >>> 8) & 0xFF)
    this.bytes.push((normalized >>> 16) & 0xFF)
    this.bytes.push((normalized >>> 24) & 0xFF)
  }

  patchUint32(offset: number, value: number): void {
    const normalized = value >>> 0
    this.bytes[offset] = normalized & 0xFF
    this.bytes[offset + 1] = (normalized >>> 8) & 0xFF
    this.bytes[offset + 2] = (normalized >>> 16) & 0xFF
    this.bytes[offset + 3] = (normalized >>> 24) & 0xFF
  }

  writeDouble(value: number): void {
    const data = new ArrayBuffer(8)
    new DataView(data).setFloat64(0, value, true)
    this.writeBytes(new Uint8Array(data))
  }

  writeString(value: string): void {
    if (value.length === 0) {
      this.writeUint32(0)
      return
    }
    const encoded = util.TextEncoder.create('utf-8').encodeInto(value)
    this.writeUint32(encoded.length)
    this.writeBytes(encoded)
  }

  writeBytes(value: Uint8Array): void {
    for (let i = 0; i < value.length; i++) {
      this.bytes.push(value[i])
    }
  }

  slice(start: number, end: number): Uint8Array {
    return new Uint8Array(this.bytes.slice(start, end))
  }

  toBytes(): Uint8Array {
    return new Uint8Array(this.bytes)
  }
}

export class KazumiHiveCollectCodec {
  static decodeHistories(bytes: Uint8Array): KazumiHistoryItem[] {
    const reader = new HiveBinaryReader(bytes)
    const records: Map<string, HiveHistory> = new Map<string, HiveHistory>()
    while (reader.offset < reader.length) {
      const frameStart = reader.offset
      const frameLength = reader.readUint32()
      const frameEnd = frameStart + frameLength
      if (frameLength < 8 || frameEnd > reader.length) throw new Error('Hive 历史 frame 长度无效')
      KazumiHiveCollectCodec.verifyFrameCrc(reader, bytes, frameStart, frameLength)
      const key = KazumiHiveCollectCodec.readHistoryFrameKey(reader)
      if (reader.offset >= frameEnd - 4) {
        records.delete(key)
      } else {
        const value = KazumiHiveCollectCodec.readValue(reader)
        if (value instanceof HiveHistory) records.set(key, value)
      }
      reader.offset = frameEnd
    }
    const result: KazumiHistoryItem[] = []
    records.forEach((value: HiveHistory) => {
      if (value.bangumiItem.id > 0 && value.adapterName.length > 0) {
        result.push(KazumiHiveCollectCodec.toCanonicalHistory(value))
      }
    })
    return result
  }

  static decodeCollectibles(bytes: Uint8Array): CollectedBangumi[] {
    const reader = new HiveBinaryReader(bytes)
    const records: Map<number, HiveCollectedBangumi> = new Map<number, HiveCollectedBangumi>()
    while (reader.offset < reader.length) {
      const frameStart = reader.offset
      try {
        const frameLength = reader.readUint32()
        const frameEnd = frameStart + frameLength
        if (frameLength < 8 || frameEnd > reader.length) {
          throw new Error('Hive 收藏 frame 长度无效')
        }
        KazumiHiveCollectCodec.verifyFrameCrc(reader, bytes, frameStart, frameLength)
        const key = KazumiHiveCollectCodec.readFrameKey(reader)
        if (reader.offset >= frameEnd - 4) {
          records.delete(key)
        } else {
          const value = KazumiHiveCollectCodec.readValue(reader)
          if (value instanceof HiveCollectedBangumi) {
            records.set(key, value)
          }
        }
        reader.offset = frameEnd
      } catch (err) {
        throw new Error(err instanceof Error ? err.message : String(err))
      }
    }

    const result: CollectedBangumi[] = []
    records.forEach((value: HiveCollectedBangumi) => {
      if (value.bangumiItem.id > 0 && CollectType.normalize(value.type) !== CollectType.none) {
        result.push(KazumiHiveCollectCodec.toLocalCollectible(value))
      }
    })
    result.sort((a: CollectedBangumi, b: CollectedBangumi) => b.createdAt - a.createdAt)
    return result
  }

  static encodeCollectibles(records: CollectedBangumi[]): Uint8Array {
    const writer = new HiveBinaryWriter()
    const byBangumiId: Map<number, CollectedBangumi> = new Map<number, CollectedBangumi>()
    for (let i = 0; i < records.length; i++) {
      const item = records[i]
      if (item.bangumiId <= 0 || CollectType.normalize(item.collectType) === CollectType.none) {
        continue
      }
      const existing = byBangumiId.get(item.bangumiId)
      if (existing === undefined || item.createdAt >= existing.createdAt) {
        byBangumiId.set(item.bangumiId, item)
      }
    }
    byBangumiId.forEach((item: CollectedBangumi, bangumiId: number) => {
      KazumiHiveCollectCodec.writeFrame(writer, bangumiId, () => {
        KazumiHiveCollectCodec.writeCollectedBangumi(writer, item)
      })
    })
    return writer.toBytes()
  }

  static decodeChanges(bytes: Uint8Array): CollectChangeRecord[] {
    const reader = new HiveBinaryReader(bytes)
    const records: Map<number, HiveCollectChange> = new Map<number, HiveCollectChange>()
    while (reader.offset < reader.length) {
      const frameStart = reader.offset
      try {
        const frameLength = reader.readUint32()
        const frameEnd = frameStart + frameLength
        if (frameLength < 8 || frameEnd > reader.length) {
          throw new Error('Hive 收藏变更 frame 长度无效')
        }
        KazumiHiveCollectCodec.verifyFrameCrc(reader, bytes, frameStart, frameLength)
        const key = KazumiHiveCollectCodec.readFrameKey(reader)
        if (reader.offset >= frameEnd - 4) {
          records.delete(key)
        } else {
          const value = KazumiHiveCollectCodec.readValue(reader)
          if (value instanceof HiveCollectChange) {
            records.set(key, value)
          }
        }
        reader.offset = frameEnd
      } catch (err) {
        throw new Error(err instanceof Error ? err.message : String(err))
      }
    }

    const result: CollectChangeRecord[] = []
    records.forEach((value: HiveCollectChange) => {
      const record = new CollectChangeRecord()
      record.id = value.id
      record.bangumiId = value.bangumiId
      record.action = value.action
      record.type = value.type
      record.timestamp = value.timestamp
      result.push(record)
    })
    result.sort((a: CollectChangeRecord, b: CollectChangeRecord) => a.timestamp - b.timestamp)
    return result
  }

  static encodeChanges(records: CollectChangeRecord[]): Uint8Array {
    const writer = new HiveBinaryWriter()
    const byId: Map<number, CollectChangeRecord> = new Map<number, CollectChangeRecord>()
    for (let i = 0; i < records.length; i++) {
      const item = records[i]
      if (item.id > 0 && item.id <= 0xFFFFFFFF && item.bangumiId > 0) {
        byId.set(item.id, item)
      }
    }
    byId.forEach((item: CollectChangeRecord, id: number) => {
      KazumiHiveCollectCodec.writeFrame(writer, id, () => {
        KazumiHiveCollectCodec.writeCollectChange(writer, item)
      })
    })
    return writer.toBytes()
  }

  private static writeFrame(writer: HiveBinaryWriter, key: number, writeValue: () => void): void {
    const start = writer.length
    writer.writeUint32(0)
    writer.writeByte(0)
    writer.writeUint32(key)
    writeValue()
    const frameLength = writer.length - start + 4
    writer.patchUint32(start, frameLength)
    const crc = KazumiHiveCollectCodec.computeCrc32(writer.slice(start, start + frameLength - 4))
    writer.writeUint32(crc)
  }

  private static writeCollectedBangumi(writer: HiveBinaryWriter, item: CollectedBangumi): void {
    writer.writeByte(HIVE_TYPE_COLLECTED_BANGUMI)
    writer.writeByte(3)
    writer.writeByte(0)
    KazumiHiveCollectCodec.writeBangumiItem(writer, item)
    writer.writeByte(1)
    KazumiHiveCollectCodec.writeDateTime(writer, item.createdAt > 0 ? item.createdAt : Date.now())
    writer.writeByte(2)
    KazumiHiveCollectCodec.writeInt(writer, CollectType.normalize(item.collectType))
  }

  private static writeBangumiItem(writer: HiveBinaryWriter, item: CollectedBangumi): void {
    writer.writeByte(HIVE_TYPE_BANGUMI_ITEM)
    writer.writeByte(15)
    writer.writeByte(0)
    KazumiHiveCollectCodec.writeInt(writer, item.bangumiId)
    writer.writeByte(1)
    KazumiHiveCollectCodec.writeInt(writer, 2)
    writer.writeByte(2)
    KazumiHiveCollectCodec.writeString(writer, item.animeName)
    writer.writeByte(3)
    KazumiHiveCollectCodec.writeString(writer, item.animeName)
    writer.writeByte(4)
    KazumiHiveCollectCodec.writeString(writer, item.animeDesc)
    writer.writeByte(5)
    KazumiHiveCollectCodec.writeString(writer, '')
    writer.writeByte(6)
    KazumiHiveCollectCodec.writeInt(writer, 0)
    writer.writeByte(7)
    KazumiHiveCollectCodec.writeInt(writer, 0)
    writer.writeByte(8)
    KazumiHiveCollectCodec.writeImages(writer, item)
    writer.writeByte(9)
    KazumiHiveCollectCodec.writeEmptyDynamicList(writer)
    writer.writeByte(10)
    KazumiHiveCollectCodec.writeStringList(writer, [])
    writer.writeByte(11)
    KazumiHiveCollectCodec.writeDouble(writer, 0)
    writer.writeByte(12)
    KazumiHiveCollectCodec.writeInt(writer, 0)
    writer.writeByte(13)
    KazumiHiveCollectCodec.writeIntList(writer, [])
    writer.writeByte(14)
    KazumiHiveCollectCodec.writeString(writer, '')
  }

  private static writeCollectChange(writer: HiveBinaryWriter, item: CollectChangeRecord): void {
    writer.writeByte(HIVE_TYPE_COLLECT_CHANGE)
    writer.writeByte(5)
    writer.writeByte(0)
    KazumiHiveCollectCodec.writeInt(writer, item.id)
    writer.writeByte(1)
    KazumiHiveCollectCodec.writeInt(writer, item.bangumiId)
    writer.writeByte(2)
    KazumiHiveCollectCodec.writeInt(writer, item.action)
    writer.writeByte(3)
    KazumiHiveCollectCodec.writeInt(writer, item.type)
    writer.writeByte(4)
    KazumiHiveCollectCodec.writeInt(writer, item.timestamp)
  }

  private static writeInt(writer: HiveBinaryWriter, value: number): void {
    writer.writeByte(HIVE_TYPE_INT)
    writer.writeDouble(value)
  }

  private static writeDouble(writer: HiveBinaryWriter, value: number): void {
    writer.writeByte(HIVE_TYPE_DOUBLE)
    writer.writeDouble(value)
  }

  private static writeString(writer: HiveBinaryWriter, value: string): void {
    writer.writeByte(HIVE_TYPE_STRING)
    writer.writeString(value)
  }

  private static writeDateTime(writer: HiveBinaryWriter, value: number): void {
    writer.writeByte(HIVE_TYPE_DATE_TIME)
    writer.writeDouble(value)
  }

  private static writeStringList(writer: HiveBinaryWriter, values: string[]): void {
    writer.writeByte(HIVE_TYPE_STRING_LIST)
    writer.writeUint32(values.length)
    for (let i = 0; i < values.length; i++) {
      writer.writeString(values[i])
    }
  }

  private static writeIntList(writer: HiveBinaryWriter, values: number[]): void {
    writer.writeByte(HIVE_TYPE_INT_LIST)
    writer.writeUint32(values.length)
    for (let i = 0; i < values.length; i++) {
      writer.writeDouble(values[i])
    }
  }

  private static writeEmptyDynamicList(writer: HiveBinaryWriter): void {
    writer.writeByte(HIVE_TYPE_LIST)
    writer.writeUint32(0)
  }

  private static writeImages(writer: HiveBinaryWriter, item: CollectedBangumi): void {
    const cover = item.getBestCover()
    writer.writeByte(HIVE_TYPE_MAP)
    writer.writeUint32(5)
    const keys: string[] = ['large', 'common', 'medium', 'small', 'grid']
    for (let i = 0; i < keys.length; i++) {
      KazumiHiveCollectCodec.writeString(writer, keys[i])
      KazumiHiveCollectCodec.writeString(writer, cover)
    }
  }

  private static readFrameKey(reader: HiveBinaryReader): number {
    const keyType = reader.readByte()
    if (keyType === 0) {
      return reader.readUint32()
    }
    if (keyType === 1) {
      const length = reader.readByte()
      reader.readBytes(length)
      throw new Error('收藏 Hive box 使用了非整数键')
    }
    throw new Error('Hive frame 键类型无效')
  }

  private static readHistoryFrameKey(reader: HiveBinaryReader): string {
    const keyType = reader.readByte()
    if (keyType === 0) return String(reader.readUint32())
    if (keyType === 1) {
      const length = reader.readByte()
      return util.TextDecoder.create('utf-8').decodeToString(reader.readBytes(length))
    }
    throw new Error('Hive frame 键类型无效')
  }

  private static readValue(reader: HiveBinaryReader): Object {
    let typeId = reader.readByte()
    if (typeId === HIVE_TYPE_EXTENSION) {
      typeId = reader.readWord()
    }
    if (typeId === HIVE_TYPE_NULL) return new HiveNullValue()
    if (typeId === HIVE_TYPE_INT || typeId === HIVE_TYPE_DOUBLE || typeId === HIVE_TYPE_DATE_TIME) {
      return reader.readDouble()
    }
    if (typeId === HIVE_TYPE_DATE_TIME_WITH_TIMEZONE) {
      const timestamp = reader.readDouble()
      reader.readByte()
      return timestamp
    }
    if (typeId === HIVE_TYPE_BOOL) return reader.readByte() > 0
    if (typeId === HIVE_TYPE_STRING) return reader.readString()
    if (typeId === HIVE_TYPE_BYTE_LIST) return reader.readBytes(reader.readUint32())
    if (typeId === HIVE_TYPE_INT_LIST || typeId === HIVE_TYPE_DOUBLE_LIST) {
      return KazumiHiveCollectCodec.readNumberList(reader)
    }
    if (typeId === HIVE_TYPE_BOOL_LIST) return KazumiHiveCollectCodec.readBoolList(reader)
    if (typeId === HIVE_TYPE_STRING_LIST) return KazumiHiveCollectCodec.readStringList(reader)
    if (typeId === HIVE_TYPE_LIST) return KazumiHiveCollectCodec.readDynamicList(reader)
    if (typeId === HIVE_TYPE_MAP) return KazumiHiveCollectCodec.readDynamicMap(reader)
    if (typeId === HIVE_TYPE_BANGUMI_ITEM) return KazumiHiveCollectCodec.readBangumiItem(reader)
    if (typeId === HIVE_TYPE_HISTORY) return KazumiHiveCollectCodec.readHistory(reader)
    if (typeId === HIVE_TYPE_PROGRESS) return KazumiHiveCollectCodec.readHistoryProgress(reader)
    if (typeId === HIVE_TYPE_COLLECTED_BANGUMI) return KazumiHiveCollectCodec.readCollectedBangumi(reader)
    if (typeId === HIVE_TYPE_BANGUMI_TAG) return KazumiHiveCollectCodec.readBangumiTag(reader)
    if (typeId === HIVE_TYPE_COLLECT_CHANGE) return KazumiHiveCollectCodec.readCollectChange(reader)
    throw new Error(`不支持的 Hive 类型: ${typeId}`)
  }

  private static readFields(reader: HiveBinaryReader): Map<number, Object> {
    const count = reader.readByte()
    const fields: Map<number, Object> = new Map<number, Object>()
    for (let i = 0; i < count; i++) {
      const fieldId = reader.readByte()
      fields.set(fieldId, KazumiHiveCollectCodec.readValue(reader))
    }
    return fields
  }

  private static readBangumiItem(reader: HiveBinaryReader): HiveBangumiItem {
    const fields = KazumiHiveCollectCodec.readFields(reader)
    const item = new HiveBangumiItem()
    item.id = KazumiHiveCollectCodec.numberField(fields, 0, -1)
    item.type = KazumiHiveCollectCodec.numberField(fields, 1, 2)
    item.name = KazumiHiveCollectCodec.stringField(fields, 2)
    item.nameCn = KazumiHiveCollectCodec.stringField(fields, 3)
    item.summary = KazumiHiveCollectCodec.stringField(fields, 4)
    item.airDate = KazumiHiveCollectCodec.stringField(fields, 5)
    item.airWeekday = KazumiHiveCollectCodec.numberField(fields, 6, 0)
    item.rank = KazumiHiveCollectCodec.numberField(fields, 7, 0)
    item.images = KazumiHiveCollectCodec.stringMapField(fields, 8)
    item.tags = KazumiHiveCollectCodec.tagListField(fields, 9)
    item.aliases = KazumiHiveCollectCodec.stringListField(fields, 10)
    item.ratingScore = KazumiHiveCollectCodec.numberField(fields, 11, 0)
    item.votes = KazumiHiveCollectCodec.numberField(fields, 12, 0)
    item.votesCount = KazumiHiveCollectCodec.numberListField(fields, 13)
    item.info = KazumiHiveCollectCodec.stringField(fields, 14)
    return item
  }

  private static readCollectedBangumi(reader: HiveBinaryReader): HiveCollectedBangumi {
    const fields = KazumiHiveCollectCodec.readFields(reader)
    const item = new HiveCollectedBangumi()
    const bangumi = fields.get(0)
    if (bangumi instanceof HiveBangumiItem) item.bangumiItem = bangumi
    item.timeMs = KazumiHiveCollectCodec.numberField(fields, 1, 0)
    item.type = KazumiHiveCollectCodec.numberField(fields, 2, CollectType.watching)
    return item
  }

  private static readBangumiTag(reader: HiveBinaryReader): HiveBangumiTag {
    const fields = KazumiHiveCollectCodec.readFields(reader)
    const tag = new HiveBangumiTag()
    tag.name = KazumiHiveCollectCodec.stringField(fields, 0)
    tag.count = KazumiHiveCollectCodec.numberField(fields, 1, 0)
    tag.totalCount = KazumiHiveCollectCodec.numberField(fields, 2, 0)
    return tag
  }

  private static readCollectChange(reader: HiveBinaryReader): HiveCollectChange {
    const fields = KazumiHiveCollectCodec.readFields(reader)
    const change = new HiveCollectChange()
    change.id = KazumiHiveCollectCodec.numberField(fields, 0, -1)
    change.bangumiId = KazumiHiveCollectCodec.numberField(fields, 1, -1)
    change.action = KazumiHiveCollectCodec.numberField(fields, 2, 0)
    change.type = KazumiHiveCollectCodec.numberField(fields, 3, 0)
    change.timestamp = KazumiHiveCollectCodec.numberField(fields, 4, 0)
    return change
  }

  private static readHistory(reader: HiveBinaryReader): HiveHistory {
    const fields = KazumiHiveCollectCodec.readFields(reader)
    const history = new HiveHistory()
    const progresses = fields.get(0)
    if (progresses instanceof Map) {
      progresses.forEach((value: Object, key: string) => {
        if (value instanceof HiveHistoryProgress) {
          const episode = Number(key)
          if (Number.isFinite(episode)) history.progresses.set(episode, value)
        }
      })
    }
    history.lastWatchEpisode = KazumiHiveCollectCodec.numberField(fields, 1, 1)
    history.adapterName = KazumiHiveCollectCodec.stringField(fields, 2)
    const bangumi = fields.get(3)
    if (bangumi instanceof HiveBangumiItem) history.bangumiItem = bangumi
    history.lastWatchTime = KazumiHiveCollectCodec.numberField(fields, 4, 0)
    history.lastSrc = KazumiHiveCollectCodec.stringField(fields, 5)
    history.lastWatchEpisodeName = KazumiHiveCollectCodec.stringField(fields, 6)
    history.entryKind = KazumiHiveCollectCodec.stringField(fields, 7)
    if (history.entryKind.length === 0) history.entryKind = 'online'
    history.episodePageUrl = KazumiHiveCollectCodec.stringField(fields, 8)
    return history
  }

  private static readHistoryProgress(reader: HiveBinaryReader): HiveHistoryProgress {
    const fields = KazumiHiveCollectCodec.readFields(reader)
    const progress = new HiveHistoryProgress()
    progress.episode = KazumiHiveCollectCodec.numberField(fields, 0, 1)
    progress.road = KazumiHiveCollectCodec.numberField(fields, 1, 0)
    progress.progressMs = KazumiHiveCollectCodec.numberField(fields, 2, 0)
    progress.updatedAtMs = KazumiHiveCollectCodec.numberField(fields, 3, 0)
    return progress
  }

  private static readNumberList(reader: HiveBinaryReader): number[] {
    const count = reader.readUint32()
    const result: number[] = []
    for (let i = 0; i < count; i++) result.push(reader.readDouble())
    return result
  }

  private static readBoolList(reader: HiveBinaryReader): boolean[] {
    const count = reader.readUint32()
    const result: boolean[] = []
    for (let i = 0; i < count; i++) result.push(reader.readByte() > 0)
    return result
  }

  private static readStringList(reader: HiveBinaryReader): string[] {
    const count = reader.readUint32()
    const result: string[] = []
    for (let i = 0; i < count; i++) result.push(reader.readString())
    return result
  }

  private static readDynamicList(reader: HiveBinaryReader): Object[] {
    const count = reader.readUint32()
    const result: Object[] = []
    for (let i = 0; i < count; i++) result.push(KazumiHiveCollectCodec.readValue(reader))
    return result
  }

  private static readDynamicMap(reader: HiveBinaryReader): Map<string, Object> {
    const count = reader.readUint32()
    const result: Map<string, Object> = new Map<string, Object>()
    for (let i = 0; i < count; i++) {
      const key = KazumiHiveCollectCodec.readValue(reader)
      const value = KazumiHiveCollectCodec.readValue(reader)
      if (typeof key === 'string') result.set(key, value)
      if (typeof key === 'number') result.set(String(key), value)
    }
    return result
  }

  private static numberField(fields: Map<number, Object>, key: number, fallback: number): number {
    const value = fields.get(key)
    return typeof value === 'number' ? value : fallback
  }

  private static stringField(fields: Map<number, Object>, key: number): string {
    const value = fields.get(key)
    return typeof value === 'string' ? value : ''
  }

  private static stringMapField(fields: Map<number, Object>, key: number): Map<string, string> {
    const result: Map<string, string> = new Map<string, string>()
    const value = fields.get(key)
    if (value instanceof Map) {
      value.forEach((entry: Object, name: string) => {
        if (typeof entry === 'string') result.set(name, entry)
      })
    }
    return result
  }

  private static stringListField(fields: Map<number, Object>, key: number): string[] {
    const result: string[] = []
    const value = fields.get(key)
    if (value instanceof Array) {
      for (let i = 0; i < value.length; i++) {
        if (typeof value[i] === 'string') result.push(value[i] as string)
      }
    }
    return result
  }

  private static numberListField(fields: Map<number, Object>, key: number): number[] {
    const result: number[] = []
    const value = fields.get(key)
    if (value instanceof Array) {
      for (let i = 0; i < value.length; i++) {
        if (typeof value[i] === 'number') result.push(value[i] as number)
      }
    }
    return result
  }

  private static tagListField(fields: Map<number, Object>, key: number): HiveBangumiTag[] {
    const result: HiveBangumiTag[] = []
    const value = fields.get(key)
    if (value instanceof Array) {
      for (let i = 0; i < value.length; i++) {
        if (value[i] instanceof HiveBangumiTag) result.push(value[i] as HiveBangumiTag)
      }
    }
    return result
  }

  private static toLocalCollectible(value: HiveCollectedBangumi): CollectedBangumi {
    const upstream = value.bangumiItem
    const item = new CollectedBangumi()
    item.bangumiId = upstream.id
    item.animeId = `bangumi:subject:${upstream.id}`
    item.animeName = upstream.nameCn.length > 0 ? upstream.nameCn : upstream.name
    item.animeDesc = upstream.summary
    item.bangumiCover = KazumiHiveCollectCodec.bestImage(upstream.images)
    item.animeCover = item.bangumiCover
    item.collectType = CollectType.normalize(value.type)
    item.createdAt = value.timeMs
    return item
  }

  private static toCanonicalHistory(value: HiveHistory): KazumiHistoryItem {
    const item = new KazumiHistoryItem()
    item.bangumiItem = KazumiHiveCollectCodec.bangumiItemToJSON(value.bangumiItem)
    item.lastWatchEpisode = value.lastWatchEpisode
    item.adapterName = value.adapterName
    item.lastWatchTime = value.lastWatchTime
    item.lastSrc = value.lastSrc
    item.lastWatchEpisodeName = value.lastWatchEpisodeName
    item.entryKind = KazumiHistoryItem.normalizeEntryKind(value.entryKind)
    item.episodePageUrl = value.episodePageUrl
    value.progresses.forEach((source: HiveHistoryProgress, episode: number) => {
      const progress = new KazumiHistoryProgress()
      progress.episode = source.episode
      progress.road = source.road
      progress.progressMs = source.progressMs
      progress.updatedAtMs = source.updatedAtMs
      item.progresses.set(episode, progress)
    })
    return item
  }

  private static bangumiItemToJSON(value: HiveBangumiItem): Record<string, Object> {
    const images: Record<string, Object> = {}
    value.images.forEach((image: string, name: string) => images[name] = image)
    const tags: Record<string, Object>[] = []
    for (let i = 0; i < value.tags.length; i++) {
      const tag: Record<string, Object> = {}
      tag['name'] = value.tags[i].name
      tag['count'] = value.tags[i].count
      tag['totalCount'] = value.tags[i].totalCount
      tags.push(tag)
    }
    const result: Record<string, Object> = {}
    result['id'] = value.id
    result['type'] = value.type
    result['name'] = value.name
    result['nameCn'] = value.nameCn
    result['summary'] = value.summary
    result['airDate'] = value.airDate
    result['airWeekday'] = value.airWeekday
    result['rank'] = value.rank
    result['images'] = images
    result['tags'] = tags
    result['alias'] = value.aliases
    result['ratingScore'] = value.ratingScore
    result['votes'] = value.votes
    result['votesCount'] = value.votesCount
    result['info'] = value.info
    return result
  }

  private static bestImage(images: Map<string, string>): string {
    const keys: string[] = ['large', 'common', 'medium', 'grid', 'small']
    for (let i = 0; i < keys.length; i++) {
      const value = images.get(keys[i]) ?? ''
      if (value.length > 0) return value
    }
    return ''
  }

  private static verifyFrameCrc(reader: HiveBinaryReader, bytes: Uint8Array,
    frameStart: number, frameLength: number): void {
    const stored = reader.peekUint32(frameStart + frameLength - 4)
    const computed = KazumiHiveCollectCodec.computeCrc32(bytes.slice(frameStart, frameStart + frameLength - 4))
    if (stored !== computed) throw new Error('Hive frame CRC 校验失败')
  }

  private static computeCrc32(bytes: Uint8Array): number {
    let crc = 0xFFFFFFFF
    for (let i = 0; i < bytes.length; i++) {
      crc = (crc ^ bytes[i]) >>> 0
      for (let bit = 0; bit < 8; bit++) {
        crc = ((crc & 1) !== 0 ? ((crc >>> 1) ^ 0xEDB88320) : (crc >>> 1)) >>> 0
      }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0
  }
}
