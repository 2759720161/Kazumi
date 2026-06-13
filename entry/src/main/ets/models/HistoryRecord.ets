export class HistoryRecord {
  id: number = -1;
  animeId: string = '';
  animeName: string = '';
  animeCover: string = '';
  animeUrl: string = '';
  sourceId: number = -1;
  episodeName: string = '';
  episodeUrl: string = '';
  positionMs: number = 0;
  durationMs: number = 0;
  updatedAt: number = 0;

  static fromJSON(json: Record<string, Object>): HistoryRecord {
    const record = new HistoryRecord();
    if (json['id'] !== undefined) record.id = json['id'] as number;
    if (json['animeId'] !== undefined) record.animeId = json['animeId'] as string;
    if (json['animeName'] !== undefined) record.animeName = json['animeName'] as string;
    if (json['animeCover'] !== undefined) record.animeCover = json['animeCover'] as string;
    if (json['animeUrl'] !== undefined) record.animeUrl = json['animeUrl'] as string;
    if (json['sourceId'] !== undefined) record.sourceId = json['sourceId'] as number;
    if (json['episodeName'] !== undefined) record.episodeName = json['episodeName'] as string;
    if (json['episodeUrl'] !== undefined) record.episodeUrl = json['episodeUrl'] as string;
    if (json['positionMs'] !== undefined) record.positionMs = json['positionMs'] as number;
    if (json['durationMs'] !== undefined) record.durationMs = json['durationMs'] as number;
    if (json['updatedAt'] !== undefined) record.updatedAt = json['updatedAt'] as number;
    return record;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['id'] = this.id;
    result['animeId'] = this.animeId;
    result['animeName'] = this.animeName;
    result['animeCover'] = this.animeCover;
    result['animeUrl'] = this.animeUrl;
    result['sourceId'] = this.sourceId;
    result['episodeName'] = this.episodeName;
    result['episodeUrl'] = this.episodeUrl;
    result['positionMs'] = this.positionMs;
    result['durationMs'] = this.durationMs;
    result['updatedAt'] = this.updatedAt;
    return result;
  }

  getProgressPercent(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    return Math.min(100, Math.floor(this.positionMs * 100 / this.durationMs));
  }
}