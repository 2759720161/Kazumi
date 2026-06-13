export class AnimeItem {
  name: string = '';
  cover: string = '';
  coverFallback: string = '';
  bangumiCover: string = '';
  coverLarge: string = '';
  coverCommon: string = '';
  coverMedium: string = '';
  desc: string = '';
  originalName: string = '';
  airDate: string = '';
  ratingScore: number = 0;
  rank: number = 0;
  tags: string[] = [];
  eps: number = 0;
  url: string = '';
  sourceName: string = '';
  sourceId: number = -1;
  bangumiId: number = -1;
  aliases: string[] = [];
  airWeekday: number = 0;
  votes: number = 0;
  votesCount: number[] = [];

  static fromJSON(json: Record<string, Object>): AnimeItem {
    const item = new AnimeItem();
    if (json['name'] !== undefined) item.name = json['name'] as string;
    if (json['cover'] !== undefined) item.cover = json['cover'] as string;
    if (json['coverFallback'] !== undefined) item.coverFallback = json['coverFallback'] as string;
    if (json['bangumiCover'] !== undefined) item.bangumiCover = json['bangumiCover'] as string;
    if (json['coverLarge'] !== undefined) item.coverLarge = json['coverLarge'] as string;
    if (json['coverCommon'] !== undefined) item.coverCommon = json['coverCommon'] as string;
    if (json['coverMedium'] !== undefined) item.coverMedium = json['coverMedium'] as string;
    if (json['desc'] !== undefined) item.desc = json['desc'] as string;
    if (json['originalName'] !== undefined) item.originalName = json['originalName'] as string;
    if (json['airDate'] !== undefined) item.airDate = json['airDate'] as string;
    if (json['ratingScore'] !== undefined) item.ratingScore = json['ratingScore'] as number;
    if (json['rank'] !== undefined) item.rank = json['rank'] as number;
    if (json['tags'] !== undefined) item.tags = json['tags'] as string[];
    if (json['eps'] !== undefined) item.eps = json['eps'] as number;
    if (json['url'] !== undefined) item.url = json['url'] as string;
    if (json['sourceName'] !== undefined) item.sourceName = json['sourceName'] as string;
    if (json['sourceId'] !== undefined) item.sourceId = json['sourceId'] as number;
    if (json['bangumiId'] !== undefined) item.bangumiId = json['bangumiId'] as number;
    if (json['aliases'] !== undefined) item.aliases = json['aliases'] as string[];
    if (json['airWeekday'] !== undefined) item.airWeekday = json['airWeekday'] as number;
    if (json['votes'] !== undefined) item.votes = json['votes'] as number;
    if (json['votesCount'] !== undefined) item.votesCount = json['votesCount'] as number[];
    return item;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['name'] = this.name;
    result['cover'] = this.cover;
    result['coverFallback'] = this.coverFallback;
    result['bangumiCover'] = this.bangumiCover;
    result['coverLarge'] = this.coverLarge;
    result['coverCommon'] = this.coverCommon;
    result['coverMedium'] = this.coverMedium;
    result['desc'] = this.desc;
    result['originalName'] = this.originalName;
    result['airDate'] = this.airDate;
    result['ratingScore'] = this.ratingScore;
    result['rank'] = this.rank;
    result['tags'] = this.tags;
    result['eps'] = this.eps;
    result['url'] = this.url;
    result['sourceName'] = this.sourceName;
    result['sourceId'] = this.sourceId;
    result['bangumiId'] = this.bangumiId;
    result['aliases'] = this.aliases;
    result['airWeekday'] = this.airWeekday;
    result['votes'] = this.votes;
    result['votesCount'] = this.votesCount;
    return result;
  }

  getUniqueId(): string {
    return `${this.sourceId}_${this.url}`;
  }

  getGridCover(): string {
    if (this.coverCommon.length > 0) return this.coverCommon;
    if (this.coverMedium.length > 0) return this.coverMedium;
    if (this.bangumiCover.length > 0) return this.bangumiCover;
    if (this.cover.length > 0) return this.cover;
    return this.coverFallback;
  }

  getDetailCover(): string {
    if (this.coverLarge.length > 0) return this.coverLarge;
    if (this.bangumiCover.length > 0) return this.bangumiCover;
    if (this.coverCommon.length > 0) return this.coverCommon;
    if (this.cover.length > 0) return this.cover;
    return this.coverFallback;
  }
}
