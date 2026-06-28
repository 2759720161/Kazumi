export class CollectType {
  static readonly none: number = 0
  static readonly watching: number = 1
  static readonly planToWatch: number = 2
  static readonly onHold: number = 3
  static readonly watched: number = 4
  static readonly abandoned: number = 5

  static getLabel(type: number): string {
    if (type === CollectType.watching) return '在看'
    if (type === CollectType.planToWatch) return '想看'
    if (type === CollectType.onHold) return '搁置'
    if (type === CollectType.watched) return '看过'
    if (type === CollectType.abandoned) return '抛弃'
    return '未收藏'
  }

  static getIcon(type: number): Resource {
    if (type === CollectType.watching) return $r('sys.symbol.media_center')
    if (type === CollectType.planToWatch) return $r('sys.symbol.star')
    if (type === CollectType.onHold) return $r('sys.symbol.timer')
    if (type === CollectType.watched) return $r('sys.symbol.checkmark')
    if (type === CollectType.abandoned) return $r('sys.symbol.heart_slash')
    return $r('sys.symbol.heart')
  }

  static isValid(type: number): boolean {
    return type >= CollectType.none && type <= CollectType.abandoned
  }
}