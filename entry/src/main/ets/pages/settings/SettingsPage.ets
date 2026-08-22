import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { PreferencesStore } from '../../store/PreferencesStore'
import { SecurityPolicy } from '../../network/SecurityPolicy'
import { RuleCatalogService } from '../../services/RuleCatalogService'
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { Logger } from '../../utils/Logger'
import { promptAction, router } from '@kit.ArkUI'
import { RULE_SOURCE_VERSION_KEY } from '../../store/SettingsChangeSignal'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_ADAPTIVE,
  HDS_MATERIAL_LEVEL_DEFAULT,
  HDS_MATERIAL_LEVEL_EXQUISITE,
  HDS_MATERIAL_LEVEL_GENTLE,
  HDS_MATERIAL_LEVEL_SMOOTH,
  PREFS_KEY_HDS_MATERIAL_LEVEL,
  getHdsMaterialLevelLabel
} from '../../utils/HdsPageStyle'
import {
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  BOTTOM_TAB_SHOW_ANIMATION_DEFAULT,
  PREFS_KEY_BOTTOM_TAB_AUTO_HIDE,
  PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION,
  getBottomTabHideDistance,
  requestBottomTabAnimation,
  resolveBottomTabOffsetByDelta,
  resolveBottomTabSnapTarget
} from '../../utils/BottomTabAutoHide'
import {
  PLAYER_AUTO_FULLSCREEN_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_FULLSCREEN
} from '../../utils/PlayerAutoFullscreen'
import {
  PLAYER_AUTO_PIP_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_PIP
} from '../../utils/PlayerAutoPiP'
import {
  MPV_DETAIL_ENHANCER_ENABLED_DEFAULT,
  MPV_DETAIL_ENHANCER_QUALITY_DEFAULT,
  PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED,
  PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY
} from '../../utils/MpvSettings'
import {
  ADVANCED_OPTIONS_UNLOCKED_KEY,
  HIDE_LOCAL_PAGE_KEY,
  PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY,
  PLAYER_DEBUG_OPTIONS_UNLOCK_TAP_COUNT,
  PLAYER_DEBUG_OPTIONS_UNLOCK_WINDOW_MS
} from '../../utils/AdvancedOptionsUnlock'
import { AppConstants } from '../../constants/AppConstants'
import { RuleShopPageContent } from './RuleShopPage'
import { DanmakuSettingsPageContent } from './DanmakuSettingsPage'
import { WebDavSyncPageContent } from './WebDavSyncPage'
import { HistoryPageContent } from '../history/HistoryPage'
import {
  ANTI_PEEP_ENABLED_DEFAULT,
  AntiPeepService,
  PREFS_KEY_ANTI_PEEP_ENABLED
} from '../../services/AntiPeepService'
import {
  API26_MATERIAL_STYLE_DEFAULT,
  API26_MATERIAL_STYLE_THIN,
  API26_MATERIAL_STYLE_REGULAR,
  API26_MATERIAL_STYLE_THICK,
  API26_MATERIAL_STYLE_ULTRA_THIN,
  API26_MATERIAL_STYLE_ULTRA_THICK,
  PREFS_KEY_API26_MATERIAL_STYLE,
  getApi26MaterialStyleLabel,
  isImmersiveMaterialSupported,
  normalizeApi26MaterialStyle
} from '../../utils/ImmersiveMaterial'

const logger = new Logger('SettingsPage')
const SETTINGS_DESTINATION_RULE_SHOP: string = 'settings_rule_shop'
const SETTINGS_DESTINATION_DANMAKU: string = 'settings_danmaku'
const SETTINGS_DESTINATION_DOWNLOAD: string = 'settings_download'
const SETTINGS_DESTINATION_HISTORY: string = 'settings_history'
const SETTINGS_DESTINATION_WEBDAV: string = 'settings_webdav'
const SETTINGS_DESTINATION_PLAYER: string = 'settings_player'
const SETTINGS_DESTINATION_APP: string = 'settings_app'
const SETTINGS_DESTINATION_ABOUT: string = 'settings_about'

@CustomDialog
struct SponsorDialog {
  controller?: CustomDialogController

  build() {
    Column() {
      Text('鼓励作者')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 18 })

      Image($r('app.media.sponsor_qr'))
        .draggable(false)
        .width('100%')
        .height(300)
        .objectFit(ImageFit.Contain)
        .borderRadius(16)
        .backgroundColor(Color.White)

      Text('您的支持是对作者最大的鼓励')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 18, bottom: 18 })

      Button('关闭')
        .width(168)
        .height(46)
        .borderRadius(23)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
        .backgroundColor($r('app.color.accent_blue'))
        .onClick(() => {
          this.controller?.close()
        })
    }
    .width('84%')
    .padding({ left: 22, right: 22, top: 26, bottom: 24 })
    .borderRadius(26)
    .backgroundColor($r('app.color.card_background'))
    .shadow({ radius: 24, color: $r('app.color.shadow_surface'), offsetY: 8 })
    .alignItems(HorizontalAlign.Center)
  }
}

@CustomDialog
struct PainlessSupportDialog {
  controller?: CustomDialogController

  build() {
    Column() {
      Text('支持说明')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 18 })

      Text('由于该应用无法上架应用商店（曾经上架过，但是被下架并封号），如果您对该应用感到满意，可以在应用市场下载“影匣”，并打开使用两分钟（可以的话，隔一两天打开一次）。影匣也会不断更新迭代，您的支持是对作者最大的鼓励。')
        .fontSize(16)
        .fontWeight(FontWeight.Regular)
        .fontColor($r('app.color.text_body'))
        .lineHeight(25)
        .textAlign(TextAlign.Start)
        .width('100%')

      Button('我已知晓')
        .width('100%')
        .height(48)
        .margin({ top: 22 })
        .borderRadius(24)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
        .backgroundColor($r('app.color.accent_blue'))
        .onClick(() => {
          this.controller?.close()
        })
    }
    .width('86%')
    .constraintSize({ maxWidth: 430 })
    .padding({ left: 24, right: 24, top: 26, bottom: 24 })
    .borderRadius(26)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Center)
  }
}

@CustomDialog
struct QqGroupDialog {
  controller?: CustomDialogController
  onCopy: () => void = () => {}
  onJoin: () => void = () => {}

  build() {
    Column() {
      Text('QQ群')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 24 })

      Text('626493332')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 26 })

      Row() {
        Text('复制')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(48)
          .onClick(() => {
            this.controller?.close()
            this.onCopy()
          })
          .stateStyles({
            pressed: {
              .opacity(0.55)
            },
            normal: {
              .opacity(1)
            }
          })

        Column()
          .width(1)
          .height(30)
          .backgroundColor($r('app.color.divider_color'))

        Text('加群')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent_blue'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(48)
          .onClick(() => {
            this.controller?.close()
            this.onJoin()
          })
          .stateStyles({
            pressed: {
              .opacity(0.55)
            },
            normal: {
              .opacity(1)
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('92%')
    .constraintSize({ maxWidth: 460 })
    .padding({ left: 28, right: 28, top: 28, bottom: 26 })
    .borderRadius({ topLeft: 30, topRight: 30, bottomLeft: 30, bottomRight: 30 })
    .backgroundColor($r('app.color.card_background'))
  }
}

@Component
export struct SettingsPage {
  @Prop standaloneDestination: string = ''
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('screenHeightVp') screenHeightVp: number = 0
  @StorageLink('bottomTabAutoHide') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabShowAnimation') bottomTabShowAnimation: boolean = BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @State ruleCount: number = 0
  @State enabledRuleCount: number = 0
  @State allowHttpRequests: boolean = false
  @State defaultPlayerEngine: string = 'mpv'
  @State mpvHwdecMode: string = 'auto'
  @State mpvHlsAdFilter: boolean = true
  @State mpvSegAllowImg: boolean = true
  @StorageLink(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED) mpvDetailEnhancerEnabled: boolean = MPV_DETAIL_ENHANCER_ENABLED_DEFAULT
  @StorageLink(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY) mpvDetailEnhancerQuality: number = MPV_DETAIL_ENHANCER_QUALITY_DEFAULT
  @StorageLink('playerAutoFullscreen') playerAutoFullscreen: boolean = PLAYER_AUTO_FULLSCREEN_DEFAULT
  @StorageLink(PREFS_KEY_PLAYER_AUTO_PIP) playerAutoPiP: boolean = PLAYER_AUTO_PIP_DEFAULT
  @StorageLink(PREFS_KEY_ANTI_PEEP_ENABLED) antiPeepEnabled: boolean = ANTI_PEEP_ENABLED_DEFAULT
  @State snifferTimeout: number = 15
  @State rules: RuleSource[] = []
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private scroller: Scroller = new Scroller()
  private playerSettingsScroller: Scroller = new Scroller()
  private appSettingsScroller: Scroller = new Scroller()
  private aboutScroller: Scroller = new Scroller()
  private settingsPathStack: NavPathStack = new NavPathStack()

  @State colorMode: number = -1
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_API26_MATERIAL_STYLE) api26MaterialStyle: string = API26_MATERIAL_STYLE_DEFAULT
  @State showPlayerEngineMenu: boolean = false
  @State showMpvHwdecMenu: boolean = false
  @StorageLink(ADVANCED_OPTIONS_UNLOCKED_KEY) showAdvancedPlayerOptions: boolean = true
  @StorageLink(HIDE_LOCAL_PAGE_KEY) hideLocalPage: boolean = false
  @StorageLink(PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY) playerDebugOptionsUnlocked: boolean = false
  @State playerEngineTapCount: number = 0
  private playerEngineFirstTapTime: number = 0
  private sponsorDialogController: CustomDialogController | null = new CustomDialogController({
    builder: SponsorDialog(),
    customStyle: true,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_modal_bg')
  })
  private painlessSupportDialogController: CustomDialogController | null = new CustomDialogController({
    builder: PainlessSupportDialog(),
    customStyle: true,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_modal_bg')
  })
  private qqGroupDialogController: CustomDialogController | null = new CustomDialogController({
    builder: QqGroupDialog({
      onCopy: () => {
        this.copyQqGroup()
      },
      onJoin: () => {
        this.openQqGroup()
      }
    }),
    customStyle: true,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_modal_bg')
  })
  @StorageLink(RULE_SOURCE_VERSION_KEY) @Watch('onRuleSourceVersionChange') ruleSourceVersion: number = 0
  @State updatableCount: number = 0
  @State selectedSettingsDestination: string = ''
  private updateCheckToken: number = 0

  aboutToAppear(): void {
    this.loadSettings()
  }

  onPageShow(): void {
    this.loadSettings()
  }

  onRuleSourceVersionChange(): void {
    this.loadSettings()
  }

  build() {
    Stack() {
      if (this.standaloneDestination.length > 0) {
        this.StandaloneSettingsDetail()
      } else {
        HdsNavigation(this.settingsPathStack) {
        Scroll(this.scroller) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')

            this.SettingsCategorySection()

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12 })
          .constraintSize({ minHeight: '100%' })
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .clip(false)
        .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
          this.updateBottomTabOffset(yOffset)
        })
        .onScrollStop(() => {
          this.snapBottomTabOffset()
        })
      }
      .width('100%')
      .height('100%')
      .mode(this.shouldUseSettingsSplitMode() ? NavigationMode.Split : NavigationMode.Stack)
      .navDestination(this.SettingsDestinationBuilder)
      .navBarWidth(300)
      .navBarWidthRange({ minWidth: 240, maxWidth: 360 })
      .minContentWidth(360)
      .divider({
        color: $r('app.color.divider_color'),
        startMargin: 0,
        endMargin: 0
      })
      .enableDragBar(false)
      .enableModeChangeAnimation(true)
      .onNavigationModeChange((mode: NavigationMode) => {
        this.handleSettingsNavigationModeChange(mode)
      })
      .titleBar(buildTitleBarOptions('我的', this.hdsMaterialLevel))
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .backgroundColor(Color.Transparent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private StandaloneSettingsDetail(): void {
    HdsNavigation() {
      Scroll(this.getSettingsDetailScroller(this.standaloneDestination)) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          if (this.standaloneDestination === SETTINGS_DESTINATION_PLAYER) {
            this.PlayerSection(false)
          } else {
            this.AppSection(false)
          }

          Blank()
            .height(this.bottomSafeHeight + 24)
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12 })
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions(this.getSettingsDestinationTitle(this.standaloneDestination), this.hdsMaterialLevel))
    .bindToScrollable([this.getSettingsDetailScroller(this.standaloneDestination)])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private SettingsCategorySection(): void {
    Column() {
      this.SectionHeader('应用设置')
      Column() {
        if (this.showAdvancedPlayerOptions) {
          this.SettingsRouteItem(
            $r('sys.symbol.cart'),
            '规则仓库',
            this.updatableCount > 0 ? this.updatableCount + ' 条规则可更新' : '浏览、安装和导入规则',
            SETTINGS_DESTINATION_RULE_SHOP,
            () => {
              this.openSettingsRouteDestination(SETTINGS_DESTINATION_RULE_SHOP, 'pages/settings/RuleShopPage')
            },
            this.updatableCount
          )
          this.ItemDivider()
        }

        this.SettingsRouteItem(
          $r('sys.symbol.barrage_setting'),
          '弹幕设置',
          '来源、样式、屏蔽与缓存',
          SETTINGS_DESTINATION_DANMAKU,
          () => {
            this.openSettingsRouteDestination(SETTINGS_DESTINATION_DANMAKU, 'pages/settings/DanmakuSettingsPage')
          }
        )

        this.ItemDivider()
        this.SettingsRouteItem(
          $r('sys.symbol.arrowshape_down_to_line_fill'),
          '下载管理',
          '查看和管理视频下载任务',
          SETTINGS_DESTINATION_DOWNLOAD,
          () => {
            this.openSettingsRouteDestination(SETTINGS_DESTINATION_DOWNLOAD, 'pages/download/DownloadPage')
          }
        )

        if (this.showAdvancedPlayerOptions) {
          this.ItemDivider()
          this.SettingsRouteItem($r('sys.symbol.clock'), '历史记录', '查看播放历史',
            SETTINGS_DESTINATION_HISTORY, () => {
            this.openSettingsRouteDestination(SETTINGS_DESTINATION_HISTORY, 'pages/history/HistoryPage')
          })
          this.ItemDivider()
          this.SettingsRouteItem(
            $r('sys.symbol.arrow_2_circlepath'),
            '观看历史同步',
            '通过 WebDAV 同步多设备观看记录',
            SETTINGS_DESTINATION_WEBDAV,
            () => {
              this.openSettingsRouteDestination(SETTINGS_DESTINATION_WEBDAV, 'pages/settings/WebDavSyncPage')
            }
          )
        }

        this.ItemDivider()
        this.SettingsCategoryItem(
          $r('sys.symbol.play_round_rectangle'),
          '播放器',
          '播放引擎、全屏与画质设置',
          SETTINGS_DESTINATION_PLAYER
        )
        this.ItemDivider()
        this.SettingsCategoryItem(
          $r('sys.symbol.moon'),
          '外观动效',
          '主题、沉浸光感与底栏动效',
          SETTINGS_DESTINATION_APP
        )
        if (this.shouldUseSettingsSplitMode()) {
          this.ItemDivider()
          this.SettingsCategoryItem(
            $r('sys.symbol.info_circle'),
            '关于',
            '版本、开源组件与支持作者',
            SETTINGS_DESTINATION_ABOUT
          )
        }
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })

      if (!this.shouldUseSettingsSplitMode()) {
        this.AdvancedSection(true)
      }
    }
    .width('100%')
  }

  @Builder
  private SettingsCategoryItem(icon: Resource, title: string, desc: string, destination: string): void {
    Row() {
      this.SettingIcon(icon)
      this.SettingTitle(title, desc)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor(this.selectedSettingsDestination === destination ?
      $r('app.color.category_menu_item_selected') : Color.Transparent)
    .onClick(() => {
      this.openSettingsDestination(destination)
    })
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(this.selectedSettingsDestination === destination ?
          $r('app.color.category_menu_item_selected') : Color.Transparent)
      }
    })
  }

  @Builder
  private SettingsRouteItem(icon: Resource, title: string, desc: string, destination: string,
    action: () => void, badgeCount: number = 0): void {
    Row() {
      this.SettingIcon(icon)
      this.SettingTitle(title, desc)

      if (badgeCount > 0) {
        Text(`${badgeCount}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor($r('app.color.status_error'))
          .margin({ left: 8, right: 8 })
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor(this.selectedSettingsDestination === destination ?
      $r('app.color.category_menu_item_selected') : Color.Transparent)
    .onClick(action)
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(this.selectedSettingsDestination === destination ?
          $r('app.color.category_menu_item_selected') : Color.Transparent)
      }
    })
  }

  @Builder
  private SettingsDestinationBuilder(name: string, _param: Object): void {
    HdsNavDestination() {
      if (name === SETTINGS_DESTINATION_RULE_SHOP) {
        RuleShopPageContent({ embedded: true })
      } else if (name === SETTINGS_DESTINATION_DANMAKU) {
        DanmakuSettingsPageContent({ embedded: true })
      } else if (name === SETTINGS_DESTINATION_HISTORY) {
        HistoryPageContent({ embedded: true })
      } else if (name === SETTINGS_DESTINATION_WEBDAV) {
        WebDavSyncPageContent({ embedded: true })
      } else {
        Scroll(this.getSettingsDetailScroller(name)) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')

            if (name === SETTINGS_DESTINATION_PLAYER) {
              this.PlayerSection(false)
            } else if (name === SETTINGS_DESTINATION_APP) {
              this.AppSection(false)
            } else {
              this.AdvancedSection(false)
            }

            Blank()
              .height(this.getSettingsDestinationBottomSpacerHeight())
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12 })
          .constraintSize({ minHeight: '100%' })
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .clip(false)
        .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
          this.updateBottomTabOffset(yOffset, this.getSettingsDetailScroller(name))
        })
        .onScrollStop(() => {
          this.snapBottomTabOffset()
        })
      }
    }
    .width('100%')
    .height('100%')
    .titleBar(buildTitleBarOptions(this.getSettingsDestinationTitle(name), this.hdsMaterialLevel))
    .hideTitleBar(this.isEmbeddedSettingsDestination(name))
    .bindToScrollable([this.getSettingsDetailScroller(name)])
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(this.shouldUseSettingsSplitMode())
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onShown(() => {
      this.selectedSettingsDestination = name
    })
    .onHidden(() => {
      setTimeout(() => {
        this.syncSelectedSettingsDestination()
      }, 0)
    })
  }

  @Builder
  AppStatusCard(): void {
    Column() {
      Row() {
        Column() {
          Text('Kazumi')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text('开源番剧聚合播放器')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Row() {
        Row() {
          Text('规则')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 4 })
          Text(`${this.enabledRuleCount}/${this.ruleCount}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Row() {
          Text('播放器')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 4 })
          Text(this.defaultPlayerEngine === 'mpv' ? 'mpv' : 'AVPlayer')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor($r('app.color.button_ghost_bg'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 14 })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .borderRadius(12)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
  }

  @Builder
  QuickAccessSection(showHeader: boolean = true): void {
    Column() {
      if (showHeader) {
        this.SectionHeader('快捷入口')
      }
      Column() {
        if (this.showAdvancedPlayerOptions) {
          Row() {
            this.SettingIcon($r('sys.symbol.cart'))
            this.SettingTitle('规则仓库',
              this.updatableCount > 0 ? this.updatableCount + ' 条规则可更新' : '浏览、安装和导入规则')

            if (this.updatableCount > 0) {
              Row() {
                Text(`${this.updatableCount}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
              .width(22)
              .height(22)
              .borderRadius(11)
              .backgroundColor($r('app.color.status_error'))
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .margin({ left: 10, right: 6 })
            }

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('sys.color.icon_secondary')])
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .borderRadius(12)
          .onClick(() => {
            router.pushUrl({ url: 'pages/settings/RuleShopPage' })
          })
          .stateStyles({
            pressed: {
              .backgroundColor($r('app.color.category_menu_item_selected'))
            },
            normal: {
              .backgroundColor(Color.Transparent)
            }
          })

          this.ItemDivider()
        }

        Row() {
          this.SettingIcon($r('sys.symbol.barrage_setting'))
          this.SettingTitle('弹幕设置', '来源、样式、屏蔽与缓存')

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width('100%')
        .height(64)
        .padding({ left: 16, right: 16 })
        .borderRadius(12)
        .onClick(() => {
          router.pushUrl({ url: 'pages/settings/DanmakuSettingsPage' })
        })
        .stateStyles({
          pressed: {
            .backgroundColor($r('app.color.category_menu_item_selected'))
          },
          normal: {
            .backgroundColor(Color.Transparent)
          }
        })

        if (this.showAdvancedPlayerOptions) {
          this.ItemDivider()

          this.NavigationItem($r('sys.symbol.clock'), '历史记录', '查看播放历史', '', () => {
            router.pushUrl({ url: 'pages/history/HistoryPage' })
          })

          this.ItemDivider()

          this.NavigationItem(
            $r('sys.symbol.arrow_2_circlepath'),
            '观看历史同步',
            '通过 WebDAV 同步多设备观看记录',
            '',
            () => {
              router.pushUrl({ url: 'pages/settings/WebDavSyncPage' })
            }
          )
        }
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  PlayerSection(showHeader: boolean = true): void {
    Column() {
      if (showHeader) {
        this.SectionHeader('播放器')
      }
      Column() {
        Row() {
          this.SettingIcon($r('sys.symbol.play_round_rectangle'))
          this.PlayerEngineTitle()
          this.PlayerEnginePicker()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

        this.ItemDivider()

        this.ToggleItem(
          $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
          '横屏自动全屏',
          '手机横屏进入全屏，转回竖屏退出',
          this.playerAutoFullscreen,
          (isOn: boolean) => {
            this.setPlayerAutoFullscreen(isOn)
          }
        )

        this.ItemDivider()

        this.ToggleItem(
          $r('sys.symbol.template'),
          '自动开启画中画',
          '离开播放页时自动转入画中画',
          this.playerAutoPiP,
          (isOn: boolean) => {
            this.setPlayerAutoPiP(isOn)
          }
        )

        if (this.defaultPlayerEngine === 'mpv') {
          this.ItemDivider()

          Row() {
            this.SettingIcon($r('sys.symbol.gearshape'))
            this.SettingTitle('硬件解码模式', '优先使用系统解码能力')
            this.MpvHwdecPicker()
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })

          if (this.showAdvancedPlayerOptions) {
            this.ItemDivider()
          }
        }

        if (this.defaultPlayerEngine === 'mpv' && this.showAdvancedPlayerOptions) {
          this.ToggleItem($r('sys.symbol.play'), 'HLS 广告跳过', '跳过常见 HLS 广告分片', this.mpvHlsAdFilter, (isOn: boolean) => {
            this.setMpvHlsAdFilter(isOn)
          })

          this.ItemDivider()

          this.ToggleItem($r('sys.symbol.doc_text'), '伪装分片处理', '允许图片扩展名的视频分片', this.mpvSegAllowImg, (isOn: boolean) => {
            this.setMpvSegAllowImg(isOn)
          })

          this.ItemDivider()

          Row() {
            this.SettingIcon($r('sys.symbol.wand_and_stars'))
            this.SettingTitle('视频画质增强', 'AI 细节增强与超分辨率缩放')

            Toggle({ type: ToggleType.Switch, isOn: this.mpvDetailEnhancerEnabled })
              .onChange((isOn: boolean) => {
                this.setDetailEnhancerEnabled(isOn)
              })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })

          if (this.mpvDetailEnhancerEnabled) {
            this.ItemDivider()

            Row() {
              this.SettingIcon($r('sys.symbol.gearshape'))
              this.SettingTitle('画质增强档位', '档位越高效果越好，性能消耗越大')
              this.DetailEnhancerPicker()
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
          }
        }
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  AppSection(showHeader: boolean = true): void {
    Column() {
      if (showHeader) {
        this.SectionHeader('外观动效')
      }
      Column() {
        Row() {
          this.SettingIcon($r('sys.symbol.moon'))
          this.SettingTitle('深色模式', '跟随系统或手动切换')
          this.ColorModePicker()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

        this.ItemDivider()

        Row() {
          this.SettingIcon($r('sys.symbol.wand_and_stars'))
          this.SettingTitle('沉浸光感等级', '调整 HDS 材质光感强度')
          this.HdsMaterialLevelPicker()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

        this.ItemDivider()

        Row() {
          this.SettingIcon($r('sys.symbol.layer'))
          this.SettingTitle('浮层材质厚度')
          this.Api26MaterialStylePicker()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

        this.ItemDivider()

        this.ToggleItem(
          $r('sys.symbol.lock'),
          '防窥模式',
          '检测到他人注视时显示系统防窥蒙层',
          this.antiPeepEnabled,
          (isOn: boolean) => {
            this.setAntiPeepEnabled(isOn)
          }
        )

        this.ItemDivider()

        this.ToggleItem(
          $r('sys.symbol.arrow_down_right_and_arrow_up_left'),
          '滑动隐藏底栏',
          '下滑时跟手收起底部页签，上滑时恢复',
          this.bottomTabAutoHide,
          (isOn: boolean) => {
            this.setBottomTabAutoHide(isOn)
          }
        )

        this.ItemDivider()

        this.ToggleItem(
          $r('sys.symbol.layer'),
          '底栏显示动画',
          '点击底栏时显示HDS动效',
          this.bottomTabShowAnimation,
          (isOn: boolean) => {
            this.setBottomTabShowAnimation(isOn)
          }
        )
        if (this.showAdvancedPlayerOptions) {
          this.ItemDivider()

          Row() {
            SymbolGlyph($r('sys.symbol.lock_open'))
              .fontSize(24)
              .fontColor([$r('app.color.status_warning')])
              .width(34)
              .margin({ right: 12 })
            this.SettingTitle('允许非 HTTPS 请求', '兼容部分旧规则源，可能降低连接安全性')

            Toggle({ type: ToggleType.Switch, isOn: this.allowHttpRequests })
              .onChange((isOn: boolean) => {
                this.allowHttpRequests = isOn
                SecurityPolicy.getInstance().setAllowHttpRequests(isOn)
              })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })

          this.ItemDivider()

          this.ToggleItem(
            $r('sys.symbol.eye_slash'),
            '隐藏下载页面',
            '隐藏底部悬浮页签中的下载页',
            this.hideLocalPage,
            (isOn: boolean) => {
              this.setHideLocalPage(isOn)
            }
          )
        }
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  AdvancedSection(showHeader: boolean = true): void {
    Column() {
      if (showHeader) {
        this.SectionHeader('关于')
      }
      Column() {
        this.VersionInfoItem()
        this.ItemDivider()
        this.QqGroupItem()
        this.ItemDivider()
        this.ThirdPartyItem()
        this.ItemDivider()
        this.SponsorItem()
        this.ItemDivider()
        this.PainlessSupportItem()
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  SectionHeader(title: string): void {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, right: 6, top: 18, bottom: 6 })
  }

  @Builder
  ItemDivider(): void {
    Row() {
      Blank()
        .width(62)
      Divider()
        .layoutWeight(1)
        .color($r('app.color.divider_color'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .padding({ right: 16 })
  }

  @Builder
  SettingIcon(icon: Resource): void {
    SymbolGlyph(icon)
      .fontSize(24)
      .fontColor([$r('app.color.accent_blue')])
      .width(34)
      .margin({ right: 12 })
  }

  @Builder
  PlayerEngineTitle(): void {
    Column() {
      Text('默认播放引擎')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.defaultPlayerEngine === 'mpv' ? '当前使用 mpv' : '当前使用 AVPlayer')
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SettingTitle(title: string, desc: string = ''): void {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (desc.length > 0) {
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NavigationItem(icon: Resource, title: string, desc: string, value: string, action: () => void): void {
    Row() {
      this.SettingIcon(icon)
      this.SettingTitle(title, desc)

      if (value.length > 0) {
        Text(value)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 10, right: 6 })
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .onClick(action)
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
  }

  @Builder
  ToggleItem(icon: Resource, title: string, desc: string, isOn: boolean, onChange: (isOn: boolean) => void): void {
    Row() {
      this.SettingIcon(icon)
      this.SettingTitle(title, desc)

      if (isOn) {
        Toggle({ type: ToggleType.Switch, isOn: true })
          .onChange(onChange)
      } else {
        Toggle({ type: ToggleType.Switch, isOn: false })
          .onChange(onChange)
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  VersionInfoItem(): void {
    Row() {
      this.SettingIcon($r('sys.symbol.info_circle'))
      Text('版本信息')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(AppConstants.APP_VERSION)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
  }

  @Builder
  QqGroupItem(): void {
    Row() {
      this.SettingIcon($r('sys.symbol.person_2'))
      Text('加入QQ群')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text('626493332')
        .fontSize(14)
        .fontColor($r('app.color.accent_blue'))
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.openQqGroupDialog()
    })
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
  }

  @Builder
  ThirdPartyItem(): void {
    this.NavigationItem(
      $r('sys.symbol.link'),
      '三方库与服务',
      '开源组件与规则仓库',
      '',
      () => {
        router.pushUrl({ url: 'pages/settings/ThirdPartyPage' })
      }
    )
  }

  @Builder
  SponsorItem(): void {
    Row() {
      this.SettingIcon($r('sys.symbol.heart_fill'))
      Text('鼓励作者')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .onClick(() => {
      this.openSponsorDialog()
    })
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
  }

  @Builder
  PlayerEnginePicker(): void {
    Row() {
      Text(this.defaultPlayerEngine === 'mpv' ? 'mpv' : 'AVPlayer')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      if (this.playerDebugOptionsUnlocked) {
        Text('▼')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
    }
    .width(112)
    .height(38)
    .padding({ left: 10, right: 8 })
    .borderRadius(12)
    .onClick(() => {
      if (!this.playerDebugOptionsUnlocked) {
        this.handlePlayerEngineDebugTap()
        return
      }
      this.showPlayerEngineMenu = true
    })
    .bindMenu(this.playerDebugOptionsUnlocked && this.showPlayerEngineMenu, this.PlayerEngineMenuContent, {
      placement: Placement.Bottom,
      showInSubWindow: false,
      onDisappear: () => {
        this.showPlayerEngineMenu = false
      }
    })
  }

  @Builder
  MpvHwdecPicker(): void {
    Row() {
      Text(this.mpvHwdecMode === 'auto' ? '自动' : (this.mpvHwdecMode === 'no' ? '关闭' : '打开'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      if (this.playerDebugOptionsUnlocked) {
        Text('▼')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
    }
    .width(112)
    .height(38)
    .padding({ left: 10, right: 8 })
    .borderRadius(12)
    .onClick(() => {
      if (!this.playerDebugOptionsUnlocked) {
        return
      }
      this.showMpvHwdecMenu = true
    })
    .bindMenu(this.playerDebugOptionsUnlocked && this.showMpvHwdecMenu, this.MpvHwdecMenuContent, {
      placement: Placement.Bottom,
      showInSubWindow: false,
      onDisappear: () => {
        this.showMpvHwdecMenu = false
      }
    })
  }

  @Builder
  ColorModePicker(): void {
    Row() {
      Text(this.colorMode === 0 ? '深色' : (this.colorMode === 1 ? '浅色' : '跟随'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      Text('▼')
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
    }
    .width(112)
    .height(38)
    .padding({ left: 10, right: 8 })
    .borderRadius(12)
    .bindMenu(this.ColorModeMenuContent, {
      placement: Placement.Bottom,
      showInSubWindow: false
    })
  }

  @Builder
  PlayerEngineMenuContent(): void {
    Menu() {
      this.SettingsMenuOption('AVPlayer', this.defaultPlayerEngine === 'avplayer', () => {
        this.setPlayerEngine('avplayer')
        this.showPlayerEngineMenu = false
      })
      this.SettingsMenuOption('mpv', this.defaultPlayerEngine === 'mpv', () => {
        this.setPlayerEngine('mpv')
        this.showPlayerEngineMenu = false
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  MpvHwdecMenuContent(): void {
    Menu() {
      this.SettingsMenuOption('打开', this.mpvHwdecMode === 'ohcodec', () => {
        this.setMpvHwdecMode('ohcodec')
        this.showMpvHwdecMenu = false
      })
      this.SettingsMenuOption('自动', this.mpvHwdecMode === 'auto', () => {
        this.setMpvHwdecMode('auto')
        this.showMpvHwdecMenu = false
      })
      this.SettingsMenuOption('关闭', this.mpvHwdecMode === 'no', () => {
        this.setMpvHwdecMode('no')
        this.showMpvHwdecMenu = false
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  ColorModeMenuContent(): void {
    Menu() {
      this.SettingsMenuOption('跟随', this.colorMode === -1, () => {
        this.setColorMode(-1)
      })
      this.SettingsMenuOption('浅色', this.colorMode === 1, () => {
        this.setColorMode(1)
      })
      this.SettingsMenuOption('深色', this.colorMode === 0, () => {
        this.setColorMode(0)
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  PainlessSupportItem(): void {
    Row() {
      this.SettingIcon($r('sys.symbol.star_fill'))
      Text('无痛支持')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .onClick(() => {
      this.openPainlessSupportDialog()
    })
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
  }

  @Builder
  HdsMaterialLevelPicker(): void {
    Row() {
      Text(getHdsMaterialLevelLabel(this.hdsMaterialLevel))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      Text('▼')
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
    }
    .width(112)
    .height(38)
    .padding({ left: 10, right: 8 })
    .borderRadius(12)
    .bindMenu(this.HdsMaterialLevelMenuContent, {
      placement: Placement.Bottom,
      showInSubWindow: false
    })
  }

  @Builder
  HdsMaterialLevelMenuContent(): void {
    Menu() {
      this.SettingsMenuOption('精致', this.hdsMaterialLevel === HDS_MATERIAL_LEVEL_EXQUISITE, () => {
        this.setHdsMaterialLevel(HDS_MATERIAL_LEVEL_EXQUISITE)
      })
      this.SettingsMenuOption('柔和', this.hdsMaterialLevel === HDS_MATERIAL_LEVEL_GENTLE, () => {
        this.setHdsMaterialLevel(HDS_MATERIAL_LEVEL_GENTLE)
      })
      this.SettingsMenuOption('平滑', this.hdsMaterialLevel === HDS_MATERIAL_LEVEL_SMOOTH, () => {
        this.setHdsMaterialLevel(HDS_MATERIAL_LEVEL_SMOOTH)
      })
      this.SettingsMenuOption('自适应', this.hdsMaterialLevel === HDS_MATERIAL_LEVEL_ADAPTIVE, () => {
        this.setHdsMaterialLevel(HDS_MATERIAL_LEVEL_ADAPTIVE)
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  Api26MaterialStylePicker(): void {
    if (isImmersiveMaterialSupported()) {
      Row() {
        Text(getApi26MaterialStyleLabel(this.api26MaterialStyle))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .layoutWeight(1)

        Text('▼')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .width(112)
      .height(38)
      .padding({ left: 10, right: 8 })
      .borderRadius(12)
      .bindMenu(this.Api26MaterialStyleMenuContent, {
        placement: Placement.Bottom,
        showInSubWindow: false
      })
    } else {
      Row() {
        Text('仅支持API26')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
      }
      .width(112)
      .height(38)
      .padding({ left: 10, right: 8 })
      .borderRadius(12)
      .onClick(() => {
        promptAction.showToast({ message: '仅支持API26机型' })
      })
    }
  }

  @Builder
  Api26MaterialStyleMenuContent(): void {
    Menu() {
      this.SettingsMenuOption('超薄', this.api26MaterialStyle === API26_MATERIAL_STYLE_ULTRA_THIN, () => {
        this.setApi26MaterialStyle(API26_MATERIAL_STYLE_ULTRA_THIN)
      })
      this.SettingsMenuOption('薄', this.api26MaterialStyle === API26_MATERIAL_STYLE_THIN, () => {
        this.setApi26MaterialStyle(API26_MATERIAL_STYLE_THIN)
      })
      this.SettingsMenuOption('标准', this.api26MaterialStyle === API26_MATERIAL_STYLE_REGULAR, () => {
        this.setApi26MaterialStyle(API26_MATERIAL_STYLE_REGULAR)
      })
      this.SettingsMenuOption('厚', this.api26MaterialStyle === API26_MATERIAL_STYLE_THICK, () => {
        this.setApi26MaterialStyle(API26_MATERIAL_STYLE_THICK)
      })
      this.SettingsMenuOption('超厚', this.api26MaterialStyle === API26_MATERIAL_STYLE_ULTRA_THICK, () => {
        this.setApi26MaterialStyle(API26_MATERIAL_STYLE_ULTRA_THICK)
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  DetailEnhancerPicker(): void {
    Row() {
      Text(this.getDetailEnhancerLabel(this.mpvDetailEnhancerQuality))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      Text('▼')
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
    }
    .width(112)
    .height(38)
    .padding({ left: 10, right: 8 })
    .borderRadius(12)
    .bindMenu(this.DetailEnhancerMenuContent, {
      placement: Placement.Bottom,
      showInSubWindow: false
    })
  }

  @Builder
  DetailEnhancerMenuContent(): void {
    Menu() {
      this.SettingsMenuOption('低 (快速)', this.mpvDetailEnhancerQuality === 1, () => {
        this.setDetailEnhancerQuality(1)
      })
      this.SettingsMenuOption('中 (均衡)', this.mpvDetailEnhancerQuality === 2, () => {
        this.setDetailEnhancerQuality(2)
      })
      this.SettingsMenuOption('高 (最佳)', this.mpvDetailEnhancerQuality === 3, () => {
        this.setDetailEnhancerQuality(3)
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  SettingsMenuOption(label: string, selected: boolean, action: () => void): void {
    MenuItem() {
      Row() {
        Text(label)
          .fontSize(16)
          .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(selected ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .borderRadius(14)
      .backgroundColor(selected ? $r('app.color.episode_item_selected_bg') : Color.Transparent)
    }
    .onClick(action)
  }

  private openSettingsDestination(destination: string, animated: boolean = true): void {
    if (!this.shouldUseSettingsSplitMode()) {
      const pageUrl = this.getStandaloneSettingsPageUrl(destination)
      if (pageUrl.length > 0) {
        router.pushUrl({ url: pageUrl })
        return
      }
    }
    const pathNames = this.settingsPathStack.getAllPathName()
    const currentDestination = pathNames.length > 0 ? pathNames[pathNames.length - 1] : ''
    if (currentDestination === destination) {
      this.selectedSettingsDestination = destination
      return
    }
    this.selectedSettingsDestination = destination
    if (this.settingsPathStack.size() > 0) {
      this.settingsPathStack.replacePath({ name: destination }, animated)
    } else {
      this.settingsPathStack.pushPath({ name: destination }, animated)
    }
  }

  private openSettingsRouteDestination(destination: string, pageUrl: string): void {
    // 下载页是完整的独立页面，分栏布局下也直接打开，避免重复维护下载任务状态。
    if (destination === SETTINGS_DESTINATION_DOWNLOAD) {
      router.pushUrl({ url: pageUrl })
      return
    }
    if (this.shouldUseSettingsSplitMode()) {
      this.openSettingsDestination(destination)
      return
    }
    router.pushUrl({ url: pageUrl })
  }

  private shouldUseSettingsSplitMode(): boolean {
    return this.screenWidthVp >= 600 && this.screenHeightVp > 0 && this.screenWidthVp > this.screenHeightVp
  }

  private handleSettingsNavigationModeChange(mode: NavigationMode): void {
    if (mode !== NavigationMode.Stack || this.settingsPathStack.size() === 0) {
      return
    }
    this.settingsPathStack.clear(false)
    this.selectedSettingsDestination = ''
  }

  private getStandaloneSettingsPageUrl(destination: string): string {
    if (destination === SETTINGS_DESTINATION_PLAYER) {
      return 'pages/settings/PlayerSettingsPage'
    }
    if (destination === SETTINGS_DESTINATION_APP) {
      return 'pages/settings/AppearanceSettingsPage'
    }
    return ''
  }

  private getSettingsDestinationBottomSpacerHeight(): number {
    if (this.shouldUseSettingsSplitMode()) {
      return getBottomSpacerHeight(this.bottomSafeHeight)
    }
    return this.bottomSafeHeight + 24
  }

  private syncSelectedSettingsDestination(): void {
    const pathNames = this.settingsPathStack.getAllPathName()
    this.selectedSettingsDestination = pathNames.length > 0 ? pathNames[pathNames.length - 1] : ''
  }

  private getSettingsDestinationTitle(destination: string): string {
    if (destination === SETTINGS_DESTINATION_RULE_SHOP) {
      return '规则仓库'
    }
    if (destination === SETTINGS_DESTINATION_DANMAKU) {
      return '弹幕设置'
    }
    if (destination === SETTINGS_DESTINATION_DOWNLOAD) {
      return '下载管理'
    }
    if (destination === SETTINGS_DESTINATION_HISTORY) {
      return '历史记录'
    }
    if (destination === SETTINGS_DESTINATION_WEBDAV) {
      return '观看历史同步'
    }
    if (destination === SETTINGS_DESTINATION_PLAYER) {
      return '播放器'
    }
    if (destination === SETTINGS_DESTINATION_APP) {
      return '外观动效'
    }
    if (destination === SETTINGS_DESTINATION_ABOUT) {
      return '关于'
    }
    return '关于'
  }

  private isEmbeddedSettingsDestination(destination: string): boolean {
    return destination === SETTINGS_DESTINATION_RULE_SHOP ||
      destination === SETTINGS_DESTINATION_DANMAKU ||
      destination === SETTINGS_DESTINATION_HISTORY ||
      destination === SETTINGS_DESTINATION_WEBDAV
  }

  private getSettingsDetailScroller(destination: string): Scroller {
    if (destination === SETTINGS_DESTINATION_PLAYER) {
      return this.playerSettingsScroller
    }
    if (destination === SETTINGS_DESTINATION_APP) {
      return this.appSettingsScroller
    }
    if (destination === SETTINGS_DESTINATION_ABOUT) {
      return this.aboutScroller
    }
    return this.aboutScroller
  }

  private async loadSettings(): Promise<void> {
    const token = ++this.updateCheckToken
    this.updatableCount = 0
    try {
      this.rules = await this.ruleSourceStore.getAll()
      this.ruleCount = this.rules.length
      this.enabledRuleCount = this.rules.filter((r: RuleSource) => r.enabled).length

      const prefs = PreferencesStore.getInstance()
      this.showAdvancedPlayerOptions = true
      this.playerDebugOptionsUnlocked = await prefs.getBoolean(
        PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY,
        this.playerDebugOptionsUnlocked
      )
      this.allowHttpRequests = await prefs.getBoolean('allow_http_requests', false)
      let savedPlayerEngine = await prefs.getString('defaultPlayerEngine', 'mpv')
      let savedHwdecMode = await prefs.getString('mpvHwdecMode', 'auto')
      if (!this.playerDebugOptionsUnlocked) {
        if (savedPlayerEngine !== 'mpv') {
          savedPlayerEngine = 'mpv'
          await prefs.setString('defaultPlayerEngine', savedPlayerEngine)
        }
        if (savedHwdecMode !== 'auto') {
          savedHwdecMode = 'auto'
          await prefs.setString('mpvHwdecMode', savedHwdecMode)
        }
      }
      this.defaultPlayerEngine = savedPlayerEngine
      this.mpvHwdecMode = savedHwdecMode
      this.mpvHlsAdFilter = await prefs.getBoolean('mpvHlsAdFilter', true)
      this.mpvSegAllowImg = await prefs.getBoolean('mpvSegAllowImg', true)
      const hasDetailEnhancerEnabled = await prefs.has(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED)
      const hasDetailEnhancerQuality = await prefs.has(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY)
      this.mpvDetailEnhancerQuality = await prefs.getNumber(
        PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY,
        2
      )
      this.mpvDetailEnhancerEnabled = await prefs.getBoolean(
        PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED,
        hasDetailEnhancerQuality ? this.mpvDetailEnhancerQuality >= 0 : MPV_DETAIL_ENHANCER_ENABLED_DEFAULT
      )
      if (this.mpvDetailEnhancerQuality < 1 || this.mpvDetailEnhancerQuality > 3) {
        this.mpvDetailEnhancerQuality = 2
      }
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, this.mpvDetailEnhancerEnabled)
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, this.mpvDetailEnhancerQuality)
      if (!hasDetailEnhancerEnabled && hasDetailEnhancerQuality) {
        await prefs.setBoolean(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, this.mpvDetailEnhancerEnabled)
      }
      this.playerAutoFullscreen = await prefs.getBoolean(
        PREFS_KEY_PLAYER_AUTO_FULLSCREEN,
        PLAYER_AUTO_FULLSCREEN_DEFAULT
      )
      this.playerAutoPiP = await prefs.getBoolean(
        PREFS_KEY_PLAYER_AUTO_PIP,
        PLAYER_AUTO_PIP_DEFAULT
      )
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, this.playerAutoPiP)
      this.bottomTabAutoHide = await prefs.getBoolean(
        PREFS_KEY_BOTTOM_TAB_AUTO_HIDE,
        BOTTOM_TAB_AUTO_HIDE_DEFAULT
      )
      this.bottomTabShowAnimation = await prefs.getBoolean(
        PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION,
        BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
      )
      this.snifferTimeout = await prefs.getNumber('snifferTimeoutMs', 15000) / 1000
      const savedColorMode = await prefs.getNumber('colorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      this.colorMode = this.normalizeColorMode(savedColorMode)
      this.hdsMaterialLevel = await prefs.getString(PREFS_KEY_HDS_MATERIAL_LEVEL, HDS_MATERIAL_LEVEL_DEFAULT)
      AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, this.hdsMaterialLevel)
      this.api26MaterialStyle = normalizeApi26MaterialStyle(
        await prefs.getString(PREFS_KEY_API26_MATERIAL_STYLE, API26_MATERIAL_STYLE_DEFAULT)
      )
      AppStorage.setOrCreate(PREFS_KEY_API26_MATERIAL_STYLE, this.api26MaterialStyle)
      this.antiPeepEnabled = await prefs.getBoolean(
        PREFS_KEY_ANTI_PEEP_ENABLED,
        ANTI_PEEP_ENABLED_DEFAULT
      )
      AppStorage.setOrCreate(PREFS_KEY_ANTI_PEEP_ENABLED, this.antiPeepEnabled)

      this.refreshUpdatableCount(token)
    } catch (err) {
      if (token === this.updateCheckToken) {
        this.updatableCount = 0
      }
      logger.error('Load settings failed: %{public}s', JSON.stringify(err))
    }
  }

  private refreshUpdatableCount(token: number): void {
    RuleCatalogService.countUpdatableRules().then((count: number) => {
      if (token === this.updateCheckToken) {
        this.updatableCount = count
      }
    }).catch((err: Error) => {
      if (token === this.updateCheckToken) {
        this.updatableCount = 0
      }
      logger.warn('Refresh rule update badge failed: %{public}s', err instanceof Error ? err.message : String(err))
    })
  }

  private handlePlayerEngineDebugTap(): void {
    const now = Date.now()
    if (this.playerEngineFirstTapTime === 0 ||
      now - this.playerEngineFirstTapTime > PLAYER_DEBUG_OPTIONS_UNLOCK_WINDOW_MS) {
      this.playerEngineFirstTapTime = now
      this.playerEngineTapCount = 1
    } else {
      this.playerEngineTapCount += 1
    }
    logger.info('Player debug tap count: %{public}d', this.playerEngineTapCount)
    if (this.playerEngineTapCount >= PLAYER_DEBUG_OPTIONS_UNLOCK_TAP_COUNT) {
      this.playerDebugOptionsUnlocked = true
      this.playerEngineTapCount = 0
      this.playerEngineFirstTapTime = 0
      PreferencesStore.getInstance().setBoolean(PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY, true).catch((err: Error) => {
        logger.error('Persist player debug options unlocked failed: %{public}s',
          err instanceof Error ? err.message : String(err))
      })
      logger.info('Player debug settings unlocked from player engine taps')
    }
  }

  private openSponsorDialog(): void {
    logger.info('Open sponsor dialog')
    this.sponsorDialogController?.open()
  }

  private openPainlessSupportDialog(): void {
    logger.info('Open painless support dialog')
    this.painlessSupportDialogController?.open()
  }

  private openQqGroupDialog(): void {
    logger.info('Open QQ group dialog')
    this.qqGroupDialogController?.open()
  }

  private async copyQqGroup(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, '626493332')
      await pasteboard.getSystemPasteboard().setData(data)
      promptAction.showToast({ message: 'QQ群号已复制' })
    } catch (err) {
      logger.warn('Copy QQ group failed: %{public}s', err instanceof Error ? err.message : String(err))
      promptAction.showToast({ message: '复制失败' })
    }
  }

  private async openQqGroup(): Promise<void> {
    const qqGroupUri: string = 'mqqapi://card/show_pslcard?src_type=internal&version=1&uin=626493332&card_type=group&source=qrcode'
    const want: Want = {
      uri: qqGroupUri
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await context.startAbility(want)
      logger.info('QQ group link opened')
    } catch (err) {
      logger.warn('Open QQ group failed: %{public}s', err instanceof Error ? err.message : String(err))
      promptAction.showToast({ message: '无法打开QQ，请先安装QQ' })
    }
  }

  private async setPlayerEngine(engine: string): Promise<void> {
    this.defaultPlayerEngine = engine
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString('defaultPlayerEngine', engine)
    } catch (err) {
      logger.error('Set player engine failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setMpvHwdecMode(mode: string): Promise<void> {
    this.mpvHwdecMode = mode
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString('mpvHwdecMode', mode)
    } catch (err) {
      logger.error('Set mpv hwdec mode failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setMpvHlsAdFilter(enabled: boolean): Promise<void> {
    this.mpvHlsAdFilter = enabled
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean('mpvHlsAdFilter', enabled)
    } catch (err) {
      logger.error('Set mpv hls ad filter failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setMpvSegAllowImg(enabled: boolean): Promise<void> {
    this.mpvSegAllowImg = enabled
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean('mpvSegAllowImg', enabled)
    } catch (err) {
      logger.error('Set mpv seg allow img failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setDetailEnhancerEnabled(enabled: boolean): Promise<void> {
    this.mpvDetailEnhancerEnabled = enabled
    if (this.mpvDetailEnhancerQuality < 1 || this.mpvDetailEnhancerQuality > 3) {
      this.mpvDetailEnhancerQuality = 2
    }
    try {
      const prefs = PreferencesStore.getInstance()
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, enabled)
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, this.mpvDetailEnhancerQuality)
      await prefs.setBoolean(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, enabled)
      await prefs.setNumber(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, this.mpvDetailEnhancerQuality)
    } catch (err) {
      logger.error('Set detail enhancer enabled failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setDetailEnhancerQuality(quality: number): Promise<void> {
    this.mpvDetailEnhancerQuality = quality
    try {
      const prefs = PreferencesStore.getInstance()
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, quality)
      await prefs.setNumber(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, quality)
    } catch (err) {
      logger.error('Set detail enhancer quality failed: %{public}s', JSON.stringify(err))
    }
  }

  private getDetailEnhancerLabel(quality: number): string {
    if (quality === 1) {
      return '低'
    }
    if (quality === 3) {
      return '高'
    }
    return '中'
  }

  private async setPlayerAutoFullscreen(enabled: boolean): Promise<void> {
    this.playerAutoFullscreen = enabled
    AppStorage.setOrCreate('playerAutoFullscreen', enabled)
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean(PREFS_KEY_PLAYER_AUTO_FULLSCREEN, enabled)
    } catch (err) {
      logger.error('Set player auto fullscreen failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setPlayerAutoPiP(enabled: boolean): Promise<void> {
    this.playerAutoPiP = enabled
    AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, enabled)
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean(PREFS_KEY_PLAYER_AUTO_PIP, enabled)
    } catch (err) {
      logger.error('Set player auto PiP failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setBottomTabAutoHide(enabled: boolean): Promise<void> {
    this.bottomTabAutoHide = enabled
    if (!enabled) {
      this.bottomTabOffset = 0
    }
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean(PREFS_KEY_BOTTOM_TAB_AUTO_HIDE, enabled)
    } catch (err) {
      logger.error('Set bottom tab auto hide failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setBottomTabShowAnimation(enabled: boolean): Promise<void> {
    this.bottomTabShowAnimation = enabled
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean(PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION, enabled)
    } catch (err) {
      logger.error('Set bottom tab show animation failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setHdsMaterialLevel(level: string): Promise<void> {
    this.hdsMaterialLevel = level
    AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, level)
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString(PREFS_KEY_HDS_MATERIAL_LEVEL, level)
    } catch (err) {
      logger.error('Set hds material level failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setApi26MaterialStyle(style: string): Promise<void> {
    if (!isImmersiveMaterialSupported()) {
      promptAction.showToast({ message: '仅支持API26机型' })
      return
    }
    this.api26MaterialStyle = normalizeApi26MaterialStyle(style)
    AppStorage.setOrCreate(PREFS_KEY_API26_MATERIAL_STYLE, this.api26MaterialStyle)
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString(PREFS_KEY_API26_MATERIAL_STYLE, this.api26MaterialStyle)
    } catch (err) {
      logger.error('Set API26 material style failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setAntiPeepEnabled(enabled: boolean): Promise<void> {
    const service = AntiPeepService.getInstance()
    if (enabled) {
      const context = getContext(this) as common.UIAbilityContext
      const enabledSuccessfully = await service.enable(context)
      if (!enabledSuccessfully) {
        this.antiPeepEnabled = false
        AppStorage.setOrCreate(PREFS_KEY_ANTI_PEEP_ENABLED, false)
        return
      }
    } else {
      service.setEnabled(false)
    }

    this.antiPeepEnabled = enabled
    AppStorage.setOrCreate(PREFS_KEY_ANTI_PEEP_ENABLED, enabled)
    try {
      await PreferencesStore.getInstance().setBoolean(PREFS_KEY_ANTI_PEEP_ENABLED, enabled)
    } catch (err) {
      logger.error('Set anti-peep enabled failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setHideLocalPage(enabled: boolean): Promise<void> {
    this.hideLocalPage = enabled
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean(HIDE_LOCAL_PAGE_KEY, enabled)
    } catch (err) {
      logger.error('Set hide local page failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setColorMode(mode: number): Promise<void> {
    this.colorMode = mode
    try {
      const context = getContext(this) as common.UIAbilityContext
      if (mode === -1) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      } else if (mode === 0) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
      } else {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
      }
      const prefs = PreferencesStore.getInstance()
      await prefs.setNumber('colorMode', mode)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Set colorMode failed: %{public}s', msg)
    }
  }

  private normalizeColorMode(mode: number): number {
    if (mode === 0 || mode === 1 || mode === -1) {
      return mode
    }
    return -1
  }

  private updateBottomTabOffset(deltaY: number, activeScroller: Scroller = this.scroller): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const currentOffset = activeScroller.currentOffset()
    if (currentOffset.yOffset <= 0) {
      requestBottomTabAnimation(false)
      this.bottomTabOffset = 0
      return
    }
    const maxOffset = getBottomTabHideDistance(this.bottomSafeHeight)
    const nextOffset = resolveBottomTabOffsetByDelta(deltaY, this.bottomTabOffset, maxOffset)
    if (Math.abs(nextOffset - this.bottomTabOffset) >= 0.5) {
      this.bottomTabOffset = nextOffset
      requestBottomTabAnimation(resolveBottomTabSnapTarget(nextOffset, maxOffset) > 0)
    }
  }

  private snapBottomTabOffset(): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const maxOffset = getBottomTabHideDistance(this.bottomSafeHeight)
    const targetOffset = resolveBottomTabSnapTarget(this.bottomTabOffset, maxOffset)
    if (Math.abs(targetOffset - this.bottomTabOffset) < 0.5) {
      return
    }
    const shouldHide = targetOffset > 0
    requestBottomTabAnimation(shouldHide)
    if (!shouldHide) {
      this.bottomTabOffset = 0
    }
  }

}
