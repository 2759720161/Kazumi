import { IPlayerEngine } from './IPlayerEngine'
import { AVPlayerEngine } from './AVPlayerEngine'
import { isMpvNapiLoaded, MpvPlayerEngine } from './MpvPlayerEngine'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('PlayerEngineFactory')

export type EngineType = 'avplayer' | 'mpv'

export class PlayerEngineFactory {
  private static readonly PREFS_KEY_MPV_CRASH_DETECTED: string = 'mpv_crash_detected'

  static async create(): Promise<IPlayerEngine> {
    const prefs = PreferencesStore.getInstance()
    const engineType = await prefs.getString('defaultPlayerEngine', 'avplayer')
    return PlayerEngineFactory.createWithFallback(engineType)
  }

  static createByType(engineType: string): IPlayerEngine {
    switch (engineType) {
      case 'mpv':
        if (!PlayerEngineFactory.isMpvNapiAvailableSync()) {
          logger.warn('mpv NAPI module not available, falling back to AVPlayer')
          return new AVPlayerEngine()
        }
        logger.info('Creating mpv engine')
        return new MpvPlayerEngine()
      case 'avplayer':
        logger.info('Creating AVPlayer engine')
        return new AVPlayerEngine()
      default:
        logger.info('Unknown engine type %{public}s, falling back to AVPlayer', engineType)
        return new AVPlayerEngine()
    }
  }

  static async createWithFallback(engineType: string): Promise<IPlayerEngine> {
    if (engineType === 'mpv') {
      const crashDetected = await PlayerEngineFactory.isMpvCrashDetected()
      if (crashDetected) {
        logger.warn('mpv crash previously detected, falling back to avplayer')
        return new AVPlayerEngine()
      }
      if (!PlayerEngineFactory.isMpvNapiAvailableSync()) {
        logger.warn('mpv NAPI module not available, falling back to avplayer')
        return new AVPlayerEngine()
      }
      logger.info('Creating mpv engine')
      return new MpvPlayerEngine()
    }
    return new AVPlayerEngine()
  }

  static getAvailableEngines(): string[] {
    const engines: string[] = ['avplayer']
    if (PlayerEngineFactory.isMpvNapiAvailableSync()) {
      engines.push('mpv')
    }
    return engines
  }

  static isMpvNapiAvailableSync(): boolean {
    const available = isMpvNapiLoaded()
    logger.info('mpv NAPI module availability: %{public}s', String(available))
    return available
  }

  static async isMpvCrashDetected(): Promise<boolean> {
    const prefs = PreferencesStore.getInstance()
    return await prefs.getBoolean(PlayerEngineFactory.PREFS_KEY_MPV_CRASH_DETECTED, false)
  }

  static async reportMpvCrash(): Promise<void> {
    const prefs = PreferencesStore.getInstance()
    await prefs.setBoolean(PlayerEngineFactory.PREFS_KEY_MPV_CRASH_DETECTED, true)
    await prefs.setString('defaultPlayerEngine', 'avplayer')
    logger.error('mpv crash reported, engine disabled and set to avplayer')
  }

  static async clearMpvCrashFlag(): Promise<void> {
    const prefs = PreferencesStore.getInstance()
    await prefs.setBoolean(PlayerEngineFactory.PREFS_KEY_MPV_CRASH_DETECTED, false)
    logger.info('mpv crash flag cleared')
  }
}
