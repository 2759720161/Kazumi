export class CollectChangeRecord {
  id: number = -1
  bangumiId: number = -1
  action: number = 0
  type: number = 0
  timestamp: number = 0

  static fromJSON(json: Record<string, Object>): CollectChangeRecord {
    const record = new CollectChangeRecord()
    if (json['id'] !== undefined) record.id = json['id'] as number
    if (json['bangumiId'] !== undefined) record.bangumiId = json['bangumiId'] as number
    if (json['action'] !== undefined) record.action = json['action'] as number
    if (json['type'] !== undefined) record.type = json['type'] as number
    if (json['timestamp'] !== undefined) record.timestamp = json['timestamp'] as number
    return record
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['id'] = this.id
    result['bangumiId'] = this.bangumiId
    result['action'] = this.action
    result['type'] = this.type
    result['timestamp'] = this.timestamp
    return result
  }
}
