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
              .padding({ left: 16, right: 16, top: 10 })
          }

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
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
  private KeywordSection(): void {
    Column() {
      this.SectionHeader('屏蔽词', this.keywordsEnabled, () => {
        this.setKeywordsEnabled(!this.keywordsEnabled)
      })
      this.InputRow('新增屏蔽词', this.keywordInput, (value: string) => {
        this.keywordInput = value
      }, () => {
        this.addKeyword()
      })
      this.RuleList(this.keywords, false)
    }
    .width('100%')
  }

  @Builder
  private RegexSection(): void {
    Column() {
      this.SectionHeader('正则规则', this.regexEnabled, () => {
        this.setRegexEnabled(!this.regexEnabled)
      })
      this.InputRow('新增正则表达式', this.regexInput, (value: string) => {
        this.regexInput = value
      }, () => {
        this.addRegexRule()
      })
      this.RuleList(this.regexRules, true)
    }
    .width('100%')
  }

  @Builder
  private SectionHeader(title: string, enabled: boolean, onToggle: () => void): void {
    Row() {
      Text(title)
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
      .justifyContent(enabled ? FlexAlign.End : FlexAlign.Start)
      .backgroundColor(enabled ? $r('app.color.accent_blue') : $r('app.color.divider_blue'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
    .onClick(() => {
      onToggle()
    })
  }

  @Builder
  private InputRow(placeholder: string, text: string, onChanged: (value: string) => void, onSubmit: () => void): void {
    Row() {
      TextInput({ placeholder: placeholder, text: text })
        .height(40)
        .fontSize(14)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .layoutWeight(1)
        .onChange((value: string) => {
          onChanged(value)
        })
        .onSubmit(() => {
          onSubmit()
        })

      Button('添加')
        .height(36)
        .fontSize(13)
        .margin({ left: 8 })
        .onClick(() => {
          onSubmit()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  private RuleList(items: string[], isRegex: boolean): void {
    if (items.length === 0) {
      Text('暂无规则')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    } else {
      Column() {
        ForEach(items, (item: string, index?: number) => {
          Row() {
            Text(item)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text('删除')
              .fontSize(13)
              .fontColor($r('app.color.status_error'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.removeRule(index ?? -1, isRegex)
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
        }, (item: string, index?: number) => `${isRegex ? 'regex' : 'keyword'}_${index}_${item}`)
      }
      .width('100%')
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
