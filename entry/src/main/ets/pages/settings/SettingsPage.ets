import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { PreferencesStore } from '../../store/PreferencesStore'
import { SecurityPolicy } from '../../network/SecurityPolicy'
import { RuleCatalogService } from '../../services/RuleCatalogService'
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import { RULE_SOURCE_VERSION_KEY } from '../../store/SettingsChangeSignal'
import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
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
  ADVANCED_OPTIONS_UNLOCKED_KEY,
  ADVANCED_OPTIONS_UNLOCK_TAP_COUNT
} from '../../utils/AdvancedOptionsUnlock'

const logger = new Logger('SettingsPage')

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

@Component
export struct SettingsPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
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
  @State snifferTimeout: number = 15
  @State rules: RuleSource[] = []
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private scroller: Scroller = new Scroller()

  @State colorMode: number = -1
  @State showPlayerEngineMenu: boolean = false
  @State showMpvHwdecMenu: boolean = false
  @StorageLink(ADVANCED_OPTIONS_UNLOCKED_KEY) showAdvancedPlayerOptions: boolean = false
  @State versionTapCount: number = 0
  private sponsorDialogController: CustomDialogController | null = new CustomDialogController({
    builder: SponsorDialog(),
    customStyle: true,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_modal_bg')
  })
  @StorageLink(RULE_SOURCE_VERSION_KEY) @Watch('onRuleSourceVersionChange') ruleSourceVersion: number = 0
  @State updatableCount: number = 0
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
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          this.QuickAccessSection()
          this.PlayerSection()
          this.AppSection()
          this.AdvancedSection()

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
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
    .titleBar(buildTitleBarOptions('我的'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
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
  QuickAccessSection(): void {
    Column() {
      this.SectionHeader('快捷入口')
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
  PlayerSection(): void {
    Column() {
      this.SectionHeader('播放器')
      Column() {
        Row() {
          this.SettingIcon($r('sys.symbol.play_round_rectangle'))
          this.PlayerEngineTitle()
          this.PlayerEnginePicker()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

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
  AppSection(): void {
    Column() {
      this.SectionHeader('应用')
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
  AdvancedSection(): void {
    Column() {
      this.SectionHeader('关于')
      Column() {
        this.VersionInfoItem()
        this.ItemDivider()
        this.QqGroupItem()
        this.ItemDivider()
        this.ThirdPartyItem()
        this.ItemDivider()
        this.SponsorItem()
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
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SettingTitle(title: string, desc: string): void {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(desc)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
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
          .fontColor($r('app.color.text_secondary'))
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

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange(onChange)
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
      Text('1.0.0')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .onClick(() => {
      this.handleVersionTap()
    })
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
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
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
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      if (this.showAdvancedPlayerOptions) {
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
      if (!this.showAdvancedPlayerOptions) {
        return
      }
      this.showPlayerEngineMenu = true
    })
    .bindMenu(this.showAdvancedPlayerOptions && this.showPlayerEngineMenu, this.PlayerEngineMenuContent, {
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
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)

      if (this.showAdvancedPlayerOptions) {
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
      if (!this.showAdvancedPlayerOptions) {
        return
      }
      this.showMpvHwdecMenu = true
    })
    .bindMenu(this.showAdvancedPlayerOptions && this.showMpvHwdecMenu, this.MpvHwdecMenuContent, {
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
        .fontColor($r('app.color.text_secondary'))
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

  private async loadSettings(): Promise<void> {
    const token = ++this.updateCheckToken
    this.updatableCount = 0
    try {
      this.rules = await this.ruleSourceStore.getAll()
      this.ruleCount = this.rules.length
      this.enabledRuleCount = this.rules.filter((r: RuleSource) => r.enabled).length

      const prefs = PreferencesStore.getInstance()
      this.allowHttpRequests = await prefs.getBoolean('allow_http_requests', false)
      let savedPlayerEngine = await prefs.getString('defaultPlayerEngine', 'mpv')
      let savedHwdecMode = await prefs.getString('mpvHwdecMode', 'auto')
      if (!this.showAdvancedPlayerOptions) {
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

  private handleVersionTap(): void {
    if (this.showAdvancedPlayerOptions) {
      return
    }
    this.versionTapCount += 1
    logger.info('Version info tap count: %{public}d', this.versionTapCount)
    if (this.versionTapCount >= ADVANCED_OPTIONS_UNLOCK_TAP_COUNT) {
      this.showAdvancedPlayerOptions = true
      this.versionTapCount = 0
      logger.info('Advanced player settings unlocked from version info')
    }
  }

  private openSponsorDialog(): void {
    logger.info('Open sponsor dialog')
    this.sponsorDialogController?.open()
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

  private updateBottomTabOffset(deltaY: number): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      return
    }
    const currentOffset = this.scroller.currentOffset()
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
