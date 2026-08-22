import mpvNapi from 'libmpv_napi.so'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('NativeRemuxService')
const MPV_EVENT_SHUTDOWN = 1
const MPV_EVENT_LOG_MESSAGE = 2
const MPV_EVENT_END_FILE = 7
const MAX_DIAGNOSTIC_LINES = 8

interface MpvBridgeEvent {
  eventId: number
  errorCode: number
  reason: number
  logPrefix: string
  logLevel: string
  logText: string
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
  diagnosticLines: string[] = []
}

export class NativeRemuxService {
  private readonly controls: Map<string, RemuxControl> = new Map()

  async remux(taskId: string, input: string, outputPath: string,
    headers: Record<string, string> = {}): Promise<string> {
    const napi = mpvNapi as MpvBridge
    const control = new RemuxControl()
    const inputPath = this.normalizeInputPath(input)
    this.validateLocalInput(inputPath)
    this.validateOutputDirectory(outputPath)
    this.controls.set(taskId, control)
    this.removeFile(outputPath)
    const contextId = napi.nativeCreate()
    let completed = false
    control.contextId = contextId
    if (contextId < 0) {
      this.controls.delete(taskId)
      throw new Error('原生转封装器创建失败')
    }
    try {
      this.requireOk(napi.nativeSetProperty(contextId, 'vo', 'null'), '设置无画面模式')
      this.requireOk(napi.nativeSetProperty(contextId, 'ao', 'null'), '设置无音频输出模式')
      this.requireOk(napi.nativeSetProperty(contextId, 'idle', 'yes'), '设置转封装空闲模式')
      this.requireOk(napi.nativeSetProperty(contextId, 'speed', '100'), '设置转封装加速')
      this.requireOk(napi.nativeSetProperty(contextId, 'msg-level',
        'cplayer=info,demuxer=debug,stream=debug,ffmpeg=debug'), '设置转封装日志级别')
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
          if (event.eventId === MPV_EVENT_LOG_MESSAGE) {
            const fatalMessage = this.handleLogMessage(taskId, control, event)
            if (fatalMessage.length > 0) {
              napi.nativeCommandAsync(contextId, ['stop'])
              finish(new Error('原生转封装失败：' + fatalMessage))
            }
          } else if (event.eventId === MPV_EVENT_END_FILE) {
            if (control.cancelled) {
              finish(new Error('下载已取消'))
            } else if (control.finishing) {
              finish(null)
            } else if (event.errorCode < 0) {
              finish(new Error(this.buildRemuxError(event.errorCode, control)))
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
        logger.info('开始原生转封装: task=%{public}s input=%{public}s output=%{public}s',
          taskId, inputPath, outputPath)
        const loadResult = napi.nativeCommand(contextId, ['loadfile', inputPath, 'replace'])
        if (loadResult < 0) {
          finish(new Error(this.buildRemuxError(loadResult, control)))
        }
      })
      if (!fileIo.accessSync(outputPath) || fileIo.statSync(outputPath).size <= 0) {
        throw new Error('转封装没有生成有效 MP4 文件')
      }
      logger.info('原生转封装完成: task=%{public}s', taskId)
      completed = true
      return new fileUri.FileUri(outputPath).toString()
    } finally {
      try { napi.nativeDestroy(contextId) } catch (_err) {}
      if (!completed) this.removeFile(outputPath)
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

  private normalizeInputPath(input: string): string {
    if (!input.toLowerCase().startsWith('file://')) {
      return input
    }
    try {
      return new fileUri.FileUri(input).path
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      throw new Error('无法解析本地转封装路径：' + message)
    }
  }

  private validateLocalInput(inputPath: string): void {
    if (this.hasUriScheme(inputPath)) {
      return
    }
    try {
      if (!fileIo.accessSync(inputPath)) {
        throw new Error('本地 HLS 清单不存在')
      }
      const stat = fileIo.statSync(inputPath)
      if (!stat.isFile() || stat.size <= 0) {
        throw new Error('本地 HLS 清单为空或不是文件')
      }
      logger.info('原生转封装输入预检通过: size=%{public}d path=%{public}s', stat.size, inputPath)
    } catch (err) {
      if (err instanceof Error && err.message.indexOf('本地 HLS 清单') === 0) {
        throw err
      }
      throw new Error('无法读取本地 HLS 清单：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private validateOutputDirectory(outputPath: string): void {
    const slashIndex = outputPath.lastIndexOf('/')
    if (slashIndex <= 0) {
      throw new Error('转封装输出路径无效')
    }
    const directory = outputPath.substring(0, slashIndex)
    try {
      if (!fileIo.accessSync(directory) || !fileIo.statSync(directory).isDirectory()) {
        throw new Error('转封装输出目录不存在')
      }
    } catch (err) {
      if (err instanceof Error && err.message === '转封装输出目录不存在') {
        throw err
      }
      throw new Error('无法访问转封装输出目录：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private hasUriScheme(value: string): boolean {
    const schemeIndex = value.indexOf('://')
    return schemeIndex > 0
  }

  private handleLogMessage(taskId: string, control: RemuxControl, event: MpvBridgeEvent): string {
    const rawText = event.logText.replace(/[\r\n]+/g, ' ').trim()
    if (rawText.length === 0) {
      return ''
    }
    const text = rawText.length > 600 ? rawText.substring(0, 600) : rawText
    const prefix = event.logPrefix.length > 0 ? event.logPrefix : 'mpv'
    const level = event.logLevel.length > 0 ? event.logLevel : 'info'
    if (level === 'fatal' || level === 'error' || level === 'warn') {
      const line = '[' + prefix + '/' + level + '] ' + text
      control.diagnosticLines.push(line)
      if (control.diagnosticLines.length > MAX_DIAGNOSTIC_LINES) {
        control.diagnosticLines.shift()
      }
    }
    if (level === 'fatal' || level === 'error') {
      logger.error('原生转封装日志: task=%{public}s [%{public}s/%{public}s] %{public}s',
        taskId, prefix, level, text)
    } else if (level === 'warn') {
      logger.warn('原生转封装日志: task=%{public}s [%{public}s/%{public}s] %{public}s',
        taskId, prefix, level, text)
    } else if (prefix === 'cplayer' || prefix === 'demuxer' || prefix === 'stream' || prefix === 'ffmpeg') {
      logger.info('原生转封装日志: task=%{public}s [%{public}s/%{public}s] %{public}s',
        taskId, prefix, level, text)
    }
    if (level === 'error' && prefix === 'recorder' && text.indexOf('Failed writing packet') >= 0) {
      return 'MP4 写入失败，媒体时间戳不连续'
    }
    if (level === 'error' && text.indexOf('non monotonically increasing dts') >= 0) {
      return 'MP4 时间戳不连续，无法继续写入'
    }
    return ''
  }

  private buildRemuxError(errorCode: number, control: RemuxControl): string {
    let message = '原生转封装失败，错误码 ' + String(errorCode)
    if (errorCode === -13) {
      message += '（媒体源加载失败）'
    } else if (errorCode === -16) {
      message += '（没有可转封装的音视频轨道）'
    } else if (errorCode === -17) {
      message += '（无法识别媒体格式）'
    } else if (errorCode === -18) {
      message += '（当前媒体格式不受支持）'
    }
    if (control.diagnosticLines.length > 0) {
      message += '：' + control.diagnosticLines[control.diagnosticLines.length - 1]
    }
    return message
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
