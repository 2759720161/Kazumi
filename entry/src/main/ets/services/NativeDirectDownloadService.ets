import { http } from '@kit.NetworkKit'
import { fileIo } from '@kit.CoreFileKit'
import { Logger } from '../utils/Logger'

const logger = new Logger('NativeDirectDownloadService')
const MAX_RETRIES = 3

class DirectRuntimeControl {
  paused: boolean = false
  cancelled: boolean = false
  requests: http.HttpRequest[] = []
}

export type DirectDownloadProgressCallback = (processedBytes: number, totalBytes: number) => void

/**
 * App-owned resumable downloader for direct HTTP resources.
 * It is used when request.agent cannot reattach to a task after a process restart.
 */
export class NativeDirectDownloadService {
  private readonly controls: Map<string, DirectRuntimeControl> = new Map()

  async start(taskId: string, url: string, path: string, headers: Record<string, string>,
    onProgress: DirectDownloadProgressCallback): Promise<number> {
    this.cancel(taskId)
    const control = new DirectRuntimeControl()
    this.controls.set(taskId, control)
    const tempPath = path + '.resume'
    let existingBytes = this.preparePartialFile(path, tempPath)
    let lastError = ''
    try {
      for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        this.ensureActive(control)
        try {
          return await this.downloadOnce(url, tempPath, headers, existingBytes, control, onProgress)
        } catch (err) {
          lastError = err instanceof Error ? err.message : String(err)
          if (lastError === 'RESET_PARTIAL' && existingBytes > 0) {
            this.removeFile(tempPath)
            existingBytes = 0
            continue
          }
          this.ensureActive(control)
          if (attempt < MAX_RETRIES - 1) {
            await this.delay([1000, 3000, 9000][attempt])
            if (fileIo.accessSync(tempPath)) {
              existingBytes = fileIo.statSync(tempPath).size
            }
          }
        }
      }
      throw new Error('直链下载失败：' + lastError)
    } finally {
      if (this.controls.get(taskId) === control) {
        this.controls.delete(taskId)
      }
    }
  }

  pause(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined) return
    control.paused = true
    this.abortRequests(control)
  }

  cancel(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined) return
    control.cancelled = true
    this.abortRequests(control)
    this.controls.delete(taskId)
  }

  release(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control !== undefined) {
      this.abortRequests(control)
      this.controls.delete(taskId)
    }
  }

  isRunning(taskId: string): boolean {
    return this.controls.has(taskId)
  }

  private async downloadOnce(url: string, tempPath: string, sourceHeaders: Record<string, string>,
    existingBytes: number, control: DirectRuntimeControl,
    onProgress: DirectDownloadProgressCallback): Promise<number> {
    const openMode = existingBytes > 0 ?
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY :
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    const target = fileIo.openSync(tempPath, openMode)
    const request = http.createHttp()
    const requestHeaders = this.copyHeaders(sourceHeaders)
    if (existingBytes > 0) {
      requestHeaders['Range'] = 'bytes=' + String(existingBytes) + '-'
    }
    let receivedBytes = 0
    let responseTotal = -1
    const receive = (data: ArrayBuffer): void => {
      // A cancelled request can still deliver one queued data event. Never
      // throw from an event callback: an uncaught callback exception crashes
      // the ArkTS process instead of reaching the request promise catch path.
      if (control.cancelled || control.paused) return
      try {
        fileIo.writeSync(target.fd, data, { offset: existingBytes + receivedBytes })
        receivedBytes += data.byteLength
        const total = responseTotal > 0 ? existingBytes + responseTotal : -1
        onProgress(existingBytes + receivedBytes, total)
      } catch (err) {
        logger.warn('写入直链下载数据失败: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    const receiveProgress = (info: http.DataReceiveProgressInfo): void => {
      if (control.cancelled || control.paused) return
      if (info.totalSize > 0) responseTotal = info.totalSize
      const total = responseTotal > 0 ? existingBytes + responseTotal : -1
      try {
        onProgress(existingBytes + receivedBytes, total)
      } catch (err) {
        logger.warn('更新直链下载进度失败: %{public}s', err instanceof Error ? err.message : String(err))
      }
    }
    request.on('dataReceive', receive)
    request.on('dataReceiveProgress', receiveProgress)
    control.requests.push(request)
    try {
      const status = await request.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: requestHeaders,
        connectTimeout: 15000,
        readTimeout: 120000
      })
      this.ensureActive(control)
      if (existingBytes > 0 && status !== 206) {
        throw new Error('RESET_PARTIAL')
      }
      if (status < 200 || status >= 300) {
        throw new Error('HTTP ' + String(status))
      }
    } finally {
      request.off('dataReceive', receive)
      request.off('dataReceiveProgress', receiveProgress)
      const index = control.requests.indexOf(request)
      if (index >= 0) control.requests.splice(index, 1)
      request.destroy()
      fileIo.closeSync(target)
    }
    const finalSize = existingBytes + receivedBytes
    if (finalSize <= 0) throw new Error('服务器返回空内容')
    fileIo.renameSync(tempPath, tempPath.substring(0, tempPath.length - '.resume'.length))
    onProgress(finalSize, responseTotal > 0 ? existingBytes + responseTotal : finalSize)
    return finalSize
  }

  private preparePartialFile(path: string, tempPath: string): number {
    try {
      if (fileIo.accessSync(tempPath)) {
        return fileIo.statSync(tempPath).size
      }
      if (fileIo.accessSync(path)) {
        const size = fileIo.statSync(path).size
        if (size > 0) {
          fileIo.renameSync(path, tempPath)
          return size
        }
        fileIo.unlinkSync(path)
      }
    } catch (err) {
      logger.warn('准备直链断点文件失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
    return 0
  }

  private ensureActive(control: DirectRuntimeControl): void {
    if (control.cancelled) throw new Error('CANCELLED')
    if (control.paused) throw new Error('PAUSED')
  }

  private abortRequests(control: DirectRuntimeControl): void {
    const requests = control.requests.slice()
    control.requests.length = 0
    for (let i = 0; i < requests.length; i++) {
      try {
        requests[i].destroy()
      } catch (_err) {
      }
    }
  }

  private copyHeaders(source: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {}
    const keys = Object.keys(source)
    for (let i = 0; i < keys.length; i++) result[keys[i]] = source[keys[i]]
    return result
  }

  private removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) fileIo.unlinkSync(path)
    } catch (_err) {
    }
  }

  private async delay(milliseconds: number): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds)
    })
  }
}
