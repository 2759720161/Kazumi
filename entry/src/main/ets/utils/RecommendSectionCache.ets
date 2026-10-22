import { RecommendCardModel } from '../models/RecommendCardModel'
import { ImageNetworkSettings } from '../store/ImageNetworkSettings'

export enum RecommendSectionType {
  TRENDING = 'trending',
  SEASONAL = 'seasonal',
  HIGH_SCORE = 'highScore'
}

export class RecommendSectionCache {
  private static sections: Map<string, RecommendCardModel[]> = new Map()
  private static networkVersion: number = -1

  private static syncNetworkConfig(): void {
    const version = ImageNetworkSettings.getVersion()
    if (RecommendSectionCache.networkVersion !== version) {
      RecommendSectionCache.networkVersion = version
      RecommendSectionCache.sections.clear()
    }
  }

  static set(sectionType: RecommendSectionType, items: RecommendCardModel[]): void {
    RecommendSectionCache.syncNetworkConfig()
    const cached: RecommendCardModel[] = []
    for (let i = 0; i < items.length; i++) {
      cached.push(RecommendCardModel.copyOf(items[i]))
    }
    RecommendSectionCache.sections.set(sectionType, cached)
  }

  static get(sectionType: RecommendSectionType): RecommendCardModel[] {
    RecommendSectionCache.syncNetworkConfig()
    const cached = RecommendSectionCache.sections.get(sectionType) ?? []
    const result: RecommendCardModel[] = []
    for (let i = 0; i < cached.length; i++) {
      result.push(RecommendCardModel.copyOf(cached[i]))
    }
    return result
  }
}
