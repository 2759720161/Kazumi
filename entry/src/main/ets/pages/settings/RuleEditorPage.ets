import { promptAction, router, curves } from '@kit.ArkUI'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitle,
  TitleBarContentOptions
} from '@kit.UIDesignKit'
import { AppConstants } from '../../constants/AppConstants'
import {
  ApiBodyType,
  ApiChapterConfig,
  ApiChapterFormat,
  ApiEpisodePageConfig,
  ApiRequestConfig,
  ApiSearchConfig,
  RuleMode
} from '../../models/ApiRuleConfig'
import { AntiCrawlerConfig, RuleInstallOrigin, RuleSource } from '../../models/RuleSource'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { SettingsChangeSignal } from '../../store/SettingsChangeSignal'
import { Logger } from '../../utils/Logger'
import {
  buildTitleBarOptions,
  getTopSpacerHeight,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

const logger = new Logger('RuleEditorPage')

@Entry
@Component
struct RuleEditorPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State ruleName: string = ''
  @State version: string = '1.0'
  @State baseUrl: string = ''
  @State searchMode: string = RuleMode.XPATH
  @State chapterMode: string = RuleMode.XPATH
  @State searchUsePost: boolean = false
  @State searchUrl: string = ''
  @State searchList: string = ''
  @State searchName: string = ''
  @State searchResult: string = ''
  @State chapterRoads: string = ''
  @State chapterResult: string = ''
  @State searchApiMethod: string = 'GET'
  @State searchApiUrl: string = ''
  @State searchApiHeaders: string = '{}'
  @State searchApiQuery: string = '{}'
  @State searchApiBodyType: string = ApiBodyType.NONE
  @State searchApiBody: string = '{}'
  @State searchApiListPath: string = ''
  @State searchApiNamePath: string = ''
  @State searchApiSourcePath: string = ''
  @State chapterApiMethod: string = 'GET'
  @State chapterApiUrl: string = ''
  @State chapterApiHeaders: string = '{}'
  @State chapterApiQuery: string = '{}'
  @State chapterApiBodyType: string = ApiBodyType.NONE
  @State chapterApiBody: string = '{}'
  @State chapterApiFormat: string = ApiChapterFormat.NESTED
  @State chapterApiRoadsPath: string = ''
  @State chapterApiRoadNamePath: string = ''
  @State chapterApiEpisodesPath: string = ''
  @State chapterApiEpisodeNamePath: string = ''
  @State chapterApiEpisodeUrlPath: string = ''
  @State chapterApiRoadNamesPath: string = ''
  @State chapterApiRoadEpisodesPath: string = ''
  @State chapterApiRoadSeparator: string = '$$$'
  @State chapterApiEpisodeSeparator: string = '#'
  @State chapterApiFieldSeparator: string = '$'
  @State chapterApiVariables: string = '{}'
  @State chapterApiPageUrl: string = ''
  @State chapterApiPageQuery: string = '{}'
  @State useLegacyParser: boolean = false
  @State adBlocker: boolean = false
  @State userAgent: string = ''
  @State referer: string = ''
  @State captchaEnabled: boolean = false
  @State captchaType: number = 1
  @State captchaDetectValue: string = ''
  @State captchaImage: string = ''
  @State captchaInput: string = ''
  @State captchaButton: string = ''
  @State captchaScript: string = ''
  @State ruleModeMenuSection: string = ''
  @State requestMethodMenuSection: string = ''
  @State saving: boolean = false
  private scroller: Scroller = new Scroller()
  private ruleStore: RuleSourceStore = new RuleSourceStore()

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          this.BasicSection()
          this.SearchSection()
          this.ChapterSection()
          this.AdvancedSection()
          Blank().height(this.bottomSafeHeight + 28)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(this.buildEditorTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  BasicSection(): void {
    Column() {
      this.SectionTitle('基本信息')
      this.Input('规则名称', this.ruleName, '例如：my-source', (value: string) => this.ruleName = value)
      this.Input('规则版本', this.version, '例如：1.0', (value: string) => this.version = value)
      this.Input('基础地址', this.baseUrl, 'https://example.com', (value: string) => this.baseUrl = value)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  SearchSection(): void {
    Column() {
      this.SectionTitle('搜索规则')
      this.ModeSwitch('search', this.searchMode)
      if (this.searchMode === RuleMode.XPATH) {
        this.MethodSwitch('searchXPath', this.searchUsePost ? 'POST' : 'GET')
        this.Input('搜索地址', this.searchUrl, '必须包含 @keyword', (value: string) => this.searchUrl = value)
        this.Input('结果列表 XPath', this.searchList, '//div[contains(@class, "item")]', (value: string) => this.searchList = value, true)
        this.Input('名称 XPath', this.searchName, '//a/text()', (value: string) => this.searchName = value, true)
        this.Input('详情地址 XPath', this.searchResult, '//a/@href', (value: string) => this.searchResult = value, true)
      } else {
        this.ApiSearchFields()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  ApiSearchFields(): void {
    this.MethodSwitch('searchApi', this.searchApiMethod)
    this.Input('搜索请求地址', this.searchApiUrl, 'https://example.com/api/search', (value: string) => this.searchApiUrl = value)
    this.Input('请求头 JSON', this.searchApiHeaders, '{ }', (value: string) => this.searchApiHeaders = value, true)
    this.Input('查询参数 JSON', this.searchApiQuery, '{"q":"@keyword"}', (value: string) => this.searchApiQuery = value, true)
    this.BodyTypeSwitch(this.searchApiBodyType, (type: string) => this.searchApiBodyType = type)
    if (this.searchApiBodyType !== ApiBodyType.NONE) {
      this.Input('请求体 JSON', this.searchApiBody, '{"keyword":"@keyword"}', (value: string) => this.searchApiBody = value, true)
    }
    this.Input('结果列表 JSONPath', this.searchApiListPath, '$.data[*]', (value: string) => this.searchApiListPath = value)
    this.Input('名称 JSONPath', this.searchApiNamePath, '$.name', (value: string) => this.searchApiNamePath = value)
    this.Input('来源 JSONPath', this.searchApiSourcePath, '$.id', (value: string) => this.searchApiSourcePath = value)
  }

  @Builder
  ChapterSection(): void {
    Column() {
      this.SectionTitle('选集规则')
      this.ModeSwitch('chapter', this.chapterMode)
      if (this.chapterMode === RuleMode.XPATH) {
        this.Input('播放线路 XPath', this.chapterRoads, '//div[contains(@class, "playlist")]', (value: string) => this.chapterRoads = value, true)
        this.Input('剧集 XPath', this.chapterResult, '//a', (value: string) => this.chapterResult = value, true)
      } else {
        this.ApiChapterFields()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  ApiChapterFields(): void {
    this.MethodSwitch('chapterApi', this.chapterApiMethod)
    this.Input('选集请求地址', this.chapterApiUrl, 'https://example.com/api/detail/@source', (value: string) => this.chapterApiUrl = value)
    this.Input('请求头 JSON', this.chapterApiHeaders, '{ }', (value: string) => this.chapterApiHeaders = value, true)
    this.Input('查询参数 JSON', this.chapterApiQuery, '{ }', (value: string) => this.chapterApiQuery = value, true)
    this.BodyTypeSwitch(this.chapterApiBodyType, (type: string) => this.chapterApiBodyType = type)
    if (this.chapterApiBodyType !== ApiBodyType.NONE) {
      this.Input('请求体 JSON', this.chapterApiBody, '{"id":"@source"}', (value: string) => this.chapterApiBody = value, true)
    }
    this.FormatSwitch(this.chapterApiFormat, (format: string) => this.chapterApiFormat = format)
    if (this.chapterApiFormat === ApiChapterFormat.NESTED) {
      this.Input('线路列表 JSONPath', this.chapterApiRoadsPath, '$.data.roads[*]，单线路可留空', (value: string) => this.chapterApiRoadsPath = value)
      this.Input('线路名称 JSONPath', this.chapterApiRoadNamePath, '$.name', (value: string) => this.chapterApiRoadNamePath = value)
      this.Input('剧集列表 JSONPath', this.chapterApiEpisodesPath, '$.episodes[*]', (value: string) => this.chapterApiEpisodesPath = value)
      this.Input('剧集名称 JSONPath', this.chapterApiEpisodeNamePath, '$.name', (value: string) => this.chapterApiEpisodeNamePath = value)
      this.Input('播放入口 JSONPath', this.chapterApiEpisodeUrlPath, '$.url，可留空并使用播放页模板', (value: string) => this.chapterApiEpisodeUrlPath = value)
    } else {
      this.Input('线路名称串 JSONPath', this.chapterApiRoadNamesPath, '$.data.names', (value: string) => this.chapterApiRoadNamesPath = value)
      this.Input('线路剧集串 JSONPath', this.chapterApiRoadEpisodesPath, '$.data.episodes', (value: string) => this.chapterApiRoadEpisodesPath = value)
      this.Input('线路分隔符', this.chapterApiRoadSeparator, '$$$', (value: string) => this.chapterApiRoadSeparator = value)
      this.Input('剧集分隔符', this.chapterApiEpisodeSeparator, '#', (value: string) => this.chapterApiEpisodeSeparator = value)
      this.Input('名称地址分隔符', this.chapterApiFieldSeparator, '$', (value: string) => this.chapterApiFieldSeparator = value)
    }
    this.Input('响应变量 JSON', this.chapterApiVariables, '{"slug":"$.data.slug"}', (value: string) => this.chapterApiVariables = value, true)
    this.Input('播放页地址模板', this.chapterApiPageUrl, 'https://example.com/play/@source/@episodeUrl', (value: string) => this.chapterApiPageUrl = value)
    this.Input('播放页查询参数 JSON', this.chapterApiPageQuery, '{ }', (value: string) => this.chapterApiPageQuery = value, true)
  }

  @Builder
  AdvancedSection(): void {
    Column() {
      this.SectionTitle('高级选项')
      this.SwitchRow('简易解析', this.useLegacyParser, (value: boolean) => this.useLegacyParser = value)
      this.SwitchRow('广告过滤', this.adBlocker, (value: boolean) => this.adBlocker = value)
      this.Input('播放 User-Agent', this.userAgent, '可选', (value: string) => this.userAgent = value, true)
      this.Input('播放 Referer', this.referer, '可选', (value: string) => this.referer = value)
      if (this.searchMode === RuleMode.XPATH) {
        this.SwitchRow('启用验证码验证', this.captchaEnabled, (value: boolean) => this.captchaEnabled = value)
        if (this.captchaEnabled) {
          this.CaptchaTypeSwitch()
          this.Input('验证页检测值', this.captchaDetectValue, '验证码图片或验证页面 XPath', (value: string) => this.captchaDetectValue = value, true)
          if (this.captchaType === 1) {
            this.Input('验证码图片 XPath', this.captchaImage, '//img[@class="captcha"]', (value: string) => this.captchaImage = value, true)
            this.Input('验证码输入框 XPath', this.captchaInput, '//input[@name="captcha"]', (value: string) => this.captchaInput = value, true)
          }
          if (this.captchaType !== 3) {
            this.Input('验证提交按钮 XPath', this.captchaButton, '//button[@type="submit"]', (value: string) => this.captchaButton = value, true)
          }
          if (this.captchaType === 3) {
            this.Input('验证脚本', this.captchaScript, 'KazumiCaptcha.done();', (value: string) => this.captchaScript = value, true)
          }
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  SectionTitle(title: string): void {
    Text(title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .textAlign(TextAlign.Start)
      .margin({ bottom: 14 })
  }

  @Builder
  Input(label: string, value: string, placeholder: string, onChanged: (value: string) => void, multiline: boolean = false): void {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 6 })
      if (multiline) {
        TextArea({ text: value, placeholder: placeholder })
          .width('100%')
          .height(92)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Start)
          .backgroundColor($r('app.color.page_background'))
          .border({ width: 1, color: $r('app.color.card_specular_border'), radius: 8 })
          .onChange(onChanged)
      } else {
        TextInput({ text: value, placeholder: placeholder })
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Start)
          .backgroundColor($r('app.color.page_background'))
          .border({ width: 1, color: $r('app.color.card_specular_border'), radius: 8 })
          .onChange(onChanged)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 14 })
  }

  @Builder
  ModeSwitch(section: string, value: string): void {
    Row() {
      Text('规则类型')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Start)
        .layoutWeight(1)

      Row() {
        Text(value === RuleMode.API ? 'API' : 'XPath')
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
      .onClick(() => {
        this.ruleModeMenuSection = section
      })
      .bindMenu(this.ruleModeMenuSection === section, this.RuleModeMenuContent, {
        placement: Placement.Bottom,
        showInSubWindow: false,
        onDisappear: () => {
          this.ruleModeMenuSection = ''
        }
      })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 14 })
  }

  @Builder
  RuleModeMenuContent(): void {
    Menu() {
      this.SelectionMenuOption('XPath', this.currentRuleMode() === RuleMode.XPATH, () => {
        this.changeRuleMode(this.ruleModeMenuSection, RuleMode.XPATH)
        this.ruleModeMenuSection = ''
      })
      this.SelectionMenuOption('API', this.currentRuleMode() === RuleMode.API, () => {
        this.changeRuleMode(this.ruleModeMenuSection, RuleMode.API)
        this.ruleModeMenuSection = ''
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  SelectionMenuOption(label: string, selected: boolean, action: () => void): void {
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

  @Builder
  MethodSwitch(section: string, value: string): void {
    Row() {
      Text('请求方法')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Start)
        .layoutWeight(1)

      Row() {
        Text(value)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
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
        this.requestMethodMenuSection = section
      })
      .bindMenu(this.requestMethodMenuSection === section, this.RequestMethodMenuContent, {
        placement: Placement.Bottom,
        showInSubWindow: false,
        onDisappear: () => {
          this.requestMethodMenuSection = ''
        }
      })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 14 })
  }

  @Builder
  RequestMethodMenuContent(): void {
    Menu() {
      this.SelectionMenuOption('GET', this.currentRequestMethod() === 'GET', () => {
        this.changeRequestMethod(this.requestMethodMenuSection, 'GET')
        this.requestMethodMenuSection = ''
      })
      this.SelectionMenuOption('POST', this.currentRequestMethod() === 'POST', () => {
        this.changeRequestMethod(this.requestMethodMenuSection, 'POST')
        this.requestMethodMenuSection = ''
      })
    }
    .width(160)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  BodyTypeSwitch(value: string, onChanged: (value: string) => void): void {
    this.SegmentRow('请求体类型', ['无', 'JSON', '表单'],
      value === ApiBodyType.JSON ? 1 : value === ApiBodyType.FORM ? 2 : 0, (selected: number) => {
      onChanged(selected === 1 ? ApiBodyType.JSON : selected === 2 ? ApiBodyType.FORM : ApiBodyType.NONE)
    })
  }

  @Builder
  FormatSwitch(value: string, onChanged: (value: string) => void): void {
    this.SegmentRow('选集响应', ['嵌套 JSON', '分隔字符串'], value === ApiChapterFormat.DELIMITED ? 1 : 0,
      (index: number) => onChanged(index === 1 ? ApiChapterFormat.DELIMITED : ApiChapterFormat.NESTED))
  }

  @Builder
  CaptchaTypeSwitch(): void {
    this.SegmentRow('验证类型', ['图片', '自动点击', '脚本'], this.captchaType - 1,
      (index: number) => this.captchaType = index + 1)
  }

  @Builder
  SegmentRow(label: string, labels: string[], selected: number, onChanged: (index: number) => void): void {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 6 })
      Row() {
        ForEach(labels, (label: string, index: number) => {
          Text(label)
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .fontWeight(index === selected ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(index === selected ? Color.White : $r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .backgroundColor(index === selected ? $r('app.color.button_primary_bg') : Color.Transparent)
            .animation({ duration: 180, curve: Curve.EaseOut })
            .onClick(() => onChanged(index))
        }, (itemLabel: string, index: number): string => `${itemLabel}_${index}_${selected}`)
      }
      .width('100%')
      .padding(2)
      .borderRadius(10)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 14 })
  }

  @Builder
  SwitchRow(label: string, value: boolean, onChanged: (value: boolean) => void): void {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange(onChanged)
    }
    .width('100%')
    .height(44)
    .margin({ bottom: 8 })
  }

  private changeRuleMode(section: string, mode: string): void {
    const current = section === 'search' ? this.searchMode : this.chapterMode
    if (current === mode) {
      return
    }
    this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion() }, () => {
      if (section === 'search') {
        this.searchMode = mode
      } else {
        this.chapterMode = mode
      }
    })
  }

  private currentRuleMode(): string {
    return this.ruleModeMenuSection === 'chapter' ? this.chapterMode : this.searchMode
  }

  private changeRequestMethod(section: string, method: string): void {
    if (this.currentRequestMethod() === method) {
      return
    }
    this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion() }, () => {
      if (section === 'searchXPath') {
        this.searchUsePost = method === 'POST'
      } else if (section === 'searchApi') {
        this.searchApiMethod = method
      } else if (section === 'chapterApi') {
        this.chapterApiMethod = method
      }
    })
  }

  private currentRequestMethod(): string {
    if (this.requestMethodMenuSection === 'searchXPath') {
      return this.searchUsePost ? 'POST' : 'GET'
    }
    if (this.requestMethodMenuSection === 'chapterApi') {
      return this.chapterApiMethod
    }
    return this.searchApiMethod
  }

  private buildSaveIcon(): HdsNavigationIconOptions {
    return {
      icon: this.saving ? $r('sys.symbol.hourglass') : $r('sys.symbol.checkmark'),
      label: this.saving ? '保存中' : '保存',
      action: () => {
        this.saveRule()
      }
    }
  }

  private buildEditorMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{ content: this.buildSaveIcon() }]
    }
  }

  private buildEditorTitle(): HdsNavigationTitle {
    return {
      mainTitle: '新建规则',
      subTitle: '创建自定义规则源'
    }
  }

  private buildEditorTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildEditorTitle(),
      menu: this.buildEditorMenu()
    }
  }

  private buildEditorTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('新建规则', this.hdsMaterialLevel)
    base.content = this.buildEditorTitleBarContent()
    return base
  }

  private async saveRule(): Promise<void> {
    if (this.saving) return
    this.saving = true
    try {
      const rule = this.buildRule()
      const existing = await this.ruleStore.getAll()
      const normalizedName = rule.name.toLowerCase()
      for (let i = 0; i < existing.length; i++) {
        if (existing[i].name.toLowerCase() === normalizedName) {
          throw new Error(`规则「${rule.name}」已存在，请使用其他名称`)
        }
      }
      rule.sortOrder = await this.ruleStore.getNextSortOrder()
      await this.ruleStore.insert(rule)
      SettingsChangeSignal.notifyRuleSourceChanged()
      promptAction.showToast({ message: `规则 ${rule.name} 已创建` })
      router.back()
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      logger.warn('Create local rule failed: %{public}s', message)
      promptAction.showToast({ message: message })
    } finally {
      this.saving = false
    }
  }

  private buildRule(): RuleSource {
    this.validateFields()
    const rule = new RuleSource()
    rule.api = String(AppConstants.SUPPORTED_API_LEVEL)
    rule.type = 'anime'
    rule.name = this.ruleName.trim()
    rule.version = this.version.trim()
    rule.baseUrl = this.baseUrl.trim()
    rule.installOrigin = RuleInstallOrigin.LOCAL
    rule.enabled = true
    rule.multiSources = true
    rule.useWebview = true
    rule.useNativePlayer = false
    rule.usePost = this.searchUsePost
    rule.useLegacyParser = this.useLegacyParser
    rule.adBlocker = this.adBlocker
    rule.userAgent = this.userAgent.trim()
    rule.referer = this.referer.trim()
    rule.searchMode = this.searchMode
    rule.chapterMode = this.chapterMode
    rule.searchURL = this.searchUrl.trim()
    rule.searchList = this.searchList.trim()
    rule.searchName = this.searchName.trim()
    rule.searchResult = this.searchResult.trim()
    rule.chapterRoads = this.chapterRoads.trim()
    rule.chapterResult = this.chapterResult.trim()
    rule.searchApiConfig = this.buildSearchApiConfig()
    rule.chapterApiConfig = this.buildChapterApiConfig()
    rule.antiCrawlerConfig = new AntiCrawlerConfig()
    rule.antiCrawlerConfig.enabled = this.captchaEnabled
    rule.antiCrawlerConfig.captchaType = this.captchaType
    rule.antiCrawlerConfig.captchaDetectValue = this.captchaDetectValue.trim()
    rule.antiCrawlerConfig.captchaImage = this.captchaImage.trim()
    rule.antiCrawlerConfig.captchaInput = this.captchaInput.trim()
    rule.antiCrawlerConfig.captchaButton = this.captchaButton.trim()
    rule.antiCrawlerConfig.captchaScript = this.captchaScript.trim()
    return rule
  }

  private buildSearchApiConfig(): ApiSearchConfig {
    const config = new ApiSearchConfig()
    if (this.searchMode !== RuleMode.API) return config
    config.request = this.buildRequest(this.searchApiMethod, this.searchApiUrl, this.searchApiHeaders,
      this.searchApiQuery, this.searchApiBodyType, this.searchApiBody, '搜索')
    config.listPath = this.searchApiListPath.trim()
    config.namePath = this.searchApiNamePath.trim()
    config.sourcePath = this.searchApiSourcePath.trim()
    return config
  }

  private buildChapterApiConfig(): ApiChapterConfig {
    const config = new ApiChapterConfig()
    if (this.chapterMode !== RuleMode.API) return config
    config.request = this.buildRequest(this.chapterApiMethod, this.chapterApiUrl, this.chapterApiHeaders,
      this.chapterApiQuery, this.chapterApiBodyType, this.chapterApiBody, '选集')
    config.format = this.chapterApiFormat
    config.roadsPath = this.chapterApiRoadsPath.trim()
    config.roadNamePath = this.chapterApiRoadNamePath.trim()
    config.episodesPath = this.chapterApiEpisodesPath.trim()
    config.episodeNamePath = this.chapterApiEpisodeNamePath.trim()
    config.episodeUrlPath = this.chapterApiEpisodeUrlPath.trim()
    config.roadNamesPath = this.chapterApiRoadNamesPath.trim()
    config.roadEpisodesPath = this.chapterApiRoadEpisodesPath.trim()
    config.roadSeparator = this.chapterApiRoadSeparator
    config.episodeSeparator = this.chapterApiEpisodeSeparator
    config.fieldSeparator = this.chapterApiFieldSeparator
    const rawVariables = this.parseRecord(this.chapterApiVariables, '响应变量')
    const variableKeys = Object.keys(rawVariables)
    for (let i = 0; i < variableKeys.length; i++) {
      config.variables[variableKeys[i]] = String(rawVariables[variableKeys[i]])
    }
    if (this.chapterApiPageUrl.trim().length > 0) {
      const page = new ApiEpisodePageConfig()
      page.url = this.chapterApiPageUrl.trim()
      page.query = this.parseRecord(this.chapterApiPageQuery, '播放页查询参数')
      config.episodePage = page
    }
    return config
  }

  private buildRequest(method: string, url: string, headers: string, query: string, bodyType: string,
    body: string, label: string): ApiRequestConfig {
    const request = new ApiRequestConfig()
    request.method = method
    request.url = url.trim()
    request.headers = this.parseRecord(headers, `${label}请求头`)
    request.query = this.parseRecord(query, `${label}查询参数`)
    request.bodyType = bodyType
    if (bodyType !== ApiBodyType.NONE) {
      request.body = this.parseJson(body, `${label}请求体`)
      if (bodyType === ApiBodyType.FORM && !this.isRecord(request.body)) {
        throw new Error(`${label}表单请求体必须是 JSON 对象`)
      }
    }
    return request
  }

  private validateFields(): void {
    if (this.ruleName.trim().length === 0) throw new Error('请填写规则名称')
    if (this.version.trim().length === 0) throw new Error('请填写规则版本')
    if (!this.isHttpUrl(this.baseUrl.trim())) throw new Error('基础地址必须是 HTTP 或 HTTPS URL')
    if (this.searchMode === RuleMode.XPATH) {
      if (this.searchUrl.trim().indexOf('@keyword') < 0 || !this.isHttpUrl(this.searchUrl.trim())) {
        throw new Error('搜索地址必须是包含 @keyword 的 HTTP 或 HTTPS URL')
      }
      this.validateXPath(this.searchList, '搜索结果列表 XPath')
      this.validateXPath(this.searchName, '名称 XPath')
      this.validateXPath(this.searchResult, '详情地址 XPath')
    } else {
      if (!this.isHttpUrl(this.searchApiUrl.trim())) throw new Error('搜索请求地址必须是 HTTP 或 HTTPS URL')
      this.validateJsonPath(this.searchApiListPath, '搜索结果列表 JSONPath')
      this.validateJsonPath(this.searchApiNamePath, '名称 JSONPath')
      this.validateJsonPath(this.searchApiSourcePath, '来源 JSONPath')
      this.parseRecord(this.searchApiHeaders, '搜索请求头')
      this.parseRecord(this.searchApiQuery, '搜索查询参数')
      if (this.searchApiBodyType !== ApiBodyType.NONE) this.parseJson(this.searchApiBody, '搜索请求体')
    }
    if (this.chapterMode === RuleMode.XPATH) {
      this.validateXPath(this.chapterRoads, '播放线路 XPath')
      this.validateXPath(this.chapterResult, '剧集 XPath')
    } else {
      if (!this.isHttpUrl(this.chapterApiUrl.trim())) throw new Error('选集请求地址必须是 HTTP 或 HTTPS URL')
      this.parseRecord(this.chapterApiHeaders, '选集请求头')
      this.parseRecord(this.chapterApiQuery, '选集查询参数')
      if (this.chapterApiBodyType !== ApiBodyType.NONE) this.parseJson(this.chapterApiBody, '选集请求体')
      if (this.chapterApiFormat === ApiChapterFormat.NESTED) {
        if (this.chapterApiRoadsPath.trim().length > 0) this.validateJsonPath(this.chapterApiRoadsPath, '线路列表 JSONPath')
        if (this.chapterApiRoadNamePath.trim().length > 0) this.validateJsonPath(this.chapterApiRoadNamePath, '线路名称 JSONPath')
        this.validateJsonPath(this.chapterApiEpisodesPath, '剧集列表 JSONPath')
        this.validateJsonPath(this.chapterApiEpisodeNamePath, '剧集名称 JSONPath')
        if (this.chapterApiEpisodeUrlPath.trim().length === 0 && this.chapterApiPageUrl.trim().length === 0) {
          throw new Error('请填写播放入口 JSONPath 或播放页地址模板')
        }
        if (this.chapterApiEpisodeUrlPath.trim().length > 0) this.validateJsonPath(this.chapterApiEpisodeUrlPath, '播放入口 JSONPath')
      } else {
        this.validateJsonPath(this.chapterApiRoadNamesPath, '线路名称串 JSONPath')
        this.validateJsonPath(this.chapterApiRoadEpisodesPath, '线路剧集串 JSONPath')
      }
      const variables = this.parseRecord(this.chapterApiVariables, '响应变量')
      const variableKeys = Object.keys(variables)
      for (let i = 0; i < variableKeys.length; i++) this.validateJsonPath(String(variables[variableKeys[i]]), `响应变量 ${variableKeys[i]}`)
      this.parseRecord(this.chapterApiPageQuery, '播放页查询参数')
    }
    if (this.captchaEnabled && this.captchaType === 1) {
      this.validateXPath(this.captchaImage, '验证码图片 XPath')
      this.validateXPath(this.captchaInput, '验证码输入框 XPath')
      this.validateXPath(this.captchaButton, '验证提交按钮 XPath')
    }
    if (this.captchaEnabled && this.captchaType === 2) this.validateXPath(this.captchaButton, '验证提交按钮 XPath')
    if (this.captchaEnabled && this.captchaType === 3 && this.captchaScript.trim().length === 0) throw new Error('请填写验证脚本')
  }

  private validateXPath(value: string, label: string): void {
    const text = value.trim()
    if (!(text.startsWith('/') || text.startsWith('./') || text.startsWith('(') || text.startsWith('@') || text.indexOf('::') >= 0)) {
      throw new Error(`${label} 不是有效 XPath`)
    }
  }

  private validateJsonPath(value: string, label: string): void {
    if (!value.trim().startsWith('$')) throw new Error(`${label} 必须以 $ 开头`)
  }

  private parseRecord(text: string, label: string): Record<string, Object> {
    const value = this.parseJson(text, label)
    if (!this.isRecord(value)) throw new Error(`${label} 必须是 JSON 对象`)
    return value as Record<string, Object>
  }

  private parseJson(text: string, label: string): Object {
    const trimmed = text.trim()
    if (trimmed.length === 0) {
      const empty: Record<string, Object> = {}
      return empty
    }
    try {
      return JSON.parse(trimmed) as Object
    } catch (_err) {
      throw new Error(`${label} 不是有效 JSON`)
    }
  }

  private isRecord(value: Object | undefined): boolean {
    return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)
  }

  private isHttpUrl(value: string): boolean {
    return value.startsWith('https://') || value.startsWith('http://')
  }
}
