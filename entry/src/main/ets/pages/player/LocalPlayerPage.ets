import { PlayerSurface } from '../../components/player/PlayerSurface'
import { GestureLayer } from '../../components/player/GestureLayer'
import { DanmakuCanvas } from '../../components/player/DanmakuCanvas'
import { IPlayerEngine, PlaybackOptions, PlayerState, VideoAspectMode } from '../../core/player/IPlayerEngine'
import { DanmakuManager } from '../../core/danmaku/DanmakuManager'
import { DanmakuFileParser, LocalDanmakuParseResult } from '../../core/danmaku/DanmakuFileParser'
import { LocalFilePicker, LocalFileResult } from '../../services/LocalFilePicker'
import { DanmakuSettingsPanelContent } from '../../components/player/DanmakuSettingsPanel'
import { DanmakuSettingsSidePanel } from '../../components/player/DanmakuSettingsSidePanel'
import { AspectModePanel } from '../../components/player/AspectModePanel'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { router, window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { getEffectiveTopSafeHeight } from '../../utils/HdsPageStyle'

const logger = new Logger('LocalPlayerPage')

@Entry
@Component
export struct LocalPlayerPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('danmakuSettingsVersion') @Watch('onDanmakuSettingsVersionChanged') danmakuSettingsVersion: number = 0
  @State videoUri: string = ''
  @State videoFileName: string = ''
  @State isPlaying: boolean = false
  @State positionMs: number = 0
  @State durationMs: number = 0
  @State speed: number = 1.0
  @State speedLabel: string = '1x'
  @State isControlVisible: boolean = true
  @State isDraggingProgress: boolean = false
  @State isFullScreen: boolean = false
  @State playbackOptions: PlaybackOptions = new PlaybackOptions()
  @State screenBrightness: number = 0.5
  @State volume: number = 1.0
  private playerEngine: IPlayerEngine | null = null
  @State hasEngine: boolean = false
  private danmakuManager: DanmakuManager | null = null
  @State isDanmakuEnabled: boolean = true
  @State showMoreMenu: boolean = false
  @State showHud: boolean = false
  @State hudText: string = ''
  @State danmakuFileName: string = ''
  @State currentAspectMode: VideoAspectMode = VideoAspectMode.contain
  @State showAspectModePanel: boolean = false
  @State showDanmakuSettingsPanel: boolean = false
  @State showDanmakuSettingsSheet: boolean = false
  @State danmakuSettingsOpenVersion: number = 0
  private controlHideTimer: number = -1
  private hudTimer: number = -1
  private wasPlayingBeforeDrag: boolean = false
  private audioManager: Object | null = null

  aboutToAppear(): void {
    this.danmakuManager = new DanmakuManager()
    this.danmakuManager.init().then(() => {
      if (this.danmakuManager !== null) {
        this.isDanmakuEnabled = this.danmakuManager.getIsDanmakuEnabled()
      }
    })

    const params = router.getParams() as Record<string, Object>
    if (params !== null) {
      if (params['videoUri'] !== undefined) this.videoUri = params['videoUri'] as string
      if (params['videoFileName'] !== undefined) this.videoFileName = params['videoFileName'] as string
    }

    if (this.videoUri.length > 0) {
      const options = new PlaybackOptions()
      options.url = this.videoUri
      this.playbackOptions = options
    }

    this.startAutoHideTimer()
    this.loadAspectModePreference()
  }

  aboutToDisappear(): void {
    this.pauseAutoHideTimer()
    this.clearHudTimer()
    if (this.danmakuManager !== null) {
      this.danmakuManager.release()
      this.danmakuManager = null
    }
    if (this.isFullScreen) {
      this.setFullScreenMode(false)
    }
  }

  onBackPress(): boolean {
    if (this.isFullScreen) {
      this.toggleFullScreen()
      return true
    }
    return false
  }

  build() {
    Stack() {
      Column() {
        if (!this.isFullScreen) {
          Column()
            .width('100%')
            .height(getEffectiveTopSafeHeight(this.topSafeHeight))
            .backgroundColor($r('app.color.page_background_media'))
        }

        this.VideoSection()

        if (!this.isFullScreen) {
          this.LocalInfoSection()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.isFullScreen ? Color.Black : $r('app.color.page_background_media'))
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background_media'))
    .bindSheet($$this.showDanmakuSettingsSheet, this.buildDanmakuSettingsSheet, {
      height: '50%',
      showClose: false,
      dragBar: true,
      onAppear: () => {
        this.pauseAutoHideTimer()
      },
      onDisappear: () => {
        this.showDanmakuSettingsSheet = false
        this.startAutoHideTimer()
      }
    })
  }

  @Builder
  private VideoSection() {
    Stack({ alignContent: Alignment.Center }) {
      this.VideoLayerContent()
    }
    .width('100%')
    .height(this.isFullScreen ? '100%' : undefined)
    .aspectRatio(this.isFullScreen ? undefined : 16 / 9)
    .layoutWeight(this.isFullScreen ? 1 : 0)
    .backgroundColor(Color.Black)
    .clip(true)
  }

  @Builder
  private VideoLayerContent() {
    if (this.videoUri.length > 0) {
      PlayerSurface({
        videoUrl: this.videoUri,
        playbackOptions: this.playbackOptions,
        fillParent: this.isFullScreen,
        aspectMode: this.currentAspectMode,
        onStateChange: (state: PlayerState) => {
          this.handlePlayerState(state)
        },
        onEngineReady: (engine: IPlayerEngine) => {
          this.playerEngine = engine
          this.hasEngine = true
          if (this.danmakuManager !== null) {
            this.danmakuManager.init().then(() => {
              this.isDanmakuEnabled = this.danmakuManager!.getIsDanmakuEnabled()
            })
          }
        }
      })

      DanmakuCanvas({
        isDanmakuEnabled: this.isDanmakuEnabled,
        onCanvasReady: (context: CanvasRenderingContext2D, width: number, height: number) => {
          if (this.danmakuManager !== null) {
            this.danmakuManager.onCanvasReady(context, width, height)
          }
        },
        onCanvasSizeChanged: (width: number, height: number) => {
          if (this.danmakuManager !== null) {
            this.danmakuManager.onCanvasSizeChanged(width, height)
          }
        }
      })
        .width('100%')
        .height('100%')
        .zIndex(2)
    } else {
      Column() {
        Text('未选择视频文件')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }

    GestureLayer({
      durationMs: this.durationMs,
      positionMs: this.positionMs,
      volume: this.volume,
      screenBrightness: this.screenBrightness,
      isPlaying: this.isPlaying,
      isControlVisible: this.isControlVisible,
      onSeek: (positionMs: number) => {
        this.seekTo(positionMs)
        this.showHudText('跳转到 ' + this.formatTime(positionMs))
        this.showControlsWithAutoHide()
      },
      onVolumeChange: (volume: number) => {
        if (this.hasEngine && this.playerEngine !== null) {
          this.playerEngine.setVolume(volume)
        }
      },
      onBrightnessChange: (brightness: number) => {
        this.requestWindowBrightness(brightness)
      },
      onTogglePlayPause: () => {
        this.togglePlayPause()
        this.showHudText(this.isPlaying ? '播放' : '暂停')
      },
      onToggleControls: () => {
        this.toggleControls()
      },
      onTemporarySpeedStart: () => {
        this.startTemporarySpeed()
      },
      onTemporarySpeedEnd: () => {
        this.endTemporarySpeed()
      }
    })
      .width('100%')
      .height('100%')
      .zIndex(4)

    this.PlayerControlOverlay()

    if (this.showHud) {
      this.HudView()
    }

    if (this.isFullScreen && this.showDanmakuSettingsPanel) {
      DanmakuSettingsSidePanel({
        showPanel: this.showDanmakuSettingsPanel,
        isDanmakuEnabled: this.isDanmakuEnabled,
        isFullScreen: this.isFullScreen,
        settingsVersion: this.danmakuSettingsOpenVersion,
        onPanelClose: () => {
          this.closeDanmakuSettings()
        },
        onToggleDanmaku: () => {
          this.toggleDanmaku()
        },
        onPauseAutoHide: () => {
          this.pauseAutoHideTimer()
        },
        onResumeAutoHide: () => {
          this.startAutoHideTimer()
        }
      })
        .zIndex(10)
    }
  }

  @Builder
  private PlayerControlOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.VideoTopBar()
        Blank()
          .layoutWeight(1)
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
        this.VideoBottomBar()
      }
      .width('100%')
      .height('100%')
      .zIndex(6)
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.showMoreMenu) {
        this.PlayerMoreMenu()
      }

      if (this.showAspectModePanel) {
        this.AspectModePanelOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(6)
    .hitTestBehavior(this.isControlVisible ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private VideoTopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([$r('app.color.text_on_primary')])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.isFullScreen) {
          this.toggleFullScreen()
        } else {
          router.back()
        }
      })

      if (this.isFullScreen) {
        Text(this.videoFileName.length > 0 ? this.videoFileName : '本地播放')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_on_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 10, right: 10 })
      } else {
        Blank()
          .layoutWeight(1)
      }

      this.TopSymbolButton($r('sys.symbol.doc_text'), '加载弹幕', () => {
        this.pickAndLoadLocalDanmaku()
      })

      this.TopSymbolButton(this.showMoreMenu ? $r('sys.symbol.xmark') : $r('sys.symbol.dot_grid_1x2'),
        this.showMoreMenu ? '收起' : '更多', () => {
        this.showMoreMenu = !this.showMoreMenu
        if (this.showMoreMenu) {
          this.pauseAutoHideTimer()
        } else {
          this.startAutoHideTimer()
        }
      })
    }
    .width('100%')
    .height(this.isFullScreen ? this.topSafeHeight + 68 : 64)
    .padding({ left: 10, right: 14, top: this.isFullScreen ? this.topSafeHeight + 8 : 8, bottom: 8 })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#AA000000', 0.0], ['#5C000000', 0.55], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : -12 })
    .opacity(this.isControlVisible ? 1 : 0)
    .animation({ duration: 250, curve: Curve.EaseInOut })
  }

  @Builder
  private VideoBottomBar() {
    Column() {
      if (this.isFullScreen) {
        this.LandscapeProgressRow()
        this.LandscapeControlRow()
      } else {
        this.PortraitControlRow()
      }
    }
    .width('100%')
    .padding({ top: this.isFullScreen ? 18 : 12 })
    .linearGradient({
      direction: GradientDirection.Top,
      colors: [['#B8000000', 0.0], ['#70000000', 0.58], ['#00000000', 1.0]]
    })
    .zIndex(6)
    .translate({ y: this.isControlVisible ? 0 : 12 })
    .opacity(this.isControlVisible ? 1 : 0)
    .animation({ duration: 250, curve: Curve.EaseInOut })
  }

  @Builder
  private LandscapeProgressRow() {
    Row() {
      Text(this.formatTime(this.positionMs))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
      this.ProgressSlider()
      Text(this.formatTime(this.durationMs))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
    }
    .width('100%')
    .height(28)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  private ProgressSlider() {
    Slider({
      value: this.durationMs > 0 ? this.positionMs : 0,
      min: 0,
      max: this.durationMs > 0 ? this.durationMs : 1,
      step: 1000
    })
      .layoutWeight(1)
      .trackColor('#55FFFFFF')
      .selectedColor($r('app.color.accent_blue'))
      .blockColor($r('app.color.text_on_primary'))
      .onChange((value: number, mode: SliderChangeMode) => {
        if (mode === SliderChangeMode.Begin) {
          this.isDraggingProgress = true
          this.wasPlayingBeforeDrag = this.isPlaying
          if (this.wasPlayingBeforeDrag && this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.pause()
          }
          this.pauseAutoHideTimer()
        } else if (mode === SliderChangeMode.Moving) {
          this.positionMs = value
        } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
          this.isDraggingProgress = false
          this.seekTo(value)
          if (this.wasPlayingBeforeDrag && this.hasEngine && this.playerEngine !== null) {
            this.playerEngine.play()
          }
          this.showControlsWithAutoHide()
        } else {
          this.positionMs = value
        }
      })
  }

  @Builder
  private PortraitControlRow() {
    Column() {
      Row() {
        Text(this.formatTime(this.positionMs))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')
        this.ProgressSlider()
        Text(this.formatTime(this.durationMs))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E6FFFFFF')
      }
      .width('100%')
      .height(24)
      .padding({ left: 14, right: 14 })

      Row() {
        if (this.isPlaying) {
          this.SymbolToolButton($r('sys.symbol.pause_fill'), '暂停', () => {
            this.togglePlayPause()
          })
        } else {
          this.SymbolToolButton($r('sys.symbol.play_fill'), '播放', () => {
            this.togglePlayPause()
          })
        }

        Blank()
          .layoutWeight(1)

        this.DanmakuToggleButton()

        this.SpeedToolButton()

        this.SymbolToolButton($r('sys.symbol.arrow_up_left_and_arrow_down_right'), '全屏', () => {
          this.toggleFullScreen()
        })
      }
      .width('100%')
      .height(50)
      .padding({ left: 10, right: 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ bottom: this.bottomSafeHeight > 0 ? this.bottomSafeHeight : 0 })
  }

  @Builder
  private LandscapeControlRow() {
    Row({ space: 8 }) {
      if (this.isPlaying) {
        this.SymbolToolButton($r('sys.symbol.pause_fill'), '暂停', () => {
          this.togglePlayPause()
        })
      } else {
        this.SymbolToolButton($r('sys.symbol.play_fill'), '播放', () => {
          this.togglePlayPause()
        })
      }

      this.DanmakuToggleButton()

      this.SymbolToolButton($r('sys.symbol.barrage_setting'), '弹幕设置', () => {
        this.openDanmakuSettings()
      })

      Blank()
        .layoutWeight(1)

      this.SpeedToolButton()

      this.SymbolToolButton(this.isFullScreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
        $r('sys.symbol.arrow_up_left_and_arrow_down_right'), this.isFullScreen ? '退出全屏' : '全屏', () => {
        this.toggleFullScreen()
      })
    }
    .height(this.bottomSafeHeight + 62)
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: this.bottomSafeHeight + 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SpeedToolButton() {
    Row() {
      Text(this.speedLabel)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(44)
    .height(40)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.nextSpeed()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private TopSymbolButton(symbol: Resource, accessibilityLabel: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private SymbolToolButton(symbol: Resource, accessibilityLabel: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(23)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .width(44)
    .height(40)
    .borderRadius(20)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private DanmakuToggleButton() {
    Row() {
      SymbolGlyph(this.isDanmakuEnabled ? $r('sys.symbol.barrage_on') : $r('sys.symbol.barrage_off  '))
        .fontSize(23)
        .renderingStrategy(this.isDanmakuEnabled ? SymbolRenderingStrategy.MULTIPLE_COLOR : SymbolRenderingStrategy.SINGLE)
        .fontColor(this.isDanmakuEnabled ?
          ['#F2FFFFFF', $r('app.color.accent_blue'), $r('app.color.accent_blue')] :
          ['#F2FFFFFF'])
    }
    .width(44)
    .height(40)
    .borderRadius(20)
    .backgroundColor('#00000000')
    .border({ width: 0, color: '#00000000' })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleDanmaku()
      this.showControlsWithAutoHide()
    })
  }

  @Builder
  private HudView() {
    Column() {
      Text(this.hudText)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_on_primary'))
        .padding({ left: 24, right: 24, top: 14, bottom: 14 })
        .borderRadius(18)
        .backgroundColor('#8A000000')
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: '#33FFFFFF' })
        .shadow({ radius: 18, color: '#66000000', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .zIndex(9)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private LocalInfoSection() {
    Column() {
      Row() {
        Text(this.videoFileName.length > 0 ? this.videoFileName : '本地播放')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.danmakuFileName.length > 0) {
          Text(this.danmakuFileName)
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Row() {
        Button('选择视频')
          .height(36)
          .fontSize(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(18)
          .margin({ right: 8 })
          .onClick(() => {
            this.pickVideoFile()
          })

        Button('加载弹幕')
          .height(36)
          .fontSize(14)
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor(Color.White)
          .borderRadius(18)
          .onClick(() => {
            this.pickAndLoadLocalDanmaku()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .padding({ bottom: this.bottomSafeHeight > 0 ? this.bottomSafeHeight : 0 })
    .backgroundColor($r('app.color.page_background_media'))
  }

  @Builder
  private PlayerMoreMenu() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.showMoreMenu = false
        })

      Column() {
        this.MoreMenuItem(this.isDanmakuEnabled ? '关闭弹幕' : '开启弹幕', () => {
          this.toggleDanmaku()
          this.showMoreMenu = false
        })
        this.MoreMenuItem('加载本地弹幕', () => {
          this.pickAndLoadLocalDanmaku()
          this.showMoreMenu = false
        })
        this.MoreMenuItem('弹幕设置', () => {
          this.openDanmakuSettings()
          this.showMoreMenu = false
        })
        this.MoreMenuItem('视频比例', () => {
          this.showAspectModePanel = true
        })
        this.MoreMenuItem('倍速', () => {
          this.nextSpeed()
          this.showMoreMenu = false
        })
      }
      .width(156)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.category_menu_surface'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
      .margin({ top: this.isFullScreen ? this.topSafeHeight + 46 : 46, right: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(8)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private AspectModePanelOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.showAspectModePanel = false
        })

      AspectModePanel({
        currentMode: this.currentAspectMode,
        onSelectMode: (mode: VideoAspectMode) => {
          this.applyAspectMode(mode)
          this.showAspectModePanel = false
          this.showMoreMenu = false
        }
      })
        .margin({ top: this.isFullScreen ? this.topSafeHeight + 46 : 46, right: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(9)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
  }

  @Builder
  private MoreMenuItem(label: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      action()
    })
  }

  @Builder
  buildDanmakuSettingsSheet() {
    DanmakuSettingsPanelContent({
      isDanmakuEnabled: this.isDanmakuEnabled,
      isFullScreen: this.isFullScreen,
      settingsVersion: this.danmakuSettingsOpenVersion,
      onToggleDanmaku: () => {
        this.toggleDanmaku()
      },
      onPanelClose: () => {
        this.showDanmakuSettingsSheet = false
      },
      onPauseAutoHide: () => {
        this.pauseAutoHideTimer()
      },
      onResumeAutoHide: () => {
        this.startAutoHideTimer()
      }
    })
  }

  private handlePlayerState(state: PlayerState): void {
    this.isPlaying = state.playing
    this.positionMs = state.positionMs
    this.durationMs = state.durationMs
    this.volume = state.volume
    this.speed = state.speed
    this.speedLabel = this.speed.toFixed(this.speed % 1 === 0 ? 0 : 2) + 'x'

    if (this.danmakuManager !== null) {
      this.danmakuManager.onPlayerStateUpdate(state)
    }
  }

  private togglePlayPause(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      if (this.isPlaying) {
        this.playerEngine.pause()
      } else {
        this.playerEngine.play()
      }
    }
  }

  private seekTo(positionMs: number): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.seek(positionMs)
    }
  }

  private toggleDanmaku(): void {
    if (this.danmakuManager !== null) {
      this.isDanmakuEnabled = this.danmakuManager.toggleDanmaku()
    }
  }

  private toggleControls(): void {
    this.isControlVisible = !this.isControlVisible
    if (this.isControlVisible) {
      this.startAutoHideTimer()
    } else {
      this.pauseAutoHideTimer()
    }
  }

  private showControlsWithAutoHide(): void {
    this.isControlVisible = true
    this.startAutoHideTimer()
  }

  private nextSpeed(): void {
    const speeds: number[] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    let currentIndex = 0
    for (let i = 0; i < speeds.length; i++) {
      if (Math.abs(this.speed - speeds[i]) < 0.01) {
        currentIndex = i
        break
      }
    }
    const nextIndex = (currentIndex + 1) % speeds.length
    const newSpeed = speeds[nextIndex]
    this.speed = newSpeed
    this.speedLabel = newSpeed % 1 === 0 ? newSpeed.toFixed(0) + 'x' : newSpeed.toFixed(2).replace(/0+$/, '').replace(/\.$/, '') + 'x'
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(newSpeed)
    }
    if (this.danmakuManager !== null) {
      const renderer = this.danmakuManager.getRenderer()
      if (renderer !== null) {
        renderer.setPlaybackSpeed(newSpeed)
      }
    }
  }

  private toggleFullScreen(): void {
    this.isFullScreen = !this.isFullScreen
    this.setFullScreenMode(this.isFullScreen)
    this.showControlsWithAutoHide()
  }

  private async setFullScreenMode(fullScreen: boolean): Promise<void> {
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      if (fullScreen) {
        mainWindow.setWindowSystemBarEnable([])
        await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE)
      } else {
        mainWindow.setWindowSystemBarEnable(['status', 'navigation'])
        await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
      }
    } catch (_err) {
      logger.warn('Failed to toggle fullscreen mode')
    }
  }

  private async requestWindowBrightness(brightness: number): Promise<void> {
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      await mainWindow.setWindowBrightness(brightness)
    } catch (_err) {
      logger.warn('Failed to apply window brightness')
    }
  }

  private applyAspectMode(mode: VideoAspectMode): void {
    this.currentAspectMode = mode
  }

  private async loadAspectModePreference(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      const savedMode = await prefs.getNumber('aspectMode', VideoAspectMode.contain)
      this.currentAspectMode = savedMode as VideoAspectMode
    } catch (_err) {
      this.currentAspectMode = VideoAspectMode.contain
    }
  }

  private startTemporarySpeed(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      this.playerEngine.setSpeed(3.0)
      this.speed = 3.0
      this.speedLabel = '3x'
    }
  }

  private endTemporarySpeed(): void {
    if (this.hasEngine && this.playerEngine !== null) {
      const targetSpeed = this.speed === 3.0 ? 1.0 : this.speed
      this.playerEngine.setSpeed(targetSpeed)
      this.speed = targetSpeed
      this.speedLabel = targetSpeed % 1 === 0 ? targetSpeed.toFixed(0) + 'x' : targetSpeed.toFixed(1) + 'x'
    }
  }

  private openDanmakuSettings(): void {
    this.danmakuSettingsOpenVersion++
    if (this.isFullScreen) {
      this.showDanmakuSettingsPanel = true
    } else {
      this.showDanmakuSettingsSheet = true
    }
    this.pauseAutoHideTimer()
  }

  private closeDanmakuSettings(): void {
    this.showDanmakuSettingsPanel = false
    this.showDanmakuSettingsSheet = false
    this.startAutoHideTimer()
  }

  private onDanmakuSettingsVersionChanged(): void {
    if (this.danmakuManager !== null) {
      this.danmakuManager.reloadSettings()
    }
  }

  private async pickAndLoadLocalDanmaku(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const fileResult: LocalFileResult | null = await LocalFilePicker.pickDanmakuFile(context)
      if (fileResult === null) {
        return
      }
      const parseResult: LocalDanmakuParseResult = DanmakuFileParser.parse(fileResult.fileName, fileResult.content)
      if (parseResult.errorMessage.length > 0) {
        this.showHudText(parseResult.errorMessage)
        return
      }
      this.danmakuFileName = fileResult.fileName
      if (this.danmakuManager !== null) {
        if (this.danmakuManager.hasDanmakuData()) {
          this.danmakuManager.appendLocalDanmaku(parseResult.items)
          this.showHudText('追加 ' + parseResult.items.length + ' 条本地弹幕')
        } else {
          this.danmakuManager.loadLocalDanmaku(parseResult.items)
          this.showHudText('加载 ' + parseResult.items.length + ' 条本地弹幕')
        }
      }
    } catch (err) {
      logger.error('加载本地弹幕失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('加载本地弹幕失败')
    }
  }

  private async pickVideoFile(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const videoResult = await LocalFilePicker.pickVideoFile(context)
      if (videoResult === null) {
        return
      }
      this.videoUri = videoResult.uri
      this.videoFileName = videoResult.fileName
      const options = new PlaybackOptions()
      options.url = this.videoUri
      this.playbackOptions = options
      logger.info('选择本地视频: %{public}s', videoResult.fileName)
    } catch (err) {
      logger.error('选择视频文件失败: %{public}s', err instanceof Error ? err.message : String(err))
      this.showHudText('选择视频文件失败')
    }
  }

  private showHudText(text: string): void {
    this.hudText = text
    this.showHud = true
    this.clearHudTimer()
    this.hudTimer = setTimeout(() => {
      this.showHud = false
    }, 1500)
  }

  private startAutoHideTimer(): void {
    this.pauseAutoHideTimer()
    this.controlHideTimer = setTimeout(() => {
      this.isControlVisible = false
    }, 5000)
  }

  private pauseAutoHideTimer(): void {
    if (this.controlHideTimer >= 0) {
      clearTimeout(this.controlHideTimer)
      this.controlHideTimer = -1
    }
  }

  private clearHudTimer(): void {
    if (this.hudTimer >= 0) {
      clearTimeout(this.hudTimer)
      this.hudTimer = -1
    }
  }

  private formatTime(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    if (hours > 0) {
      return hours + ':' + String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
    }
    return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0')
  }
}
