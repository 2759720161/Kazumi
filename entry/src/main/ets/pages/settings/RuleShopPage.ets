import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationTitle,
  TitleBarContentOptions
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import { RuleCatalogItem } from '../../models/RuleCatalogItem'
import { RuleSource } from '../../models/RuleSource'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleCatalogService } from '../../services/RuleCatalogService'
import { DefaultRuleSourceInitializer } from '../../utils/DefaultRuleSourceInitializer'
import { SettingsChangeSignal } from '../../store/SettingsChangeSignal'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { createThickImmersiveMaterial } from '../../utils/ImmersiveMaterial'
import { promptAction, curves } from '@kit.ArkUI'

const logger = new Logger('RuleShopPage')
const PREF_RULE_REPOSITORY_URL = 'rule_repository_url'

@Entry
@Component
struct RuleShopPage {
  build() {
    Column() {
      RuleShopPageContent()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct RuleShopPageContent {
  @Prop embedded: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State catalogItems: RuleCatalogItem[] = []
  @State localRules: RuleSource[] = []
  @State loading: boolean = false
  @State sortByTime: boolean = true
  @State errorMessage: string = ''
  @State installingName: string = ''
  @State togglingName: string = ''
  @State deletingName: string = ''
  @State showActionMenu: boolean = false
  @State showLinkImportDialog: boolean = false
  @State showDeleteDialog: boolean = false
  @State deleteTargetName: string = ''
  @State importUrl: string = ''
  @State operationMessage: string = ''
  @State isLinkImporting: boolean = false
  @State canRefreshRepository: boolean = false
  @State repositoryUrl: string = ''
  @State enableMenuRuleName: string = ''
  @State backgroundInstalling: boolean = false
  @State backgroundInstallDone: number = 0
  @State backgroundInstallTotal: number = 0
  private scroller: Scroller = new Scroller()
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()

  aboutToAppear(): void {
    this.loadCatalog()
  }

  build() {
    Stack() {
      HdsNavigation() {
        Scroll(this.scroller) {
          Column() {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')

            this.SortToggle()
            this.OperationMessageSection()
            this.CatalogList()

            if (!this.loading && this.catalogItems.length === 0 && this.errorMessage.length === 0) {
              this.EmptyCatalogSection()
            }

            if (this.errorMessage.length > 0) {
              this.ErrorSection()
            }

            if (this.loading && this.catalogItems.length === 0) {
              this.LoadingSection()
            }

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
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
      .titleBar(this.buildRepositoryTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.embedded)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (this.showActionMenu) {
        this.ActionMenuOverlay()
      }

      if (this.showLinkImportDialog) {
        this.LinkImportDialogOverlay()
      }

      if (this.showDeleteDialog) {
        this.DeleteRuleDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  OperationMessageSection(): void {
    if (this.operationMessage.length > 0) {
      Row() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.accent_blue')])
          .margin({ right: 8 })

        Text(this.operationMessage)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 0.5, color: $r('app.color.card_specular_border') })
        .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
        .margin({ bottom: 8 })
    }
  }

  @Builder
  SortToggle(): void {
    Row() {
      Row() {
        Text('按更新时间')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.sortByTime ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(34)
          .borderRadius(10)
          .backgroundColor(this.sortByTime ? $r('app.color.button_primary_bg') : Color.Transparent)
          .onClick(() => {
            this.sortByTime = true
          })

        Text('按名称')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(!this.sortByTime ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(34)
          .borderRadius(10)
          .backgroundColor(!this.sortByTime ? $r('app.color.button_primary_bg') : Color.Transparent)
          .onClick(() => {
            this.sortByTime = false
          })
      }
      .width(184)
      .height(38)
      .padding(2)
      .borderRadius(12)
      .backgroundColor($r('app.color.page_background'))

      Blank()

      Text(this.sortByTime ? '最新优先' : '名称排序')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
  }

  @Builder
  CatalogList(): void {
    if (this.catalogItems.length > 0) {
      Column() {
        ForEach(this.getSortedItems(), (item: RuleCatalogItem) => {
          this.CatalogItemRow(item)
        }, (item: RuleCatalogItem) => this.buildCatalogItemKey(item))
      }
      .width('100%')
    }
  }

  @Builder
  CatalogItemRow(item: RuleCatalogItem): void {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(item.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            this.RuleStatusBadge(item)
          }
          .width('100%')

          Text(this.buildRuleSubtitle(item))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .margin({ right: 12 })

        this.StatusButton(item)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        this.RuleChip(`v${item.version}`)
        this.RuleChip(item.useNativePlayer ? '原生播放' : '网页解析')

        if (item.antiCrawlerEnabled) {
          this.RuleWarnChip('验证')
        }
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
    .animation({ duration: 280, curve: curves.springMotion() })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: curves.springMotion() }))
  }

  @Builder
  RuleStatusBadge(item: RuleCatalogItem): void {
    Text(RuleCatalogService.getRuleStatus(item, this.localRules) === 'nonexistent' ? '仓库已移除' :
      RuleCatalogService.getRuleStatus(item, this.localRules) === 'installed' ?
      (this.isRuleEnabled(item.name) ? '已启用' : '已安装') :
      (RuleCatalogService.getRuleStatus(item, this.localRules) === 'update' ? '可更新' : '未安装'))
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(RuleCatalogService.getRuleStatus(item, this.localRules) === 'nonexistent' ?
        $r('app.color.status_warning') :
        RuleCatalogService.getRuleStatus(item, this.localRules) === 'install' ?
          $r('app.color.text_secondary') : $r('app.color.accent_blue'))
      .backgroundColor(RuleCatalogService.getRuleStatus(item, this.localRules) === 'nonexistent' ?
        $r('app.color.page_background') :
        RuleCatalogService.getRuleStatus(item, this.localRules) === 'install' ?
          $r('app.color.page_background') : $r('app.color.episode_item_selected_bg'))
      .borderRadius(9)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .margin({ left: 8 })
  }

  @Builder
  RuleChip(label: string): void {
    Text(label)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .backgroundColor($r('app.color.page_background'))
      .borderRadius(8)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .margin({ right: 6 })
  }

  @Builder
  RuleWarnChip(label: string): void {
    Text(label)
      .fontSize(11)
      .fontColor($r('app.color.status_warning'))
      .backgroundColor($r('app.color.page_background'))
      .borderRadius(8)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  StatusButton(item: RuleCatalogItem): void {
    if (RuleCatalogService.getRuleStatus(item, this.localRules) === 'nonexistent') {
      Row() {
        Text('已移除')
          .fontSize(13)
          .fontColor($r('app.color.status_warning'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.EnableButtonByName(item.name)
      }
      .alignItems(VerticalAlign.Center)
    } else if (RuleCatalogService.getRuleStatus(item, this.localRules) === 'installed') {
      this.EnableButtonByName(item.name)
    } else if (RuleCatalogService.getRuleStatus(item, this.localRules) === 'update') {
      Row() {
        Button('更新')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.button_accent_bg'))
          .fontColor($r('app.color.text_on_primary'))
          .padding({ left: 14, right: 14 })
          .enabled(this.isRuleOperationIdle())
          .onClick(() => {
            this.onInstallRule(item.name)
          })

        this.EnableButtonByName(item.name)
      }
      .alignItems(VerticalAlign.Center)
    } else {
      Button('安装')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.button_primary_bg'))
        .fontColor($r('app.color.text_on_primary'))
        .padding({ left: 14, right: 14 })
        .enabled(this.isRuleOperationIdle())
        .onClick(() => {
          this.onInstallRule(item.name)
        })
    }
  }

  @Builder
  EnableButtonByName(name: string): void {
    Row() {
      Text(this.isRuleEnabled(name) ? '启用' : '关闭')
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
    .width(86)
    .height(36)
    .padding({ left: 10, right: 8 })
    .borderRadius(12)
    .margin({ left: 8 })
    .enabled(this.isRuleOperationIdle())
    .stateStyles({
      pressed: {
        .backgroundColor($r('app.color.category_menu_item_selected'))
      },
      normal: {
        .backgroundColor(Color.Transparent)
      }
    })
    .onClick(() => {
      this.enableMenuRuleName = name
    })
    .bindMenu(this.enableMenuRuleName === name, this.RuleEnableMenuContent, {
      placement: Placement.Bottom,
      showInSubWindow: false,
      onDisappear: () => {
        this.enableMenuRuleName = ''
      }
    })
  }

  @Builder
  RuleEnableMenuContent(): void {
    Menu() {
      this.RuleEnableMenuItem('启用', true)
      this.RuleEnableMenuItem('关闭', false)
      this.RuleDeleteMenuItem()
    }
    .width(132)
    .fontColor($r('app.color.text_primary'))
    .radius(20)
  }

  @Builder
  RuleEnableMenuItem(label: string, enabled: boolean): void {
    MenuItem() {
      Row() {
        Text(label)
          .fontSize(16)
          .fontWeight(this.isRuleEnabled(this.enableMenuRuleName) === enabled ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.isRuleEnabled(this.enableMenuRuleName) === enabled ?
            $r('app.color.accent_blue') : $r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .borderRadius(14)
      .backgroundColor(this.isRuleEnabled(this.enableMenuRuleName) === enabled ?
        $r('app.color.episode_item_selected_bg') : Color.Transparent)
    }
    .onClick(() => {
      this.setRuleEnabledByName(this.enableMenuRuleName, enabled)
      this.enableMenuRuleName = ''
    })
  }

  @Builder
  RuleDeleteMenuItem(): void {
    MenuItem() {
      Row() {
        Text('删除')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.status_error'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .borderRadius(14)
    }
    .onClick(() => {
      this.requestDeleteRule(this.enableMenuRuleName)
      this.enableMenuRuleName = ''
    })
  }

  @Builder
  ErrorSection(): void {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(36)
        .fontColor([$r('app.color.status_warning')])
        .margin({ bottom: 10 })

      Text(this.errorMessage)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 12 })

      Button('刷新')
        .fontSize(14)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.button_primary_bg'))
        .fontColor($r('app.color.text_on_primary'))
        .enabled(!this.loading)
        .onClick(() => {
          this.loadCatalog()
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 180 })
    .padding({ left: 24, right: 24, top: 28, bottom: 28 })
    .alignItems(HorizontalAlign.Center)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
  }

  @Builder
  LoadingSection(): void {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.text_secondary'))
        .margin({ bottom: 8 })

      Text('加载中...')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .constraintSize({ minHeight: 180 })
    .padding({ top: 36, bottom: 36 })
    .alignItems(HorizontalAlign.Center)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
  }

  @Builder
  EmptyCatalogSection(): void {
    Column() {
      Text('暂无规则')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 6 })

      Text(this.repositoryUrl.length > 0 ? '刷新仓库或从右上角导入规则' : '请先从右上角通过链接导入规则仓库')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ minHeight: 220 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16 })
  }

  private getSortedItems(): RuleCatalogItem[] {
    const items = [...this.catalogItems]
    if (this.sortByTime) {
      items.sort((a: RuleCatalogItem, b: RuleCatalogItem) => {
        const priorityDiff = this.getRuleSortPriority(a) - this.getRuleSortPriority(b)
        if (priorityDiff !== 0) {
          return priorityDiff
        }
        return b.lastUpdate - a.lastUpdate
      })
    } else {
      items.sort((a: RuleCatalogItem, b: RuleCatalogItem) => {
        const priorityDiff = this.getRuleSortPriority(a) - this.getRuleSortPriority(b)
        if (priorityDiff !== 0) {
          return priorityDiff
        }
        return a.name.localeCompare(b.name)
      })
    }
    return items
  }

  private buildCatalogItemKey(item: RuleCatalogItem): string {
    const status = RuleCatalogService.getRuleStatus(item, this.localRules)
    const enabled = this.isRuleEnabled(item.name) ? 'enabled' : 'disabled'
    return `${item.name}_${item.version}_${status}_${enabled}`
  }

  private getRuleSortPriority(item: RuleCatalogItem): number {
    return this.findLocalRule(item.name) !== null ? 0 : 1
  }

  private buildRuleSubtitle(item: RuleCatalogItem): string {
    const parts: string[] = []
    if (item.author.length > 0) {
      parts.push(item.author)
    }
    const updateText = this.formatLastUpdate(item.lastUpdate)
    if (updateText.length > 0) {
      parts.push(updateText)
    }
    return parts.length > 0 ? parts.join(' · ') : '规则信息'
  }

  private formatLastUpdate(timestamp: number): string {
    if (timestamp <= 0) {
      return ''
    }
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = date.getMonth() + 1
    const day = date.getDate()
    return `${year}-${month < 10 ? '0' + String(month) : String(month)}-${day < 10 ? '0' + String(day) : String(day)}`
  }

  private async loadCatalog(): Promise<void> {
    this.errorMessage = ''
    this.loading = true
    try {
      this.localRules = await this.ruleSourceStore.getAll()
      this.catalogItems = this.mergeCatalogItems([], this.localRules)
      const repositoryUrl = await this.getSavedRepositoryUrl()
      this.repositoryUrl = repositoryUrl
      this.canRefreshRepository = repositoryUrl.length > 0
      if (repositoryUrl.length === 0) {
        this.loading = false
        return
      }
      this.refreshCatalogInBackground(repositoryUrl)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.errorMessage = `加载失败: ${msg}`
      logger.error('Load catalog failed: %{public}s', msg)
      this.loading = false
    }
  }

  private async refreshCatalogInBackground(repositoryUrl: string): Promise<void> {
    this.loading = true
    try {
      const remoteItems = await RuleCatalogService.fetchCatalog(repositoryUrl)
      this.localRules = await this.ruleSourceStore.getAll()
      this.catalogItems = this.mergeCatalogItems(remoteItems, this.localRules, true)
      this.errorMessage = ''
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      if (this.catalogItems.length === 0) {
        this.errorMessage = `更新仓库失败: ${msg}`
      }
      logger.error('Refresh catalog failed: %{public}s', msg)
    } finally {
      this.loading = false
    }
  }

  private mergeCatalogItems(remoteItems: RuleCatalogItem[], localRules: RuleSource[],
    repositorySynced: boolean = false): RuleCatalogItem[] {
    const result: RuleCatalogItem[] = []
    const names: string[] = []
    for (let i = 0; i < localRules.length; i++) {
      const remote = this.findCatalogItem(remoteItems, localRules[i].name)
      result.push(remote !== null ? remote :
        this.buildCatalogItemFromLocalRule(localRules[i], repositorySynced))
      names.push(localRules[i].name)
    }
    for (let i = 0; i < remoteItems.length; i++) {
      if (!this.containsName(names, remoteItems[i].name)) {
        result.push(remoteItems[i])
      }
    }
    return result
  }

  private buildCatalogItemFromLocalRule(rule: RuleSource, repositorySynced: boolean = false): RuleCatalogItem {
    const item = new RuleCatalogItem()
    item.name = rule.name
    item.version = rule.version
    item.useNativePlayer = rule.useNativePlayer
    item.author = '本地已安装'
    item.lastUpdate = rule.updatedAt > 0 ? rule.updatedAt : rule.createdAt
    item.antiCrawlerEnabled = rule.antiCrawlerConfig.enabled
    item.repositoryMissing = repositorySynced
    return item
  }

  private findCatalogItem(items: RuleCatalogItem[], name: string): RuleCatalogItem | null {
    for (let i = 0; i < items.length; i++) {
      if (items[i].name === name) {
        return items[i]
      }
    }
    return null
  }

  private containsName(names: string[], name: string): boolean {
    for (let i = 0; i < names.length; i++) {
      if (names[i] === name) {
        return true
      }
    }
    return false
  }

  private async onInstallRule(name: string): Promise<void> {
    this.installingName = name
    try {
      const repositoryUrl = await this.getSavedRepositoryUrl()
      const result = await RuleCatalogService.tryInstallRule(name, repositoryUrl)
      if (result === 0) {
        promptAction.showToast({ message: `规则 ${name} 安装/更新成功` })
        this.localRules = await this.ruleSourceStore.getAll()
        this.catalogItems = this.mergeCatalogItems(this.catalogItems, this.localRules)
      } else if (result === 1) {
        promptAction.showToast({ message: '应用版本过低，此规则不兼容' })
      } else {
        promptAction.showToast({ message: '安装/更新规则失败' })
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      promptAction.showToast({ message: `安装失败: ${msg}` })
      logger.error('Install rule failed: %{public}s', msg)
    } finally {
      this.installingName = ''
    }
  }

  private findLocalRule(name: string): RuleSource | null {
    for (let i = 0; i < this.localRules.length; i++) {
      if (this.localRules[i].name === name) {
        return this.localRules[i]
      }
    }
    return null
  }

  private isRuleEnabled(name: string): boolean {
    const rule = this.findLocalRule(name)
    return rule !== null && rule.enabled
  }

  private async toggleRuleEnabledByName(name: string): Promise<void> {
    await this.setRuleEnabledByName(name, !this.isRuleEnabled(name))
  }

  private async setRuleEnabledByName(name: string, enabled: boolean): Promise<void> {
    const rule = this.findLocalRule(name)
    if (rule === null) {
      this.operationMessage = '规则源不存在'
      return
    }
    if (rule.enabled === enabled) {
      this.operationMessage = `${rule.name} 已处于${enabled ? '启用' : '关闭'}状态`
      return
    }
    this.togglingName = rule.name
    try {
      await this.ruleSourceStore.setEnabled(rule.id, enabled)
      SettingsChangeSignal.notifyRuleSourceChanged()
      this.localRules = await this.ruleSourceStore.getAll()
      this.operationMessage = `${rule.name} 已${enabled ? '启用' : '关闭'}`
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `切换失败: ${msg}`
      logger.error('Toggle rule failed: %{public}s', msg)
    } finally {
      this.togglingName = ''
    }
  }

  private isRuleOperationIdle(): boolean {
    return this.installingName.length === 0 && this.togglingName.length === 0 && this.deletingName.length === 0
  }

  private requestDeleteRule(name: string): void {
    const rule = this.findLocalRule(name)
    if (rule === null) {
      this.operationMessage = '规则源不存在'
      return
    }
    this.deleteTargetName = rule.name
    this.showDeleteDialog = true
  }

  private async confirmDeleteRule(): Promise<void> {
    const rule = this.findLocalRule(this.deleteTargetName)
    if (rule === null) {
      this.showDeleteDialog = false
      this.deleteTargetName = ''
      this.operationMessage = '规则源不存在'
      return
    }
    this.deletingName = rule.name
    try {
      await this.ruleSourceStore.deleteById(rule.id)
      SettingsChangeSignal.notifyRuleSourceChanged()
      await this.refreshCatalogAfterRuleMutation()
      this.operationMessage = `${rule.name} 已删除`
      promptAction.showToast({ message: `规则 ${rule.name} 已删除` })
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `删除失败: ${msg}`
      logger.error('Delete rule failed: %{public}s', msg)
    } finally {
      this.deletingName = ''
      this.deleteTargetName = ''
      this.showDeleteDialog = false
    }
  }

  private async refreshCatalogAfterRuleMutation(): Promise<void> {
    this.localRules = await this.ruleSourceStore.getAll()
    const repositoryUrl = await this.getSavedRepositoryUrl()
    this.repositoryUrl = repositoryUrl
    this.canRefreshRepository = repositoryUrl.length > 0
    if (repositoryUrl.length === 0) {
      this.catalogItems = this.mergeCatalogItems([], this.localRules)
      return
    }

    try {
      const remoteItems = await RuleCatalogService.fetchCatalog(repositoryUrl)
      this.catalogItems = this.mergeCatalogItems(remoteItems, this.localRules, true)
      this.errorMessage = ''
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Refresh catalog after rule mutation failed: %{public}s', msg)
      this.catalogItems = this.mergeCatalogItems(this.getCatalogSnapshotWithoutLocalOnlyRules(), this.localRules)
    }
  }

  private getCatalogSnapshotWithoutLocalOnlyRules(): RuleCatalogItem[] {
    const result: RuleCatalogItem[] = []
    for (let i = 0; i < this.catalogItems.length; i++) {
      const item = this.catalogItems[i]
      if (item.author !== '本地已安装' || this.findLocalRule(item.name) !== null) {
        result.push(item)
      }
    }
    return result
  }

  @Builder
  ActionMenuOverlay(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.color_transparent'))
        .onClick(() => {
          this.showActionMenu = false
        })

      Column() {
        this.ActionMenuItem('链接导入', () => {
          this.openLinkImportDialog('')
        })
        if (this.canRefreshRepository) {
          this.ActionMenuItem('刷新仓库', () => {
            this.showActionMenu = false
            this.loadCatalog()
          })
        }
      }
      .width(176)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.category_menu_surface'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.category_menu_divider') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
      .systemMaterial(createThickImmersiveMaterial())
      .margin({ top: getTopSpacerHeight(this.topSafeHeight) - 10, right: 12 })
    }
    .width('100%')
    .height('100%')
    .zIndex(20)
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseInOut }))
  }

  @Builder
  ActionMenuItem(label: string, action: () => void): void {
    Row() {
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(42)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      action()
    })
  }

  @Builder
  LinkImportDialogOverlay(): void {
    Column() {
      Column() {
        Text('链接导入')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 14 })

        TextInput({ placeholder: '粘贴 GitHub 仓库、index.json 或规则 JSON 链接', text: this.importUrl })
          .width('100%')
          .height(44)
          .onChange((value: string) => {
            this.importUrl = value
          })

        Row() {
          Button('取消')
            .fontSize(14)
            .height(38)
            .borderRadius(19)
            .backgroundColor($r('app.color.button_ghost_bg'))
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .enabled(!this.isLinkImporting)
            .onClick(() => {
              this.showLinkImportDialog = false
            })

          Button(this.isLinkImporting ? '导入中...' : '导入')
            .fontSize(14)
            .height(38)
            .borderRadius(19)
            .backgroundColor($r('app.color.button_primary_bg'))
            .fontColor($r('app.color.text_on_primary'))
            .layoutWeight(1)
            .margin({ left: 10 })
            .enabled(!this.isLinkImporting)
            .onClick(() => {
              this.importFromLink()
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('86%')
      .padding({ left: 20, right: 20, top: 24, bottom: 20 })
      .borderRadius(24)
      .backgroundColor($r('app.color.card_background'))
      .shadow({ radius: 24, color: $r('app.color.shadow_surface'), offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.overlay_modal_bg'))
    .zIndex(30)
  }

  @Builder
  DeleteRuleDialogOverlay(): void {
    Column() {
      Column() {
        Text('删除规则')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 24 })

        Text(`确定要删除规则「${this.deleteTargetName}」吗？删除后该规则不会参与播放源搜索，可重新从仓库安装。`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(26)
          .width('100%')
          .margin({ bottom: 26 })

        Row() {
          Text('取消')
            .layoutWeight(1)
            .height(52)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.deletingName.length === 0) {
                this.showDeleteDialog = false
                this.deleteTargetName = ''
              }
            })

          Divider()
            .vertical(true)
            .height(34)
            .color($r('app.color.divider_color'))
            .margin({ left: 4, right: 4 })

          Text(this.deletingName.length > 0 ? '删除中...' : '删除')
            .layoutWeight(1)
            .height(52)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.status_error'))
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.deletingName.length === 0) {
                this.confirmDeleteRule()
              }
            })
        }
        .width('100%')
        .height(52)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 20 })
      .borderRadius(34)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.overlay_modal_bg'))
    .padding({ left: 20, right: 20, bottom: 28 })
    .zIndex(40)
    .onClick(() => {
      if (this.deletingName.length === 0) {
        this.showDeleteDialog = false
        this.deleteTargetName = ''
      }
    })
  }

  private openLinkImportDialog(url: string): void {
    this.importUrl = url
    this.showActionMenu = false
    this.showLinkImportDialog = true
  }

  private async importFromLink(): Promise<void> {
    const url = this.normalizeRepositoryLink(this.importUrl.trim())
    if (url.length === 0) {
      this.operationMessage = '请输入规则链接'
      return
    }
    this.isLinkImporting = true
    this.operationMessage = '正在从链接导入...'
    try {
      if (this.isRepositoryIndexUrl(url)) {
        this.operationMessage = '正在加载规则仓库...'
        const remoteItems = await this.connectRepository(url)
        this.operationMessage = `仓库已连接，共 ${remoteItems.length} 条规则，正在后台安装`
        this.showLinkImportDialog = false
        this.installRepositoryRulesInBackground(url, remoteItems)
      } else {
        const count = await DefaultRuleSourceInitializer.importFromUrl(url)
        SettingsChangeSignal.notifyRuleSourceChanged()
        await this.refreshLocalRulesAfterImport()
        this.operationMessage = `已导入 ${count} 条规则`
        this.showLinkImportDialog = false
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `链接导入失败: ${msg}`
      logger.error('Import from link failed: %{public}s', msg)
    } finally {
      this.isLinkImporting = false
    }
  }

  private async connectRepository(url: string): Promise<RuleCatalogItem[]> {
    const remoteItems = await RuleCatalogService.fetchCatalog(url)
    await this.saveRepositoryStateIfNeeded(url)
    this.localRules = await this.ruleSourceStore.getAll()
    this.catalogItems = this.mergeCatalogItems(remoteItems, this.localRules, true)
    this.repositoryUrl = url
    this.canRefreshRepository = true
    this.errorMessage = ''
    return remoteItems
  }

  private async installRepositoryRulesInBackground(repositoryUrl: string, remoteItems: RuleCatalogItem[]): Promise<void> {
    if (this.backgroundInstalling) {
      return
    }
    this.backgroundInstalling = true
    this.backgroundInstallDone = 0
    this.backgroundInstallTotal = this.countInstallableRules(remoteItems)
    if (this.backgroundInstallTotal === 0) {
      this.backgroundInstalling = false
      this.operationMessage = '仓库规则已是最新'
      return
    }

    let failed = 0
    try {
      for (let i = 0; i < remoteItems.length; i++) {
        const item = remoteItems[i]
        const status = RuleCatalogService.getRuleStatus(item, this.localRules)
        if (status === 'installed') {
          continue
        }
        const result = await RuleCatalogService.tryInstallRule(item.name, repositoryUrl)
        if (result === 0) {
          this.backgroundInstallDone++
          this.localRules = await this.ruleSourceStore.getAll()
          this.catalogItems = this.mergeCatalogItems(remoteItems, this.localRules, true)
          this.operationMessage = `后台安装规则 ${this.backgroundInstallDone}/${this.backgroundInstallTotal}`
        } else {
          failed++
        }
      }
      this.localRules = await this.ruleSourceStore.getAll()
      this.catalogItems = this.mergeCatalogItems(remoteItems, this.localRules, true)
      SettingsChangeSignal.notifyRuleSourceChanged()
      this.operationMessage = failed > 0 ?
        `后台安装完成，失败 ${failed} 条` :
        `已安装 ${this.backgroundInstallDone} 条规则`
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `后台安装中断: ${msg}`
      logger.error('Background install failed: %{public}s', msg)
    } finally {
      this.backgroundInstalling = false
      this.backgroundInstallTotal = 0
      this.backgroundInstallDone = 0
    }
  }

  private countInstallableRules(items: RuleCatalogItem[]): number {
    let count = 0
    for (let i = 0; i < items.length; i++) {
      if (RuleCatalogService.getRuleStatus(items[i], this.localRules) !== 'installed') {
        count++
      }
    }
    return count
  }

  private async refreshLocalRulesAfterImport(): Promise<void> {
    this.localRules = await this.ruleSourceStore.getAll()
    this.catalogItems = this.mergeCatalogItems(this.catalogItems, this.localRules)
  }

  private async loadRepositoryState(): Promise<void> {
    const repositoryUrl = await this.getSavedRepositoryUrl()
    this.repositoryUrl = repositoryUrl
    this.canRefreshRepository = repositoryUrl.length > 0
  }

  private async saveRepositoryStateIfNeeded(url: string): Promise<void> {
    if (!this.isRepositoryIndexUrl(url)) {
      return
    }
    const prefs = PreferencesStore.getInstance()
    await prefs.setString(PREF_RULE_REPOSITORY_URL, url)
    this.repositoryUrl = url
    this.canRefreshRepository = true
  }

  private normalizeRepositoryLink(url: string): string {
    const normalized = this.normalizeInputUrl(url)
    const githubPrefix = 'https://github.com/'
    if (normalized.startsWith(githubPrefix)) {
      const parts = normalized.substring(githubPrefix.length).split('/')
      if (parts.length === 2 && parts[0].length > 0 && parts[1].length > 0) {
        return `https://raw.githubusercontent.com/${parts[0]}/${parts[1]}/main/index.json`
      }
      if (parts.length >= 5 && parts[0].length > 0 && parts[1].length > 0 && parts[2] === 'blob') {
        const owner = parts[0]
        const repo = parts[1]
        const ref = parts[3]
        const path = parts.slice(4).join('/')
        return `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path}`
      }
      if (parts.length >= 3 && parts[0].length > 0 && parts[1].length > 0 && parts[2] === 'tree') {
        const owner = parts[0]
        const repo = parts[1]
        const ref = parts.length >= 4 && parts[3].length > 0 ? parts[3] : 'main'
        const folder = parts.length > 4 ? parts.slice(4).join('/') + '/' : ''
        return `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${folder}index.json`
      }
    }

    const rawGithubPrefix = 'https://raw.githubusercontent.com/'
    if (normalized.startsWith(rawGithubPrefix)) {
      const parts = normalized.substring(rawGithubPrefix.length).split('/')
      if (parts.length === 3 && parts[0].length > 0 && parts[1].length > 0 && parts[2].length > 0) {
        return `${normalized}/index.json`
      }
      if (parts.length === 5 && parts[2] === 'refs' && parts[3] === 'heads' &&
        parts[0].length > 0 && parts[1].length > 0 && parts[4].length > 0) {
        return `${normalized}/index.json`
      }
    }

    const jsDelivrGithubPrefix = 'https://cdn.jsdelivr.net/gh/'
    if (normalized.startsWith(jsDelivrGithubPrefix)) {
      const rest = normalized.substring(jsDelivrGithubPrefix.length)
      const parts = rest.split('/')
      if (parts.length === 2 && parts[0].length > 0 && parts[1].length > 0) {
        return `${jsDelivrGithubPrefix}${parts[0]}/${parts[1]}@main/index.json`
      }
      if (parts.length >= 2 && parts[0].length > 0 && parts[1].length > 0 &&
        parts[1].indexOf('@') > 0 && !this.jsDelivrPathHasFile(parts)) {
        return `${normalized}/index.json`
      }
    }
    return normalized
  }

  private jsDelivrPathHasFile(parts: string[]): boolean {
    if (parts.length <= 2) {
      return false
    }
    const last = parts[parts.length - 1]
    return last.indexOf('.') > 0
  }

  private isRepositoryIndexUrl(url: string): boolean {
    return this.normalizeInputUrl(url).endsWith('/index.json')
  }

  private normalizeInputUrl(input: string): string {
    let text = input.trim()
    const markdownStart = text.indexOf('](')
    if (text.startsWith('[') && markdownStart > 0 && text.endsWith(')')) {
      text = text.substring(markdownStart + 2, text.length - 1).trim()
    }
    if ((text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'")) ||
      (text.startsWith('<') && text.endsWith('>'))) {
      text = text.substring(1, text.length - 1).trim()
    }
    const hashIndex = text.indexOf('#')
    if (hashIndex >= 0) {
      text = text.substring(0, hashIndex)
    }
    const queryIndex = text.indexOf('?')
    if (queryIndex >= 0) {
      text = text.substring(0, queryIndex)
    }
    return text.replace(/\/+$/, '')
  }

  private async getSavedRepositoryUrl(): Promise<string> {
    const prefs = PreferencesStore.getInstance()
    return (await prefs.getString(PREF_RULE_REPOSITORY_URL, '')).trim()
  }

  private buildRepositoryMoreIcon(): HdsNavigationIconOptions {
    return {
      icon: this.showActionMenu ? $r('sys.symbol.xmark') : $r('sys.symbol.dot_grid_1x2'),
      label: 'more',
      action: () => {
        this.showActionMenu = !this.showActionMenu
      }
    }
  }

  private buildRepositoryMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{ content: this.buildRepositoryMoreIcon() }]
    }
  }

  private buildRepositoryTitle(): HdsNavigationTitle {
    return {
      mainTitle: '规则仓库',
      subTitle: this.localRules.length > 0 ? `已安装 ${this.localRules.length} 条` : '从仓库安装或导入规则'
    }
  }

  private buildRepositoryTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildRepositoryTitle(),
      menu: this.buildRepositoryMenu()
    }
  }

  private buildRepositoryTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('规则仓库', this.hdsMaterialLevel)
    base.content = this.buildRepositoryTitleBarContent()
    return base
  }
}
