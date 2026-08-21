export const HOME_PRELOAD_ENABLED_KEY: string = 'homeBackgroundPreloadEnabled'

export function setHomePreloadEnabled(enabled: boolean): void {
  AppStorage.setOrCreate(HOME_PRELOAD_ENABLED_KEY, enabled)
}

export function isHomePreloadEnabled(): boolean {
  return AppStorage.get<boolean>(HOME_PRELOAD_ENABLED_KEY) !== false
}
