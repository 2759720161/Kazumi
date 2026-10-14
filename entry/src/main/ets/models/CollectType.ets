export class CollectType {
  static readonly none: number = 0
  static readonly watching: number = 1
  static readonly planToWatch: number = 2
  static readonly onHold: number = 3
  static readonly watched: number = 4
  static readonly abandoned: number = 5

  // 保留旧调用名，默认收藏行为与上游一致地归入“在看”。
  static readonly favorite: number = CollectType.watching

  static getLabel(type: number): string {
    switch (CollectType.normalize(type)) {
      case CollectType.watching:
        return '在看'
      case CollectType.planToWatch:
        return '想看'
      case CollectType.onHold:
        return '搁置'
      case CollectType.watched:
        return '看过'
      case CollectType.abandoned:
        return '抛弃'
      default:
        return '未追'
    }
  }

  static getIcon(type: number): Resource {
    switch (CollectType.normalize(type)) {
      case CollectType.watching:
        return $r('sys.symbol.heart_fill')
      case CollectType.planToWatch:
        return $r('sys.symbol.clock')
      case CollectType.onHold:
        return $r('sys.symbol.pause_fill')
      case CollectType.watched:
        return $r('sys.symbol.checkmark_circle_fill')
      case CollectType.abandoned:
        return $r('sys.symbol.heart_slash')
      default:
        return $r('sys.symbol.heart')
    }
  }

  static isValid(type: number): boolean {
    return type >= CollectType.none && type <= CollectType.abandoned
  }

  static isFavorite(type: number): boolean {
    return CollectType.isValid(type) && type !== CollectType.none
  }

  static normalize(type: number): number {
    return CollectType.isValid(type) ? type : CollectType.none
  }
}
