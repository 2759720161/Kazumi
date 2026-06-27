import { IPlayerEngine, PlaybackOptions, PlayerState } from '../core/player/IPlayerEngine'
import { AVPlayerEngine } from '../core/player/AVPlayerEngine'

class FilterTestCase {
  url: string = ''
  expected: boolean = false
  constructor(url: string, expected: boolean) {
    this.url = url
    this.expected = expected
  }
}

@Entry
@Component
struct AVPlayerPocPage {
  @State testUrl: string = 'https://media.w3.org/2010/05/sintel/trailer.mp4'
  @State statusText: string = 'idle'
  @State positionMs: number = 0
  @State durationMs: number = 0
  @State isPlaying: boolean = false
  @State isBuffering: boolean = false
  @State volume: number = 1.0
  @State speed: number = 1.0
  @State errorMsg: string = ''
  @State stateLog: string[] = []
  @State surfaceId: string = ''
  @State pocConclusions: string[] = []
  private player: AVPlayerEngine = new AVPlayerEngine()
  private xcomponentId: string = 'avplayer_xcomponent'
  private xcomponentController: XComponentController = new XComponentController()

  aboutToAppear(): void {
    this.player.onStateChange((state: PlayerState) => {
      this.statusText = state.stateName
      this.positionMs = state.positionMs
      this.durationMs = state.durationMs
      this.isPlaying = state.playing
      this.isBuffering = state.buffering
      this.volume = state.volume
      this.speed = state.speed
      this.errorMsg = state.error
      this.addLog('State: ' + state.stateName +
        ' | pos=' + state.positionMs + 'ms' +
        ' | dur=' + state.durationMs + 'ms' +
        ' | playing=' + state.playing +
        ' | buffering=' + state.buffering +
        (state.error ? ' | err=' + state.error : ''))
    })
  }

  aboutToDisappear(): void {
    this.player.release()
  }

  addLog(msg: string): void {
    let time = new Date().toLocaleTimeString()
    this.stateLog = ['[' + time + '] ' + msg, ...this.stateLog].slice(0, 30)
  }

  startPlay(): void {
    let sid = this.xcomponentController.getXComponentSurfaceId()
    if (sid) {
      this.surfaceId = sid
      this.player.setSurfaceId(sid)
      this.addLog('Surface ID: ' + sid)
    }
    this.addLog('Preparing: ' + this.testUrl)
    let options = new PlaybackOptions()
    options.url = this.testUrl
    this.player.prepare(options)
  }

  buildPocConclusions(): void {
    this.pocConclusions = [
      '=== T0.3 AVPlayer POC Conclusion Document ===',
      '',
      '1. State Machine:',
      '   idle -> initialized -> prepared -> playing <-> paused',
      '   playing -> completed -> stopped',
      '   Any state -> error / released',
      '',
      '2. URL Setting: player.url = string (direct string assignment)',
      '   - Supports http/https URLs for m3u8/mp4',
      '   - Headers support: NOT natively supported by AVPlayer',
      '',
      '3. Surface Binding: player.surfaceId = string (property assignment)',
      '   - surfaceId from XComponentController.getXComponentSurfaceId()',
      '   - Must set surfaceId BEFORE setting url',
      '',
      '4. Playback Controls:',
      '   - play()/pause()/stop()/seek(ms)/setSpeed(PlaybackSpeed)/setVolume(vol)',
      '   - Speed enum: SPEED_FORWARD_0_25/50/75/100/125/175/200_X',
      '   - Volume range: 0.0-1.0',
      '',
      '5. Event Listeners:',
      '   - on("stateChange", (state: string) => void)',
      '   - on("timeUpdate", (time: number) => void)',
      '   - on("bufferingUpdate", (infoType: BufferingInfoType, value: number) => void)',
      '   - on("error", () => void)',
      '',
      '6. BufferingInfoType enum:',
      '   - BUFFERING_START=1, BUFFERING_END=2, BUFFERING_PERCENT=3, CACHED_DURATION=4',
      '',
      '7. Headers/Referer/UA Support:',
      '   - AVPlayer does NOT natively support custom headers',
      '   - Degradation: local proxy injection (TBD) or mpv engine',
      '',
      '8. AVPlayer MVP Subset:',
      '   - Can play: direct m3u8/mp4 URLs without custom headers',
      '   - Cannot play: URLs requiring custom headers/referer/proxy',
      '   - Recommendation: AVPlayer as basic player, mpv for advanced',
      '',
      '9. Go/No-Go: AVPlayer covers basic playback scenarios.',
      '   - For header-required sources, show "current player unsupported" message.',
      '   - mpv priority remains P1 (Phase 3).',
    ]
  }

  build() {
    Column() {
      Text('T0.3 AVPlayer POC')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })

      Scroll() {
        Column() {
          Row() {
            TextInput({ text: this.testUrl, placeholder: 'Enter video URL' })
              .onChange((value: string) => { this.testUrl = value })
              .layoutWeight(1)
              .height(40)
          }
          .width('100%')
          .margin({ bottom: 8 })

          Row() {
            Button('Bunny MP4')
              .onClick(() => {
                this.testUrl = 'https://media.w3.org/2010/05/sintel/trailer.mp4'
              })
              .fontSize(11)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
              .layoutWeight(1)
            Button('Bunny M3U8')
              .onClick(() => {
                this.testUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'
              })
              .fontSize(11)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 8 })

          XComponent({ id: this.xcomponentId, type: 'surface', controller: this.xcomponentController })
            .onLoad(() => {
              this.addLog('XComponent loaded')
              let sid = this.xcomponentController.getXComponentSurfaceId()
              if (sid) {
                this.surfaceId = sid
                this.addLog('Surface ID from controller: ' + sid)
              }
            })
            .width('100%')
            .height(200)
            .margin({ bottom: 8 })

          Column() {
            Row() {
              Text('State: ').fontSize(13).fontWeight(FontWeight.Bold)
              Text(this.statusText).fontSize(13)
                .fontColor(this.statusText === 'error' ? Color.Red :
                           this.statusText === 'playing' ? Color.Green :
                           this.statusText === 'prepared' ? Color.Blue : Color.Black)
            }.width('100%')
            Row() {
              Text('Position: ').fontSize(12)
              Text(this.formatTime(this.positionMs)).fontSize(12)
              Text(' / ').fontSize(12)
              Text(this.formatTime(this.durationMs)).fontSize(12)
            }.width('100%')
            Row() {
              Text('Volume: ').fontSize(12)
              Text(this.volume.toFixed(2)).fontSize(12)
              Text('  Speed: ').fontSize(12)
              Text(this.speed.toFixed(2) + 'x').fontSize(12)
            }.width('100%')
            if (this.isBuffering) {
              Text('Buffering...').fontSize(12).fontColor(Color.Orange)
            }
            if (this.errorMsg) {
              Text('Error: ' + this.errorMsg).fontSize(12).fontColor(Color.Red)
            }
          }
          .width('100%')
          .padding(8)
          .backgroundColor('#f0f0f0')
          .borderRadius(8)
          .margin({ bottom: 8 })

          Row() {
            Button('Prepare')
              .onClick(() => this.startPlay())
              .enabled(this.statusText === 'idle' || this.statusText === 'stopped' || this.statusText === 'creating' || this.statusText === '')
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button(this.isPlaying ? 'Pause' : 'Play')
              .onClick(() => {
                if (this.isPlaying) {
                  this.player.pause()
                } else {
                  this.player.play()
                }
              })
              .enabled(this.statusText === 'prepared' || this.statusText === 'playing' || this.statusText === 'paused' || this.statusText === 'completed')
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button('Stop')
              .onClick(() => this.player.stop())
              .enabled(this.statusText === 'prepared' || this.statusText === 'playing' || this.statusText === 'paused' || this.statusText === 'completed')
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
          }
          .width('100%')
          .margin({ bottom: 4 })

          Row() {
            Button('Seek +10s')
              .onClick(() => this.player.seek(this.positionMs + 10000))
              .enabled(this.statusText === 'prepared' || this.statusText === 'playing' || this.statusText === 'paused')
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button('Seek -10s')
              .onClick(() => this.player.seek(Math.max(0, this.positionMs - 10000)))
              .enabled(this.statusText === 'prepared' || this.statusText === 'playing' || this.statusText === 'paused')
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button('Release')
              .onClick(() => this.player.release())
              .layoutWeight(1)
              .fontSize(12)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
          }
          .width('100%')
          .margin({ bottom: 4 })

          Row() {
            Button('0.5x')
              .onClick(() => this.player.setSpeed(0.5))
              .layoutWeight(1)
              .fontSize(11)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button('1.0x')
              .onClick(() => this.player.setSpeed(1.0))
              .layoutWeight(1)
              .fontSize(11)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button('1.5x')
              .onClick(() => this.player.setSpeed(1.5))
              .layoutWeight(1)
              .fontSize(11)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            Button('2.0x')
              .onClick(() => this.player.setSpeed(2.0))
              .layoutWeight(1)
              .fontSize(11)
              .backgroundColor('#D9007DFF')
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: '#4DFFFFFF' })
              .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
          }
          .width('100%')
          .margin({ bottom: 4 })

          Row() {
            Text('Volume:').fontSize(12).margin({ right: 4 })
            Slider({ value: this.volume, min: 0, max: 1, step: 0.1 })
              .onChange((value: number) => {
                this.player.setVolume(value)
              })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 8 })

          Divider().margin({ bottom: 8 })

          Button('Generate POC Conclusion Document')
            .onClick(() => this.buildPocConclusions())
            .width('100%')
            .backgroundColor('#D9007DFF')
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .border({ width: 0.5, color: '#4DFFFFFF' })
            .shadow({ radius: 12, color: '#22007DFF', offsetY: 3 })
            .margin({ bottom: 8 })

          if (this.pocConclusions.length > 0) {
            Text('POC Conclusion:')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .margin({ bottom: 4 })
            ForEach(this.pocConclusions, (line: string, index?: number) => {
              Text(line)
                .fontSize(10)
                .fontFamily('monospace')
                .width('100%')
            }, (line: string, index?: number) => index?.toString() ?? '')
          }

          Divider().margin({ top: 8, bottom: 8 })

          Text('State Log:')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(this.stateLog, (msg: string, index?: number) => {
            Text(msg)
              .fontSize(9)
              .fontColor(msg.indexOf('error') !== -1 ? Color.Red : Color.Gray)
              .width('100%')
          }, (msg: string, index?: number) => index?.toString() ?? '')
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background('#FFFFFF')
    .ignoreLayoutSafeArea()
    .padding(16)
  }

  private formatTime(ms: number): string {
    let totalSec = Math.floor(ms / 1000)
    let min = Math.floor(totalSec / 60)
    let sec = totalSec % 60
    return min + ':' + (sec < 10 ? '0' : '') + sec
  }
}
