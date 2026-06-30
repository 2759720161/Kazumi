import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { PreferencesStore } from '../../store/PreferencesStore'
import { SecurityPolicy } from '../../network/SecurityPolicy'
import { RuleCatalogService } from '../../services/RuleCatalogService'
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import { DandanCredentialStore } from '../../core/danmaku/DandanCredentialStore'
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

const logger = new Logger('SettingsPage')

interface SettingOption {
  label: string;
  value: string | number | boolean;
  action: () => void;
}

@Component
export struct SettingsPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
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
  @State showColorModeMenu: boolean = false
  @State showCompactModeMenu: boolean = false
  @State showAdvancedPlayerOptions: boolean = false
  @State versionTapCount: number = 0

  @State isDanmakuCredentialConfigured: boolean = false
  @StorageLink('home_compact_mode') compactMode: boolean = false
  @StorageLink(RULE_SOURCE_VERSION_KEY) @Watch('onRuleSourceVersionChange') ruleSourceVersion: number = 0
  @State updatableCount: number = 0

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
          Text('弹幕')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 4 })
          Text(this.isDanmakuCredentialConfigured ? '已配置' : '未配置')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDanmakuCredentialConfigured ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor(this.isDanmakuCredentialConfigured ? $r('app.color.accent_blue_light') : $r('app.color.button_ghost_bg'))

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

        Row() {
          this.SettingIcon($r('sys.symbol.barrage_setting'))
          this.SettingTitle('弹幕设置',
            this.isDanmakuCredentialConfigured ? '来源、样式、屏蔽与缓存' : '配置弹幕来源和显示效果')

          Row() {
            Text(this.isDanmakuCredentialConfigured ? '已配置' : '未配置')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isDanmakuCredentialConfigured ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(10)
          .backgroundColor(this.isDanmakuCredentialConfigured ? $r('app.color.accent_blue_light') : $r('app.color.button_ghost_bg'))
          .margin({ left: 10, right: 6 })

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

        this.ItemDivider()

        this.NavigationItem($r('sys.symbol.clock'), '历史记录', '查看播放历史', '', () => {
          router.pushUrl({ url: 'pages/history/HistoryPage' })
        })
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

          this.ItemDivider()
        }

        if (this.defaultPlayerEngine === 'mpv') {
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

        Row() {
          this.SettingIcon($r('sys.symbol.square_grid_2x2'))
          this.SettingTitle('推荐页布局', '调整首页卡片密度')
          this.CompactModePicker()
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })

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
      this.SectionHeader('高级')
      Column() {
        this.NavigationItem($r('sys.symbol.wrench_and_screwdriver'), '规则调试', '测试规则搜索、分集和播放解析', '', () => {
          router.pushUrl({ url: 'pages/settings/RuleDebugPage' })
        })
        this.ItemDivider()
        this.VersionInfoItem()
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
      this.closeOptionMenus()
      this.showPlayerEngineMenu = true
    })
    .bindPopup(this.showAdvancedPlayerOptions && this.showPlayerEngineMenu, {
      builder: this.PlayerEngineMenuContent,
      placement: Placement.Bottom,
      showInSubWindow: false,
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.showPlayerEngineMenu = false
        }
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
      this.closeOptionMenus()
      this.showMpvHwdecMenu = true
    })
    .bindPopup(this.showAdvancedPlayerOptions && this.showMpvHwdecMenu, {
      builder: this.MpvHwdecMenuContent,
      placement: Placement.Bottom,
      showInSubWindow: false,
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.showMpvHwdecMenu = false
        }
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
    .onClick(() => {
      this.closeOptionMenus()
      this.showColorModeMenu = true
    })
    .bindPopup(this.showColorModeMenu, {
      builder: this.ColorModeMenuContent,
      placement: Placement.Bottom,
      showInSubWindow: false,
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.showColorModeMenu = false
        }
      }
    })
  }

  @Builder
  CompactModePicker(): void {
    Row() {
      Text(this.compactMode ? '紧凑' : '默认')
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
    .onClick(() => {
      this.closeOptionMenus()
      this.showCompactModeMenu = true
    })
    .bindPopup(this.showCompactModeMenu, {
      builder: this.CompactModeMenuContent,
      placement: Placement.Bottom,
      showInSubWindow: false,
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.showCompactModeMenu = false
        }
      }
    })
  }

  @Builder
  PlayerEngineMenuContent(): void {
    this.OptionMenuContent([
      { label: 'AVPlayer', value: 'avplayer', action: () => { this.setPlayerEngine('avplayer') } },
      { label: 'mpv', value: 'mpv', action: () => { this.setPlayerEngine('mpv') } }
    ], this.defaultPlayerEngine, () => {
      this.showPlayerEngineMenu = false
    })
  }

  @Builder
  MpvHwdecMenuContent(): void {
    this.OptionMenuContent([
      { label: '打开', value: 'ohcodec', action: () => { this.setMpvHwdecMode('ohcodec') } },
      { label: '自动', value: 'auto', action: () => { this.setMpvHwdecMode('auto') } },
      { label: '关闭', value: 'no', action: () => { this.setMpvHwdecMode('no') } }
    ], this.mpvHwdecMode, () => {
      this.showMpvHwdecMenu = false
    })
  }

  @Builder
  ColorModeMenuContent(): void {
    this.OptionMenuContent([
      { label: '跟随', value: -1, action: () => { this.setColorMode(-1) } },
      { label: '浅色', value: 1, action: () => { this.setColorMode(1) } },
      { label: '深色', value: 0, action: () => { this.setColorMode(0) } }
    ], this.colorMode, () => {
      this.showColorModeMenu = false
    })
  }

  @Builder
  CompactModeMenuContent(): void {
    this.OptionMenuContent([
      { label: '默认', value: false, action: () => { this.compactMode = false } },
      { label: '紧凑', value: true, action: () => { this.compactMode = true } }
    ], this.compactMode, () => {
      this.showCompactModeMenu = false
    })
  }

  @Builder
  OptionMenuContent(options: SettingOption[], selectedValue: string | number | boolean, closeAction: () => void): void {
    Column() {
      ForEach(options, (item: SettingOption, index?: number) => {
        Text(item.label)
          .fontSize(16)
          .fontWeight(this.isOptionSelected(item.value, selectedValue) ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.isOptionSelected(item.value, selectedValue) ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
          .width('100%')
          .height(56)
          .padding({ left: 22, right: 22 })
          .textAlign(TextAlign.Start)
          .borderRadius(14)
          .backgroundColor(this.isOptionSelected(item.value, selectedValue) ? $r('app.color.episode_item_selected_bg') : Color.Transparent)
          .onClick(() => {
            item.action()
            closeAction()
          })
      }, (item: SettingOption, index?: number) => 'setting_option_' + index)
    }
    .width(188)
    .padding(8)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
  }

  private isOptionSelected(itemValue: string | number | boolean, selectedValue: string | number | boolean): boolean {
    return itemValue === selectedValue
  }

  private closeOptionMenus(): void {
    this.showPlayerEngineMenu = false
    this.showMpvHwdecMenu = false
    this.showColorModeMenu = false
    this.showCompactModeMenu = false
  }

  private async loadSettings(): Promise<void> {
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
      this.snifferTimeout = await prefs.getNumber('snifferTimeoutMs', 15000) / 1000
      const savedColorMode = await prefs.getNumber('colorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      this.colorMode = this.normalizeColorMode(savedColorMode)

      const credStore = DandanCredentialStore.getInstance()
      await credStore.init()
      this.isDanmakuCredentialConfigured = credStore.hasCredentials()

      RuleCatalogService.countUpdatableRules().then((count: number) => {
        this.updatableCount = count
      }).catch(() => {})
    } catch (err) {
      logger.error('Load settings failed: %{public}s', JSON.stringify(err))
    }
  }

  private handleVersionTap(): void {
    if (this.showAdvancedPlayerOptions) {
      return
    }
    this.versionTapCount += 1
    logger.info('Version info tap count: %{public}d', this.versionTapCount)
    if (this.versionTapCount >= 10) {
      this.showAdvancedPlayerOptions = true
      this.versionTapCount = 0
      logger.info('Advanced player settings unlocked from version info')
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

}
