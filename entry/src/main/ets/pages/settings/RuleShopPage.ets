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
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'
import { RuleCatalogItem } from '../../models/RuleCatalogItem'
import { RuleSource } from '../../models/RuleSource'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleCatalogService } from '../../services/RuleCatalogService'
import { DefaultRuleSourceInitializer } from '../../utils/DefaultRuleSourceInitializer'
import { SettingsChangeSignal } from '../../store/SettingsChangeSignal'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { picker } from '@kit.CoreFileKit'
import { fileIo as fs } from '@kit.CoreFileKit'

const logger = new Logger('RuleShopPage')
const PREF_RULE_REPOSITORY_URL = 'rule_repository_url'

@Entry
@Component
struct RuleShopPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State catalogItems: RuleCatalogItem[] = []
  @State localRules: RuleSource[] = []
  @State loading: boolean = false
  @State sortByTime: boolean = true
  @State errorMessage: string = ''
  @State installingName: string = ''
  @State togglingName: string = ''
  @State showActionMenu: boolean = false
  @State showLinkImportDialog: boolean = false
  @State importUrl: string = ''
  @State operationMessage: string = ''
  @State isLinkImporting: boolean = false
  @State isFileImporting: boolean = false
  @State isExporting: boolean = false
  @State canRefreshRepository: boolean = false
  @State repositoryUrl: string = ''
  @State enableMenuRuleName: string = ''
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

            this.RepositorySummary()
            this.SortToggle()
            this.OperationMessageSection()
            this.CatalogList()

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
      .titleBar(this.buildRepositoryTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (this.showActionMenu) {
        this.ActionMenuOverlay()
      }

      if (this.showLinkImportDialog) {
        this.LinkImportDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RepositorySummary(): void {
    Column() {
      Row() {
        Column() {
          Text('规则仓库')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text(this.repositoryUrl.length > 0 ? '从已导入的规则仓库安装、更新和管理播放规则' : '通过右上角链接导入规则仓库')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.accent_blue'))
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.episode_item_selected_bg'))
        .opacity(this.loading ? 1 : 0)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })

      Row() {
        this.SummaryMetric('仓库', String(this.catalogItems.length))
        this.SummaryDivider()
        this.SummaryMetric('已安装', String(this.localRules.length))
        this.SummaryDivider()
        this.SummaryMetric('可更新', String(this.getUpdateCount()))
        this.SummaryDivider()
        this.SummaryMetric('已启用', String(this.getEnabledCount()))
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 14 })
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
  SummaryMetric(label: string, value: string): void {
    Column() {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.accent_blue'))
        .maxLines(1)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SummaryDivider(): void {
    Divider()
      .vertical(true)
      .height(28)
      .color($r('app.color.divider_color'))
      .strokeWidth(0.5)
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
        }, (item: RuleCatalogItem) => item.name)
      }
      .width('100%')
    } else if (!this.loading && this.errorMessage.length === 0) {
      this.EmptyCatalogSection()
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
  }

  @Builder
  RuleStatusBadge(item: RuleCatalogItem): void {
    Text(RuleCatalogService.getRuleStatus(item, this.localRules) === 'installed' ?
      (this.isRuleEnabled(item.name) ? '已启用' : '已安装') :
      (RuleCatalogService.getRuleStatus(item, this.localRules) === 'update' ? '可更新' : '未安装'))
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(RuleCatalogService.getRuleStatus(item, this.localRules) === 'install' ?
        $r('app.color.text_secondary') : $r('app.color.accent_blue'))
      .backgroundColor(RuleCatalogService.getRuleStatus(item, this.localRules) === 'install' ?
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
    if (RuleCatalogService.getRuleStatus(item, this.localRules) === 'installed') {
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
          .enabled(this.installingName.length === 0 && this.togglingName.length === 0)
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
        .enabled(this.installingName.length === 0 && this.togglingName.length === 0)
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
    .enabled(this.installingName.length === 0 && this.togglingName.length === 0)
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
    .bindPopup(this.enableMenuRuleName === name, {
      builder: this.RuleEnableMenuContent,
      placement: Placement.Bottom,
      showInSubWindow: false,
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.enableMenuRuleName = ''
        }
      }
    })
  }

  @Builder
  RuleEnableMenuContent(): void {
    Column() {
      this.RuleEnableMenuItem('启用', true)
      this.RuleEnableMenuItem('关闭', false)
    }
    .width(132)
    .padding(8)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
  }

  @Builder
  RuleEnableMenuItem(label: string, enabled: boolean): void {
    Text(label)
      .fontSize(16)
      .fontWeight(this.isRuleEnabled(this.enableMenuRuleName) === enabled ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.isRuleEnabled(this.enableMenuRuleName) === enabled ?
        $r('app.color.accent_blue') : $r('app.color.text_primary'))
      .width('100%')
      .height(52)
      .padding({ left: 18, right: 18 })
      .textAlign(TextAlign.Start)
      .borderRadius(14)
      .backgroundColor(this.isRuleEnabled(this.enableMenuRuleName) === enabled ?
        $r('app.color.episode_item_selected_bg') : Color.Transparent)
      .onClick(() => {
        this.setRuleEnabledByName(this.enableMenuRuleName, enabled)
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
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(36)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ bottom: 10 })

      Text('暂无规则')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 4 })

      Text(this.repositoryUrl.length > 0 ? '刷新仓库或从右上角导入规则' : '请先从右上角通过链接导入规则仓库')
        .fontSize(13)
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

  private getSortedItems(): RuleCatalogItem[] {
    const items = [...this.catalogItems]
    if (this.sortByTime) {
      items.sort((a: RuleCatalogItem, b: RuleCatalogItem) => b.lastUpdate - a.lastUpdate)
    } else {
      items.sort((a: RuleCatalogItem, b: RuleCatalogItem) => a.name.localeCompare(b.name))
    }
    return items
  }

  private getEnabledCount(): number {
    let count = 0
    for (let i = 0; i < this.localRules.length; i++) {
      if (this.localRules[i].enabled) {
        count++
      }
    }
    return count
  }

  private getUpdateCount(): number {
    let count = 0
    for (let i = 0; i < this.catalogItems.length; i++) {
      if (RuleCatalogService.getRuleStatus(this.catalogItems[i], this.localRules) === 'update') {
        count++
      }
    }
    return count
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
    this.loading = true
    this.errorMessage = ''
    try {
      this.localRules = await this.ruleSourceStore.getAll()
      const repositoryUrl = await this.getSavedRepositoryUrl()
      this.repositoryUrl = repositoryUrl
      this.canRefreshRepository = repositoryUrl.length > 0
      if (repositoryUrl.length === 0) {
        this.catalogItems = []
        return
      }
      this.catalogItems = await RuleCatalogService.fetchCatalog(repositoryUrl)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.errorMessage = `加载失败: ${msg}`
      logger.error('Load catalog failed: %{public}s', msg)
    } finally {
      this.loading = false
    }
  }

  private async onInstallRule(name: string): Promise<void> {
    this.installingName = name
    try {
      const repositoryUrl = await this.getSavedRepositoryUrl()
      const result = await RuleCatalogService.tryInstallRule(name, repositoryUrl)
      if (result === 0) {
        promptAction.showToast({ message: `规则 ${name} 安装/更新成功` })
        this.localRules = await this.ruleSourceStore.getAll()
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
        this.ActionMenuItem('导入规则', () => {
          this.showActionMenu = false
          this.importFromFile()
        })
        this.ActionMenuItem('导出规则', () => {
          this.showActionMenu = false
          this.exportRules()
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

        TextInput({ placeholder: '输入规则 JSON 或 index.json 链接', text: this.importUrl })
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
      let count = 0
      if (this.isRepositoryIndexUrl(url)) {
        count = await DefaultRuleSourceInitializer.importFromCatalogUrl(url)
      } else {
        count = await DefaultRuleSourceInitializer.importFromUrl(url)
      }
      SettingsChangeSignal.notifyRuleSourceChanged()
      await this.saveRepositoryStateIfNeeded(url)
      this.operationMessage = `已导入 ${count} 条规则`
      this.showLinkImportDialog = false
      await this.loadCatalog()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `链接导入失败: ${msg}`
      logger.error('Import from link failed: %{public}s', msg)
    } finally {
      this.isLinkImporting = false
    }
  }

  private async importFromFile(): Promise<void> {
    this.isFileImporting = true
    this.operationMessage = '请选择规则 JSON 文件...'
    try {
      const context = getContext(this) as common.UIAbilityContext
      const docViewPicker = new picker.DocumentViewPicker(context)
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      const uris: Array<string> = await docViewPicker.select(documentSelectOptions)
      if (uris.length === 0) {
        this.operationMessage = '导入已取消'
        return
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(uris[0])
      const buf = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buf)
      fs.closeSync(file)
      const arr = new Uint8Array(buf)
      let jsonStr = ''
      for (let i = 0; i < arr.length; i++) {
        jsonStr += String.fromCharCode(arr[i])
      }
      const count = await DefaultRuleSourceInitializer.importFromJson(jsonStr)
      SettingsChangeSignal.notifyRuleSourceChanged()
      this.operationMessage = `已导入 ${count} 条规则`
      await this.loadCatalog()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `文件导入失败: ${msg}`
      logger.error('File import failed: %{public}s', msg)
    } finally {
      this.isFileImporting = false
    }
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
    const normalized = url.trim().replace(/\/+$/, '')
    const githubPrefix = 'https://github.com/'
    if (normalized.startsWith(githubPrefix)) {
      const parts = normalized.substring(githubPrefix.length).split('/')
      if (parts.length === 2 && parts[0].length > 0 && parts[1].length > 0) {
        return `https://raw.githubusercontent.com/${parts[0]}/${parts[1]}/main/index.json`
      }
    }
    return normalized
  }

  private isRepositoryIndexUrl(url: string): boolean {
    return url.trim().replace(/\/+$/, '').endsWith('/index.json')
  }

  private async getSavedRepositoryUrl(): Promise<string> {
    const prefs = PreferencesStore.getInstance()
    return (await prefs.getString(PREF_RULE_REPOSITORY_URL, '')).trim()
  }

  private async exportRules(): Promise<void> {
    this.isExporting = true
    this.operationMessage = '正在导出规则...'
    try {
      const rules = await this.ruleSourceStore.getAll()
      if (rules.length === 0) {
        this.operationMessage = '没有可导出的规则'
        return
      }
      const jsonArr: Object[] = []
      for (let i = 0; i < rules.length; i++) {
        jsonArr.push(rules[i].toJSON())
      }
      const context = getContext(this) as common.UIAbilityContext
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.newFileNames = ['kazumi_rules.json']
      const docViewPicker = new picker.DocumentViewPicker(context)
      const uris: Array<string> = await docViewPicker.save(documentSaveOptions)
      if (uris.length > 0) {
        const file = fs.openSync(uris[0], fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
        fs.writeSync(file.fd, JSON.stringify(jsonArr))
        fs.closeSync(file)
        this.operationMessage = `已导出 ${rules.length} 条规则`
      } else {
        this.operationMessage = '导出已取消'
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.operationMessage = `导出失败: ${msg}`
      logger.error('Export rules failed: %{public}s', msg)
    } finally {
      this.isExporting = false
    }
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
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('规则仓库')
    base.content = this.buildRepositoryTitleBarContent()
    return base
  }
}
