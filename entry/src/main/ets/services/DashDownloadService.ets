import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { VideoDownloadSnapshot } from '../models/VideoDownloadTask'
import { DrmOfflineLicenseService } from './DrmOfflineLicenseService'
import { NativeRemuxService } from './NativeRemuxService'

export type DashProgressCallback = (isLive: boolean, videoTracks: number,
  audioTracks: number, subtitleTracks: number) => void

class DashInspection {
  isLive: boolean = false
  videoTracks: number = 0
  audioTracks: number = 0
  subtitleTracks: number = 0
  drmScheme: string = ''
  pssh: Uint8Array = new Uint8Array(0)
  licenseUrl: string = ''
}

export class DashDownloadService {
  private readonly remuxer: NativeRemuxService = new NativeRemuxService()
  private readonly drmService: DrmOfflineLicenseService = new DrmOfflineLicenseService()

  async start(snapshot: VideoDownloadSnapshot, progress: DashProgressCallback): Promise<string> {
    const manifest = await this.fetchManifest(snapshot.sourceUrl, snapshot.headers)
    const inspection = this.inspect(manifest, snapshot.drmScheme)
    snapshot.isLive = inspection.isLive
    snapshot.videoTrackCount = inspection.videoTracks
    snapshot.audioTrackCount = inspection.audioTracks
    snapshot.subtitleTrackCount = inspection.subtitleTracks
    progress(inspection.isLive, inspection.videoTracks, inspection.audioTracks, inspection.subtitleTracks)
    if (inspection.drmScheme.length > 0 && snapshot.drmOfflineKeyId.length === 0) {
      const license = await this.drmService.acquire(
        snapshot.drmScheme.length > 0 ? snapshot.drmScheme : inspection.drmScheme,
        inspection.pssh, 'video/mp4',
        snapshot.drmLicenseUrl.length > 0 ? snapshot.drmLicenseUrl : inspection.licenseUrl,
        Object.keys(snapshot.drmHeaders).length > 0 ? snapshot.drmHeaders : snapshot.headers)
      snapshot.drmScheme = license.schemeUuid
      snapshot.drmOfflineKeyId = license.mediaKeyIdBase64
      snapshot.drmPluginName = license.pluginName
      progress(inspection.isLive, inspection.videoTracks, inspection.audioTracks, inspection.subtitleTracks)
    }
    return await this.remuxer.remux(snapshot.taskId, snapshot.sourceUrl,
      snapshot.targetDirectory + '/video.mp4', snapshot.headers)
  }

  pause(taskId: string): void { this.remuxer.pause(taskId) }
  resume(taskId: string): void { this.remuxer.resume(taskId) }
  cancel(taskId: string): void { this.remuxer.cancel(taskId) }
  finish(taskId: string): void { this.remuxer.finish(taskId) }
  isRunning(taskId: string): boolean { return this.remuxer.isRunning(taskId) }

  private async fetchManifest(url: string, headers: Record<string, string>): Promise<string> {
    const client = http.createHttp()
    try {
      const result = await client.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        maxLimit: 4 * 1024 * 1024
      })
      if (result.responseCode < 200 || result.responseCode >= 300) {
        throw new Error('MPD 请求失败：HTTP ' + String(result.responseCode))
      }
      if (typeof result.result !== 'string' || result.result.indexOf('<MPD') < 0) {
        throw new Error('资源不是有效的 DASH/MPD 清单')
      }
      return result.result
    } finally {
      client.destroy()
    }
  }

  private inspect(manifest: string, preferredDrmScheme: string = ''): DashInspection {
    const info = new DashInspection()
    const mpdTag = this.firstMatch(manifest, /<MPD\b([^>]*)>/i)
    info.isLive = /\btype\s*=\s*["']dynamic["']/i.test(mpdTag)
    const sets = manifest.match(/<AdaptationSet\b[\s\S]*?<\/AdaptationSet\s*>/gi) || []
    for (let i = 0; i < sets.length; i++) {
      const setText = sets[i].toLowerCase()
      if (setText.indexOf('video') >= 0) info.videoTracks++
      else if (setText.indexOf('audio') >= 0) info.audioTracks++
      else if (setText.indexOf('text') >= 0 || setText.indexOf('subtitle') >= 0 ||
        setText.indexOf('application') >= 0) {
        info.subtitleTracks++
      }
    }
    const protection = manifest.match(/<ContentProtection\b[^>]*(?:\/>|>[\s\S]*?<\/ContentProtection\s*>)/gi) || []
    let selectedProtectionPriority = 0
    let preferredMarker = preferredDrmScheme.toLowerCase()
    if (preferredMarker.indexOf('widevine') >= 0) preferredMarker = 'edef8ba9'
    if (preferredMarker.indexOf('playready') >= 0) preferredMarker = '9a04f079'
    for (let i = 0; i < protection.length; i++) {
      const scheme = this.attribute(protection[i], 'schemeIdUri')
      let psshText = this.firstMatch(protection[i],
        /<(?:cenc:)?pssh\b[^>]*>([\s\S]*?)<\/(?:cenc:)?pssh\s*>/i)
      if (psshText.length === 0) {
        psshText = this.firstMatch(protection[i], /<(?:mspr:)?pro\b[^>]*>([\s\S]*?)<\/(?:mspr:)?pro\s*>/i)
      }
      if (psshText.length === 0) continue
      const normalizedScheme = scheme.toLowerCase()
      let priority = normalizedScheme.indexOf('edef8ba9') >= 0 || normalizedScheme.indexOf('9a04f079') >= 0 ? 2 : 1
      if (preferredMarker.length > 0 && normalizedScheme.indexOf(preferredMarker) >= 0) priority += 10
      if (priority < selectedProtectionPriority) continue
      info.drmScheme = scheme
      info.pssh = new util.Base64Helper().decodeSync(psshText.replace(/\s/g, ''))
      selectedProtectionPriority = priority
    }
    const licenseTag = this.firstMatch(manifest,
      /<(?:ms:laurl|dashif:Laurl|Laurl)\b([^>]*)>(?:[\s\S]*?<\/(?:ms:laurl|dashif:Laurl|Laurl)\s*>)?/i)
    info.licenseUrl = this.attribute(licenseTag, 'licenseUrl')
    if (info.licenseUrl.length === 0) info.licenseUrl = this.attribute(licenseTag, 'href')
    if (info.licenseUrl.length === 0) {
      info.licenseUrl = this.firstMatch(manifest,
        /<(?:ms:laurl|dashif:Laurl|Laurl)\b[^>]*>\s*([^<\s][^<]*?)\s*<\//i)
    }
    return info
  }

  private firstMatch(value: string, expression: RegExp): string {
    const match = expression.exec(value)
    return match !== null && match.length > 1 ? match[1].trim() : ''
  }

  private attribute(value: string, name: string): string {
    const expression = new RegExp('\\b' + name + '\\s*=\\s*["\\\']([^"\\\']*)["\\\']', 'i')
    return this.firstMatch(value, expression)
  }
}
