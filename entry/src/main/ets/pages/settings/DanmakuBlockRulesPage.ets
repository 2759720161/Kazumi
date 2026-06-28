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
import {
  DanmakuStyleSettings,
  DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED,
  DANMAKU_PREFS_KEY_BLOCK_KEYWORDS,
  DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED,
  DANMAKU_PREFS_KEY_BLOCK_REGEX
} from '../../core/danmaku/DanmakuStyleSettings'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuBlockRulesPage')

@Entry
@Component
export struct DanmakuBlockRulesPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State keywordsEnabled: boolean = true
  @State regexEnabled: boolean = true
  @State keywords: string[] = []
  @State regexRules: string[] = []
  @State keywordInput: string = ''
  @State regexInput: string = ''
  @State message: string = ''
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadRules()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          this.KeywordSection()
          this.RegexSection()

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 18, right: 18, top: 10 })
          }

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
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
    .titleBar(buildTitleBarOptions('弹幕屏蔽管理'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private SectionHeader(title: string): void {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, right: 6, top: 18, bottom: 6 })
  }

  @Builder
  private KeywordSection(): void {
    Column() {
      this.SectionHeader('屏蔽词')
      Column() {
        Row() {
          Text('屏蔽词')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Row() {
            Blank()
              .width(20)
              .height(20)
              .borderRadius(10)
              .backgroundColor(Color.White)
          }
          .width(44)
          .height(24)
          .borderRadius(12)
          .padding(2)
          .justifyContent(this.keywordsEnabled ? FlexAlign.End : FlexAlign.Start)
          .backgroundColor(this.keywordsEnabled ? $r('app.color.accent_blue') : $r('app.color.divider_blue'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 6 })
        .onClick(() => {
          this.setKeywordsEnabled(!this.keywordsEnabled)
        })

        Row() {
          TextInput({ placeholder: '新增屏蔽词', text: this.keywordInput })
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.keywordInput = value
            })
            .onSubmit(() => {
              this.addKeyword()
            })

          Button('添加')
            .height(36)
            .fontSize(13)
            .margin({ left: 8 })
            .onClick(() => {
              this.addKeyword()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        this.KeywordChipList()
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
  private KeywordChipList(): void {
    if (this.keywords.length === 0) {
      Text('暂无规则')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 14 })
    } else {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignContent: FlexAlign.Start }) {
        ForEach(this.keywords, (item: string, index?: number) => {
          Row() {
            Text(item)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 120 })
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.multiply'))
              .fontSize(14)
              .fontColor([$r('sys.color.icon_secondary')])
              .margin({ left: 4 })
              .onClick(() => {
                this.removeRule(index ?? -1, false)
              })
          }
          .height(30)
          .padding({ left: 12, right: 8 })
          .borderRadius(15)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .margin({ right: 6, bottom: 6 })
        }, (item: string, index?: number) => `keyword_${index}_${item}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 14 })
    }
  }

  @Builder
  private RegexSection(): void {
    Column() {
      this.SectionHeader('正则规则')
      Column() {
        Row() {
          Text('正则规则')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Row() {
            Blank()
              .width(20)
              .height(20)
              .borderRadius(10)
              .backgroundColor(Color.White)
          }
          .width(44)
          .height(24)
          .borderRadius(12)
          .padding(2)
          .justifyContent(this.regexEnabled ? FlexAlign.End : FlexAlign.Start)
          .backgroundColor(this.regexEnabled ? $r('app.color.accent_blue') : $r('app.color.divider_blue'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 6 })
        .onClick(() => {
          this.setRegexEnabled(!this.regexEnabled)
        })

        Row() {
          TextInput({ placeholder: '新增正则表达式', text: this.regexInput })
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.regexInput = value
            })
            .onSubmit(() => {
              this.addRegexRule()
            })

          Button('添加')
            .height(36)
            .fontSize(13)
            .margin({ left: 8 })
            .onClick(() => {
              this.addRegexRule()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        this.RegexChipList()
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
  private RegexChipList(): void {
    if (this.regexRules.length === 0) {
      Text('暂无规则')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 14 })
    } else {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignContent: FlexAlign.Start }) {
        ForEach(this.regexRules, (item: string, index?: number) => {
          Row() {
            Text(item)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 120 })
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.multiply'))
              .fontSize(14)
              .fontColor([$r('sys.color.icon_secondary')])
              .margin({ left: 4 })
              .onClick(() => {
                this.removeRule(index ?? -1, true)
              })
          }
          .height(30)
          .padding({ left: 12, right: 8 })
          .borderRadius(15)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .margin({ right: 6, bottom: 6 })
        }, (item: string, index?: number) => `regex_${index}_${item}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 14 })
    }
  }

  private async loadRules(): Promise<void> {
    try {
      const settings = await DanmakuStyleSettings.load()
      this.keywordsEnabled = settings.blockKeywordsEnabled
      this.regexEnabled = settings.blockRegexEnabled
      this.keywords = this.parseKeywordList(settings.blockKeywordsText)
      this.regexRules = this.parseRegexList(settings.blockRegexText)
    } catch (err) {
      logger.error('Load block rules failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setKeywordsEnabled(value: boolean): Promise<void> {
    this.keywordsEnabled = value
    await PreferencesStore.getInstance().setBoolean(DANMAKU_PREFS_KEY_BLOCK_KEYWORDS_ENABLED, value)
  }

  private async setRegexEnabled(value: boolean): Promise<void> {
    this.regexEnabled = value
    await PreferencesStore.getInstance().setBoolean(DANMAKU_PREFS_KEY_BLOCK_REGEX_ENABLED, value)
  }

  private async addKeyword(): Promise<void> {
    const normalized = this.keywordInput.trim()
    if (normalized.length === 0) {
      return
    }
    if (this.keywords.indexOf(normalized) >= 0) {
      this.message = '屏蔽词已存在'
      return
    }
    this.keywords.push(normalized)
    this.keywordInput = ''
    await this.saveKeywords()
    this.message = '屏蔽词已添加'
  }

  private async addRegexRule(): Promise<void> {
    const normalized = this.regexInput.trim()
    if (normalized.length === 0) {
      return
    }
    if (!this.isRegexValid(normalized)) {
      this.message = '正则表达式无效'
      return
    }
    if (this.regexRules.indexOf(normalized) >= 0) {
      this.message = '正则规则已存在'
      return
    }
    this.regexRules.push(normalized)
    this.regexInput = ''
    await this.saveRegexRules()
    this.message = '正则规则已添加'
  }

  private async removeRule(index: number, isRegex: boolean): Promise<void> {
    if (index < 0) {
      return
    }
    if (isRegex) {
      if (index >= this.regexRules.length) {
        return
      }
      this.regexRules.splice(index, 1)
      await this.saveRegexRules()
      this.message = '正则规则已删除'
    } else {
      if (index >= this.keywords.length) {
        return
      }
      this.keywords.splice(index, 1)
      await this.saveKeywords()
      this.message = '屏蔽词已删除'
    }
  }

  private async saveKeywords(): Promise<void> {
    await PreferencesStore.getInstance().setString(
      DANMAKU_PREFS_KEY_BLOCK_KEYWORDS, DanmakuStyleSettings.clampText(this.keywords.join(' ')))
  }

  private async saveRegexRules(): Promise<void> {
    await PreferencesStore.getInstance().setString(
      DANMAKU_PREFS_KEY_BLOCK_REGEX, DanmakuStyleSettings.clampText(this.regexRules.join('|')))
  }

  private parseKeywordList(text: string): string[] {
    const result: string[] = []
    const parts = text.split(/[\s,，;；、]+/)
    for (let i = 0; i < parts.length; i++) {
      const item = parts[i].trim()
      if (item.length > 0 && result.indexOf(item) < 0) {
        result.push(item)
      }
    }
    return result
  }

  private parseRegexList(text: string): string[] {
    const result: string[] = []
    const parts = text.split('|')
    for (let i = 0; i < parts.length; i++) {
      const item = parts[i].trim()
      if (item.length > 0 && result.indexOf(item) < 0) {
        result.push(item)
      }
    }
    return result
  }

  private isRegexValid(value: string): boolean {
    try {
      new RegExp(value)
      return true
    } catch (_err) {
      return false
    }
  }
}
