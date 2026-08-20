import mpvNapi from 'libmpv_napi.so'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('NativeRemuxService')
const MPV_EVENT_SHUTDOWN = 1
const MPV_EVENT_END_FILE = 7

interface MpvBridgeEvent {
  eventId: number
  errorCode: number
  reason: number
}

interface MpvBridge {
  nativeCreate(): number
  nativeInitialize(ctxId: number): number
  nativeCommand(ctxId: number, args: string[]): number
  nativeCommandAsync(ctxId: number, args: string[]): number
  nativeSetProperty(ctxId: number, name: string, value: string): number
  nativeDestroy(ctxId: number): void
  nativeOnEvent(ctxId: number, callback: (event: MpvBridgeEvent) => void): number
}

class RemuxControl {
  contextId: number = -1
  paused: boolean = false
  cancelled: boolean = false
  finishing: boolean = false
}

export class NativeRemuxService {
  private readonly controls: Map<string, RemuxControl> = new Map()

  async remux(taskId: string, input: string, outputPath: string,
    headers: Record<string, string> = {}): Promise<string> {
    const napi = mpvNapi as MpvBridge
    const control = new RemuxControl()
    this.controls.set(taskId, control)
    this.removeFile(outputPath)
    const contextId = napi.nativeCreate()
    control.contextId = contextId
    if (contextId < 0) {
      this.controls.delete(taskId)
      throw new Error('原生转封装器创建失败')
    }
    try {
      this.requireOk(napi.nativeSetProperty(contextId, 'vo', 'null'), '设置无画面模式')
      this.requireOk(napi.nativeSetProperty(contextId, 'ao', 'null'), '设置无音频输出模式')
      this.requireOk(napi.nativeSetProperty(contextId, 'idle', 'yes'), '设置转封装空闲模式')
      this.requireOk(napi.nativeSetProperty(contextId, 'stream-record', outputPath), '设置 MP4 输出')
      const headerText = this.buildHeaderText(headers)
      if (headerText.length > 0) {
        this.requireOk(napi.nativeSetProperty(contextId, 'http-header-fields', headerText), '设置媒体请求头')
      }
      this.requireOk(napi.nativeInitialize(contextId), '初始化原生转封装器')
      await new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
        let settled = false
        const finish = (err: Error | null): void => {
          if (settled) return
          settled = true
          if (err === null) {
            resolve()
          } else {
            reject(err)
          }
        }
        const eventResult = napi.nativeOnEvent(contextId, (event: MpvBridgeEvent): void => {
          if (event.eventId === MPV_EVENT_END_FILE) {
            if (control.cancelled) {
              finish(new Error('下载已取消'))
            } else if (control.finishing) {
              finish(null)
            } else if (event.errorCode < 0) {
              finish(new Error('原生转封装失败，错误码 ' + String(event.errorCode)))
            } else {
              finish(null)
            }
          } else if (event.eventId === MPV_EVENT_SHUTDOWN) {
            finish(control.cancelled ? new Error('下载已取消') : new Error('原生转封装器异常退出'))
          }
        })
        if (eventResult < 0) {
          finish(new Error('监听原生转封装状态失败'))
          return
        }
        const loadResult = napi.nativeCommand(contextId, ['loadfile', input, 'replace'])
        if (loadResult < 0) {
          finish(new Error('原生媒体源加载失败，错误码 ' + String(loadResult)))
        }
      })
      if (!fileIo.accessSync(outputPath) || fileIo.statSync(outputPath).size <= 0) {
        throw new Error('转封装没有生成有效 MP4 文件')
      }
      logger.info('原生转封装完成: task=%{public}s', taskId)
      return new fileUri.FileUri(outputPath).toString()
    } finally {
      try { napi.nativeDestroy(contextId) } catch (_err) {}
      if (this.controls.get(taskId) === control) this.controls.delete(taskId)
    }
  }

  pause(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined || control.contextId < 0) return
    control.paused = true
    const napi = mpvNapi as MpvBridge
    napi.nativeCommandAsync(control.contextId, ['set', 'pause', 'yes'])
  }

  resume(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined || control.contextId < 0) return
    control.paused = false
    const napi = mpvNapi as MpvBridge
    napi.nativeCommandAsync(control.contextId, ['set', 'pause', 'no'])
  }

  isRunning(taskId: string): boolean { return this.controls.has(taskId) }

  cancel(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined || control.contextId < 0) return
    control.cancelled = true
    const napi = mpvNapi as MpvBridge
    napi.nativeCommandAsync(control.contextId, ['stop'])
  }

  finish(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined || control.contextId < 0) throw new Error('原生录制任务当前未运行')
    control.finishing = true
    control.paused = false
    const napi = mpvNapi as MpvBridge
    napi.nativeCommandAsync(control.contextId, ['set', 'pause', 'no'])
    napi.nativeCommandAsync(control.contextId, ['stop'])
  }

  private requireOk(result: number, action: string): void {
    if (result < 0) throw new Error(action + '失败，错误码 ' + String(result))
  }

  private buildHeaderText(headers: Record<string, string>): string {
    const lines: string[] = []
    const keys = Object.keys(headers)
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === 'host') continue
      lines.push(keys[i] + ': ' + headers[keys[i]].replace(/[\r\n]/g, ''))
    }
    return lines.join(',')
  }

  private removeFile(path: string): void {
    try { if (fileIo.accessSync(path)) fileIo.unlinkSync(path) } catch (_err) {}
  }
}
