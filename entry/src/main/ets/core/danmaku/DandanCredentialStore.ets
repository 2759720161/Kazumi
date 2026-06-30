import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { BUILTIN_DANDAN_APP_ID, BUILTIN_DANDAN_APP_SECRET } from './DandanBuiltinCredentials'

const logger = new Logger('DandanCredentialStore')

const PREFS_KEY_APP_ID = 'dandan_app_id'
const PREFS_KEY_APP_SECRET = 'dandan_app_secret'

export class DandanCredentialStore {
  private appId: string = ''
  private appSecret: string = ''
  private initialized: boolean = false

  private static instance: DandanCredentialStore | null = null

  private constructor() {}

  static getInstance(): DandanCredentialStore {
    if (DandanCredentialStore.instance === null) {
      DandanCredentialStore.instance = new DandanCredentialStore()
    }
    return DandanCredentialStore.instance
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return
    }
    try {
      const prefs = PreferencesStore.getInstance()
      this.appId = await prefs.getString(PREFS_KEY_APP_ID, '')
      this.appSecret = await prefs.getString(PREFS_KEY_APP_SECRET, '')
      this.initialized = true
      logger.info('凭据初始化完成, appId=%{public}s, appSecret=***',
        this.appId.length > 0 ? '已配置' : '未配置')
    } catch (_err) {
      logger.error('凭据读取失败, 使用空凭据')
      this.appId = ''
      this.appSecret = ''
      this.initialized = true
    }
  }

  hasCredentials(): boolean {
    return this.getEffectiveAppId().length > 0 && this.getEffectiveAppSecret().length > 0
  }

  getAppId(): string {
    return this.getEffectiveAppId()
  }

  getAppSecret(): string {
    return this.getEffectiveAppSecret()
  }

  hasUserCredentials(): boolean {
    return this.appId.length > 0 && this.appSecret.length > 0
  }

  async setCredentials(appId: string, appSecret: string): Promise<void> {
    this.appId = appId
    this.appSecret = appSecret
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString(PREFS_KEY_APP_ID, appId)
      await prefs.setString(PREFS_KEY_APP_SECRET, appSecret)
      this.initialized = true
      logger.info('凭据已更新, appId=%{public}s, hasCredentials=%{public}s',
        appId.length > 0 ? '已配置' : '未配置', String(this.hasCredentials()))
    } catch (_err) {
      logger.error('凭据持久化失败')
    }
  }

  async clearCredentials(): Promise<void> {
    this.appId = ''
    this.appSecret = ''
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.delete(PREFS_KEY_APP_ID)
      await prefs.delete(PREFS_KEY_APP_SECRET)
      logger.info('凭据已清除')
    } catch (_err) {
      logger.error('凭据清除失败')
    }
  }

  private getEffectiveAppId(): string {
    return this.appId.length > 0 ? this.appId : BUILTIN_DANDAN_APP_ID
  }

  private getEffectiveAppSecret(): string {
    return this.appSecret.length > 0 ? this.appSecret : BUILTIN_DANDAN_APP_SECRET
  }
}
