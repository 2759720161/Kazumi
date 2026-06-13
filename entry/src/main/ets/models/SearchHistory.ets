export class SearchHistory {
  id: number = -1;
  keyword: string = '';
  timestamp: number = 0;

  static fromJSON(json: Record<string, Object>): SearchHistory {
    const record = new SearchHistory();
    if (json['id'] !== undefined) record.id = json['id'] as number;
    if (json['keyword'] !== undefined) record.keyword = json['keyword'] as string;
    if (json['timestamp'] !== undefined) record.timestamp = json['timestamp'] as number;
    return record;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['id'] = this.id;
    result['keyword'] = this.keyword;
    result['timestamp'] = this.timestamp;
    return result;
  }
}