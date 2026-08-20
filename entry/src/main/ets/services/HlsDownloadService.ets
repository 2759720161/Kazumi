import { http } from '@kit.NetworkKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { VideoDownloadSnapshot } from '../models/VideoDownloadTask'
import { Logger } from '../utils/Logger'

const logger = new Logger('HlsDownloadService')
const MAX_MANIFEST_DEPTH = 3
const MAX_SEGMENT_CONCURRENCY = 4
const MAX_RETRIES = 3
const HLS_DIRECTORY_MARKER = '.kazumi-hls'
const HLS_PLAN_FINGERPRINT_FILE = '.kazumi-hls-plan'

class HlsByteRange {
  start: number = -1
  length: number = 0

  toHeader(): string {
    if (this.start < 0 || this.length <= 0) {
      return ''
    }
    return 'bytes=' + String(this.start) + '-' + String(this.start + this.length - 1)
  }
}

class HlsResource {
  url: string = ''
  localFile: string = ''
  range: HlsByteRange | null = null
}

class HlsKeyDirective {
  method: string = ''
  url: string = ''
  iv: string = ''
  localFile: string = ''
}

class HlsMapDirective {
  url: string = ''
  localFile: string = ''
  range: HlsByteRange | null = null
}

class HlsSegment {
  sequence: number = 0
  url: string = ''
  localFile: string = ''
  duration: number = 0
  title: string = ''
  discontinuity: boolean = false
  range: HlsByteRange | null = null
  key: HlsKeyDirective | null = null
  map: HlsMapDirective | null = null
}

class HlsDownloadPlan {
  targetDuration: number = 1
  mediaSequence: number = 0
  segments: HlsSegment[] = []
  resources: HlsResource[] = []
  hasEndList: boolean = false
  sourceUrl: string = ''
  isIFrameOnly: boolean = false
}

class HlsVariantSelection {
  url: string = ''
  attributes: Record<string, string> = {}
}

class HlsRenditionPlan {
  type: string = ''
  groupId: string = ''
  name: string = ''
  language: string = ''
  defaultValue: string = 'NO'
  autoSelect: string = 'NO'
  forced: string = 'NO'
  characteristics: string = ''
  channels: string = ''
  sourceUrl: string = ''
  localPlaylistFile: string = ''
  plan: HlsDownloadPlan = new HlsDownloadPlan()
}

class HlsDownloadBundle {
  hasMasterPlaylist: boolean = false
  variant: HlsVariantSelection = new HlsVariantSelection()
  videoPlan: HlsDownloadPlan = new HlsDownloadPlan()
  renditions: HlsRenditionPlan[] = []
}

class HlsRuntimeControl {
  paused: boolean = false
  cancelled: boolean = false
  finishing: boolean = false
  failed: boolean = false
  requests: http.HttpRequest[] = []
}

export type HlsProgressCallback = (completedSegments: number, totalSegments: number, totalBytes: number) => void

export class HlsDownloadService {
  private readonly controls: Map<string, HlsRuntimeControl> = new Map()

  async start(snapshot: VideoDownloadSnapshot, progressCallback: HlsProgressCallback): Promise<string> {
    const control = new HlsRuntimeControl()
    this.controls.set(snapshot.taskId, control)
    this.ensureManagedDirectory(snapshot.targetDirectory)

    const bundle = await this.loadBundle(snapshot.sourceUrl, snapshot.headers, control)
    if (bundle.videoPlan.segments.length === 0) {
      throw new Error('M3U8 中未找到可下载的媒体分片')
    }
    snapshot.audioTrackCount = this.countRenditions(bundle, 'AUDIO')
    snapshot.subtitleTrackCount = this.countRenditions(bundle, 'SUBTITLES')
    snapshot.videoTrackCount = 1 + this.countRenditions(bundle, 'VIDEO')
    snapshot.iframeTrackCount = this.countRenditions(bundle, 'IFRAME')
    snapshot.isLive = !bundle.videoPlan.hasEndList
    if (snapshot.isLive) this.restoreExistingLiveTimeline(snapshot.targetDirectory, bundle)
    this.ensurePlanFingerprint(snapshot.targetDirectory, this.buildBundleFingerprint(bundle), snapshot.isLive)
    const plans: HlsDownloadPlan[] = [bundle.videoPlan]
    for (let i = 0; i < bundle.renditions.length; i++) {
      plans.push(bundle.renditions[i].plan)
    }
    const allSegments: HlsSegment[] = []
    for (let i = 0; i < plans.length; i++) {
      for (let j = 0; j < plans[i].segments.length; j++) {
        allSegments.push(plans[i].segments[j])
      }
    }
    snapshot.totalSegments = allSegments.length
    let completed = 0
    let totalBytes = 0
    for (let i = 0; i < allSegments.length; i++) {
      const path = snapshot.targetDirectory + '/' + allSegments[i].localFile
      if (this.isCompleteFile(path, allSegments[i].range)) {
        completed++
        totalBytes += fileIo.statSync(path).size
      }
    }
    progressCallback(completed, allSegments.length, totalBytes)

    for (let i = 0; i < plans.length; i++) {
      for (let j = 0; j < plans[i].resources.length; j++) {
        this.ensureActive(control)
        const resource = plans[i].resources[j]
        const path = snapshot.targetDirectory + '/' + resource.localFile
        if (!this.isCompleteFile(path, resource.range)) {
          await this.downloadWithRetry(resource.url, path, snapshot.headers, resource.range, control)
        }
      }
    }

    let nextIndex = 0
    const worker = async (): Promise<void> => {
      while (true) {
        this.ensureActive(control as HlsRuntimeControl)
        const index = nextIndex
        nextIndex++
        if (index >= allSegments.length) {
          return
        }
        const segment = allSegments[index]
        const path = snapshot.targetDirectory + '/' + segment.localFile
        if (this.isCompleteFile(path, segment.range)) {
          continue
        }
        let bytes = 0
        try {
          bytes = await this.downloadWithRetry(segment.url, path, snapshot.headers, segment.range,
            control as HlsRuntimeControl)
        } catch (err) {
          control.failed = true
          this.abortRequests(control as HlsRuntimeControl)
          throw new Error(err instanceof Error ? err.message : String(err))
        }
        completed++
        totalBytes += bytes
        progressCallback(completed, allSegments.length, totalBytes)
      }
    }

    const workers: Promise<void>[] = []
    const workerCount = Math.min(MAX_SEGMENT_CONCURRENCY, allSegments.length)
    for (let i = 0; i < workerCount; i++) {
      workers.push(worker())
    }
    await this.waitForWorkers(workers)
    this.ensureActive(control)

    const playlistPath = snapshot.targetDirectory + '/playlist.m3u8'
    if (bundle.hasMasterPlaylist) {
      this.writeTextFile(snapshot.targetDirectory + '/video.m3u8', this.buildLocalPlaylist(bundle.videoPlan))
      for (let i = 0; i < bundle.renditions.length; i++) {
        const rendition = bundle.renditions[i]
        this.writeTextFile(snapshot.targetDirectory + '/' + rendition.localPlaylistFile,
          this.buildLocalPlaylist(rendition.plan))
      }
      this.writeTextFile(playlistPath, this.buildLocalMasterPlaylist(bundle))
    } else {
      this.writeTextFile(playlistPath, this.buildLocalPlaylist(bundle.videoPlan))
    }
    while (!bundle.videoPlan.hasEndList && !control.finishing) {
      this.ensureActive(control)
      await this.delay(Math.max(1000, bundle.videoPlan.targetDuration * 1000))
      const fresh = await this.loadBundle(snapshot.sourceUrl, snapshot.headers, control)
      const added = await this.mergeAndDownloadFreshBundle(snapshot, bundle, fresh, control,
        (bytes: number): void => {
          completed++
          totalBytes += bytes
          snapshot.totalSegments = this.countBundleSegments(bundle)
          progressCallback(completed, snapshot.totalSegments, totalBytes)
        })
      snapshot.totalSegments = this.countBundleSegments(bundle)
      if (added === 0) {
        progressCallback(completed, snapshot.totalSegments, totalBytes)
      }
      this.writeBundlePlaylists(snapshot.targetDirectory, playlistPath, bundle)
    }
    if (control.finishing) {
      bundle.videoPlan.hasEndList = true
      for (let i = 0; i < bundle.renditions.length; i++) bundle.renditions[i].plan.hasEndList = true
      this.writeBundlePlaylists(snapshot.targetDirectory, playlistPath, bundle)
    }
    snapshot.isLive = false
    if (this.controls.get(snapshot.taskId) === control) {
      this.controls.delete(snapshot.taskId)
    }
    logger.info('HLS下载完成: task=%{public}s segments=%{public}d tracks=%{public}d',
      snapshot.taskId, allSegments.length, bundle.renditions.length)
    return new fileUri.FileUri(playlistPath).toString()
  }

  pause(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined) {
      return
    }
    control.paused = true
    this.abortRequests(control)
  }

  cancel(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined) {
      return
    }
    control.cancelled = true
    this.abortRequests(control)
    this.controls.delete(taskId)
  }

  finish(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control === undefined) throw new Error('直播下载任务当前未运行')
    control.finishing = true
    control.paused = false
  }

  release(taskId: string): void {
    const control = this.controls.get(taskId)
    if (control !== undefined) {
      this.abortRequests(control)
      this.controls.delete(taskId)
    }
  }

  private async mergeAndDownloadFreshBundle(snapshot: VideoDownloadSnapshot, current: HlsDownloadBundle,
    fresh: HlsDownloadBundle, control: HlsRuntimeControl, onSegment: (bytes: number) => void): Promise<number> {
    let added = await this.mergeAndDownloadPlan(snapshot, current.videoPlan, fresh.videoPlan, control, onSegment)
    for (let i = 0; i < fresh.renditions.length; i++) {
      const incoming = fresh.renditions[i]
      const incomingPlan = incoming.plan
      let existing: HlsRenditionPlan | null = null
      for (let j = 0; j < current.renditions.length; j++) {
        const candidate = current.renditions[j]
        if (candidate.type === incoming.type && candidate.groupId === incoming.groupId &&
          candidate.name === incoming.name && candidate.sourceUrl === incoming.sourceUrl) {
          existing = candidate
          break
        }
      }
      if (existing === null) {
        const empty = new HlsDownloadPlan()
        empty.sourceUrl = incomingPlan.sourceUrl
        incoming.plan = empty
        current.renditions.push(incoming)
        existing = incoming
      }
      added += await this.mergeAndDownloadPlan(snapshot, existing.plan, incomingPlan,
        control, onSegment)
    }
    current.videoPlan.hasEndList = fresh.videoPlan.hasEndList
    current.variant = fresh.variant
    current.hasMasterPlaylist = fresh.hasMasterPlaylist
    snapshot.audioTrackCount = this.countRenditions(current, 'AUDIO')
    snapshot.subtitleTrackCount = this.countRenditions(current, 'SUBTITLES')
    snapshot.videoTrackCount = 1 + this.countRenditions(current, 'VIDEO')
    snapshot.iframeTrackCount = this.countRenditions(current, 'IFRAME')
    return added
  }

  private async mergeAndDownloadPlan(snapshot: VideoDownloadSnapshot, current: HlsDownloadPlan,
    fresh: HlsDownloadPlan, control: HlsRuntimeControl, onSegment: (bytes: number) => void): Promise<number> {
    for (let i = 0; i < fresh.resources.length; i++) {
      const resource = fresh.resources[i]
      let found = false
      for (let j = 0; j < current.resources.length; j++) {
        if (current.resources[j].localFile === resource.localFile) {
          found = true
          break
        }
      }
      if (!found) current.resources.push(resource)
      const path = snapshot.targetDirectory + '/' + resource.localFile
      if (!this.isCompleteFile(path, resource.range)) {
        await this.downloadWithRetry(resource.url, path, snapshot.headers, resource.range, control)
      }
    }
    let added = 0
    for (let i = 0; i < fresh.segments.length; i++) {
      const segment = fresh.segments[i]
      let found = false
      for (let j = 0; j < current.segments.length; j++) {
        if (current.segments[j].sequence === segment.sequence &&
          current.segments[j].localFile === segment.localFile) {
          found = true
          break
        }
      }
      if (found) continue
      current.segments.push(segment)
      const bytes = await this.downloadWithRetry(segment.url, snapshot.targetDirectory + '/' + segment.localFile,
        snapshot.headers, segment.range, control)
      added++
      onSegment(bytes)
    }
    current.hasEndList = fresh.hasEndList
    if (current.sourceUrl.length === 0) current.sourceUrl = fresh.sourceUrl
    return added
  }

  private writeBundlePlaylists(directory: string, playlistPath: string, bundle: HlsDownloadBundle): void {
    if (bundle.hasMasterPlaylist) {
      this.writeTextFile(directory + '/video.m3u8', this.buildLocalPlaylist(bundle.videoPlan))
      for (let i = 0; i < bundle.renditions.length; i++) {
        this.writeTextFile(directory + '/' + bundle.renditions[i].localPlaylistFile,
          this.buildLocalPlaylist(bundle.renditions[i].plan))
      }
      this.writeTextFile(playlistPath, this.buildLocalMasterPlaylist(bundle))
    } else {
      this.writeTextFile(playlistPath, this.buildLocalPlaylist(bundle.videoPlan))
    }
  }

  private countBundleSegments(bundle: HlsDownloadBundle): number {
    let count = bundle.videoPlan.segments.length
    for (let i = 0; i < bundle.renditions.length; i++) count += bundle.renditions[i].plan.segments.length
    return count
  }

  private restoreExistingLiveTimeline(directory: string, bundle: HlsDownloadBundle): void {
    const videoFile = bundle.hasMasterPlaylist ? 'video.m3u8' : 'playlist.m3u8'
    const existingVideo = this.readExistingLocalPlan(directory + '/' + videoFile)
    if (existingVideo !== null) bundle.videoPlan = this.combineExistingPlan(existingVideo, bundle.videoPlan)
    for (let i = 0; i < bundle.renditions.length; i++) {
      const existing = this.readExistingLocalPlan(directory + '/' + bundle.renditions[i].localPlaylistFile)
      if (existing !== null) bundle.renditions[i].plan = this.combineExistingPlan(existing,
        bundle.renditions[i].plan)
    }
  }

  private combineExistingPlan(existing: HlsDownloadPlan, fresh: HlsDownloadPlan): HlsDownloadPlan {
    for (let i = 0; i < fresh.resources.length; i++) existing.resources.push(fresh.resources[i])
    for (let i = 0; i < fresh.segments.length; i++) {
      let found = false
      for (let j = 0; j < existing.segments.length; j++) {
        if (existing.segments[j].sequence === fresh.segments[i].sequence &&
          existing.segments[j].localFile === fresh.segments[i].localFile) {
          found = true
          break
        }
      }
      if (!found) existing.segments.push(fresh.segments[i])
    }
    existing.targetDuration = Math.max(existing.targetDuration, fresh.targetDuration)
    existing.hasEndList = fresh.hasEndList
    existing.sourceUrl = fresh.sourceUrl
    existing.isIFrameOnly = existing.isIFrameOnly || fresh.isIFrameOnly
    return existing
  }

  private readExistingLocalPlan(path: string): HlsDownloadPlan | null {
    if (!fileIo.accessSync(path)) return null
    const plan = new HlsDownloadPlan()
    const lines = fileIo.readTextSync(path).split(/\r?\n/)
    let duration = 0
    let title = ''
    let key: HlsKeyDirective | null = null
    let map: HlsMapDirective | null = null
    let discontinuity = false
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.indexOf('#EXT-X-TARGETDURATION:') === 0) {
        plan.targetDuration = Math.max(1, this.parsePositiveInt(line.substring('#EXT-X-TARGETDURATION:'.length)))
      } else if (line.indexOf('#EXT-X-MEDIA-SEQUENCE:') === 0) {
        plan.mediaSequence = this.parsePositiveInt(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length))
      } else if (line.indexOf('#EXT-X-I-FRAMES-ONLY') === 0) {
        plan.isIFrameOnly = true
      } else if (line.indexOf('#EXT-X-ENDLIST') === 0) {
        plan.hasEndList = true
      } else if (line.indexOf('#EXT-X-DISCONTINUITY') === 0) {
        discontinuity = true
      } else if (line.indexOf('#EXT-X-KEY:') === 0) {
        const attrs = this.parseAttributes(line.substring('#EXT-X-KEY:'.length))
        if ((attrs['METHOD'] || '').toUpperCase() === 'NONE') {
          key = null
        } else {
          key = new HlsKeyDirective()
          key.method = attrs['METHOD'] || ''
          key.iv = attrs['IV'] || ''
          key.localFile = attrs['URI'] || ''
        }
      } else if (line.indexOf('#EXT-X-MAP:') === 0) {
        const attrs = this.parseAttributes(line.substring('#EXT-X-MAP:'.length))
        map = new HlsMapDirective()
        map.localFile = attrs['URI'] || ''
      } else if (line.indexOf('#EXTINF:') === 0) {
        const value = line.substring('#EXTINF:'.length)
        const comma = value.indexOf(',')
        duration = parseFloat(comma >= 0 ? value.substring(0, comma) : value)
        if (isNaN(duration)) duration = 0
        title = comma >= 0 ? value.substring(comma + 1) : ''
      } else if (line.length > 0 && line.charAt(0) !== '#') {
        const segment = new HlsSegment()
        segment.sequence = plan.mediaSequence + plan.segments.length
        segment.localFile = line
        segment.url = line
        segment.duration = duration
        segment.title = title
        segment.key = key
        segment.map = map
        segment.discontinuity = discontinuity
        plan.segments.push(segment)
        duration = 0
        title = ''
        discontinuity = false
      }
    }
    return plan.segments.length > 0 ? plan : null
  }

  removeDirectory(path: string): void {
    try {
      if (path.length > 0 && fileIo.accessSync(path)) {
        fileIo.rmdirSync(path)
      }
    } catch (err) {
      logger.warn('清理HLS目录失败: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async loadBundle(url: string, headers: Record<string, string>,
    control: HlsRuntimeControl): Promise<HlsDownloadBundle> {
    this.ensureActive(control)
    const manifest = await this.fetchText(url, headers, control)
    this.validateManifest(manifest)
    const variant = this.selectBestVariant(manifest, url)
    const bundle = new HlsDownloadBundle()
    if (variant.url.length === 0) {
      bundle.videoPlan = this.parseMediaPlaylist(manifest, url, '')
      return bundle
    }
    bundle.hasMasterPlaylist = true
    bundle.variant = variant
    bundle.videoPlan = await this.loadMediaPlan(variant.url, headers, control, 'video_')
    bundle.renditions = await this.loadRenditionPlans(manifest, url, variant, headers, control)
    return bundle
  }

  private async loadMediaPlan(url: string, headers: Record<string, string>, control: HlsRuntimeControl,
    localPrefix: string): Promise<HlsDownloadPlan> {
    let manifestUrl = url
    for (let depth = 0; depth < MAX_MANIFEST_DEPTH; depth++) {
      this.ensureActive(control)
      const manifest = await this.fetchText(manifestUrl, headers, control)
      this.validateManifest(manifest)
      const variant = this.selectBestVariant(manifest, manifestUrl)
      if (variant.url.length > 0) {
        manifestUrl = variant.url
        continue
      }
      const plan = this.parseMediaPlaylist(manifest, manifestUrl, localPrefix)
      plan.sourceUrl = manifestUrl
      return plan
    }
    throw new Error('M3U8 嵌套层级过深')
  }

  private selectBestVariant(manifest: string, baseUrl: string): HlsVariantSelection {
    const lines = manifest.split(/\r?\n/)
    const best = new HlsVariantSelection()
    let bestBandwidth = -1
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.indexOf('#EXT-X-STREAM-INF:') !== 0) {
        continue
      }
      const attrs = this.parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length))
      const bandwidth = this.parsePositiveInt(attrs['BANDWIDTH'])
      const uri = this.findNextUri(lines, i + 1)
      if (uri.length > 0 && bandwidth >= bestBandwidth) {
        bestBandwidth = bandwidth
        best.url = this.resolveUrl(uri, baseUrl)
        best.attributes = attrs
      }
    }
    return best
  }

  private async loadRenditionPlans(manifest: string, baseUrl: string, variant: HlsVariantSelection,
    headers: Record<string, string>, control: HlsRuntimeControl): Promise<HlsRenditionPlan[]> {
    const selectedAudioGroup = variant.attributes['AUDIO'] || ''
    const selectedSubtitleGroup = variant.attributes['SUBTITLES'] || ''
    const selectedVideoGroup = variant.attributes['VIDEO'] || ''
    const pending: HlsRenditionPlan[] = []
    const lines = manifest.split(/\r?\n/)
    let audioIndex = 0
    let subtitleIndex = 0
    let videoIndex = 0
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.indexOf('#EXT-X-MEDIA:') !== 0) {
        continue
      }
      const attrs = this.parseAttributes(line.substring('#EXT-X-MEDIA:'.length))
      const type = (attrs['TYPE'] || '').toUpperCase()
      const groupId = attrs['GROUP-ID'] || ''
      const isAudio = type === 'AUDIO' && groupId === selectedAudioGroup
      const isSubtitle = type === 'SUBTITLES' && groupId === selectedSubtitleGroup
      const isVideo = type === 'VIDEO' && groupId === selectedVideoGroup
      const uri = attrs['URI'] || ''
      if ((!isAudio && !isSubtitle && !isVideo) || uri.length === 0) {
        continue
      }
      const rendition = new HlsRenditionPlan()
      rendition.type = type
      rendition.groupId = groupId
      rendition.name = attrs['NAME'] || (isAudio ? '音轨' : (isVideo ? '视角' : '字幕'))
      rendition.language = attrs['LANGUAGE'] || ''
      rendition.defaultValue = this.normalizeYesNo(attrs['DEFAULT'])
      rendition.autoSelect = this.normalizeYesNo(attrs['AUTOSELECT'])
      rendition.forced = this.normalizeYesNo(attrs['FORCED'])
      rendition.characteristics = attrs['CHARACTERISTICS'] || ''
      rendition.channels = attrs['CHANNELS'] || ''
      rendition.sourceUrl = this.resolveUrl(uri, baseUrl)
      if (isAudio) {
        const prefix = 'audio_' + this.padNumber(audioIndex, 3)
        rendition.localPlaylistFile = prefix + '.m3u8'
        audioIndex++
      } else if (isSubtitle) {
        const prefix = 'subtitle_' + this.padNumber(subtitleIndex, 3)
        rendition.localPlaylistFile = prefix + '.m3u8'
        subtitleIndex++
      } else {
        const prefix = 'angle_' + this.padNumber(videoIndex, 3)
        rendition.localPlaylistFile = prefix + '.m3u8'
        videoIndex++
      }
      pending.push(rendition)
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.indexOf('#EXT-X-I-FRAME-STREAM-INF:') !== 0) continue
      const attrs = this.parseAttributes(line.substring('#EXT-X-I-FRAME-STREAM-INF:'.length))
      const uri = attrs['URI'] || ''
      if (uri.length === 0) continue
      const rendition = new HlsRenditionPlan()
      rendition.type = 'IFRAME'
      rendition.name = 'I-frame'
      rendition.sourceUrl = this.resolveUrl(uri, baseUrl)
      rendition.localPlaylistFile = 'iframe_' + this.padNumber(pending.length, 3) + '.m3u8'
      rendition.characteristics = this.serializeAttributes(attrs, 'URI')
      pending.push(rendition)
    }

    for (let i = 0; i < pending.length; i++) {
      const prefix = pending[i].localPlaylistFile.substring(0,
        pending[i].localPlaylistFile.length - '.m3u8'.length) + '_'
      pending[i].plan = await this.loadMediaPlan(pending[i].sourceUrl, headers, control, prefix)
      if (pending[i].plan.segments.length === 0) {
        throw new Error(pending[i].type + ' 轨道中没有可下载分片')
      }
    }
    return pending
  }

  private validateManifest(manifest: string): void {
    if (manifest.trim().indexOf('#EXTM3U') !== 0) {
      throw new Error('资源不是有效的 M3U8 播放列表')
    }
  }

  private parseMediaPlaylist(manifest: string, baseUrl: string, localPrefix: string): HlsDownloadPlan {
    const plan = new HlsDownloadPlan()
    const lines = manifest.split(/\r?\n/)
    let currentDuration = 0
    let currentTitle = ''
    let currentKey: HlsKeyDirective | null = null
    let currentMap: HlsMapDirective | null = null
    let pendingRange: string = ''
    let pendingDiscontinuity = false
    let hasEndList = false
    let explicitVod = false
    const rangeOffsets: Map<string, number> = new Map()
    const keyFiles: Map<string, string> = new Map()
    const mapFiles: Map<string, string> = new Map()

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length === 0) {
        continue
      }
      if (line.indexOf('#EXT-X-TARGETDURATION:') === 0) {
        plan.targetDuration = Math.max(1, this.parsePositiveInt(line.substring('#EXT-X-TARGETDURATION:'.length)))
      } else if (line.indexOf('#EXT-X-MEDIA-SEQUENCE:') === 0) {
        plan.mediaSequence = this.parsePositiveInt(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length))
      } else if (line.indexOf('#EXT-X-PLAYLIST-TYPE:') === 0) {
        explicitVod = line.substring('#EXT-X-PLAYLIST-TYPE:'.length).trim().toUpperCase() === 'VOD'
      } else if (line.indexOf('#EXT-X-ENDLIST') === 0) {
        hasEndList = true
      } else if (line.indexOf('#EXT-X-I-FRAMES-ONLY') === 0) {
        plan.isIFrameOnly = true
      } else if (line.indexOf('#EXT-X-DISCONTINUITY') === 0) {
        pendingDiscontinuity = true
      } else if (line.indexOf('#EXT-X-BYTERANGE:') === 0) {
        pendingRange = line.substring('#EXT-X-BYTERANGE:'.length).trim()
      } else if (line.indexOf('#EXT-X-KEY:') === 0) {
        currentKey = this.parseKey(line.substring('#EXT-X-KEY:'.length), baseUrl, plan, keyFiles, localPrefix)
      } else if (line.indexOf('#EXT-X-MAP:') === 0) {
        currentMap = this.parseMap(line.substring('#EXT-X-MAP:'.length), baseUrl, plan, mapFiles, rangeOffsets,
          localPrefix)
      } else if (line.indexOf('#EXTINF:') === 0) {
        const extInf = line.substring('#EXTINF:'.length)
        const comma = extInf.indexOf(',')
        const durationText = comma >= 0 ? extInf.substring(0, comma) : extInf
        currentDuration = parseFloat(durationText)
        if (isNaN(currentDuration) || currentDuration < 0) {
          currentDuration = 0
        }
        currentTitle = comma >= 0 ? extInf.substring(comma + 1) : ''
      } else if (line.charAt(0) !== '#') {
        const segment = new HlsSegment()
        segment.sequence = plan.mediaSequence + plan.segments.length
        segment.url = this.resolveUrl(line, baseUrl)
        segment.localFile = localPrefix + 'seg_' + this.padNumber(segment.sequence, 10) + '_' +
          this.shortHash(segment.url + '|' + pendingRange) +
          this.extractExtension(line)
        segment.duration = currentDuration
        segment.title = currentTitle
        segment.discontinuity = pendingDiscontinuity
        segment.key = currentKey
        segment.map = currentMap
        segment.range = this.parseByteRange(pendingRange, segment.url, rangeOffsets)
        plan.segments.push(segment)
        currentDuration = 0
        currentTitle = ''
        pendingRange = ''
        pendingDiscontinuity = false
      }
    }

    plan.hasEndList = hasEndList || explicitVod
    return plan
  }

  private parseKey(input: string, baseUrl: string, plan: HlsDownloadPlan,
    keyFiles: Map<string, string>, localPrefix: string): HlsKeyDirective | null {
    const attrs = this.parseAttributes(input)
    const method = (attrs['METHOD'] || '').toUpperCase()
    if (method.length === 0 || method === 'NONE') {
      return null
    }
    if (method !== 'AES-128' && method !== 'SAMPLE-AES') {
      throw new Error('暂不支持 ' + method + ' 加密的 HLS 资源')
    }
    const keyFormat = attrs['KEYFORMAT'] || 'identity'
    if (keyFormat !== 'identity') {
      throw new Error('暂不支持 DRM HLS 资源')
    }
    const url = this.resolveUrl(attrs['URI'] || '', baseUrl)
    if (url.length === 0) {
      throw new Error('HLS 密钥地址为空')
    }
    let localFile = keyFiles.get(url)
    if (localFile === undefined) {
      localFile = localPrefix + 'key_' + this.shortHash(url) + '.key'
      keyFiles.set(url, localFile)
      const resource = new HlsResource()
      resource.url = url
      resource.localFile = localFile
      plan.resources.push(resource)
    }
    const key = new HlsKeyDirective()
    key.method = method
    key.url = url
    key.iv = attrs['IV'] || ''
    key.localFile = localFile
    return key
  }

  private parseMap(input: string, baseUrl: string, plan: HlsDownloadPlan,
    mapFiles: Map<string, string>, rangeOffsets: Map<string, number>, localPrefix: string): HlsMapDirective {
    const attrs = this.parseAttributes(input)
    const url = this.resolveUrl(attrs['URI'] || '', baseUrl)
    if (url.length === 0) {
      throw new Error('HLS 初始化片段地址为空')
    }
    const rangeText = attrs['BYTERANGE'] || ''
    const resourceKey = url + '|' + rangeText
    let localFile = mapFiles.get(resourceKey)
    const range = this.parseByteRange(rangeText, url, rangeOffsets)
    if (localFile === undefined) {
      localFile = localPrefix + 'init_' + this.shortHash(resourceKey) + this.extractExtension(url, '.mp4')
      mapFiles.set(resourceKey, localFile)
      const resource = new HlsResource()
      resource.url = url
      resource.localFile = localFile
      resource.range = range
      plan.resources.push(resource)
    }
    const map = new HlsMapDirective()
    map.url = url
    map.localFile = localFile
    map.range = range
    return map
  }

  private parseByteRange(input: string, url: string, offsets: Map<string, number>): HlsByteRange | null {
    if (input.length === 0) {
      return null
    }
    const parts = input.split('@')
    const length = this.parsePositiveInt(parts[0])
    if (length <= 0) {
      return null
    }
    let start = parts.length > 1 ? this.parsePositiveInt(parts[1]) : (offsets.get(url) || 0)
    const range = new HlsByteRange()
    range.start = start
    range.length = length
    offsets.set(url, start + length)
    return range
  }

  private buildLocalPlaylist(plan: HlsDownloadPlan): string {
    const lines: string[] = ['#EXTM3U', '#EXT-X-VERSION:7',
      '#EXT-X-TARGETDURATION:' + String(plan.targetDuration),
      '#EXT-X-MEDIA-SEQUENCE:' + String(plan.mediaSequence)]
    if (plan.hasEndList) lines.push('#EXT-X-PLAYLIST-TYPE:VOD')
    if (plan.isIFrameOnly) lines.push('#EXT-X-I-FRAMES-ONLY')
    let lastKey = ''
    let lastMap = ''
    for (let i = 0; i < plan.segments.length; i++) {
      const segment = plan.segments[i]
      const keyIdentity = segment.key === null ? 'none' : segment.key.localFile + '|' + segment.key.iv
      if (keyIdentity !== lastKey) {
        if (segment.key === null) {
          lines.push('#EXT-X-KEY:METHOD=NONE')
        } else {
          let keyLine = '#EXT-X-KEY:METHOD=' + segment.key.method + ',URI="' + segment.key.localFile + '"'
          if (segment.key.iv.length > 0) {
            keyLine += ',IV=' + segment.key.iv
          }
          lines.push(keyLine)
        }
        lastKey = keyIdentity
      }
      const mapIdentity = segment.map === null ? '' : segment.map.localFile
      if (mapIdentity.length > 0 && mapIdentity !== lastMap) {
        lines.push('#EXT-X-MAP:URI="' + mapIdentity + '"')
        lastMap = mapIdentity
      }
      if (segment.discontinuity) {
        lines.push('#EXT-X-DISCONTINUITY')
      }
      lines.push('#EXTINF:' + segment.duration.toFixed(6) + ',' + segment.title)
      lines.push(segment.localFile)
    }
    if (plan.hasEndList) lines.push('#EXT-X-ENDLIST')
    return lines.join('\n') + '\n'
  }

  private buildLocalMasterPlaylist(bundle: HlsDownloadBundle): string {
    const lines: string[] = ['#EXTM3U', '#EXT-X-VERSION:7', '#EXT-X-INDEPENDENT-SEGMENTS']
    let hasAudio = false
    let hasSubtitles = false
    for (let i = 0; i < bundle.renditions.length; i++) {
      const rendition = bundle.renditions[i]
      if (rendition.type === 'IFRAME') {
        lines.push('#EXT-X-I-FRAME-STREAM-INF:' + rendition.characteristics +
          ',URI="' + rendition.localPlaylistFile + '"')
        continue
      }
      if (rendition.type === 'AUDIO') {
        hasAudio = true
      } else if (rendition.type === 'SUBTITLES') {
        hasSubtitles = true
      }
      lines.push(this.buildLocalRenditionLine(rendition))
    }
    lines.push('#EXT-X-STREAM-INF:' + this.buildLocalVariantAttributes(bundle.variant.attributes,
      hasAudio, hasSubtitles))
    lines.push('video.m3u8')
    return lines.join('\n') + '\n'
  }

  private buildLocalRenditionLine(rendition: HlsRenditionPlan): string {
    let line = '#EXT-X-MEDIA:TYPE=' + rendition.type +
      ',GROUP-ID="' + this.escapeQuotedValue(rendition.groupId) + '"' +
      ',NAME="' + this.escapeQuotedValue(rendition.name) + '"'
    if (rendition.language.length > 0) {
      line += ',LANGUAGE="' + this.escapeQuotedValue(rendition.language) + '"'
    }
    line += ',DEFAULT=' + rendition.defaultValue + ',AUTOSELECT=' + rendition.autoSelect
    if (rendition.type === 'SUBTITLES') {
      line += ',FORCED=' + rendition.forced
    }
    if (rendition.characteristics.length > 0) {
      line += ',CHARACTERISTICS="' + this.escapeQuotedValue(rendition.characteristics) + '"'
    }
    if (rendition.channels.length > 0) {
      line += ',CHANNELS="' + this.escapeQuotedValue(rendition.channels) + '"'
    }
    line += ',URI="' + rendition.localPlaylistFile + '"'
    return line
  }

  private buildLocalVariantAttributes(source: Record<string, string>, hasAudio: boolean,
    hasSubtitles: boolean): string {
    const parts: string[] = []
    const bandwidth = this.parsePositiveInt(source['BANDWIDTH'] || '')
    parts.push('BANDWIDTH=' + String(Math.max(1, bandwidth)))
    this.pushBareAttribute(parts, source, 'AVERAGE-BANDWIDTH')
    this.pushQuotedAttribute(parts, source, 'CODECS')
    this.pushBareAttribute(parts, source, 'RESOLUTION')
    this.pushBareAttribute(parts, source, 'FRAME-RATE')
    this.pushBareAttribute(parts, source, 'VIDEO-RANGE')
    this.pushBareAttribute(parts, source, 'HDCP-LEVEL')
    if (hasAudio && (source['AUDIO'] || '').length > 0) {
      parts.push('AUDIO="' + this.escapeQuotedValue(source['AUDIO']) + '"')
    }
    if (hasSubtitles && (source['SUBTITLES'] || '').length > 0) {
      parts.push('SUBTITLES="' + this.escapeQuotedValue(source['SUBTITLES']) + '"')
    }
    if ((source['VIDEO'] || '').length > 0) {
      parts.push('VIDEO="' + this.escapeQuotedValue(source['VIDEO']) + '"')
    }
    return parts.join(',')
  }

  private pushBareAttribute(parts: string[], source: Record<string, string>, key: string): void {
    const value = source[key] || ''
    if (value.length > 0) {
      parts.push(key + '=' + value)
    }
  }

  private pushQuotedAttribute(parts: string[], source: Record<string, string>, key: string): void {
    const value = source[key] || ''
    if (value.length > 0) {
      parts.push(key + '="' + this.escapeQuotedValue(value) + '"')
    }
  }

  private normalizeYesNo(value: string | undefined): string {
    return value !== undefined && value.toUpperCase() === 'YES' ? 'YES' : 'NO'
  }

  private escapeQuotedValue(value: string): string {
    return value.replace(/"/g, "'")
  }

  private serializeAttributes(attributes: Record<string, string>, omittedKey: string): string {
    const parts: string[] = []
    const keys = Object.keys(attributes)
    const bare = ['BANDWIDTH', 'AVERAGE-BANDWIDTH', 'RESOLUTION', 'FRAME-RATE', 'HDCP-LEVEL', 'VIDEO-RANGE']
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      if (key === omittedKey) continue
      const value = attributes[key]
      parts.push(key + (bare.indexOf(key) >= 0 ? '=' + value : '="' + this.escapeQuotedValue(value) + '"'))
    }
    return parts.join(',')
  }

  private shortHash(value: string): string {
    let hash = 2166136261
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i)
      hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0).toString(16)
  }

  private async fetchText(url: string, headers: Record<string, string>, control: HlsRuntimeControl): Promise<string> {
    const request = http.createHttp()
    this.addRequest(control, request)
    try {
      const result = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000,
        maxLimit: 2 * 1024 * 1024
      })
      if (result.responseCode < 200 || result.responseCode >= 300) {
        throw new Error('HTTP ' + String(result.responseCode))
      }
      if (typeof result.result !== 'string') {
        throw new Error('播放列表响应格式错误')
      }
      return result.result
    } finally {
      this.removeRequest(control, request)
      request.destroy()
    }
  }

  private async downloadWithRetry(url: string, path: string, headers: Record<string, string>,
    range: HlsByteRange | null, control: HlsRuntimeControl): Promise<number> {
    if (fileIo.accessSync(path) && !this.isCompleteFile(path, range)) {
      this.removeFile(path)
      this.removeFile(path + '.size')
    }
    let lastMessage = ''
    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      this.ensureActive(control)
      try {
        return await this.downloadBinary(url, path, headers, range, control)
      } catch (err) {
        lastMessage = err instanceof Error ? err.message : String(err)
        if (lastMessage.startsWith('RESET_PARTIAL:')) {
          this.removeFile(path + '.tmp')
        }
        this.ensureActive(control)
        if (attempt < MAX_RETRIES - 1) {
          await this.delay([1000, 3000, 9000][attempt])
        }
      }
    }
    throw new Error('分片下载失败：' + lastMessage)
  }

  private async downloadBinary(url: string, path: string, sourceHeaders: Record<string, string>,
    range: HlsByteRange | null, control: HlsRuntimeControl): Promise<number> {
    const tempPath = path + '.tmp'
    let existingBytes = 0
    if (fileIo.accessSync(tempPath)) {
      existingBytes = fileIo.statSync(tempPath).size
    }
    if (range !== null && existingBytes > range.length) {
      this.removeFile(tempPath)
      existingBytes = 0
    }
    if (range !== null && existingBytes === range.length && existingBytes > 0) {
      fileIo.renameSync(tempPath, path)
      this.writeTextFile(path + '.size', String(existingBytes))
      return existingBytes
    }
    const openMode = existingBytes > 0 ?
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY :
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    const target = fileIo.openSync(tempPath, openMode)
    const request = http.createHttp()
    const headers = this.copyHeaders(sourceHeaders)
    if (range !== null && range.length > 0) {
      headers['Range'] = 'bytes=' + String(range.start + existingBytes) + '-' +
        String(range.start + range.length - 1)
    } else if (existingBytes > 0) {
      headers['Range'] = 'bytes=' + String(existingBytes) + '-'
    }
    let bytes = 0
    let receiveTotal = -1
    const receive = (data: ArrayBuffer): void => {
      fileIo.writeSync(target.fd, data, { offset: existingBytes + bytes })
      bytes += data.byteLength
    }
    const progress = (info: http.DataReceiveProgressInfo): void => {
      if (info.totalSize > 0) {
        receiveTotal = info.totalSize
      }
    }
    request.on('dataReceive', receive)
    request.on('dataReceiveProgress', progress)
    this.addRequest(control, request)
    try {
      const status = await request.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 120000
      })
      const requiresPartialResponse = existingBytes > 0 || range !== null
      const validStatus = requiresPartialResponse ? status === 206 : status >= 200 && status < 300
      if (!validStatus) {
        throw new Error('RESET_PARTIAL: HTTP ' + String(status))
      }
    } finally {
      request.off('dataReceive', receive)
      request.off('dataReceiveProgress', progress)
      this.removeRequest(control, request)
      request.destroy()
      fileIo.closeSync(target)
    }
    const finalSize = existingBytes + bytes
    if (finalSize <= 0) {
      throw new Error('RESET_PARTIAL: 服务器返回空分片')
    }
    const expectedSize = range !== null ? range.length :
      (receiveTotal > 0 ? existingBytes + receiveTotal : finalSize)
    if (finalSize !== expectedSize) {
      throw new Error('分片长度不完整：' + String(finalSize) + '/' + String(expectedSize))
    }
    fileIo.renameSync(tempPath, path)
    this.writeTextFile(path + '.size', String(finalSize))
    return finalSize
  }

  private writeTextFile(path: string, content: string): void {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, content)
    } finally {
      fileIo.closeSync(file)
    }
  }

  ensureManagedDirectory(path: string): void {
    const markerPath = path + '/' + HLS_DIRECTORY_MARKER
    try {
      if (fileIo.accessSync(markerPath)) {
        return
      }
      const marker = fileIo.openSync(markerPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.closeSync(marker)
    } catch (err) {
      logger.warn('创建HLS目录标记失败: %{public}s', String(err))
    }
  }

  private countRenditions(bundle: HlsDownloadBundle, type: string): number {
    let count = 0
    for (let i = 0; i < bundle.renditions.length; i++) {
      if (bundle.renditions[i].type === type) {
        count++
      }
    }
    return count
  }

  private buildBundleFingerprint(bundle: HlsDownloadBundle): string {
    const parts: string[] = ['layout=3']
    this.appendPlanFingerprint(parts, 'video', bundle.videoPlan)
    for (let i = 0; i < bundle.renditions.length; i++) {
      const rendition = bundle.renditions[i]
      parts.push('rendition=' + rendition.type + '|' + rendition.groupId + '|' + rendition.name + '|' +
        rendition.language + '|' + this.urlIdentity(rendition.sourceUrl))
      this.appendPlanFingerprint(parts, rendition.localPlaylistFile, rendition.plan)
    }
    const value = parts.join('\n')
    let hash = 0
    for (let i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0
    }
    return 'v2:' + String(value.length) + ':' + String(hash)
  }

  private appendPlanFingerprint(parts: string[], name: string, plan: HlsDownloadPlan): void {
    parts.push('plan=' + name + '|' + String(plan.mediaSequence) + '|' + String(plan.segments.length))
    for (let i = 0; i < plan.segments.length; i++) {
      const segment = plan.segments[i]
      const range = segment.range === null ? '' : segment.range.toHeader()
      const key = segment.key === null ? '' :
        this.urlIdentity(segment.key.url) + '|' + segment.key.iv
      const map = segment.map === null ? '' : this.urlIdentity(segment.map.url)
      parts.push(String(i) + '|' + this.urlIdentity(segment.url) + '|' + segment.duration.toFixed(6) + '|' +
        range + '|' + key + '|' + map)
    }
  }

  private urlIdentity(url: string): string {
    return url.split('?')[0].split('#')[0]
  }

  private ensurePlanFingerprint(directory: string, fingerprint: string, live: boolean = false): void {
    const fingerprintPath = directory + '/' + HLS_PLAN_FINGERPRINT_FILE
    const storedFingerprint = live ? 'live:' + fingerprint : fingerprint
    try {
      if (fileIo.accessSync(fingerprintPath)) {
        const existing = fileIo.readTextSync(fingerprintPath).trim()
        if (existing === storedFingerprint || live || existing.startsWith('live:')) {
          return
        }
        logger.warn('HLS清单结构已变化，清理旧分片后重新下载')
        this.clearManagedDownloadFiles(directory)
      } else if (this.hasManagedDownloadFiles(directory)) {
        logger.info('旧版HLS任务缺少清单指纹，清理分片后安全重建')
        this.clearManagedDownloadFiles(directory)
      }
      this.writeTextFile(fingerprintPath, storedFingerprint)
    } catch (err) {
      throw new Error('校验HLS断点数据失败：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private hasManagedDownloadFiles(directory: string): boolean {
    const names = fileIo.listFileSync(directory)
    for (let i = 0; i < names.length; i++) {
      if (this.isManagedDownloadFile(names[i])) {
        return true
      }
    }
    return false
  }

  private clearManagedDownloadFiles(directory: string): void {
    const names = fileIo.listFileSync(directory)
    for (let i = 0; i < names.length; i++) {
      if (!this.isManagedDownloadFile(names[i])) {
        continue
      }
      const path = directory + '/' + names[i]
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    }
  }

  private isManagedDownloadFile(name: string): boolean {
    return name === HLS_PLAN_FINGERPRINT_FILE || name.endsWith('.m3u8') || name.endsWith('.tmp') ||
      name.endsWith('.size') ||
      name.indexOf('seg_') === 0 || name.indexOf('video_') === 0 || name.indexOf('audio_') === 0 ||
      name.indexOf('subtitle_') === 0 || name.indexOf('key_') === 0 || name.indexOf('init_') === 0
  }

  private ensureActive(control: HlsRuntimeControl): void {
    if (control.cancelled) {
      throw new Error('下载已取消')
    }
    if (control.paused) {
      throw new Error('下载已暂停')
    }
    if (control.failed) {
      throw new Error('其他分片下载失败')
    }
  }

  private async waitForWorkers(workers: Promise<void>[]): Promise<void> {
    let firstErrorMessage = ''
    const guarded: Promise<void>[] = []
    for (let i = 0; i < workers.length; i++) {
      guarded.push(workers[i].catch((err: Object): void => {
        if (firstErrorMessage.length === 0) {
          firstErrorMessage = err instanceof Error ? err.message : String(err)
        }
      }))
    }
    await Promise.all(guarded)
    if (firstErrorMessage.length > 0) {
      throw new Error(firstErrorMessage)
    }
  }

  private abortRequests(control: HlsRuntimeControl): void {
    const requests = control.requests.slice()
    control.requests = []
    for (let i = 0; i < requests.length; i++) {
      try {
        requests[i].destroy()
      } catch (_err) {
      }
    }
  }

  private addRequest(control: HlsRuntimeControl, request: http.HttpRequest): void {
    control.requests.push(request)
  }

  private removeRequest(control: HlsRuntimeControl, request: http.HttpRequest): void {
    const index = control.requests.indexOf(request)
    if (index >= 0) {
      control.requests.splice(index, 1)
    }
  }

  private isCompleteFile(path: string, range: HlsByteRange | null): boolean {
    try {
      if (!fileIo.accessSync(path)) {
        return false
      }
      const actualSize = fileIo.statSync(path).size
      if (actualSize <= 0) {
        return false
      }
      if (range !== null) {
        return actualSize === range.length
      }
      const sizePath = path + '.size'
      if (!fileIo.accessSync(sizePath)) {
        return false
      }
      const expectedSize = parseInt(fileIo.readTextSync(sizePath).trim(), 10)
      return expectedSize > 0 && actualSize === expectedSize
    } catch (_err) {
      return false
    }
  }

  private removeFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_err) {
    }
  }

  private copyHeaders(source: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {}
    const keys = Object.keys(source)
    for (let i = 0; i < keys.length; i++) {
      headers[keys[i]] = source[keys[i]]
    }
    return headers
  }

  private parseAttributes(input: string): Record<string, string> {
    const result: Record<string, string> = {}
    let key = ''
    let value = ''
    let readingKey = true
    let quoted = false
    const commit = (): void => {
      const cleanKey = key.trim()
      let cleanValue = value.trim()
      if (cleanValue.length >= 2 && cleanValue.charAt(0) === '"' &&
        cleanValue.charAt(cleanValue.length - 1) === '"') {
        cleanValue = cleanValue.substring(1, cleanValue.length - 1)
      }
      if (cleanKey.length > 0) {
        result[cleanKey] = cleanValue
      }
      key = ''
      value = ''
      readingKey = true
    }
    for (let i = 0; i < input.length; i++) {
      const ch = input.charAt(i)
      if (ch === '"') {
        quoted = !quoted
      }
      if (readingKey && ch === '=') {
        readingKey = false
      } else if (!readingKey && ch === ',' && !quoted) {
        commit()
      } else if (readingKey) {
        key += ch
      } else {
        value += ch
      }
    }
    commit()
    return result
  }

  private findNextUri(lines: string[], start: number): string {
    for (let i = start; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length > 0 && line.charAt(0) !== '#') {
        return line
      }
    }
    return ''
  }

  private resolveUrl(uri: string, baseUrl: string): string {
    if (uri.indexOf('http://') === 0 || uri.indexOf('https://') === 0) {
      return uri
    }
    const scheme = baseUrl.indexOf('://')
    if (scheme < 0) {
      return uri
    }
    const originStart = scheme + 3
    const firstSlash = baseUrl.indexOf('/', originStart)
    const origin = firstSlash < 0 ? baseUrl : baseUrl.substring(0, firstSlash)
    if (uri.charAt(0) === '/') {
      return origin + this.normalizePath(uri)
    }
    const queryFree = baseUrl.split('?')[0].split('#')[0]
    const lastSlash = queryFree.lastIndexOf('/')
    const basePath = lastSlash >= 0 ? queryFree.substring(origin.length, lastSlash + 1) : '/'
    return origin + this.normalizePath(basePath + uri)
  }

  private normalizePath(path: string): string {
    const parts = path.split('/')
    const output: string[] = []
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length === 0 || parts[i] === '.') {
        continue
      }
      if (parts[i] === '..') {
        if (output.length > 0) {
          output.pop()
        }
      } else {
        output.push(parts[i])
      }
    }
    return '/' + output.join('/')
  }

  private extractExtension(url: string, fallback: string = '.ts'): string {
    const clean = url.split('?')[0].split('#')[0].toLowerCase()
    const extensions = ['.ts', '.m4s', '.mp4', '.aac', '.vtt', '.webvtt']
    for (let i = 0; i < extensions.length; i++) {
      if (clean.endsWith(extensions[i])) {
        return extensions[i]
      }
    }
    return fallback
  }

  private parsePositiveInt(value: string): number {
    const parsed = parseInt(value, 10)
    return isNaN(parsed) || parsed < 0 ? 0 : parsed
  }

  private padNumber(value: number, width: number): string {
    let text = String(value)
    while (text.length < width) {
      text = '0' + text
    }
    return text
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms)
    })
  }
}
