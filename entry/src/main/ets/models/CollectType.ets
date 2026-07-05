export class CollectType {
  static readonly none: number = 0
  static readonly favorite: number = 1
  static readonly watching: number = 1
  static readonly planToWatch: number = 1
  static readonly onHold: number = 1
  static readonly watched: number = 1
  static readonly abandoned: number = 1

  static getLabel(type: number): string {
    if (CollectType.isFavorite(type)) return '已收藏'
    return '未收藏'
  }

  static getIcon(type: number): Resource {
    if (CollectType.isFavorite(type)) return $r('sys.symbol.heart_fill')
    return $r('sys.symbol.heart')
  }

  static isValid(type: number): boolean {
    return type >= CollectType.none
  }

  static isFavorite(type: number): boolean {
    return type > CollectType.none
  }

  static normalize(type: number): number {
    return CollectType.isFavorite(type) ? CollectType.favorite : CollectType.none
  }
}
