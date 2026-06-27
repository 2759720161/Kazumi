export const COLLECT_VERSION_KEY = 'collectVersion'

export class CollectChangeSignal {
  private static version: number = 0

  static notifyChanged(): void {
    const now = Date.now()
    CollectChangeSignal.version = Math.max(CollectChangeSignal.version + 1, now)
    if (!AppStorage.set<number>(COLLECT_VERSION_KEY, CollectChangeSignal.version)) {
      AppStorage.setOrCreate<number>(COLLECT_VERSION_KEY, CollectChangeSignal.version)
    }
  }
}
