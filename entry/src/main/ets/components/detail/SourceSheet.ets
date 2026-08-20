import { PluginSearchState, SearchResultRef } from '../../models/PluginSearchState'
import { PlaybackSource } from '../../models/PlaybackRoad'
import { PluginSearchService } from '../../core/engine/PluginSearchService'
import { CaptchaDialog } from './CaptchaDialog'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel'
import { RuleSource } from '../../models/RuleSource'
import { Logger } from '../../utils/Logger'
import { createThinImmersiveMaterial, createThickImmersiveMaterial } from '../../utils/ImmersiveMaterial'
import { webview } from '@kit.ArkWeb'

const logger = new Logger('SourceSheet')
const TABLET_SOURCE_SHEET_BREAKPOINT: number = 840
const TABLET_SOURCE_RAIL_WIDTH: number = 220
const WIDE_TABLET_SOURCE_RAIL_WIDTH: number = 260
const CAPTCHA_RETRY_DELAY_MS: number = 3200
const SOURCE_SHEET_PILL_RADIUS: number = 19

function normalizeWebScriptStringResult(result: Object): string {
  const raw = String(result).trim()
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    try {
      return String(JSON.parse(raw))
    } catch (e) {
    }
  }
  if (raw.length >= 2 && raw.startsWith("'") && raw.endsWith("'")) {
    return raw.substring(1, raw.length - 1)
  }
  return raw
}

export class SourceSheetSnapshot {
  pluginStates: PluginSearchState[] = []
  selectedPluginId: number = -1
  selectedResult: SearchResultRef | null = null
  hasUserSelectedPlugin: boolean = false
}

@Component
export struct SourceSheet {
  @State pluginStates: PluginSearchState[] = []
  @State selectedPluginIndex: number = 0
  @State isSearching: boolean = false
  @State selectedResult: SearchResultRef | null = null
  @State isQueryingRoads: boolean = false
  @State queryRoadsError: string = ''
  @State showCaptchaDialog: boolean = false
  @State captchaUrl: string = ''
  @State captchaType: number = 1
  @State captchaImage: string = ''
  @State captchaInput: string = ''
  @State captchaScript: string = ''
  @State captchaButton: string = ''
  @State captchaRuleSourceName: string = ''
  @State showAliasDialog: boolean = false
  @State showManualSearchDialog: boolean = false
  @State manualSearchKeyword: string = ''
  @State captchaRetrying: boolean = false
  @State webRoadFallbackActive: boolean = false
  @State webRoadFallbackUrl: string = ''
  @State sheetWidthVp: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 360
  @StorageLink('keyboardAvoidHeight') keyboardAvoidHeight: number = 0
  @Prop animeName: string = ''
  @Prop animeOriginalName: string = ''
  @Prop animeAliases: string[] = []
  @Prop @Watch('onCloseSignalChange') closeSignal: number = 0
  @Prop preserveOnDisappear: boolean = false
  @Prop restoreSnapshot: SourceSheetSnapshot | null = null
  private searchService: PluginSearchService = new PluginSearchService()
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private isClosed: boolean = false
  private hasUserSelectedPlugin: boolean = false
  private roadsRequestToken: number = 0
  private webRoadFallbackToken: number = 0
  private webRoadFallbackResult: SearchResultRef | null = null
  private webRoadFallbackController: webview.WebviewController = new webview.WebviewController()
  onRoadsReady?: ((source: PlaybackSource) => void)
  onSnapshotChanged?: ((snapshot: SourceSheetSnapshot) => void)

  aboutToAppear(): void {
    this.isClosed = false
    this.searchService.setOnStateChange((states: PluginSearchState[]) => {
      if (!this.isClosed) {
        this.applyPluginStates(states)
      }
    })
    if (this.restoreFromSnapshot()) {
      return
    }
    this.startSearch()
  }

  aboutToDisappear(): void {
    if (this.preserveOnDisappear) {
      return
    }
    this.cancelSearch()
  }

  build() {
    Stack() {
      Column() {
        if (this.isTabletSheetLayout()) {
          this.TabletSheetContent()
        } else {
          this.PhoneSheetContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.showCaptchaDialog) {
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.overlay_topbar_bg'))

        CaptchaDialog({
          captchaUrl: this.captchaUrl,
          captchaType: this.captchaType,
          captchaImage: this.captchaImage,
          captchaInput: this.captchaInput,
          captchaScript: this.captchaScript,
          captchaButton: this.captchaButton,
          ruleSourceName: this.captchaRuleSourceName,
          onVerified: () => {
            this.showCaptchaDialog = false
            this.retryCurrentPlugin(true)
          },
          onCancelled: () => {
            this.showCaptchaDialog = false
            this.searchService.updatePluginErrorById(this.getSelectedPluginId(), '验证取消或超时，可重试')
          }
        })
      }

      if (this.showAliasDialog) {
        this.AliasDialogOverlay()
      }

      if (this.showManualSearchDialog) {
        this.ManualSearchDialogOverlay()
      }

      if (this.webRoadFallbackActive) {
        Web({ src: this.webRoadFallbackUrl, controller: this.webRoadFallbackController })
          .width(1)
          .height(1)
          .opacity(0.01)
          .onPageEnd(() => {
            this.onWebRoadFallbackPageEnd()
          })
          .onErrorReceive((event) => {
            if (event && event.error) {
              logger.warn('Road fallback WebView error: %{public}s', event.error.getErrorInfo())
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.sheetWidthVp = this.normalizeSize(newArea.width)
    })
  }

  @Builder
  private PhoneSheetContent(): void {
    this.CompactHeader()
    this.SourceChips()

    if (this.pluginStates.length > 0 && this.selectedPluginIndex < this.pluginStates.length) {
      this.PluginContentArea()
    } else {
      this.EmptySourceState()
    }
  }

  @Builder
  private TabletSheetContent(): void {
    this.CompactHeader()

    Row() {
      this.TabletSourceRail()

      Column()
        .width(0.5)
        .height('100%')
        .backgroundColor($r('app.color.border_subtle'))
        .opacity(0.8)

      if (this.pluginStates.length > 0 && this.selectedPluginIndex < this.pluginStates.length) {
        this.PluginContentArea()
      } else {
        this.EmptySourceState()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private EmptySourceState(): void {
    Column() {
      Text('暂无可用播放源')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private CompactHeader(): void {
    Column() {
      Row() {
        Column() {
          Text('选择播放源')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)

          Row() {
            Text('关键词：')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(this.getCurrentKeyword().length > 0 ? this.getCurrentKeyword() : '等待番剧信息')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

      }
      .width('100%')

      Row() {
        Row() {
          Text(`${this.getMatchedSourceCount()} 已匹配`)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(SOURCE_SHEET_PILL_RADIUS)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Row() {
          Text(`${this.pluginStates.length} 源`)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(SOURCE_SHEET_PILL_RADIUS)
        .backgroundColor($r('app.color.button_ghost_bg'))
        .margin({ left: 8 })

        Blank()

        Row() {
          if (this.isSearchInProgress()) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color($r('app.color.accent_blue'))
              .margin({ right: 6 })
            Text('检索中')
              .fontSize(12)
              .fontColor($r('app.color.accent_blue'))
          } else {
            Column()
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor($r('app.color.status_success'))
              .margin({ right: 6 })
            Text('已完成')
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
          }
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(SOURCE_SHEET_PILL_RADIUS)
        .backgroundColor($r('app.color.button_ghost_bg'))
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 8 })
  }

  @Builder
  private TabletSourceRail(): void {
    Column() {
      Row() {
        Text('播放源')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.getMatchedSourceCount()}/${this.pluginStates.length}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.pluginStates.length > 0) {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.pluginStates, (state: PluginSearchState, index?: number) => {
              this.TabletSourceItem(state, index === undefined ? 0 : index)
            }, (state: PluginSearchState, index?: number) =>
              `tablet_source_${state.pluginId}_${state.status}_${state.searchResults.length}_${index}`)
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width(this.getTabletSourceRailWidth())
    .height('100%')
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
  }

  @Builder
  private TabletSourceItem(state: PluginSearchState, index: number): void {
    Row() {
      Column()
        .width(7)
        .height(7)
        .borderRadius(3.5)
        .backgroundColor(this.getChipStatusColor(state))
        .margin({ right: 10 })

      Column() {
        Text(state.pluginName)
          .fontSize(14)
          .fontWeight(this.selectedPluginIndex === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedPluginIndex === index ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.buildSourceItemStatusText(state))
          .fontSize(12)
          .fontColor(this.selectedPluginIndex === index ? $r('app.color.accent_blue') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (state.status === 'pending' && this.isSearchInProgress()) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color($r('app.color.accent_blue'))
          .margin({ left: 8 })
      } else if (this.hasSearchResults(state)) {
        Row() {
          Text(`${state.searchResults.length}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor($r('app.color.accent_blue'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ left: 8 })
      }
    }
    .width('100%')
    .height(58)
    .padding({ left: 12, right: 10 })
    .borderRadius(12)
    .backgroundColor(this.selectedPluginIndex === index ? $r('app.color.button_ghost_bg') : Color.Transparent)
    .border({
      width: this.selectedPluginIndex === index ? 1 : 0,
      color: this.selectedPluginIndex === index ? $r('app.color.accent_blue') : Color.Transparent
    })
    .onClick(() => {
      this.onPluginSelected(index)
    })
  }

  @Builder
  private SourceChips(): void {
    if (this.pluginStates.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.pluginStates, (state: PluginSearchState, index?: number) => {
            this.SourceChip(state, index === undefined ? 0 : index)
          }, (state: PluginSearchState, index?: number) =>
            `source_chip_${state.pluginId}_${state.status}_${state.searchResults.length}_${index}`)
        }
        .padding({ left: 20, right: 20 })
      }
      .width('100%')
      .height(46)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .margin({ bottom: 4 })
    }
  }

  @Builder
  private SourceChip(state: PluginSearchState, index: number): void {
    Row() {
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(this.getChipStatusColor(state))
        .margin({ right: 6 })

      Text(state.pluginName)
        .fontSize(13)
        .fontWeight(this.selectedPluginIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selectedPluginIndex === index ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.hasSearchResults(state)) {
        Row() {
          Text(`${state.searchResults.length}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(20)
        .height(20)
        .borderRadius(10)
        .backgroundColor($r('app.color.accent_blue'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ left: 6 })
      } else if (state.status === 'captcha') {
        Text('验证')
          .fontSize(11)
          .fontColor($r('app.color.status_warning'))
          .margin({ left: 4 })
      } else if (state.status === 'pending' && this.isSearchInProgress()) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color($r('app.color.accent_blue'))
          .margin({ left: 4 })
      } else if (state.status === 'error') {
        Text('失败')
          .fontSize(11)
          .fontColor($r('app.color.status_error'))
          .margin({ left: 4 })
      } else if (state.status === 'noResult') {
        Text('0')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
      } else if (state.status === 'success') {
        Text('0')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
      }
    }
    .height(38)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 10 })
    .borderRadius(SOURCE_SHEET_PILL_RADIUS)
    .backgroundColor(this.selectedPluginIndex === index ? $r('app.color.button_ghost_bg') : $r('app.color.card_background'))
    .border({
      width: this.selectedPluginIndex === index ? 1.2 : 0.5,
      color: this.selectedPluginIndex === index ? $r('app.color.accent_blue') : $r('app.color.card_specular_border')
    })
    .shadow({
      radius: this.selectedPluginIndex === index ? 12 : 4,
      color: this.selectedPluginIndex === index ? $r('app.color.shadow_button_accent') : $r('app.color.shadow_surface'),
      offsetY: this.selectedPluginIndex === index ? 3 : 1
    })
    .onClick(() => {
      this.onPluginSelected(index)
    })
  }

  @Builder
  private PluginContentArea(): void {
    Column() {
      if (this.captchaRetrying) {
        this.LoadingStateCard('验证成功', '正在重新检索播放源，请稍候')
      } else if (this.hasSearchResults(this.pluginStates[this.selectedPluginIndex])) {
        if (this.isQueryingRoads) {
          this.LoadingStateCard('正在解析',
            this.selectedResult !== null ? this.selectedResult.name : '正在解析可播放剧集')
        } else if (this.queryRoadsError.length > 0) {
          this.RoadsErrorCard()
        } else {
          this.SuccessResultArea()
        }
      } else if (this.pluginStates[this.selectedPluginIndex].status === 'pending') {
        if (this.isSearchInProgress()) {
          this.LoadingStateCard('正在检索播放源', '正在使用当前规则源匹配番剧资源')
        } else {
          this.PendingFinishedStateCard()
        }
      } else if (this.pluginStates[this.selectedPluginIndex].status === 'success') {
        if (this.isQueryingRoads) {
          this.LoadingStateCard('正在解析',
            this.selectedResult !== null ? this.selectedResult.name : '正在解析可播放剧集')
        } else if (this.queryRoadsError.length > 0) {
          this.RoadsErrorCard()
        } else {
          this.SuccessResultArea()
        }
      } else if (this.pluginStates[this.selectedPluginIndex].status === 'noResult') {
        this.NoResultStateCard()
      } else if (this.pluginStates[this.selectedPluginIndex].status === 'captcha') {
        this.CaptchaStateCard()
      } else if (this.pluginStates[this.selectedPluginIndex].status === 'error') {
        this.ErrorStateCard()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SuccessResultArea(): void {
    Column() {
      Row() {
        Column() {
          Text('匹配结果')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.pluginStates[this.selectedPluginIndex].pluginName)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(`${this.pluginStates[this.selectedPluginIndex].searchResults.length} 个结果`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.pluginStates[this.selectedPluginIndex].searchResults.length === 0) {
        this.NoResultStateCard()
      } else {
        List({ space: 10 }) {
          ForEach(this.pluginStates[this.selectedPluginIndex].searchResults, (result: SearchResultRef, index?: number) => {
            ListItem() {
              this.ResultCard(result)
            }
          }, (result: SearchResultRef, index?: number) => `result_${result.sourceId}_${index}`)

          ListItem() {
            this.SupplementarySearchEntry()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 18, right: 18, top: 8, bottom: 0 })
  }

  @Builder
  private ResultCard(result: SearchResultRef): void {
    Row() {
      Column() {
        Text(result.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(result.sourceName.length > 0 ? result.sourceName : this.pluginStates[this.selectedPluginIndex].pluginName)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('·')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4, right: 4 })
          Text('匹配结果')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button({ type: ButtonType.Normal }) {
        Text('解析播放')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_primary'))
      }
        .height(32)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.accent_blue'))
        .borderRadius(16)
        .onClick(() => {
          this.onSearchResultSelected(result)
        })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 14, bottom: 14 })
    .borderRadius(18)
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .onClick(() => {
      this.onSearchResultSelected(result)
    })
  }

  @Builder
  private SupplementarySearchEntry(): void {
    Row() {
      Text('仍未找到？')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
      Button('别名检索')
        .fontSize(12)
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(Color.White)
        .fontColor(Color.Black)
        .borderRadius(14)
        .border({ width: 0.5, color: $r('app.color.border_subtle') })
        .margin({ left: 8 })
        .onClick(() => {
          this.openAliasDialog()
        })
      Button('手动检索')
        .fontSize(12)
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.accent_blue'))
        .fontColor($r('app.color.text_on_primary'))
        .borderRadius(14)
        .margin({ left: 8 })
        .onClick(() => {
          this.openManualSearchDialog()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 14 })
  }

  @Builder
  private LoadingStateCard(title: string, message: string): void {
    Column() {
      LoadingProgress()
        .width(42)
        .height(42)
        .color($r('app.color.accent_blue'))
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16 })
      Text(message)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  @Builder
  private RoadsErrorCard(): void {
    Column() {
      this.StateBadge('线路解析失败', this.queryRoadsError.length > 0 ? this.queryRoadsError : '当前资源暂时无法获取可播放剧集')
      Row() {
        Button('重试解析')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .systemMaterial(createThickImmersiveMaterial())
          .margin({ right: 12 })
          .onClick(() => {
            if (this.selectedResult !== null) {
              this.onSearchResultSelected(this.selectedResult)
            }
          })

        Button('返回匹配')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
          .systemMaterial(createThickImmersiveMaterial())
          .onClick(() => {
            this.returnToMatchedResults()
          })
      }
      .margin({ top: 18 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private NoResultStateCard(): void {
    Column() {
      this.StateBadge('未匹配到资源', '当前规则源没有返回结果，可换源或使用别名重新检索')
      Row() {
        Button('别名检索')
        .fontSize(14)
        .height(42)
        .padding({ left: 20, right: 20 })
          .backgroundColor(Color.White)
          .fontColor(Color.Black)
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
          .margin({ right: 12 })
          .onClick(() => {
            this.openAliasDialog()
          })
        Button('手动检索')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .onClick(() => {
            this.openManualSearchDialog()
          })
      }
      .margin({ top: 18 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private PendingFinishedStateCard(): void {
    Column() {
      this.StateBadge('该源未返回结果', '检索任务已结束，但当前规则源没有按时返回可用数据')
      Row() {
        Button('重试')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .systemMaterial(createThickImmersiveMaterial())
          .margin({ right: 12 })
          .onClick(() => {
            this.retryCurrentPlugin()
          })
        Button('手动检索')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .onClick(() => {
            this.openManualSearchDialog()
          })
      }
      .margin({ top: 18 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private CaptchaStateCard(): void {
    Column() {
      this.StateBadge('需要完成验证', '该规则源触发站点验证，完成后会自动重试匹配')
      Row() {
        Button('进行验证')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_info_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .shadow({ radius: 12, color: $r('app.color.shadow_button_info'), offsetY: 4 })
          .systemMaterial(createThickImmersiveMaterial())
          .margin({ right: 12 })
          .onClick(() => {
            this.openCaptchaDialog()
          })
        Button('重试')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
          .systemMaterial(createThickImmersiveMaterial())
          .onClick(() => {
            this.retryCurrentPlugin()
          })
      }
      .margin({ top: 18 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private ErrorStateCard(): void {
    Column() {
      this.StateBadge('检索失败',
        this.pluginStates[this.selectedPluginIndex].errorMessage.length > 0 ? this.pluginStates[this.selectedPluginIndex].errorMessage : '当前播放源返回异常')
      Row() {
        Button('重试')
          .fontSize(14)
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .systemMaterial(createThickImmersiveMaterial())
          .margin({ right: 10 })
          .onClick(() => {
            this.retryCurrentPlugin()
          })
        Button('别名检索')
          .fontSize(14)
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor(Color.White)
          .fontColor(Color.Black)
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
          .margin({ right: 10 })
          .onClick(() => {
            this.openAliasDialog()
          })
        Button('手动')
          .fontSize(14)
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor($r('app.color.accent_blue'))
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .onClick(() => {
            this.openManualSearchDialog()
          })
      }
      .margin({ top: 18 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private StateBadge(title: string, message: string): void {
    Column() {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
      Text(message)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .borderRadius(22)
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 16, color: $r('app.color.shadow_surface'), offsetY: 5 })
    .systemMaterial(createThickImmersiveMaterial())
  }

  @Builder
  private AliasDialogOverlay(): void {
    Column() {}
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.overlay_topbar_bg'))

    Column() {
      Column() {
        Text('选择别名检索')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 16 })

        if (this.getAliasList().length === 0) {
          Text('暂无可用别名')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ bottom: 16 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.getAliasList(), (alias: string, index?: number) => {
                Row() {
                  Text(alias)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_background'))
                .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
                .margin({ bottom: 4 })
                .onClick(() => {
                  this.showAliasDialog = false
                  this.queryCurrentSource(alias)
                })
              }, (alias: string, index?: number) => `alias_${index}`)
            }
          }
          .height(280)
          .scrollBar(BarState.Off)
          .margin({ bottom: 16 })
        }

        Row() {
          Button('取消')
            .fontSize(13)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
            .layoutWeight(1)
            .onClick(() => {
              this.showAliasDialog = false
            })
        }
        .width('100%')
      }
      .width(this.getFloatingDialogWidth())
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 6 })
      .systemMaterial(createThickImmersiveMaterial())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ManualSearchDialogOverlay(): void {
    Column() {}
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.overlay_topbar_bg'))
      .onClick(() => {
        this.showManualSearchDialog = false
      })

    Column() {
      Column() {
        Text('手动检索')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 16 })

        TextInput({ text: this.manualSearchKeyword, placeholder: '输入搜索关键词' })
          .fontSize(14)
          .width('100%')
          .height(44)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(12)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_hint'))
          .backgroundColor($r('app.color.button_ghost_bg'))
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
          .systemMaterial(createThinImmersiveMaterial())
          .onChange((value: string) => {
            this.manualSearchKeyword = value
          })
          .margin({ bottom: 18 })

        Row() {
          Button('取消')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .height(42)
            .backgroundColor($r('app.color.button_ghost_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(21)
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .layoutWeight(1)
            .margin({ right: 8 })
            .onClick(() => {
              this.showManualSearchDialog = false
            })
          Button('搜索')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .height(42)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(21)
            .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
            .layoutWeight(1)
            .onClick(() => {
              const keyword = this.manualSearchKeyword.trim()
              if (keyword.length > 0) {
                this.showManualSearchDialog = false
                this.queryCurrentSource(keyword)
              }
            })
        }
        .width('100%')
      }
      .width(this.getFloatingDialogWidth())
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 6 })
      .systemMaterial(createThickImmersiveMaterial())
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 18, right: 18, bottom: this.getManualSearchKeyboardPadding() })
    .translate({ y: this.getManualSearchDialogOffsetY() })
  }

  private getChipStatusColor(state: PluginSearchState): ResourceStr {
    if (this.hasSearchResults(state)) {
      return $r('app.color.status_success')
    }
    if (state.status === 'captcha') {
      return $r('app.color.status_warning')
    }
    if (state.status === 'error') {
      return $r('app.color.status_error')
    }
    if (state.status === 'noResult') {
      return $r('app.color.text_secondary')
    }
    return state.getStatusColor()
  }

  private isTabletSheetLayout(): boolean {
    return this.getEffectiveSheetWidth() >= TABLET_SOURCE_SHEET_BREAKPOINT
  }

  private getTabletSourceRailWidth(): number {
    if (this.getEffectiveSheetWidth() >= 1200) {
      return WIDE_TABLET_SOURCE_RAIL_WIDTH
    }
    return TABLET_SOURCE_RAIL_WIDTH
  }

  private getEffectiveSheetWidth(): number {
    return this.sheetWidthVp > 0 ? this.sheetWidthVp : this.screenWidthVp
  }

  private normalizeSize(value: Length): number {
    if (typeof value === 'number') {
      return Math.ceil(value)
    }
    const parsed = parseFloat(String(value))
    if (isNaN(parsed)) {
      return 0
    }
    return Math.ceil(parsed)
  }

  private getFloatingDialogWidth(): Length {
    if (this.isTabletSheetLayout()) {
      return 420
    }
    return '85%'
  }

  private buildSourceItemStatusText(state: PluginSearchState): string {
    if (this.hasSearchResults(state)) {
      return `${state.searchResults.length} 个匹配结果`
    }
    if (state.status === 'pending') {
      return this.isSearchInProgress() ? '检索中' : '等待结果'
    }
    if (state.status === 'captcha') {
      return '需要验证'
    }
    if (state.status === 'noResult') {
      return '暂无匹配'
    }
    if (state.status === 'error') {
      return '检索失败'
    }
    if (state.status === 'success') {
      return '暂无匹配'
    }
    return '等待检索'
  }

  private getMatchedSourceCount(): number {
    let count = 0
    for (let i = 0; i < this.pluginStates.length; i++) {
      if (this.hasSearchResults(this.pluginStates[i])) {
        count++
      }
    }
    return count
  }

  private getSearchingSourceCount(): number {
    let count = 0
    for (let i = 0; i < this.pluginStates.length; i++) {
      if (this.pluginStates[i].status === 'pending') {
        count++
      }
    }
    return count
  }

  private isSearchInProgress(): boolean {
    if (!this.isSearching) {
      return false
    }
    return this.pluginStates.length === 0 || this.getSearchingSourceCount() > 0
  }

  private hasSearchResults(state: PluginSearchState): boolean {
    return state.searchResults.length > 0
  }

  private getPluginSortPriority(state: PluginSearchState): number {
    if (state.searchResults.length > 0) return 0
    if (state.status === 'captcha') return 1
    if (state.status === 'pending') return 2
    if (state.status === 'success') return 3
    if (state.status === 'noResult') return 4
    if (state.status === 'error') return 5
    return 6
  }

  private findFirstMatchedPluginIndex(): number {
    for (let i = 0; i < this.pluginStates.length; i++) {
      if (this.pluginStates[i].searchResults.length > 0) {
        return i
      }
    }
    return -1
  }

  private switchToNextPlugin(): void {
    if (this.pluginStates.length <= 1) {
      return
    }
    let nextIndex = this.selectedPluginIndex + 1
    for (let i = 0; i < this.pluginStates.length; i++) {
      const checkIndex = (this.selectedPluginIndex + 1 + i) % this.pluginStates.length
      const status = this.pluginStates[checkIndex].status
      if (status !== 'captcha' && status !== 'error') {
        nextIndex = checkIndex
        break
      }
    }
    if (nextIndex !== this.selectedPluginIndex) {
      this.onPluginSelected(nextIndex)
    }
  }

  private async startSearch(): Promise<void> {
    let keyword = this.animeName.length > 0 ? this.animeName : this.animeOriginalName
    if (keyword.length === 0) {
      return
    }
    this.isSearching = true
    this.resetRoadQueryState()
    try {
      await this.searchService.searchAll(keyword)
    } finally {
      if (!this.isClosed) {
        this.isSearching = false
        this.applyPluginStates(this.searchService.getPluginStates().slice())
      }
    }
  }

  private async onSearchResultSelected(result: SearchResultRef): Promise<void> {
    if (this.isClosed) {
      return
    }
    const resultPluginIndex = this.findPluginIndexById(result.sourceId)
    if (resultPluginIndex >= 0) {
      this.selectedPluginIndex = resultPluginIndex
    }
    this.hasUserSelectedPlugin = true
    const requestToken = ++this.roadsRequestToken
    const requestPluginId = result.sourceId
    const currentResult = result
    this.selectedResult = result
    this.emitSnapshot()
    this.isQueryingRoads = true
    this.queryRoadsError = ''
    logger.info('queryRoads start token=%{public}d pluginId=%{public}d name=%{public}s',
      requestToken, requestPluginId, result.name)
    try {
      const source = await this.searchService.queryRoads(result)
      logger.info('queryRoads done token=%{public}d pluginId=%{public}d status=%{public}s roads=%{public}d',
        requestToken, requestPluginId, source.status, source.roads.length)
      if (this.isClosed || requestToken !== this.roadsRequestToken) {
        logger.warn('queryRoads result stale token=%{public}d currentToken=%{public}d, discarding',
          requestToken, this.roadsRequestToken)
        return
      }
      if (this.selectedResult !== currentResult && this.hasUserSelectedPlugin) {
        const currentSelectedId = this.getSelectedPluginId()
        if (currentSelectedId !== requestPluginId) {
          logger.warn('queryRoads plugin mismatch requestPluginId=%{public}d currentSelectedId=%{public}d, discarding',
            requestPluginId, currentSelectedId)
          return
        }
      }
      if (source.status === 'error') {
        this.queryRoadsError = source.message.length > 0 ? source.message : '获取线路失败'
        logger.error('Query roads failed for %{public}s: %{public}s', result.name, this.queryRoadsError)
      } else if (source.status === 'empty') {
        if (this.startWebRoadFallback(result, requestToken)) {
          this.queryRoadsError = '正在通过网页模式解析线路'
          return
        }
        this.queryRoadsError = '该源无可用剧集'
      } else if (this.onRoadsReady) {
        logger.info('onRoadsReady emit pluginId=%{public}d roads=%{public}d', requestPluginId, source.roads.length)
        this.onRoadsReady(source)
      }
    } catch (err) {
      if (this.isClosed || requestToken !== this.roadsRequestToken) {
        return
      }
      this.queryRoadsError = err instanceof Error ? err.message : '获取线路异常'
      logger.error('Query roads exception: %{public}s', this.queryRoadsError)
    } finally {
      if (!this.isClosed && !this.webRoadFallbackActive &&
        (requestToken === this.roadsRequestToken || this.selectedResult === currentResult)) {
        this.isQueryingRoads = false
      }
    }
  }

  private startWebRoadFallback(result: SearchResultRef, requestToken: number): boolean {
    if (result.url.length === 0 || !result.url.startsWith('http')) {
      return false
    }
    this.webRoadFallbackToken = requestToken
    this.webRoadFallbackResult = result
    this.webRoadFallbackUrl = result.url
    this.webRoadFallbackActive = true
    this.isQueryingRoads = true
    logger.info('Road WebView fallback start token=%{public}d pluginId=%{public}d url=%{public}s',
      requestToken, result.sourceId, result.url.substring(0, 120))
    return true
  }

  private onWebRoadFallbackPageEnd(): void {
    const token = this.webRoadFallbackToken
    const result = this.webRoadFallbackResult
    if (!this.webRoadFallbackActive || result === null) {
      return
    }
    setTimeout(() => {
      this.captureWebRoadFallbackHtml(token)
    }, 500)
  }

  private captureWebRoadFallbackHtml(token: number): void {
    const result = this.webRoadFallbackResult
    if (!this.webRoadFallbackActive || result === null || token !== this.roadsRequestToken) {
      return
    }
    const script = 'document.documentElement ? document.documentElement.outerHTML : document.body.outerHTML'
    this.webRoadFallbackController.runJavaScript(script, (err, jsResult) => {
      if (err) {
        logger.warn('Road WebView fallback HTML capture failed')
        this.finishWebRoadFallbackError(token, '网页模式解析失败')
        return
      }
      const html = normalizeWebScriptStringResult(jsResult)
      const normalizedHtml = html.replace(/\\\//g, '/')
      logger.info('Road WebView fallback captured token=%{public}d htmlLength=%{public}d hasVodPlay=%{public}s',
        token, html.length, String(normalizedHtml.indexOf('/vod/play/') !== -1 || normalizedHtml.indexOf('/vodplay/') !== -1))
      this.parseWebRoadFallbackHtml(token, result, html)
    })
  }

  private async parseWebRoadFallbackHtml(token: number, result: SearchResultRef, html: string): Promise<void> {
    if (this.isClosed || token !== this.roadsRequestToken) {
      return
    }
    try {
      const source = await this.searchService.queryRoadsFromHtml(result, html)
      if (this.isClosed || token !== this.roadsRequestToken) {
        return
      }
      logger.info('Road WebView fallback parsed token=%{public}d status=%{public}s roads=%{public}d',
        token, source.status, source.roads.length)
      if (source.status === 'success' && this.onRoadsReady) {
        this.clearWebRoadFallback()
        this.queryRoadsError = ''
        this.isQueryingRoads = false
        this.onRoadsReady(source)
      } else {
        this.finishWebRoadFallbackError(token, source.message.length > 0 ? source.message : '网页模式未解析到线路')
      }
    } catch (err) {
      this.finishWebRoadFallbackError(token, err instanceof Error ? err.message : '网页模式解析异常')
    }
  }

  private finishWebRoadFallbackError(token: number, message: string): void {
    if (this.isClosed || token !== this.roadsRequestToken) {
      return
    }
    this.clearWebRoadFallback()
    this.isQueryingRoads = false
    this.queryRoadsError = message
    logger.warn('Road WebView fallback failed token=%{public}d: %{public}s', token, message)
  }

  private clearWebRoadFallback(): void {
    this.webRoadFallbackActive = false
    this.webRoadFallbackUrl = ''
    this.webRoadFallbackResult = null
    try {
      this.webRoadFallbackController.loadUrl('about:blank')
    } catch (e) {
    }
  }

  private async retryCurrentPlugin(afterCaptcha: boolean = false): Promise<void> {
    if (this.isClosed) {
      return
    }
    if (this.captchaRetrying) {
      return
    }
    const pluginId = this.getSelectedPluginId()
    if (pluginId < 0) {
      return
    }
    this.captchaRetrying = true
    this.resetRoadQueryState()
    this.isSearching = true
    const keyword = this.getCurrentKeyword()
    const maxAttempts = 1
    try {
      for (let attempt = 0; attempt < maxAttempts; attempt++) {
        if (this.isClosed) {
          return
        }
        if (afterCaptcha) {
          const delayMs = CAPTCHA_RETRY_DELAY_MS
          logger.info('Retry plugin after captcha, attempt=%{public}d/%{public}d, delay=%{public}d',
            attempt + 1, maxAttempts, delayMs)
          await this.sleep(delayMs)
        }
        await this.searchService.retryPluginById(pluginId, keyword)
        return
      }
    } finally {
      this.captchaRetrying = false
      if (!this.isClosed) {
        this.isSearching = false
        this.applyPluginStates(this.searchService.getPluginStates().slice())
      }
    }
  }

  private async queryCurrentSource(keyword: string): Promise<void> {
    if (this.isClosed || keyword.length === 0) {
      return
    }
    if (this.selectedPluginIndex < 0 || this.selectedPluginIndex >= this.pluginStates.length) {
      return
    }
    this.resetRoadQueryState()
    this.isSearching = true
    const pluginId = this.pluginStates[this.selectedPluginIndex].pluginId
    logger.info('Query current source only, pluginId=%{public}d, keyword=%{public}s', pluginId, keyword)
    try {
      await this.searchService.querySource(pluginId, keyword)
    } finally {
      if (!this.isClosed) {
        this.isSearching = false
        this.applyPluginStates(this.searchService.getPluginStates().slice())
      }
    }
  }

  private applyPluginStates(states: PluginSearchState[]): void {
    const selectedPluginId = this.getSelectedPluginId()

    const sorted = states.slice()
    sorted.sort((a: PluginSearchState, b: PluginSearchState) => {
      const priorityA = this.getPluginSortPriority(a)
      const priorityB = this.getPluginSortPriority(b)
      if (priorityA !== priorityB) {
        return priorityA - priorityB
      }
      return b.searchResults.length - a.searchResults.length
    })

    this.pluginStates = sorted

    if (this.pluginStates.length === 0) {
      this.selectedPluginIndex = 0
      this.emitSnapshot()
      return
    }

    if (this.hasUserSelectedPlugin && selectedPluginId >= 0) {
      const nextIndex = this.findPluginIndexById(selectedPluginId)
      if (nextIndex >= 0) {
        this.selectedPluginIndex = nextIndex
        this.emitSnapshot()
        return
      }
    }

    if ((this.selectedResult !== null || this.isQueryingRoads) && selectedPluginId >= 0) {
      const lockedIndex = this.findPluginIndexById(selectedPluginId)
      if (lockedIndex >= 0) {
        this.selectedPluginIndex = lockedIndex
        this.emitSnapshot()
        return
      }
    }

    const matchedIndex = this.findFirstMatchedPluginIndex()
    if (matchedIndex >= 0) {
      this.selectedPluginIndex = matchedIndex
      this.resetRoadQueryState()
      this.emitSnapshot()
      return
    }

    if (this.selectedPluginIndex < 0 || this.selectedPluginIndex >= this.pluginStates.length) {
      this.selectedPluginIndex = 0
    }
    this.emitSnapshot()
  }

  private getSelectedPluginId(): number {
    if (this.selectedPluginIndex < 0 || this.selectedPluginIndex >= this.pluginStates.length) {
      return -1
    }
    return this.pluginStates[this.selectedPluginIndex].pluginId
  }

  private findPluginIndexById(pluginId: number): number {
    for (let i = 0; i < this.pluginStates.length; i++) {
      if (this.pluginStates[i].pluginId === pluginId) {
        return i
      }
    }
    return -1
  }

  private openAliasDialog(): void {
    if (this.getAliasList().length === 1) {
      this.queryCurrentSource(this.getAliasList()[0])
      return
    }
    this.showAliasDialog = true
  }

  private openManualSearchDialog(): void {
    this.manualSearchKeyword = ''
    this.showManualSearchDialog = true
  }

  private getManualSearchKeyboardPadding(): number {
    return this.keyboardAvoidHeight > 0 ? Math.min(this.keyboardAvoidHeight, 260) : 0
  }

  private getManualSearchDialogOffsetY(): number {
    if (this.keyboardAvoidHeight <= 0) {
      return 0
    }
    return -Math.min(this.keyboardAvoidHeight * 0.32, 120)
  }

  private getAliasList(): string[] {
    const list: string[] = []
    const current = this.getCurrentKeyword()
    if (this.animeOriginalName.length > 0 && this.animeOriginalName !== current) {
      list.push(this.animeOriginalName)
    }
    for (let i = 0; i < this.animeAliases.length; i++) {
      const alias = this.animeAliases[i]
      if (alias.length > 0 && alias !== current && list.indexOf(alias) === -1) {
        list.push(alias)
      }
    }
    if (list.length === 0 && this.animeOriginalName.length > 0 && this.animeOriginalName !== this.animeName) {
      list.push(this.animeOriginalName)
    }
    return list
  }

  private async openCaptchaDialog(): Promise<void> {
    if (this.showCaptchaDialog) {
      return
    }
    if (this.selectedPluginIndex < 0 || this.selectedPluginIndex >= this.pluginStates.length) {
      return
    }

    const state = this.pluginStates[this.selectedPluginIndex]
    const rule = await this.ruleStore.getById(state.pluginId)
    if (rule === null) {
      this.searchService.updatePluginErrorById(state.pluginId, '规则源不存在')
      return
    }

    this.prepareCaptchaConfig(rule)
    this.showCaptchaDialog = true
  }

  private prepareCaptchaConfig(rule: RuleSource): void {
    const keyword = this.animeName.length > 0 ? this.animeName : this.animeOriginalName
    const runtime = new RuleRuntimeModel(rule)
    const config = rule.antiCrawlerConfig
    this.captchaUrl = this.resolveCaptchaUrl(config.captchaDetectValue, runtime, keyword)
    this.captchaType = config.captchaType
    this.captchaImage = config.captchaImage
    this.captchaInput = config.captchaInput
    this.captchaScript = config.captchaScript
    this.captchaButton = config.captchaButton
    this.captchaRuleSourceName = rule.name
  }

  private resolveCaptchaUrl(candidate: string, runtime: RuleRuntimeModel, keyword: string): string {
    if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
      return candidate
    }
    return runtime.buildSearchUrl(keyword)
  }

  private restoreFromSnapshot(): boolean {
    const snapshot = this.restoreSnapshot
    if (snapshot === null || snapshot.pluginStates.length === 0) {
      return false
    }
    const restoredStates = this.clonePluginStates(snapshot.pluginStates)
    this.hasUserSelectedPlugin = snapshot.hasUserSelectedPlugin
    this.isSearching = false
    this.isQueryingRoads = false
    this.queryRoadsError = ''
    this.searchService.restoreStates(restoredStates)
    this.pluginStates = restoredStates
    const restoredIndex = this.findPluginIndexById(snapshot.selectedPluginId)
    if (restoredIndex >= 0) {
      this.selectedPluginIndex = restoredIndex
    } else {
      this.selectedPluginIndex = 0
    }
    this.selectedResult = this.cloneSearchResult(snapshot.selectedResult)
    this.emitSnapshot()
    return true
  }

  private emitSnapshot(): void {
    if (!this.onSnapshotChanged) {
      return
    }
    const snapshot = new SourceSheetSnapshot()
    snapshot.pluginStates = this.clonePluginStates(this.pluginStates)
    snapshot.selectedPluginId = this.getSelectedPluginId()
    snapshot.selectedResult = this.cloneSearchResult(this.selectedResult)
    snapshot.hasUserSelectedPlugin = this.hasUserSelectedPlugin
    this.onSnapshotChanged(snapshot)
  }

  private clonePluginStates(states: PluginSearchState[]): PluginSearchState[] {
    const cloned: PluginSearchState[] = []
    for (let i = 0; i < states.length; i++) {
      const src = states[i]
      const state = new PluginSearchState()
      state.pluginId = src.pluginId
      state.pluginName = src.pluginName
      state.status = src.status
      state.errorMessage = src.errorMessage
      state.keyword = src.keyword
      state.searchResults = this.cloneSearchResults(src.searchResults)
      cloned.push(state)
    }
    return cloned
  }

  private cloneSearchResults(results: SearchResultRef[]): SearchResultRef[] {
    const cloned: SearchResultRef[] = []
    for (let i = 0; i < results.length; i++) {
      const result = this.cloneSearchResult(results[i])
      if (result !== null) {
        cloned.push(result)
      }
    }
    return cloned
  }

  private cloneSearchResult(result: SearchResultRef | null): SearchResultRef | null {
    if (result === null) {
      return null
    }
    const cloned = new SearchResultRef()
    cloned.name = result.name
    cloned.url = result.url
    cloned.sourceId = result.sourceId
    cloned.sourceName = result.sourceName
    return cloned
  }

  private onCloseSignalChange(): void {
    this.cancelSearch()
  }

  private cancelSearch(): void {
    this.isClosed = true
    this.selectedResult = null
    this.clearWebRoadFallback()
    this.showCaptchaDialog = false
    this.showAliasDialog = false
    this.showManualSearchDialog = false
    this.searchService.cancel()
  }

  private onPluginSelected(index: number): void {
    if (index < 0 || index >= this.pluginStates.length) {
      return
    }
    this.hasUserSelectedPlugin = true
    if (this.selectedPluginIndex === index) {
      return
    }
    this.selectedPluginIndex = index
    this.resetRoadQueryState()
    this.emitSnapshot()
  }

  private resetRoadQueryState(): void {
    this.roadsRequestToken++
    this.clearWebRoadFallback()
    this.selectedResult = null
    this.isQueryingRoads = false
    this.queryRoadsError = ''
  }

  private returnToMatchedResults(): void {
    this.roadsRequestToken++
    this.clearWebRoadFallback()
    this.selectedResult = null
    this.isQueryingRoads = false
    this.queryRoadsError = ''
    this.emitSnapshot()
  }

  private getCurrentKeyword(): string {
    return this.animeName.length > 0 ? this.animeName : this.animeOriginalName
  }

  private shouldRetryAfterCaptcha(pluginId: number): boolean {
    const states = this.searchService.getPluginStates()
    for (let i = 0; i < states.length; i++) {
      if (states[i].pluginId === pluginId) {
        return states[i].status === 'captcha' || states[i].status === 'noResult'
      }
    }
    return false
  }

  private sleep(delayMs: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, delayMs)
    })
  }
}
