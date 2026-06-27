export class RuleCatalogItem {
  name: string = ''
  version: string = ''
  useNativePlayer: boolean = false
  author: string = ''
  lastUpdate: number = 0
  antiCrawlerEnabled: boolean = false

  static fromJSON(json: Record<string, Object>): RuleCatalogItem {
    const item = new RuleCatalogItem()
    if (json['name'] !== undefined) item.name = json['name'] as string
    if (json['version'] !== undefined) item.version = json['version'] as string
    if (json['useNativePlayer'] !== undefined) item.useNativePlayer = json['useNativePlayer'] as boolean
    if (json['author'] !== undefined) item.author = json['author'] as string
    if (json['lastUpdate'] !== undefined) item.lastUpdate = json['lastUpdate'] as number
    if (json['antiCrawlerEnabled'] !== undefined) item.antiCrawlerEnabled = json['antiCrawlerEnabled'] as boolean
    return item
  }
}
