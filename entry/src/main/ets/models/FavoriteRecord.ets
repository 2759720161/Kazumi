export class FavoriteRecord {
  id: number = -1;
  animeId: string = '';
  animeName: string = '';
  animeCover: string = '';
  animeDesc: string = '';
  animeUrl: string = '';
  sourceName: string = '';
  sourceId: number = -1;
  createdAt: number = 0;

  static fromJSON(json: Record<string, Object>): FavoriteRecord {
    const record = new FavoriteRecord();
    if (json['id'] !== undefined) record.id = json['id'] as number;
    if (json['animeId'] !== undefined) record.animeId = json['animeId'] as string;
    if (json['animeName'] !== undefined) record.animeName = json['animeName'] as string;
    if (json['animeCover'] !== undefined) record.animeCover = json['animeCover'] as string;
    if (json['animeDesc'] !== undefined) record.animeDesc = json['animeDesc'] as string;
    if (json['animeUrl'] !== undefined) record.animeUrl = json['animeUrl'] as string;
    if (json['sourceName'] !== undefined) record.sourceName = json['sourceName'] as string;
    if (json['sourceId'] !== undefined) record.sourceId = json['sourceId'] as number;
    if (json['createdAt'] !== undefined) record.createdAt = json['createdAt'] as number;
    return record;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['id'] = this.id;
    result['animeId'] = this.animeId;
    result['animeName'] = this.animeName;
    result['animeCover'] = this.animeCover;
    result['animeDesc'] = this.animeDesc;
    result['animeUrl'] = this.animeUrl;
    result['sourceName'] = this.sourceName;
    result['sourceId'] = this.sourceId;
    result['createdAt'] = this.createdAt;
    return result;
  }
}