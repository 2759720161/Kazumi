import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { DandanCredentialStore } from '../../core/danmaku/DandanCredentialStore'
import { DandanApiClient } from '../../core/danmaku/DandanApiClient'
import { DanmakuCacheStore, DanmakuCacheSummary } from '../../core/danmaku/DanmakuCacheStore'
import { router } from '@kit.ArkUI'
import {
  DanmakuStyleSettings,
  DANMAKU_PREFS_KEY_BORDER,
  DANMAKU_PREFS_KEY_BORDER_SIZE,
  DANMAKU_PREFS_KEY_COLOR,
  DANMAKU_PREFS_KEY_FONT_SIZE,
  DANMAKU_PREFS_KEY_FONT_WEIGHT,
  DANMAKU_PREFS_KEY_OPACITY,
  DANMAKU_PREFS_KEY_SCROLL_DURATION,
  DANMAKU_PREFS_KEY_LINE_HEIGHT,
  DANMAKU_PREFS_KEY_DISPLAY_AREA,
  DANMAKU_PREFS_KEY_HIDE_SCROLL,
  DANMAKU_PREFS_KEY_HIDE_TOP,
  DANMAKU_PREFS_KEY_HIDE_BOTTOM,
  DANMAKU_PREFS_KEY_HIDE_COLOR,
  DANMAKU_PREFS_KEY_BILIBILI_SOURCE,
  DANMAKU_PREFS_KEY_GAMER_SOURCE,
  DANMAKU_PREFS_KEY_DANDAN_SOURCE,
  DANMAKU_PREFS_KEY_FOLLOW_SPEED,
  DANMAKU_PREFS_KEY_DEDUPLICATION,
  DANMAKU_PREFS_KEY_MAX_LENGTH,
  DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED,
  DANMAKU_PREFS_KEY_BLOCK_KEYWORDS,
  DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED,
  DANMAKU_PREFS_KEY_BLOCK_REGEX,
  DANMAKU_PREFS_KEY_TIME_OFFSET,
  DANMAKU_PREFS_KEY_MASSIVE_MODE
} from '../../core/danmaku/DanmakuStyleSettings'

const logger = new Logger('DanmakuSettingsPage')

@Component
struct DanmakuSettingsSwitchRow {
  @Link value: boolean
  title: string = ''
  onToggle: (value: boolean) => void = () => {}

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .onChange((isOn: boolean) => {
          this.value = isOn
          this.onToggle(isOn)
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }
}

@Entry
@Component
export struct DanmakuSettingsPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State dandanAppId: string = ''
  @State dandanAppSecret: string = ''
  @State isDanmakuCredentialConfigured: boolean = false
  @State isTestingConnection: boolean = false
  @State testConnectionMessage: string = ''
  @State danmakuBorder: boolean = true
  @State danmakuBorderSize: number = 1.5
  @State danmakuColor: boolean = true
  @State danmakuFontSize: number = 25
  @State danmakuFontWeight: number = 4
  @State danmakuOpacity: number = 1.0
  @State danmakuScrollDuration: number = 8
  @State danmakuLineHeight: number = 1.2
  @State danmakuDisplayArea: number = 1.0
  @State danmakuHideScroll: boolean = false
  @State danmakuHideTop: boolean = false
  @State danmakuHideBottom: boolean = false
  @State danmakuHideColor: boolean = false
  @State danmakuBiliBiliSource: boolean = true
  @State danmakuGamerSource: boolean = true
  @State danmakuDanDanSource: boolean = true
  @State danmakuFollowSpeed: boolean = true
  @State danmakuDeduplication: boolean = false
  @State danmakuMaxLength: number = 100
  @State danmakuBlockKeywordsEnabled: boolean = true
  @State danmakuBlockKeywords: string = ''
  @State danmakuBlockRegexEnabled: boolean = true
  @State danmakuBlockRegex: string = ''
  @State danmakuTimeOffset: number = 0
  @State danmakuMassiveMode: boolean = false
  @State message: string = ''
  @State cacheFileCount: number = 0
  @State cacheExpiredCount: number = 0
  @State cacheSizeText: string = '0 B'
  @State isClearingCache: boolean = false
  @State isEditingCredentials: boolean = false
  @State keywordCount: number = 0
  @State regexCount: number = 0
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadSettings()
  }

  onPageShow(): void {
    this.loadSettings()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          this.DanmakuStatusCard()
          this.SourceSection()
          this.SourceFilterSection()
          this.DisplayBasicSection()
          this.DisplayAdvancedSection()
          this.StyleSection()
          this.FilterSection()
          this.CacheSection()

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
    .titleBar(buildTitleBarOptions('弹幕设置'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  DanmakuStatusCard(): void {
    Column() {
      Row() {
        Text('弹幕配置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      Row() {
        Row() {
          Text('来源')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 4 })
          Text(this.getActiveSourceNames())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Row() {
          Text('缓存')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 4 })
          Text(`${this.cacheFileCount} 文件`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Row() {
          Text('屏蔽')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 4 })
          Text(`${this.keywordCount + this.regexCount} 条`)
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
  DanmakuPreviewCard(): void {
    Column() {
      Row() {
        Text('弹幕预览')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 0, bottom: 6 })

      Column() {
        if (this.danmakuBorder) {
          Text('2333 太棒了吧')
            .fontSize(this.danmakuFontSize)
            .fontWeight(this.mapFontWeight(this.danmakuFontWeight))
            .fontColor(this.danmakuColor ? Color.White : $r('app.color.text_primary'))
            .opacity(this.danmakuOpacity)
            .border({
              width: this.danmakuBorderSize,
              color: Color.Black
            })
            .borderStyle(BorderStyle.Solid)
            .padding(2)
            .margin({ bottom: 6 })

          Text('这个角色好可爱啊')
            .fontSize(this.danmakuFontSize)
            .fontWeight(this.mapFontWeight(this.danmakuFontWeight))
            .fontColor(this.danmakuColor ? '#FFE53B' : $r('app.color.text_primary'))
            .opacity(this.danmakuOpacity)
            .border({
              width: this.danmakuBorderSize,
              color: Color.Black
            })
            .borderStyle(BorderStyle.Solid)
            .padding(2)
            .margin({ bottom: 6 })

          Text('前方高能注意')
            .fontSize(this.danmakuFontSize)
            .fontWeight(this.mapFontWeight(this.danmakuFontWeight))
            .fontColor(this.danmakuColor ? '#FF6B6B' : $r('app.color.text_primary'))
            .opacity(this.danmakuOpacity)
            .border({
              width: this.danmakuBorderSize,
              color: Color.Black
            })
            .borderStyle(BorderStyle.Solid)
            .padding(2)
        } else {
          Text('2333 太棒了吧')
            .fontSize(this.danmakuFontSize)
            .fontWeight(this.mapFontWeight(this.danmakuFontWeight))
            .fontColor(this.danmakuColor ? Color.White : $r('app.color.text_primary'))
            .opacity(this.danmakuOpacity)
            .padding(2)
            .margin({ bottom: 6 })

          Text('这个角色好可爱啊')
            .fontSize(this.danmakuFontSize)
            .fontWeight(this.mapFontWeight(this.danmakuFontWeight))
            .fontColor(this.danmakuColor ? '#FFE53B' : $r('app.color.text_primary'))
            .opacity(this.danmakuOpacity)
            .padding(2)
            .margin({ bottom: 6 })

          Text('前方高能注意')
            .fontSize(this.danmakuFontSize)
            .fontWeight(this.mapFontWeight(this.danmakuFontWeight))
            .fontColor(this.danmakuColor ? '#FF6B6B' : $r('app.color.text_primary'))
            .opacity(this.danmakuOpacity)
            .padding(2)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 12, bottom: 14 })
    }
    .width('100%')
    .borderRadius(12)
    .clip(true)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
  }

  @Builder
  private SectionTitle(title: string, extra: string = ''): void {
    Row() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)

      if (extra.length > 0) {
        Text(extra)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 18, bottom: 6 })
  }

  @Builder
  private ItemDivider(): void {
    Row() {
      Blank()
        .width(16)
      Divider()
        .layoutWeight(1)
        .color($r('app.color.divider_color'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .padding({ right: 16 })
  }

  @Builder
  private SourceSection(): void {
    Column() {
      this.SectionTitle('弹幕源')

      Column() {
        if (this.isDanmakuCredentialConfigured && !this.isEditingCredentials) {
          Text('DanDanPlay API 凭据')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 4 })

          Text('AppId: ' + this.maskedAppId())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 10 })

          if (this.testConnectionMessage.length > 0) {
            Text(this.testConnectionMessage)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
          }

          Row() {
            Button('测试连接')
              .height(36)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .enabled(!this.isTestingConnection)
              .backgroundColor($r('app.color.button_ghost_bg'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(18)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.testDanmakuConnection()
              })

            Button('重新配置')
              .height(36)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.button_ghost_bg'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(18)
              .layoutWeight(1)
              .margin({ left: 8, right: 8 })
              .onClick(() => {
                this.isEditingCredentials = true
              })

            Button('清除')
              .height(36)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.button_ghost_bg'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(18)
              .layoutWeight(1)
              .margin({ left: 8 })
              .onClick(() => {
                this.clearDanmakuCredentials()
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 14 })
        } else {
          Text('DanDanPlay API 凭据')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 4 })

          Text('用于弹弹Play弹幕搜索与匹配；不配置也可以使用其他来源。')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 10 })

          TextInput({ placeholder: 'AppId', text: this.dandanAppId })
            .width('100%')
            .height(44)
            .fontSize(14)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ left: 16, right: 16, bottom: 8 })
            .onChange((value: string) => {
              this.dandanAppId = value
            })
            .onBlur(() => {
              this.saveDanmakuCredentials()
            })

          TextInput({ placeholder: 'AppSecret', text: this.dandanAppSecret })
            .width('100%')
            .height(44)
            .fontSize(14)
            .type(InputType.Password)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ left: 16, right: 16, bottom: 12 })
            .onChange((value: string) => {
              this.dandanAppSecret = value
            })
            .onBlur(() => {
              this.saveDanmakuCredentials()
            })

          Row() {
            Button('保存')
              .height(36)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .enabled(this.dandanAppId.trim().length > 0 && this.dandanAppSecret.trim().length > 0)
              .backgroundColor($r('app.color.button_ghost_bg'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(18)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.saveDanmakuCredentials()
              })

            Button(this.isTestingConnection ? '测试中...' : '测试连接')
              .height(36)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .enabled(!this.isTestingConnection && this.dandanAppId.length > 0 && this.dandanAppSecret.length > 0)
              .backgroundColor($r('app.color.button_ghost_bg'))
              .fontColor($r('app.color.text_primary'))
              .borderRadius(18)
              .layoutWeight(1)
              .margin({ left: 8, right: 8 })
              .onClick(() => {
                this.testDanmakuConnection()
              })

            if (this.isDanmakuCredentialConfigured) {
              Button('取消')
                .height(36)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .backgroundColor($r('app.color.button_ghost_bg'))
                .fontColor($r('app.color.text_primary'))
                .borderRadius(18)
                .layoutWeight(1)
                .margin({ left: 8 })
                .onClick(() => {
                  this.isEditingCredentials = false
                  const credStore = DandanCredentialStore.getInstance()
                  this.dandanAppId = credStore.getAppId()
                  this.dandanAppSecret = credStore.getAppSecret()
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 12 })

          if (this.testConnectionMessage.length > 0) {
            Text(this.testConnectionMessage)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 12 })
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
  private SourceFilterSection(): void {
    Column() {
      this.SectionTitle('弹幕来源过滤')
      Column() {
        DanmakuSettingsSwitchRow({
          title: 'BiliBili',
          value: $danmakuBiliBiliSource,
          onToggle: (value: boolean) => {
            this.setDanmakuBiliBiliSource(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: 'Gamer',
          value: $danmakuGamerSource,
          onToggle: (value: boolean) => {
            this.setDanmakuGamerSource(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '弹弹Play',
          value: $danmakuDanDanSource,
          onToggle: (value: boolean) => {
            this.setDanmakuDanDanSource(value)
          }
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
  private DisplayBasicSection(): void {
    Column() {
      this.SectionTitle('弹幕显示 · 基础')
      Column() {
        this.SliderRow('显示区域', 'danmakuDisplayArea', 0.25, 1, 0.25, true, (value: number) => {
          this.setDanmakuDisplayArea(value)
        })
        this.ItemDivider()
        this.SliderRow('滚动时长', 'danmakuScrollDuration', 4, 12, 0.5, true, (value: number) => {
          this.setDanmakuScrollDuration(value)
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '跟随视频倍速',
          value: $danmakuFollowSpeed,
          onToggle: (value: boolean) => {
            this.setDanmakuFollowSpeed(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '弹幕去重',
          value: $danmakuDeduplication,
          onToggle: (value: boolean) => {
            this.setDanmakuDeduplication(value)
          }
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
  private DisplayAdvancedSection(): void {
    Column() {
      this.SectionTitle('弹幕显示 · 高级')
      Column() {
        this.SliderRow('行高', 'danmakuLineHeight', 1.0, 2.5, 0.1, true, (value: number) => {
          this.setDanmakuLineHeight(value)
        })
        this.ItemDivider()
        this.SliderRow('时间轴偏移', 'danmakuTimeOffset', -60, 60, 0.25, true, (value: number) => {
          this.setDanmakuTimeOffset(value)
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '海量弹幕',
          value: $danmakuMassiveMode,
          onToggle: (value: boolean) => {
            this.setDanmakuMassiveMode(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '隐藏滚动弹幕',
          value: $danmakuHideScroll,
          onToggle: (value: boolean) => {
            this.setDanmakuHideScroll(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '隐藏顶部弹幕',
          value: $danmakuHideTop,
          onToggle: (value: boolean) => {
            this.setDanmakuHideTop(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '隐藏底部弹幕',
          value: $danmakuHideBottom,
          onToggle: (value: boolean) => {
            this.setDanmakuHideBottom(value)
          }
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '隐藏彩色弹幕',
          value: $danmakuHideColor,
          onToggle: (value: boolean) => {
            this.setDanmakuHideColor(value)
          }
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
  private StyleSection(): void {
    Column() {
      Row() {
        Text('弹幕样式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Button('恢复默认')
          .height(30)
          .fontSize(12)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .fontColor($r('app.color.text_primary'))
          .borderRadius(15)
          .onClick(() => {
            this.resetDanmakuStyleSettings()
          })
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 18, bottom: 6 })

      this.DanmakuPreviewCard()

      Column() {
        DanmakuSettingsSwitchRow({
          title: '弹幕描边',
          value: $danmakuBorder,
          onToggle: (value: boolean) => {
            this.setDanmakuBorder(value)
          }
        })
        this.ItemDivider()
        this.SliderRow('描边粗细', 'danmakuBorderSize', 0.1, 3, 0.1, this.danmakuBorder, (value: number) => {
          this.setDanmakuBorderSize(value)
        })
        this.ItemDivider()
        DanmakuSettingsSwitchRow({
          title: '弹幕颜色',
          value: $danmakuColor,
          onToggle: (value: boolean) => {
            this.setDanmakuColor(value)
          }
        })
        this.ItemDivider()
        this.SliderRow('字体大小', 'danmakuFontSize', 10, 48, 1, true, (value: number) => {
          this.setDanmakuFontSize(value)
        })
        this.ItemDivider()
        this.SliderRow('字体字重', 'danmakuFontWeight', 1, 9, 1, true, (value: number) => {
          this.setDanmakuFontWeight(value)
        })
        this.ItemDivider()
        this.SliderRow('不透明度', 'danmakuOpacity', 0.1, 1, 0.05, true, (value: number) => {
          this.setDanmakuOpacity(value)
        })
        this.ItemDivider()
        this.SliderRow('最大长度', 'danmakuMaxLength', 20, 200, 10, true, (value: number) => {
          this.setDanmakuMaxLength(value)
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
  private FilterSection(): void {
    Column() {
      this.SectionTitle('弹幕屏蔽')
      Column() {
        Row() {
          Column() {
            Text('屏蔽词')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Text(this.danmakuBlockKeywordsEnabled ? `${this.keywordCount} 条规则已启用` : '已禁用')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.keywordCount > 0) {
            Row() {
              Text(`${this.keywordCount}`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .width(22)
            .height(22)
            .borderRadius(11)
            .backgroundColor($r('app.color.accent_blue'))
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ right: 8 })
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
          router.pushUrl({ url: 'pages/settings/DanmakuBlockRulesPage' })
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
          Column() {
            Text('正则屏蔽')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Text(this.danmakuBlockRegexEnabled ? `${this.regexCount} 条规则已启用` : '已禁用')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.regexCount > 0) {
            Row() {
              Text(`${this.regexCount}`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .width(22)
            .height(22)
            .borderRadius(11)
            .backgroundColor($r('app.color.accent_blue'))
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ right: 8 })
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
          router.pushUrl({ url: 'pages/settings/DanmakuBlockRulesPage' })
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
          Text('高级屏蔽管理')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text('进入')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 6 })

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('sys.color.icon_secondary')])
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/settings/DanmakuBlockRulesPage' })
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
  private CacheSection(): void {
    Column() {
      this.SectionTitle('弹幕缓存')

      Column() {
        Row() {
          Column() {
            Text('弹幕缓存')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(`${this.cacheFileCount} 个文件，${this.cacheSizeText}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 2 })
            if (this.cacheExpiredCount > 0) {
              Text(`${this.cacheExpiredCount} 个已过期`)
                .fontSize(12)
                .fontColor($r('app.color.status_warning'))
                .width('100%')
                .margin({ top: 2 })
            }
          }
          .layoutWeight(1)

          Button('清过期')
            .height(36)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .enabled(!this.isClearingCache && this.cacheExpiredCount > 0)
            .backgroundColor($r('app.color.button_ghost_bg'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(18)
            .width(78)
            .margin({ right: 8 })
            .onClick(() => {
              this.clearExpiredDanmakuCache()
            })

          Button(this.isClearingCache ? '清理中...' : '清理缓存')
            .height(36)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .enabled(!this.isClearingCache && this.cacheFileCount > 0)
            .backgroundColor($r('app.color.button_ghost_bg'))
            .fontColor($r('app.color.text_primary'))
            .borderRadius(18)
            .width(92)
            .onClick(() => {
              this.clearDanmakuCache()
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 64 })
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })

        if (this.message.length > 0) {
          this.ItemDivider()
          Text(this.message)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 12 })
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
  private SliderRow(title: string, stateKey: string, min: number, max: number, step: number,
    enabled: boolean, onChanged: (value: number) => void): void {
    Column() {
      Row() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(enabled ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .layoutWeight(1)

        Text(this.getSliderValueText(stateKey))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 0 })

      Slider({ value: this.getSliderValue(stateKey), min: min, max: max, step: step })
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 })
        .enabled(enabled)
        .onChange((sliderValue: number) => {
          this.setSliderValue(stateKey, sliderValue)
          onChanged(sliderValue)
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
  }

  private getActiveSourceNames(): string {
    const names: string[] = []
    if (this.danmakuBiliBiliSource) {
      names.push('B站')
    }
    if (this.danmakuGamerSource) {
      names.push('Gamer')
    }
    if (this.danmakuDanDanSource) {
      names.push('弹弹')
    }
    if (names.length === 0) {
      return '无'
    }
    return names.join('/')
  }

  private maskedAppId(): string {
    const id = this.dandanAppId
    if (id.length <= 4) {
      return id
    }
    return '****' + id.substring(id.length - 4)
  }

  private mapFontWeight(weight: number): FontWeight {
    if (weight <= 1) return FontWeight.Lighter
    if (weight <= 3) return FontWeight.Lighter
    if (weight <= 5) return FontWeight.Normal
    if (weight <= 7) return FontWeight.Bold
    if (weight <= 8) return FontWeight.Bolder
    return FontWeight.Bolder
  }

  private getSliderValue(stateKey: string): number {
    if (stateKey === 'danmakuDisplayArea') return this.danmakuDisplayArea
    if (stateKey === 'danmakuScrollDuration') return this.danmakuScrollDuration
    if (stateKey === 'danmakuLineHeight') return this.danmakuLineHeight
    if (stateKey === 'danmakuBorderSize') return this.danmakuBorderSize
    if (stateKey === 'danmakuFontSize') return this.danmakuFontSize
    if (stateKey === 'danmakuFontWeight') return this.danmakuFontWeight
    if (stateKey === 'danmakuOpacity') return this.danmakuOpacity
    if (stateKey === 'danmakuMaxLength') return this.danmakuMaxLength
    if (stateKey === 'danmakuTimeOffset') return this.danmakuTimeOffset
    return 0
  }

  private setSliderValue(stateKey: string, value: number): void {
    if (stateKey === 'danmakuDisplayArea') this.danmakuDisplayArea = value
    if (stateKey === 'danmakuScrollDuration') this.danmakuScrollDuration = value
    if (stateKey === 'danmakuLineHeight') this.danmakuLineHeight = value
    if (stateKey === 'danmakuBorderSize') this.danmakuBorderSize = value
    if (stateKey === 'danmakuFontSize') this.danmakuFontSize = value
    if (stateKey === 'danmakuFontWeight') this.danmakuFontWeight = value
    if (stateKey === 'danmakuOpacity') this.danmakuOpacity = value
    if (stateKey === 'danmakuMaxLength') this.danmakuMaxLength = value
    if (stateKey === 'danmakuTimeOffset') this.danmakuTimeOffset = value
  }

  private getSliderValueText(stateKey: string): string {
    if (stateKey === 'danmakuDisplayArea') return `${Math.round(this.danmakuDisplayArea * 100)}%`
    if (stateKey === 'danmakuScrollDuration') return `${this.danmakuScrollDuration.toFixed(1)} 秒`
    if (stateKey === 'danmakuLineHeight') return this.danmakuLineHeight.toFixed(1)
    if (stateKey === 'danmakuBorderSize') return this.danmakuBorderSize.toFixed(1)
    if (stateKey === 'danmakuFontSize') return `${Math.floor(this.danmakuFontSize)}`
    if (stateKey === 'danmakuFontWeight') return `${Math.floor(this.danmakuFontWeight)}`
    if (stateKey === 'danmakuOpacity') return `${Math.round(this.danmakuOpacity * 100)}%`
    if (stateKey === 'danmakuMaxLength') return `${Math.floor(this.danmakuMaxLength)}`
    if (stateKey === 'danmakuTimeOffset') {
      if (this.danmakuTimeOffset === 0) return '无偏移'
      if (this.danmakuTimeOffset > 0) return `延后${this.danmakuTimeOffset.toFixed(2)}秒`
      return `提前${Math.abs(this.danmakuTimeOffset).toFixed(2)}秒`
    }
    return ''
  }

  private async loadSettings(): Promise<void> {
    try {
      await this.loadDanmakuStyleSettings()
      const credStore = DandanCredentialStore.getInstance()
      await credStore.init()
      this.isDanmakuCredentialConfigured = credStore.hasCredentials()
      this.dandanAppId = credStore.getAppId()
      this.dandanAppSecret = credStore.getAppSecret()
      this.isEditingCredentials = !this.isDanmakuCredentialConfigured
      await this.refreshCacheSummary()
      this.updateFilterCounts()
    } catch (err) {
      logger.error('Load danmaku settings failed: %{public}s', JSON.stringify(err))
    }
  }

  private updateFilterCounts(): void {
    this.keywordCount = this.parseKeywordCount(this.danmakuBlockKeywords)
    this.regexCount = this.parseRegexCount(this.danmakuBlockRegex)
  }

  private parseKeywordCount(text: string): number {
    const parts = text.split(/[\s,，;；、]+/)
    let count = 0
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].trim().length > 0) {
        count++
      }
    }
    return count
  }

  private parseRegexCount(text: string): number {
    const parts = text.split('|')
    let count = 0
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].trim().length > 0) {
        count++
      }
    }
    return count
  }

  private async loadDanmakuStyleSettings(): Promise<void> {
    const settings = await DanmakuStyleSettings.load()
    this.danmakuBorder = settings.border
    this.danmakuBorderSize = settings.borderSize
    this.danmakuColor = settings.useSourceColor
    this.danmakuFontSize = settings.fontSize
    this.danmakuFontWeight = settings.fontWeight
    this.danmakuOpacity = settings.opacity
    this.danmakuScrollDuration = settings.scrollDurationSec
    this.danmakuLineHeight = settings.lineHeight
    this.danmakuDisplayArea = settings.displayArea
    this.danmakuHideScroll = settings.hideScroll
    this.danmakuHideTop = settings.hideTop
    this.danmakuHideBottom = settings.hideBottom
    this.danmakuHideColor = settings.hideColor
    this.danmakuBiliBiliSource = settings.biliBiliSource
    this.danmakuGamerSource = settings.gamerSource
    this.danmakuDanDanSource = settings.danDanSource
    this.danmakuFollowSpeed = settings.followSpeed
    this.danmakuDeduplication = settings.deduplication
    this.danmakuMaxLength = settings.maxLength
    this.danmakuBlockKeywordsEnabled = settings.blockKeywordsEnabled
    this.danmakuBlockKeywords = settings.blockKeywordsText
    this.danmakuBlockRegexEnabled = settings.blockRegexEnabled
    this.danmakuBlockRegex = settings.blockRegexText
    this.danmakuTimeOffset = settings.danmakuTimeOffset
    this.danmakuMassiveMode = settings.massiveMode
    logger.info('弹幕设置页加载: color=%{public}s, hideColor=%{public}s, hideScroll=%{public}s, hideTop=%{public}s, hideBottom=%{public}s',
      String(this.danmakuColor), String(this.danmakuHideColor), String(this.danmakuHideScroll),
      String(this.danmakuHideTop), String(this.danmakuHideBottom))
  }

  private async saveDanmakuCredentials(): Promise<void> {
    try {
      const store = DandanCredentialStore.getInstance()
      await store.setCredentials(this.dandanAppId.trim(), this.dandanAppSecret.trim())
      this.isDanmakuCredentialConfigured = store.hasCredentials()
      this.dandanAppId = store.getAppId()
      this.dandanAppSecret = store.getAppSecret()
      this.testConnectionMessage = this.isDanmakuCredentialConfigured ? '凭据已保存' : '请输入完整凭据'
      if (this.isDanmakuCredentialConfigured) {
        this.isEditingCredentials = false
      }
    } catch (_err) {
      this.testConnectionMessage = '凭据保存失败'
      logger.error('保存弹幕凭据失败')
    }
  }

  private async testDanmakuConnection(): Promise<void> {
    this.isTestingConnection = true
    this.testConnectionMessage = '正在测试连接...'
    try {
      await this.saveDanmakuCredentials()
      const client = DandanApiClient.getInstance()
      const queryParameters: Record<string, string> = {}
      queryParameters['keyword'] = 'test'
      const result = await client.get('/api/v2/search/anime', queryParameters)
      if (result.isSuccessful) {
        this.testConnectionMessage = '连接成功'
      } else if (result.statusCode === 403) {
        this.testConnectionMessage = '连接失败: HTTP 403 (鉴权失败)'
      } else {
        this.testConnectionMessage = `连接失败: HTTP ${result.statusCode}`
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.testConnectionMessage = msg.toLowerCase().indexOf('timeout') >= 0 ? '连接失败: 请求超时' : '连接失败: 网络错误'
    } finally {
      this.isTestingConnection = false
    }
  }

  private async clearDanmakuCredentials(): Promise<void> {
    try {
      const store = DandanCredentialStore.getInstance()
      await store.clearCredentials()
      this.dandanAppId = ''
      this.dandanAppSecret = ''
      this.isDanmakuCredentialConfigured = false
      this.isEditingCredentials = true
      this.testConnectionMessage = '凭据已清除'
    } catch (_err) {
      this.dandanAppId = ''
      this.dandanAppSecret = ''
      this.isDanmakuCredentialConfigured = false
      this.isEditingCredentials = true
      this.testConnectionMessage = '清除可能不完整'
    }
  }

  private async setDanmakuBorder(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_BORDER, enabled, (value: boolean) => {
      this.danmakuBorder = value
    })
  }

  private async setDanmakuBorderSize(value: number): Promise<void> {
    const nextValue = Math.round(Math.max(0.1, Math.min(3, value)) * 10) / 10
    this.danmakuBorderSize = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_BORDER_SIZE, nextValue)
  }

  private async setDanmakuColor(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_COLOR, enabled, (value: boolean) => {
      this.danmakuColor = value
    })
  }

  private async setDanmakuFontSize(value: number): Promise<void> {
    const nextValue = Math.floor(Math.max(10, Math.min(48, value)))
    this.danmakuFontSize = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_FONT_SIZE, nextValue)
  }

  private async setDanmakuFontWeight(value: number): Promise<void> {
    const nextValue = Math.floor(Math.max(1, Math.min(9, value)))
    this.danmakuFontWeight = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_FONT_WEIGHT, nextValue)
  }

  private async setDanmakuOpacity(value: number): Promise<void> {
    const nextValue = Math.round(Math.max(0.1, Math.min(1, value)) * 100) / 100
    this.danmakuOpacity = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_OPACITY, nextValue)
  }

  private async setDanmakuScrollDuration(value: number): Promise<void> {
    const nextValue = Math.round(Math.max(4, Math.min(12, value)) * 2) / 2
    this.danmakuScrollDuration = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_SCROLL_DURATION, nextValue)
  }

  private async setDanmakuLineHeight(value: number): Promise<void> {
    const nextValue = Math.round(Math.max(1.0, Math.min(2.5, value)) * 10) / 10
    this.danmakuLineHeight = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_LINE_HEIGHT, nextValue)
  }

  private async setDanmakuDisplayArea(value: number): Promise<void> {
    const nextValue = Math.round(Math.max(0.25, Math.min(1, value)) * 4) / 4
    this.danmakuDisplayArea = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_DISPLAY_AREA, nextValue)
  }

  private async setDanmakuHideScroll(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_HIDE_SCROLL, enabled, (value: boolean) => {
      this.danmakuHideScroll = value
    })
  }

  private async setDanmakuHideTop(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_HIDE_TOP, enabled, (value: boolean) => {
      this.danmakuHideTop = value
    })
  }

  private async setDanmakuHideBottom(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_HIDE_BOTTOM, enabled, (value: boolean) => {
      this.danmakuHideBottom = value
    })
  }

  private async setDanmakuHideColor(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_HIDE_COLOR, enabled, (value: boolean) => {
      this.danmakuHideColor = value
    })
  }

  private async setDanmakuBiliBiliSource(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_BILIBILI_SOURCE, enabled, (value: boolean) => {
      this.danmakuBiliBiliSource = value
    })
  }

  private async setDanmakuGamerSource(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_GAMER_SOURCE, enabled, (value: boolean) => {
      this.danmakuGamerSource = value
    })
  }

  private async setDanmakuDanDanSource(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_DANDAN_SOURCE, enabled, (value: boolean) => {
      this.danmakuDanDanSource = value
    })
  }

  private async setDanmakuFollowSpeed(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_FOLLOW_SPEED, enabled, (value: boolean) => {
      this.danmakuFollowSpeed = value
    })
  }

  private async setDanmakuDeduplication(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_DEDUPLICATION, enabled, (value: boolean) => {
      this.danmakuDeduplication = value
    })
  }

  private async setDanmakuMassiveMode(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_MASSIVE_MODE, enabled, (value: boolean) => {
      this.danmakuMassiveMode = value
    })
  }

  private async setDanmakuMaxLength(value: number): Promise<void> {
    const nextValue = Math.floor(Math.max(20, Math.min(200, value)) / 10) * 10
    this.danmakuMaxLength = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_MAX_LENGTH, nextValue)
  }

  private async setDanmakuBlockKeywordsEnabled(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED, enabled, (value: boolean) => {
      this.danmakuBlockKeywordsEnabled = value
    })
  }

  private async setDanmakuBlockKeywords(value: string): Promise<void> {
    const nextValue = DanmakuStyleSettings.clampText(value)
    this.danmakuBlockKeywords = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setString(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS, nextValue)
    this.updateFilterCounts()
  }

  private async setDanmakuBlockRegexEnabled(enabled: boolean): Promise<void> {
    await this.setBooleanSetting(DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED, enabled, (value: boolean) => {
      this.danmakuBlockRegexEnabled = value
    })
  }

  private async setDanmakuBlockRegex(value: string): Promise<void> {
    const nextValue = DanmakuStyleSettings.clampText(value)
    this.danmakuBlockRegex = nextValue
    this.message = this.isValidDanmakuRegex(nextValue) ? '' : '正则表达式无效，将在播放时忽略'
    await PreferencesStore.getInstance().setString(DANMAKU_PREFS_KEY_BLOCK_REGEX, nextValue)
    this.updateFilterCounts()
  }

  private async setDanmakuTimeOffset(value: number): Promise<void> {
    const nextValue = Math.round(Math.max(-60, Math.min(60, value)) * 4) / 4
    this.danmakuTimeOffset = nextValue
    this.message = ''
    await PreferencesStore.getInstance().setNumber(DANMAKU_PREFS_KEY_TIME_OFFSET, nextValue)
  }

  private async setBooleanSetting(key: string, value: boolean, applyValue: (value: boolean) => void): Promise<void> {
    applyValue(value)
    this.message = ''
    await PreferencesStore.getInstance().setBoolean(key, value)
    const saved = await PreferencesStore.getInstance().getBoolean(key, !value)
    if (saved !== value) {
      applyValue(saved)
      this.message = '设置保存失败，已恢复原状态'
      logger.warn('Boolean setting verify failed: key=%{public}s, expected=%{public}s, saved=%{public}s',
        key, String(value), String(saved))
      return
    }
    logger.info('Boolean setting saved: key=%{public}s, value=%{public}s', key, String(saved))
  }

  private async resetDanmakuStyleSettings(): Promise<void> {
    try {
      await DanmakuStyleSettings.reset()
      await this.loadDanmakuStyleSettings()
      this.updateFilterCounts()
      this.message = '弹幕设置已恢复默认'
    } catch (err) {
      this.message = '恢复默认失败'
      logger.error('Reset danmaku settings failed: %{public}s', JSON.stringify(err))
    }
  }

  private async refreshCacheSummary(): Promise<void> {
    const summary: DanmakuCacheSummary = await DanmakuCacheStore.getInstance().getSummary()
    this.cacheFileCount = summary.fileCount
    this.cacheExpiredCount = summary.expiredCount
    this.cacheSizeText = this.formatBytes(summary.totalBytes)
  }

  private async clearExpiredDanmakuCache(): Promise<void> {
    this.isClearingCache = true
    try {
      const removed = await DanmakuCacheStore.getInstance().clearExpired()
      await this.refreshCacheSummary()
      this.message = `已清理 ${removed} 个过期缓存`
    } catch (err) {
      this.message = '清理过期缓存失败'
      logger.error('Clear expired danmaku cache failed: %{public}s', JSON.stringify(err))
    } finally {
      this.isClearingCache = false
    }
  }

  private async clearDanmakuCache(): Promise<void> {
    this.isClearingCache = true
    try {
      await DanmakuCacheStore.getInstance().clearAll()
      await this.refreshCacheSummary()
      this.message = '弹幕缓存已清理'
    } catch (err) {
      this.message = '清理弹幕缓存失败'
      logger.error('Clear danmaku cache failed: %{public}s', JSON.stringify(err))
    } finally {
      this.isClearingCache = false
    }
  }

  private isValidDanmakuRegex(value: string): boolean {
    const pattern = value.trim()
    if (pattern.length === 0) {
      return true
    }
    try {
      new RegExp(pattern)
      return true
    } catch (_err) {
      return false
    }
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`
    }
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  }
}
