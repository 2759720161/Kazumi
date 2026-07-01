import { HlsKeyMetadata, HlsSegmentMetadata, StreamMetadata, VariantStreamMetadata } from '../player/StreamMetadata'

export class HlsManifestParser {
  parse(manifest: string, baseUrl: string): StreamMetadata {
    const metadata = new StreamMetadata()
    metadata.sourceType = 'hls_manifest'
    metadata.isHls = manifest.indexOf('#EXTM3U') !== -1
    if (!metadata.isHls) {
      metadata.warnings.push('not_hls_manifest')
      return metadata
    }

    const lines = manifest.split(/\r?\n/)
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.indexOf('#EXT-X-STREAM-INF:') === 0) {
        metadata.isMasterPlaylist = true
        const attrs = this.parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length))
        const variant = new VariantStreamMetadata()
        variant.bandwidth = this.parsePositiveInt(attrs['BANDWIDTH'])
        const resolution = attrs['RESOLUTION'] || ''
        const size = this.parseResolution(resolution)
        variant.width = size[0]
        variant.height = size[1]
        variant.codecs = this.parseCodecs(attrs['CODECS'] || '')
        variant.uri = this.findNextUri(lines, i + 1, baseUrl)
        metadata.variants.push(variant)
        this.mergeVariant(metadata, variant)
      } else if (line.indexOf('#EXT-X-MEDIA:') === 0) {
        const attrs = this.parseAttributes(line.substring('#EXT-X-MEDIA:'.length))
        const uri = attrs['URI'] || ''
        if (uri.length > 0 && !this.hasCodec(metadata, 'external-media')) {
          metadata.codecs.push('external-media')
        }
      }
    }

    if (!metadata.isMasterPlaylist) {
      this.parseMediaPlaylist(lines, baseUrl, metadata)
    }
    this.addCodecWarnings(metadata)
    return metadata
  }

  private mergeVariant(metadata: StreamMetadata, variant: VariantStreamMetadata): void {
    if (variant.bandwidth > 0) {
      if (metadata.minBandwidth === 0 || variant.bandwidth < metadata.minBandwidth) {
        metadata.minBandwidth = variant.bandwidth
      }
      if (variant.bandwidth > metadata.maxBandwidth) {
        metadata.maxBandwidth = variant.bandwidth
      }
    }
    if (variant.width > metadata.maxWidth) {
      metadata.maxWidth = variant.width
    }
    if (variant.height > metadata.maxHeight) {
      metadata.maxHeight = variant.height
    }
    for (let i = 0; i < variant.codecs.length; i++) {
      const codec = variant.codecs[i]
      if (!this.hasCodec(metadata, codec)) {
        metadata.codecs.push(codec)
      }
    }
  }

  private parseMediaPlaylist(lines: string[], baseUrl: string, metadata: StreamMetadata): void {
    let currentDuration = 0
    let currentGroup = 0
    let currentKey: HlsKeyMetadata | null = null
    let hasEndList = false
    let explicitVod = false
    let explicitEvent = false

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      const lower = line.toLowerCase()
      if (line.length === 0) {
        continue
      }
      if (line.indexOf('#EXT-X-TARGETDURATION:') === 0) {
        metadata.targetDuration = this.parsePositiveInt(line.substring('#EXT-X-TARGETDURATION:'.length))
        continue
      }
      if (line.indexOf('#EXT-X-PLAYLIST-TYPE:') === 0) {
        const playlistType = line.substring('#EXT-X-PLAYLIST-TYPE:'.length).trim().toUpperCase()
        explicitVod = playlistType === 'VOD'
        explicitEvent = playlistType === 'EVENT'
        continue
      }
      if (line.indexOf('#EXT-X-ENDLIST') === 0) {
        hasEndList = true
        continue
      }
      if (line.indexOf('#EXT-X-DISCONTINUITY') === 0) {
        currentGroup++
        continue
      }
      if (line.indexOf('#EXT-X-KEY:') === 0) {
        currentKey = this.parseKey(line.substring('#EXT-X-KEY:'.length), baseUrl)
        if (currentKey !== null) {
          metadata.hasEncryptedSegments = true
          if (currentKey.uri.length > 0 && !this.hasString(metadata.uniqueKeyUris, currentKey.uri)) {
            metadata.uniqueKeyUris.push(currentKey.uri)
          }
        }
        continue
      }
      if (line.indexOf('#EXTINF:') === 0) {
        currentDuration = this.parseExtinfDuration(line.substring('#EXTINF:'.length))
        continue
      }
      if (line.charAt(0) === '#') {
        continue
      }
      const segment = new HlsSegmentMetadata()
      segment.uri = this.resolveUrl(line, baseUrl)
      segment.duration = currentDuration
      segment.discontinuityGroup = currentGroup
      segment.key = currentKey
      metadata.segments.push(segment)
      metadata.totalDuration += currentDuration
      this.addSegmentCodecHint(lower, metadata)
      currentDuration = 0
    }

    if (metadata.segments.length > 0) {
      metadata.isVod = hasEndList || explicitVod || !explicitEvent
      metadata.discontinuityGroupCount = this.countDiscontinuityGroups(metadata.segments)
      this.markLikelyAdSegments(metadata)
    } else {
      this.scanSegmentHints(lines, metadata)
    }
  }

  private parseKey(input: string, baseUrl: string): HlsKeyMetadata | null {
    const attrs = this.parseAttributes(input)
    const method = attrs['METHOD'] || ''
    if (method.length === 0 || method.toUpperCase() === 'NONE') {
      return null
    }
    const key = new HlsKeyMetadata()
    key.method = method
    const uri = attrs['URI'] || ''
    key.uri = uri.length > 0 ? this.resolveUrl(uri, baseUrl) : ''
    key.iv = attrs['IV'] || ''
    return key
  }

  private parseExtinfDuration(input: string): number {
    const commaIndex = input.indexOf(',')
    const value = commaIndex >= 0 ? input.substring(0, commaIndex) : input
    const parsed = parseFloat(value)
    if (isNaN(parsed) || parsed < 0) {
      return 0
    }
    return parsed
  }

  private addSegmentCodecHint(lowerLine: string, metadata: StreamMetadata): void {
    if (lowerLine.indexOf('.ts') !== -1 && !this.hasCodec(metadata, 'mpegts')) {
      metadata.codecs.push('mpegts')
    }
    if ((lowerLine.indexOf('.m4s') !== -1 || lowerLine.indexOf('.mp4') !== -1) &&
      !this.hasCodec(metadata, 'fmp4')) {
      metadata.codecs.push('fmp4')
    }
  }

  private countDiscontinuityGroups(segments: HlsSegmentMetadata[]): number {
    const groups: number[] = []
    for (let i = 0; i < segments.length; i++) {
      const group = segments[i].discontinuityGroup
      if (groups.indexOf(group) < 0) {
        groups.push(group)
      }
    }
    return groups.length
  }

  private markLikelyAdSegments(metadata: StreamMetadata): void {
    if (metadata.discontinuityGroupCount <= 1) {
      return
    }
    const groupDurations: Record<string, number> = {}
    let maxDuration = 0
    for (let i = 0; i < metadata.segments.length; i++) {
      const key = String(metadata.segments[i].discontinuityGroup)
      groupDurations[key] = (groupDurations[key] || 0) + metadata.segments[i].duration
      if (groupDurations[key] > maxDuration) {
        maxDuration = groupDurations[key]
      }
    }
    const groupKeys = Object.keys(groupDurations).sort((a: string, b: string): number => {
      return parseInt(a, 10) - parseInt(b, 10)
    })
    if (groupKeys.length <= 1 || maxDuration <= 0) {
      return
    }
    const firstGroup = groupKeys[0]
    const lastGroup = groupKeys[groupKeys.length - 1]
    const adGroups: string[] = []
    for (let i = 0; i < groupKeys.length; i++) {
      const key = groupKeys[i]
      const duration = groupDurations[key]
      const edgeShort = (key === firstGroup || key === lastGroup) && duration > 0 && duration < 30
      const isolatedShort = duration > 0 && duration < 10
      const muchShorter = duration > 0 && duration < maxDuration * 0.3
      if (edgeShort || isolatedShort || muchShorter) {
        adGroups.push(key)
      }
    }
    for (let i = 0; i < metadata.segments.length; i++) {
      const segment = metadata.segments[i]
      if (adGroups.indexOf(String(segment.discontinuityGroup)) >= 0) {
        segment.likelyAd = true
        metadata.likelyAdSegmentCount++
        metadata.likelyAdDuration += segment.duration
      }
    }
    if (metadata.likelyAdSegmentCount > 0) {
      metadata.warnings.push('hls_ad_discontinuity')
    }
  }

  private scanSegmentHints(lines: string[], metadata: StreamMetadata): void {
    for (let i = 0; i < lines.length; i++) {
      this.addSegmentCodecHint(lines[i].trim().toLowerCase(), metadata)
    }
  }

  private addCodecWarnings(metadata: StreamMetadata): void {
    for (let i = 0; i < metadata.codecs.length; i++) {
      const codec = metadata.codecs[i].toLowerCase()
      if (codec.indexOf('mp4a') === 0) {
        metadata.hasAacAudio = true
      }
      if (codec.indexOf('hvc1') === 0 || codec.indexOf('hev1') === 0) {
        metadata.hasHevcVideo = true
      }
      if (codec.indexOf('dvhe') === 0 || codec.indexOf('dvh1') === 0) {
        metadata.hasDolbyVision = true
      }
      if (codec.indexOf('hvc1.2') === 0 || codec.indexOf('hev1.2') === 0 ||
        codec.indexOf('dvhe') === 0 || codec.indexOf('dvh1') === 0) {
        metadata.hasHdrCodecHint = true
      }
    }
    if (metadata.hasAacAudio) {
      metadata.warnings.push('aac_audio')
    }
    if (metadata.hasHevcVideo) {
      metadata.warnings.push('hevc_video')
    }
    if (metadata.hasDolbyVision) {
      metadata.warnings.push('dolby_vision')
    }
    if (metadata.hasHdrCodecHint) {
      metadata.warnings.push('hdr_codec_hint')
    }
  }

  private parseAttributes(input: string): Record<string, string> {
    const attrs: Record<string, string> = {}
    let key = ''
    let value = ''
    let readingKey = true
    let inQuote = false

    const commit = () => {
      const cleanKey = key.trim()
      if (cleanKey.length > 0) {
        let cleanValue = value.trim()
        if (cleanValue.length >= 2 && cleanValue.charAt(0) === '"' &&
          cleanValue.charAt(cleanValue.length - 1) === '"') {
          cleanValue = cleanValue.substring(1, cleanValue.length - 1)
        }
        attrs[cleanKey] = cleanValue
      }
      key = ''
      value = ''
      readingKey = true
    }

    for (let i = 0; i < input.length; i++) {
      const ch = input.charAt(i)
      if (ch === '"') {
        inQuote = !inQuote
      }
      if (readingKey && ch === '=') {
        readingKey = false
        continue
      }
      if (!readingKey && ch === ',' && !inQuote) {
        commit()
        continue
      }
      if (readingKey) {
        key += ch
      } else {
        value += ch
      }
    }
    commit()
    return attrs
  }

  private parseCodecs(value: string): string[] {
    const codecs: string[] = []
    const parts = value.split(',')
    for (let i = 0; i < parts.length; i++) {
      const codec = parts[i].trim()
      if (codec.length > 0) {
        codecs.push(codec)
      }
    }
    return codecs
  }

  private parseResolution(value: string): number[] {
    const parts = value.toLowerCase().split('x')
    if (parts.length !== 2) {
      return [0, 0]
    }
    return [this.parsePositiveInt(parts[0]), this.parsePositiveInt(parts[1])]
  }

  private parsePositiveInt(value: string): number {
    const parsed = parseInt(value, 10)
    if (isNaN(parsed) || parsed < 0) {
      return 0
    }
    return parsed
  }

  private findNextUri(lines: string[], startIndex: number, baseUrl: string): string {
    for (let i = startIndex; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length === 0) {
        continue
      }
      if (line.charAt(0) === '#') {
        continue
      }
      return this.resolveUrl(line, baseUrl)
    }
    return ''
  }

  private resolveUrl(uri: string, baseUrl: string): string {
    if (uri.indexOf('http://') === 0 || uri.indexOf('https://') === 0) {
      return uri
    }
    const schemeIndex = baseUrl.indexOf('://')
    if (schemeIndex < 0) {
      return uri
    }
    const originStart = schemeIndex + 3
    const pathStart = baseUrl.indexOf('/', originStart)
    if (pathStart < 0) {
      return baseUrl + '/' + uri
    }
    if (uri.charAt(0) === '/') {
      return baseUrl.substring(0, pathStart) + uri
    }
    const dirEnd = baseUrl.lastIndexOf('/')
    if (dirEnd <= schemeIndex + 2) {
      return baseUrl + '/' + uri
    }
    return baseUrl.substring(0, dirEnd + 1) + uri
  }

  private hasCodec(metadata: StreamMetadata, codec: string): boolean {
    for (let i = 0; i < metadata.codecs.length; i++) {
      if (metadata.codecs[i] === codec) {
        return true
      }
    }
    return false
  }

  private hasString(values: string[], value: string): boolean {
    for (let i = 0; i < values.length; i++) {
      if (values[i] === value) {
        return true
      }
    }
    return false
  }
}
