export class CollectedBangumi {
  id: number = -1
  animeId: string = ''
  bangumiId: number = -1
  animeName: string = ''
  animeCover: string = ''
  bangumiCover: string = ''
  coverFallback: string = ''
  animeDesc: string = ''
  animeUrl: string = ''
  sourceName: string = ''
  sourceId: number = -1
  collectType: number = 1
  createdAt: number = 0

  getBestCover(): string {
    if (this.bangumiCover.length > 0) return this.bangumiCover
    if (this.animeCover.length > 0) return this.animeCover
    return this.coverFallback
  }

  getKey(): string {
    return this.animeId
  }

  static fromJSON(json: Record<string, Object>): CollectedBangumi {
    const item = new CollectedBangumi()
    if (json['id'] !== undefined) item.id = json['id'] as number
    if (json['animeId'] !== undefined) item.animeId = json['animeId'] as string
    if (json['bangumiId'] !== undefined) item.bangumiId = json['bangumiId'] as number
    if (json['animeName'] !== undefined) item.animeName = json['animeName'] as string
    if (json['animeCover'] !== undefined) item.animeCover = json['animeCover'] as string
    if (json['bangumiCover'] !== undefined) item.bangumiCover = json['bangumiCover'] as string
    if (json['coverFallback'] !== undefined) item.coverFallback = json['coverFallback'] as string
    if (json['animeDesc'] !== undefined) item.animeDesc = json['animeDesc'] as string
    if (json['animeUrl'] !== undefined) item.animeUrl = json['animeUrl'] as string
    if (json['sourceName'] !== undefined) item.sourceName = json['sourceName'] as string
    if (json['sourceId'] !== undefined) item.sourceId = json['sourceId'] as number
    if (json['collectType'] !== undefined) item.collectType = json['collectType'] as number
    if (json['createdAt'] !== undefined) item.createdAt = json['createdAt'] as number
    return item
  }

  toJSON(): Record<string, Object> {
    const result: Record<string, Object> = {}
    result['id'] = this.id
    result['animeId'] = this.animeId
    result['bangumiId'] = this.bangumiId
    result['animeName'] = this.animeName
    result['animeCover'] = this.animeCover
    result['bangumiCover'] = this.bangumiCover
    result['coverFallback'] = this.coverFallback
    result['animeDesc'] = this.animeDesc
    result['animeUrl'] = this.animeUrl
    result['sourceName'] = this.sourceName
    result['sourceId'] = this.sourceId
    result['collectType'] = this.collectType
    result['createdAt'] = this.createdAt
    return result
  }
}