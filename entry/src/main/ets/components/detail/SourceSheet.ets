import { PluginSearchState, SearchResultRef } from '../../models/PluginSearchState'
import { PlaybackSource } from '../../models/PlaybackRoad'
import { PluginSearchService } from '../../core/engine/PluginSearchService'
import { CaptchaDialog } from './CaptchaDialog'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel'
import { RuleSource } from '../../models/RuleSource'
import { Logger } from '../../utils/Logger'

const logger = new Logger('SourceSheet')

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
  @State showKeywordMenu: boolean = false
  @Prop animeName: string = ''
  @Prop animeOriginalName: string = ''
  @Prop animeAliases: string[] = []
  @Prop @Watch('onCloseSignalChange') closeSignal: number = 0
  private searchService: PluginSearchService = new PluginSearchService()
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private isClosed: boolean = false
  private captchaRetrying: boolean = false
  private hasUserSelectedPlugin: boolean = false
  onRoadsReady?: ((source: PlaybackSource) => void)
  onOpenExternal?: () => void

  aboutToAppear(): void {
    this.isClosed = false
    this.searchService.setOnStateChange((states: PluginSearchState[]) => {
      if (!this.isClosed) {
        this.applyPluginStates(states)
      }
    })
    this.startSearch()
  }

  aboutToDisappear(): void {
    this.cancelSearch()
  }

  build() {
    Stack() {
      Column() {
        this.CompactHeader()
        this.SourceChips()

        if (this.pluginStates.length > 0 && this.selectedPluginIndex < this.pluginStates.length) {
          this.PluginContentArea()
        } else {
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
            this.searchService.updatePluginError(this.selectedPluginIndex, '验证取消或超时，可重试')
          }
        })
      }

      if (this.showAliasDialog) {
        this.AliasDialogOverlay()
      }

      if (this.showManualSearchDialog) {
        this.ManualSearchDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
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
            Text('换关键词')
              .fontSize(12)
              .fontColor($r('app.color.accent_blue'))
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.onOpenExternal !== undefined) {
          Button() {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(22)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor($r('app.color.surface_button_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
          .margin({ left: 10 })
          .onClick(() => {
            if (this.onOpenExternal) {
              this.onOpenExternal()
            }
          })
        }
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
        .borderRadius(10)
        .backgroundColor($r('app.color.button_ghost_bg'))

        Row() {
          Text(`${this.pluginStates.length} 源`)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
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
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor($r('app.color.button_ghost_bg'))
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 8 })
    .bindPopup(this.showKeywordMenu, {
      builder: this.KeywordMenuContent,
      placement: Placement.Bottom,
      showInSubWindow: false,
      onStateChange: (e: PopupStateChangeParam) => {
        if (!e.isVisible) {
          this.showKeywordMenu = false
        }
      }
    })
  }

  @Builder
  private KeywordMenuContent(): void {
    Column() {
      if (this.animeOriginalName.length > 0 && this.animeOriginalName !== this.getCurrentKeyword()) {
        Text('使用原名')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .height(48)
          .padding({ left: 18, right: 18 })
          .textAlign(TextAlign.Start)
          .borderRadius(12)
          .onClick(() => {
            this.showKeywordMenu = false
            this.queryCurrentSource(this.animeOriginalName)
          })
      }

      if (this.getAliasList().length > 0) {
        Text('使用别名')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .height(48)
          .padding({ left: 18, right: 18 })
          .textAlign(TextAlign.Start)
          .borderRadius(12)
          .onClick(() => {
            this.showKeywordMenu = false
            this.openAliasDialog()
          })
      }

      Text('手动输入')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .height(48)
        .padding({ left: 18, right: 18 })
        .textAlign(TextAlign.Start)
        .borderRadius(12)
        .onClick(() => {
          this.showKeywordMenu = false
          this.openManualSearchDialog()
        })
    }
    .width(160)
    .padding(6)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 8 })
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
    .padding({ left: 14, right: 10 })
    .borderRadius(19)
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
    if (this.hasSearchResults(this.pluginStates[this.selectedPluginIndex])) {
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
        Scroll() {
          Column() {
            ForEach(this.pluginStates[this.selectedPluginIndex].searchResults, (result: SearchResultRef, index?: number) => {
              this.ResultCard(result)
            }, (result: SearchResultRef, index?: number) => `result_${result.sourceId}_${index}`)

            this.SupplementarySearchEntry()
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
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

      Button('解析播放')
        .fontSize(13)
        .height(32)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.button_accent_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .fontColor($r('app.color.text_on_primary'))
        .borderRadius(16)
        .shadow({ radius: 8, color: $r('app.color.shadow_button_accent'), offsetY: 2 })
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
    .margin({ bottom: 10 })
    .onClick(() => {
      this.onSearchResultSelected(result)
    })
  }

  @Builder
  private SupplementarySearchEntry(): void {
    Row() {
      Text('仍未找到？')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Button('别名检索')
        .fontSize(12)
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.button_ghost_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .fontColor($r('app.color.text_secondary'))
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
        .backgroundColor($r('app.color.button_accent_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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
      Button('重试解析')
        .fontSize(14)
        .height(42)
        .padding({ left: 22, right: 22 })
        .backgroundColor($r('app.color.button_accent_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .fontColor($r('app.color.text_on_primary'))
        .borderRadius(21)
        .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
        .margin({ top: 18 })
        .onClick(() => {
          if (this.selectedResult !== null) {
            this.onSearchResultSelected(this.selectedResult)
          }
        })
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
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(21)
          .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .margin({ right: 12 })
          .onClick(() => {
            this.openAliasDialog()
          })
        Button('手动检索')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
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
          .margin({ right: 12 })
          .onClick(() => {
            this.retryCurrentPlugin()
          })
        Button('手动检索')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
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
          .margin({ right: 12 })
          .onClick(() => {
            this.openCaptchaDialog()
          })
        Button('换个源')
          .fontSize(14)
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
          .onClick(() => {
            this.switchToNextPlugin()
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
          .margin({ right: 10 })
          .onClick(() => {
            this.retryCurrentPlugin()
          })
        Button('别名检索')
          .fontSize(14)
          .height(42)
          .padding({ left: 18, right: 18 })
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
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
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_secondary'))
          .borderRadius(21)
          .border({ width: 0.5, color: $r('app.color.border_subtle') })
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
      .width('85%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.border_specular') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 6 })
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

    Column() {
      Column() {
        Text('手动检索')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 16 })

        TextInput({ text: this.manualSearchKeyword, placeholder: '输入搜索关键词' })
          .fontSize(14)
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(8)
          .backgroundColor($r('app.color.card_background'))
          .onChange((value: string) => {
            this.manualSearchKeyword = value
          })
          .margin({ bottom: 16 })

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
            .margin({ right: 8 })
            .onClick(() => {
              this.showManualSearchDialog = false
            })
          Button('搜索')
            .fontSize(13)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
            .layoutWeight(1)
            .enabled(this.manualSearchKeyword.trim().length > 0)
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
      .width('85%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .shadow({ radius: 20, color: $r('app.color.shadow_surface'), offsetY: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
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
    const currentResult = result
    this.selectedResult = result
    this.isQueryingRoads = true
    this.queryRoadsError = ''
    try {
      const source = await this.searchService.queryRoads(result)
      if (this.isClosed || this.selectedResult !== currentResult) {
        return
      }
      if (source.status === 'error') {
        this.queryRoadsError = source.message.length > 0 ? source.message : '获取线路失败'
        logger.error('Query roads failed for %{public}s: %{public}s', result.name, this.queryRoadsError)
      } else if (source.status === 'empty') {
        this.queryRoadsError = '该源无可用剧集'
      } else if (this.onRoadsReady) {
        this.onRoadsReady(source)
      }
    } catch (err) {
      if (this.isClosed || this.selectedResult !== currentResult) {
        return
      }
      this.queryRoadsError = err instanceof Error ? err.message : '获取线路异常'
      logger.error('Query roads exception: %{public}s', this.queryRoadsError)
    } finally {
      if (!this.isClosed && this.selectedResult === currentResult) {
        this.isQueryingRoads = false
      }
    }
  }

  private async retryCurrentPlugin(afterCaptcha: boolean = false): Promise<void> {
    if (this.isClosed) {
      return
    }
    if (this.captchaRetrying) {
      return
    }
    this.captchaRetrying = true
    this.resetRoadQueryState()
    this.isSearching = true
    const keyword = this.getCurrentKeyword()
    const maxAttempts = afterCaptcha ? 3 : 1
    try {
      for (let attempt = 0; attempt < maxAttempts; attempt++) {
        if (this.isClosed) {
          return
        }
        if (afterCaptcha) {
          const delayMs = attempt === 0 ? 1200 : 2200
          logger.info('Retry plugin after captcha, attempt=%{public}d/%{public}d, delay=%{public}d',
            attempt + 1, maxAttempts, delayMs)
          await this.sleep(delayMs)
        }
        await this.searchService.retryPlugin(this.selectedPluginIndex, keyword)
        if (!afterCaptcha || !this.shouldRetryAfterCaptcha()) {
          return
        }
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
      return
    }

    if (this.hasUserSelectedPlugin && selectedPluginId >= 0) {
      const nextIndex = this.findPluginIndexById(selectedPluginId)
      if (nextIndex >= 0) {
        this.selectedPluginIndex = nextIndex
        return
      }
    }

    const matchedIndex = this.findFirstMatchedPluginIndex()
    if (matchedIndex >= 0) {
      this.selectedPluginIndex = matchedIndex
      this.resetRoadQueryState()
      return
    }

    if (this.selectedPluginIndex < 0 || this.selectedPluginIndex >= this.pluginStates.length) {
      this.selectedPluginIndex = 0
    }
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
      this.searchService.updatePluginError(this.selectedPluginIndex, '规则源不存在')
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

  private onCloseSignalChange(): void {
    this.cancelSearch()
  }

  private cancelSearch(): void {
    this.isClosed = true
    this.selectedResult = null
    this.showCaptchaDialog = false
    this.showAliasDialog = false
    this.showManualSearchDialog = false
    this.showKeywordMenu = false
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
  }

  private resetRoadQueryState(): void {
    this.selectedResult = null
    this.isQueryingRoads = false
    this.queryRoadsError = ''
  }

  private getCurrentKeyword(): string {
    return this.animeName.length > 0 ? this.animeName : this.animeOriginalName
  }

  private shouldRetryAfterCaptcha(): boolean {
    const states = this.searchService.getPluginStates()
    if (this.selectedPluginIndex < 0 || this.selectedPluginIndex >= states.length) {
      return false
    }
    const state = states[this.selectedPluginIndex]
    return state.status === 'captcha' || state.status === 'noResult'
  }

  private sleep(delayMs: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, delayMs)
    })
  }
}
