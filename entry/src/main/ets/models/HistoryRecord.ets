export class HistoryEpisodeProgress {
  episode: number = 1;
  road: number = 0;
  progressMs: number = 0;
  updatedAtMs: number = 0;

  static fromJSON(json: Record<string, Object>): HistoryEpisodeProgress {
    const progress = new HistoryEpisodeProgress();
    if (typeof json['episode'] === 'number') progress.episode = json['episode'] as number;
    if (typeof json['road'] === 'number') progress.road = json['road'] as number;
    if (typeof json['progressMs'] === 'number') progress.progressMs = json['progressMs'] as number;
    if (typeof json['updatedAtMs'] === 'number') progress.updatedAtMs = json['updatedAtMs'] as number;
    return progress;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['episode'] = this.episode;
    result['road'] = this.road;
    result['progressMs'] = this.progressMs;
    result['updatedAtMs'] = this.updatedAtMs;
    return result;
  }

  clone(): HistoryEpisodeProgress {
    return HistoryEpisodeProgress.fromJSON(this.toJSON());
  }
}

export class HistoryRecord {
  id: number = -1;
  animeId: string = '';
  animeName: string = '';
  animeCover: string = '';
  animeUrl: string = '';
  bangumiId: number = -1;
  sourceId: number = -1;
  episodeName: string = '';
  episodeUrl: string = '';
  positionMs: number = 0;
  durationMs: number = 0;
  roadIndex: number = -1;
  episodeIndex: number = -1;
  updatedAt: number = 0;
  sourceName: string = '';
  entryKind: string = 'online';
  episodePageUrl: string = '';
  progresses: Map<number, HistoryEpisodeProgress> = new Map();
  bangumiItemJSON: string = '';

  static fromJSON(json: Record<string, Object>): HistoryRecord {
    const record = new HistoryRecord();
    if (json['id'] !== undefined) record.id = json['id'] as number;
    if (json['animeId'] !== undefined) record.animeId = json['animeId'] as string;
    if (json['animeName'] !== undefined) record.animeName = json['animeName'] as string;
    if (json['animeCover'] !== undefined) record.animeCover = json['animeCover'] as string;
    if (json['animeUrl'] !== undefined) record.animeUrl = json['animeUrl'] as string;
    if (json['bangumiId'] !== undefined) record.bangumiId = json['bangumiId'] as number;
    if (json['sourceId'] !== undefined) record.sourceId = json['sourceId'] as number;
    if (json['episodeName'] !== undefined) record.episodeName = json['episodeName'] as string;
    if (json['episodeUrl'] !== undefined) record.episodeUrl = json['episodeUrl'] as string;
    if (json['positionMs'] !== undefined) record.positionMs = json['positionMs'] as number;
    if (json['durationMs'] !== undefined) record.durationMs = json['durationMs'] as number;
    if (json['roadIndex'] !== undefined) record.roadIndex = json['roadIndex'] as number;
    if (json['episodeIndex'] !== undefined) record.episodeIndex = json['episodeIndex'] as number;
    if (json['updatedAt'] !== undefined) record.updatedAt = json['updatedAt'] as number;
    if (json['sourceName'] !== undefined) record.sourceName = json['sourceName'] as string;
    if (json['entryKind'] !== undefined) record.entryKind = HistoryRecord.normalizeEntryKind(String(json['entryKind']));
    if (json['episodePageUrl'] !== undefined) record.episodePageUrl = String(json['episodePageUrl']);
    if (json['bangumiItemJSON'] !== undefined) record.bangumiItemJSON = String(json['bangumiItemJSON']);
    record.readProgresses(json['progresses']);
    record.ensureCurrentProgress();
    return record;
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    result['id'] = this.id;
    result['animeId'] = this.animeId;
    result['animeName'] = this.animeName;
    result['animeCover'] = this.animeCover;
    result['animeUrl'] = this.animeUrl;
    result['bangumiId'] = this.bangumiId;
    result['sourceId'] = this.sourceId;
    result['episodeName'] = this.episodeName;
    result['episodeUrl'] = this.episodeUrl;
    result['positionMs'] = this.positionMs;
    result['durationMs'] = this.durationMs;
    result['roadIndex'] = this.roadIndex;
    result['episodeIndex'] = this.episodeIndex;
    result['updatedAt'] = this.updatedAt;
    result['sourceName'] = this.sourceName;
    result['entryKind'] = this.entryKind;
    result['episodePageUrl'] = this.episodePageUrl;
    result['progresses'] = this.progressesToJSON();
    result['bangumiItemJSON'] = this.bangumiItemJSON;
    return result;
  }

  static normalizeEntryKind(value: string): string {
    return value === 'offline' ? 'offline' : 'online';
  }

  ensureCurrentProgress(): void {
    if (this.episodeIndex < 0) return;
    const episode = this.episodeIndex + 1;
    if (this.progresses.has(episode)) return;
    this.updateCurrentProgress();
  }

  updateCurrentProgress(): void {
    if (this.episodeIndex < 0) return;
    const episode = this.episodeIndex + 1;
    const progress = new HistoryEpisodeProgress();
    progress.episode = episode;
    progress.road = this.roadIndex >= 0 ? this.roadIndex : 0;
    progress.progressMs = Math.max(0, this.positionMs);
    progress.updatedAtMs = this.updatedAt > 0 ? this.updatedAt : Date.now();
    this.progresses.set(episode, progress);
  }

  mergeProgressesFrom(source: HistoryRecord): void {
    const episodes = Array.from(source.progresses.keys());
    for (let i = 0; i < episodes.length; i++) {
      const incoming = source.progresses.get(episodes[i]);
      if (incoming === undefined) continue;
      const existing = this.progresses.get(episodes[i]);
      if (existing === undefined || incoming.updatedAtMs > existing.updatedAtMs) {
        this.progresses.set(episodes[i], incoming.clone());
      }
    }
  }

  progressesToJSONString(): string {
    return JSON.stringify(this.progressesToJSON());
  }

  readProgressesJSON(text: string): void {
    if (text.trim().length === 0) return;
    try {
      this.readProgresses(JSON.parse(text) as Record<string, Object>);
    } catch (_err) {
      this.progresses.clear();
    }
  }

  private readProgresses(value: Object | undefined): void {
    if (value === undefined || value === null) return;
    const json = value as Record<string, Object>;
    const keys = Object.keys(json);
    for (let i = 0; i < keys.length; i++) {
      const item = json[keys[i]];
      if (item === undefined || item === null) continue;
      const progress = HistoryEpisodeProgress.fromJSON(item as Record<string, Object>);
      const episodeFromKey = Number(keys[i]);
      const episode = Number.isFinite(episodeFromKey) ? episodeFromKey : progress.episode;
      if (episode <= 0) continue;
      progress.episode = episode;
      this.progresses.set(episode, progress);
    }
  }

  private progressesToJSON(): Record<string, Object> {
    const result: Record<string, Object> = {};
    const episodes = Array.from(this.progresses.keys());
    episodes.sort((a: number, b: number) => a - b);
    for (let i = 0; i < episodes.length; i++) {
      const progress = this.progresses.get(episodes[i]);
      if (progress !== undefined) result[String(episodes[i])] = progress.toJSON();
    }
    return result;
  }

}
