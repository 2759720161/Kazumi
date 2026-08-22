export const HOME_PRELOAD_ENABLED_KEY: string = 'homeBackgroundPreloadEnabled'
export const HOME_PRELOAD_MODE_KEY: string = 'homeBackgroundPreloadMode'
export const HOME_PRELOAD_MODE_SECTIONS: string = 'sections'
export const HOME_PRELOAD_MODE_TOPIC: string = 'topic'
export const HOME_PRELOAD_GROUP_GENERAL: string = 'general'
export const HOME_PRELOAD_GROUP_SECTIONS: string = 'sections'
export const HOME_PRELOAD_GROUP_TOPIC: string = 'topic'

export function setHomePreloadEnabled(enabled: boolean): void {
  AppStorage.setOrCreate(HOME_PRELOAD_ENABLED_KEY, enabled)
}

export function isHomePreloadEnabled(): boolean {
  return AppStorage.get<boolean>(HOME_PRELOAD_ENABLED_KEY) !== false
}

export function setHomePreloadMode(mode: string): void {
  AppStorage.setOrCreate(HOME_PRELOAD_MODE_KEY, mode)
}
