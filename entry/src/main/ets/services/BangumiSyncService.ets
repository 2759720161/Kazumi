import { UIContext } from '@kit.ArkUI'
import { BangumiCollectionApi, BangumiSyncProgress } from '../core/api/BangumiCollectionApi'
import { BangumiSyncConfig, BangumiSyncProtocol } from '../models/BangumiSync'
import { PreferencesStore } from '../store/PreferencesStore'
import { FavoriteStore } from '../store/FavoriteStore'
import { CollectChangeStore } from '../store/CollectChangeStore'
import { CollectChangeSignal } from '../store/CollectChangeSignal'
import { RdbManager } from '../store/RdbManager'

const CONFIG_KEY: string = 'bangumi_sync_config'

export class BangumiSyncService {
  private static instance: BangumiSyncService = new BangumiSyncService()
  private queue: Promise<void> = Promise.resolve()
  private pending: number = 0

  static getInstance(): BangumiSyncService {
    return BangumiSyncService.instance
  }

  isBusy(): boolean {
    return this.pending > 0
  }

  async getConfig(): Promise<BangumiSyncConfig> {
    const text = await PreferencesStore.getInstance().getString(CONFIG_KEY, '')
    const config = new BangumiSyncConfig()
    if (text.length === 0) return config
    const data = JSON.parse(text) as Record<string, Object>
    config.enabled = data['enabled'] === true
    config.token = typeof data['token'] === 'string' ? (data['token'] as string).trim() : ''
    config.immediateToast = data['immediateToast'] !== false
    config.priority = data['priority'] === 1 ? 1 : 0
    return config
  }

  private async saveConfig(config: BangumiSyncConfig): Promise<void> {
    await PreferencesStore.getInstance().setStringOrThrow(CONFIG_KEY, JSON.stringify(config))
    AppStorage.setOrCreate('bangumiSyncEnabled', config.enabled)
    AppStorage.set<boolean>('bangumiSyncEnabled', config.enabled)
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (this.isBusy()) throw new Error('Bangumi 正在处理收藏，请稍后重试')
    return this.runCollectOperation(async () => {
      const config = await this.getConfig()
      if (enabled) await new BangumiCollectionApi(config.token).getUsername()
      config.enabled = enabled
      await this.saveConfig(config)
    })
  }

  async saveAndVerify(token: string): Promise<string> {
    if (this.isBusy()) throw new Error('Bangumi 正在处理收藏，请稍后重试')
    let username = ''
    await this.runCollectOperation(async () => {
      const config = await this.getConfig()
      config.token = token.trim()
      if (config.enabled && config.token.length === 0) throw new Error('Access Token 不能为空')
      await this.saveConfig(config)
      try {
        username = await new BangumiCollectionApi(config.token).getUsername()
      } catch (err) {
        config.enabled = false
        await this.saveConfig(config)
        throw new Error(err instanceof Error ? err.message : 'Bangumi 验证失败')
      }
    })
    return username
  }

  async setOptions(immediateToast: boolean, priority: number): Promise<void> {
    return this.runCollectOperation(async () => {
      const config = await this.getConfig()
      config.immediateToast = immediateToast
      config.priority = priority === 1 ? 1 : 0
      await this.saveConfig(config)
    })
  }

  // Controller mutations share the queue with full sync so network waits cannot overwrite a newer local edit.
  runCollectOperation(action: () => Promise<void>): Promise<void> {
    this.pending++
    const operation = this.queue.then(action)
    this.queue = operation.then(() => { this.pending-- }, () => { this.pending-- })
    return operation
  }

  // Called inside runCollectOperation, before starting a local database transaction.
  async syncBeforeLocalChange(id: number, type: number, uiContext?: UIContext): Promise<void> {
    if (id <= 0) return
    const config = await this.getConfig()
    if (!config.enabled) return
    if (config.immediateToast) this.showToast(uiContext, '正在同步到 Bangumi…')
    try {
      await new BangumiCollectionApi(config.token).updateCollection(id, type)
      if (config.immediateToast) this.showToast(uiContext, '已同步到 Bangumi')
    } catch (err) {
      const message = '同步到 Bangumi 失败，已取消本次状态修改：' +
        (err instanceof Error ? err.message : '网络异常')
      this.showToast(uiContext, message)
      throw new Error(message)
    }
  }

  private showToast(uiContext: UIContext | undefined, message: string): void {
    try {
      uiContext?.getPromptAction().showToast({ message: message })
    } catch (err) {
      // A page can disappear during a request. Its toast must not interrupt the database write.
    }
  }

  async syncNow(progress?: BangumiSyncProgress): Promise<number> {
    if (this.isBusy()) throw new Error('Bangumi 正在处理收藏，请稍后重试')
    let changes = 0
    await this.runCollectOperation(async () => {
      const config = await this.getConfig()
      if (!config.enabled) throw new Error('请先开启 Bangumi 同步')
      const api = new BangumiCollectionApi(config.token)
      progress?.('正在验证 Bangumi 账号', 0, 0)
      const username = await api.getUsername()
      const remote = await api.getCollections(username, progress)
      const store = new FavoriteStore()
      const changeStore = new CollectChangeStore()
      const plan = BangumiSyncProtocol.plan(await store.getAllCollected(), remote, config.priority)
      const total = plan.uploads.length + plan.downloads.length
      for (let i = 0; i < plan.uploads.length; i++) {
        progress?.('正在上传本地状态', changes, total)
        await api.updateCollection(plan.uploads[i].bangumiId, plan.uploads[i].collectType)
        changes++
        progress?.('正在上传本地状态', changes, total)
      }
      const rdb = RdbManager.getInstance()
      let localChanged = false
      try {
        for (let i = 0; i < plan.downloads.length; i++) {
          const item = plan.downloads[i]
          const existing = await store.getCollectedByBangumiId(item.bangumiId)
          rdb.beginTransaction()
          try {
            if (existing === null) await store.addCollected(item)
            else await store.updateCollectType(existing.animeId, item.collectType)
            await changeStore.appendChange(item.bangumiId, existing === null ? 1 : 2, item.collectType)
            rdb.commit()
          } catch (err) {
            rdb.rollBack()
            throw new Error(err instanceof Error ? err.message : '保存收藏失败')
          }
          localChanged = true
          changes++
          progress?.('正在更新本地状态', changes, total)
        }
      } finally {
        if (localChanged) CollectChangeSignal.notifyChanged()
      }
      progress?.(total === 0 ? '未发现状态差异，无需同步' : 'Bangumi 状态同步完成', 1, 1)
    })
    return changes
  }
}
