import { RecommendCardModel } from '../models/RecommendCardModel'

export enum RecommendSectionType {
  TRENDING = 'trending',
  SEASONAL = 'seasonal',
  HIGH_SCORE = 'highScore'
}

export class RecommendSectionCache {
  private static sections: Map<string, RecommendCardModel[]> = new Map()

  static set(sectionType: RecommendSectionType, items: RecommendCardModel[]): void {
    const cached: RecommendCardModel[] = []
    for (let i = 0; i < items.length; i++) {
      cached.push(RecommendCardModel.copyOf(items[i]))
    }
    RecommendSectionCache.sections.set(sectionType, cached)
  }

  static get(sectionType: RecommendSectionType): RecommendCardModel[] {
    const cached = RecommendSectionCache.sections.get(sectionType) ?? []
    const result: RecommendCardModel[] = []
    for (let i = 0; i < cached.length; i++) {
      result.push(RecommendCardModel.copyOf(cached[i]))
    }
    return result
  }
}
