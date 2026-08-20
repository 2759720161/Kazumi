import { bundleManager, common, wantAgent, WantAgent } from '@kit.AbilityKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('BackgroundDownloadService')
const DATA_TRANSFER_MODE = 'dataTransfer'
const DOWNLOAD_LIVE_VIEW_TYPE_CODE = 8
const PROGRESS_UPDATE_INTERVAL_MS = 1000
const DOWNLOAD_NOTIFICATION_BASE_ID = 7300

export type BackgroundDownloadCancelledHandler = () => void

export class BackgroundDownloadService {
  private static instance: BackgroundDownloadService | null = null
  private readonly activeTaskIds: Set<string> = new Set()
  private context: common.UIAbilityContext | null = null
  private notificationId: number = 0
  private startingPromise: Promise<void> | null = null
  private lastProgressUpdateAt: number = 0
  private cancellationHandler: BackgroundDownloadCancelledHandler | null = null
  private cancellationSubscribed: boolean = false

  static getInstance(): BackgroundDownloadService {
    if (BackgroundDownloadService.instance === null) {
      BackgroundDownloadService.instance = new BackgroundDownloadService()
    }
    return BackgroundDownloadService.instance
  }

  setCancellationHandler(handler: BackgroundDownloadCancelledHandler): void {
    this.cancellationHandler = handler
    this.subscribeCancellation()
  }

  async acquire(context: common.UIAbilityContext, taskId: string, title: string): Promise<void> {
    this.context = context
    this.activeTaskIds.add(taskId)
    if (this.notificationId > 0) {
      this.updateProgress(taskId, title, 0)
      return
    }
    if (this.startingPromise === null) {
      this.startingPromise = this.startBackgroundTask(context)
    }
    try {
      await this.startingPromise
    } finally {
      this.startingPromise = null
    }
    if (this.activeTaskIds.has(taskId)) {
      this.updateProgress(taskId, title, 0)
    } else if (this.activeTaskIds.size === 0) {
      await this.stopBackgroundTask()
    }
  }

  async release(taskId: string): Promise<void> {
    this.activeTaskIds.delete(taskId)
    if (this.activeTaskIds.size > 0) {
      return
    }
    if (this.startingPromise !== null) {
      try {
        await this.startingPromise
      } catch (_err) {
      }
    }
    if (this.activeTaskIds.size === 0) {
      await this.stopBackgroundTask()
    }
  }

  updateProgress(taskId: string, title: string, percent: number): void {
    if (this.notificationId <= 0) {
      return
    }
    const normalizedPercent = Math.max(0, Math.min(100, Math.floor(percent)))
    const now = Date.now()
    if (normalizedPercent > 0 && normalizedPercent < 100 &&
      now - this.lastProgressUpdateAt < PROGRESS_UPDATE_INTERVAL_MS) {
      return
    }
    this.lastProgressUpdateAt = now
    this.publishProgress(taskId, title, normalizedPercent)
  }

  publishPaused(taskId: string, title: string, percent: number): void {
    this.publishPausedNotification(taskId, title, percent).catch((err: Object): void => {
      logger.warn('发布暂停通知失败: %{public}s', err instanceof Error ? err.message : String(err))
    })
  }

  cancelTaskNotification(taskId: string): void {
    notificationManager.cancel(this.getTaskNotificationId(taskId)).catch((_err: Object): void => {
    })
  }

  private async startBackgroundTask(context: common.UIAbilityContext): Promise<void> {
    try {
      const bundleName = this.getBundleName()
      if (bundleName.length === 0) {
        throw new Error('无法获取应用包名')
      }
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: bundleName,
          abilityName: 'EntryAbility',
          parameters: {
            downloadAction: 'open'
          }
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 7201,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      const agent: WantAgent = await wantAgent.getWantAgent(info)
      const result = await backgroundTaskManager.startBackgroundRunning(context, [DATA_TRANSFER_MODE], agent)
      this.notificationId = result.notificationId
      logger.info('下载长时任务已启动: notificationId=%{public}d', this.notificationId)
    } catch (err) {
      this.notificationId = 0
      logger.warn('启动下载长时任务失败，下载将仅在前台可靠运行: %{public}s',
        err instanceof Error ? err.message : String(err))
    }
  }

  private async stopBackgroundTask(): Promise<void> {
    const context = this.context
    if (context === null || this.notificationId <= 0) {
      return
    }
    this.notificationId = 0
    this.lastProgressUpdateAt = 0
    try {
      await backgroundTaskManager.stopBackgroundRunning(context)
      logger.info('下载长时任务已停止')
    } catch (err) {
      logger.warn('停止下载长时任务失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async publishProgress(taskId: string, title: string, percent: number): Promise<void> {
    const data: Record<string, Object> = {}
    data['title'] = title.length > 0 ? title : 'Kazumi 视频'
    data['fileName'] = title.length > 0 ? title : '视频下载'
    data['progressValue'] = percent
    const template: notificationManager.NotificationTemplate = {
      name: 'downloadTemplate',
      data: data
    }
    const openAgent = await this.createActionAgent(taskId, 'open', 1)
    const pauseAgent = await this.createActionAgent(taskId, 'pause', 2)
    const cancelAgent = await this.createActionAgent(taskId, 'cancel', 3)
    const request: notificationManager.NotificationRequest = {
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          typeCode: DOWNLOAD_LIVE_VIEW_TYPE_CODE,
          title: '视频下载',
          text: title + ' · ' + String(percent) + '%'
        }
      },
      id: this.notificationId,
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      template: template,
      updateOnly: true,
      wantAgent: openAgent,
      tapDismissed: false,
      actionButtons: [{ title: '暂停', wantAgent: pauseAgent }, { title: '取消', wantAgent: cancelAgent }]
    }
    await notificationManager.publish(request).catch((err: Object) => {
      logger.warn('更新下载进度通知失败: %{public}s', err instanceof Error ? err.message : String(err))
    })
  }

  private async publishPausedNotification(taskId: string, title: string, percent: number): Promise<void> {
    const openAgent = await this.createActionAgent(taskId, 'open', 4)
    const resumeAgent = await this.createActionAgent(taskId, 'resume', 5)
    const cancelAgent = await this.createActionAgent(taskId, 'cancel', 6)
    const request: notificationManager.NotificationRequest = {
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '下载已暂停',
          text: title + ' · ' + String(Math.max(0, Math.min(100, percent))) + '%'
        }
      },
      id: this.getTaskNotificationId(taskId),
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      wantAgent: openAgent,
      tapDismissed: false,
      isAlertOnce: true,
      actionButtons: [{ title: '继续', wantAgent: resumeAgent }, { title: '取消', wantAgent: cancelAgent }]
    }
    await notificationManager.publish(request)
  }

  private async createActionAgent(taskId: string, action: string, actionCode: number): Promise<WantAgent> {
    const bundleName = this.getBundleName()
    if (bundleName.length === 0) {
      throw new Error('无法获取应用包名')
    }
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          downloadAction: action,
          downloadTaskId: taskId
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.getTaskNotificationId(taskId) * 10 + actionCode,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return await wantAgent.getWantAgent(info)
  }

  private getTaskNotificationId(taskId: string): number {
    let hash = 0
    for (let i = 0; i < taskId.length; i++) {
      hash = (hash * 31 + taskId.charCodeAt(i)) & 0x7FFFFFFF
    }
    return DOWNLOAD_NOTIFICATION_BASE_ID + hash % 100000
  }

  private subscribeCancellation(): void {
    if (this.cancellationSubscribed) {
      return
    }
    try {
      backgroundTaskManager.on('continuousTaskCancel',
        (_info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
          this.notificationId = 0
          this.lastProgressUpdateAt = 0
          if (this.activeTaskIds.size === 0) {
            return
          }
          this.activeTaskIds.clear()
          if (this.cancellationHandler !== null) {
            this.cancellationHandler()
          }
        })
      this.cancellationSubscribed = true
    } catch (err) {
      logger.warn('监听下载长时任务取消事件失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private getBundleName(): string {
    try {
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      return bundleManager.getBundleInfoForSelfSync(flags).name
    } catch (_err) {
      return ''
    }
  }
}
