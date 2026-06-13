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
  @State captchaScript: string = ''
  @State captchaButton: string = ''
  @State captchaRuleSourceName: string = ''
  @Prop animeName: string = ''
  @Prop animeOriginalName: string = ''
  @Prop @Watch('onCloseSignalChange') closeSignal: number = 0
  private searchService: PluginSearchService = new PluginSearchService()
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private isClosed: boolean = false
  private roadsRequestToken: number = 0
  onRoadsReady?: ((source: PlaybackSource) => void)
  onOpenExternal?: () => void

  aboutToAppear(): void {
    this.isClosed = false
    this.searchService.setOnStateChange((states: PluginSearchState[]) => {
      if (!this.isClosed) {
        this.pluginStates = states
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
        Row() {
          Text('选择播放源')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)

          if (this.onOpenExternal) {
            Button() {
              SymbolGlyph($r('sys.symbol.share'))
                .fontSize(16)
                .fontColor([$r('app.color.text_secondary')])
            }
              .width(32)
              .height(32)
              .backgroundColor($r('app.color.button_ghost_bg'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: $r('app.color.border_subtle') })
              .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
              .borderRadius(16)
              .onClick(() => {
                if (this.onOpenExternal) {
                  this.onOpenExternal()
                }
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        if (this.pluginStates.length > 0) {
          Scroll() {
            Row() {
              ForEach(this.pluginStates, (state: PluginSearchState, index?: number) => {
                Column() {
                  Row() {
                    Text(state.pluginName)
                      .fontSize(13)
                      .fontColor(index === this.selectedPluginIndex ? $r('app.color.tab_icon_selected') : $r('app.color.text_secondary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Circle()
                      .width(8)
                      .height(8)
                      .fill(state.getStatusColor())
                      .margin({ left: 6 })
                  }
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(8)
                .backgroundColor(index === this.selectedPluginIndex ? $r('app.color.card_background') : $r('app.color.color_transparent'))
                .backgroundBlurStyle(index === this.selectedPluginIndex ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
                .border({ width: 0.5, color: index === this.selectedPluginIndex ? $r('app.color.border_specular') : $r('app.color.color_transparent') })
                .shadow({
                  radius: index === this.selectedPluginIndex ? 10 : 0,
                  color: $r('app.color.shadow_button_primary'),
                  offsetY: index === this.selectedPluginIndex ? 3 : 0
                })
                .onClick(() => {
                  if (index !== undefined) {
                    this.onPluginSelected(index)
                  }
                })
              }, (state: PluginSearchState, index?: number) => `tab_${state.pluginId}_${index}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .padding({ left: 16, right: 16 })
        }

        Divider().margin({ top: 4, bottom: 4 })

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

      if (this.showCaptchaDialog) {
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.overlay_topbar_bg'))

        CaptchaDialog({
          captchaUrl: this.captchaUrl,
          captchaType: this.captchaType,
          captchaScript: this.captchaScript,
          captchaButton: this.captchaButton,
          ruleSourceName: this.captchaRuleSourceName,
          onVerified: () => {
            this.showCaptchaDialog = false
            this.retryCurrentPlugin()
          },
          onCancelled: () => {
            this.showCaptchaDialog = false
            this.searchService.updatePluginError(this.selectedPluginIndex, '验证取消或超时，可重试')
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PluginContentArea() {
    if (this.pluginStates[this.selectedPluginIndex].status === 'pending') {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.text_secondary'))
        Text('搜索中...')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.pluginStates[this.selectedPluginIndex].status === 'success') {
      if (this.isQueryingRoads) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.text_secondary'))
          Text('获取播放线路中...')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.queryRoadsError.length > 0) {
        Column() {
          Text(this.queryRoadsError)
            .fontSize(14)
            .fontColor($r('app.color.text_error'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 16, left: 16, right: 16 })
          Button('重试')
            .fontSize(13)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
            .onClick(() => {
              if (this.selectedResult !== null) {
                this.onSearchResultSelected(this.selectedResult)
              }
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.pluginStates[this.selectedPluginIndex].searchResults, (result: SearchResultRef, index?: number) => {
            ListItem() {
              Row() {
                Text(result.name)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                this.onSearchResultSelected(result)
              })
            }
          }, (result: SearchResultRef, index?: number) => `result_${result.sourceId}_${index}`)
        }
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider_color') })
        .layoutWeight(1)
      }
    } else if (this.pluginStates[this.selectedPluginIndex].status === 'noResult') {
      Column() {
        Text('无结果')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 16 })
        Row() {
          Button('别名检索')
            .fontSize(13)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
            .margin({ right: 12 })
            .onClick(() => {
              this.retryWithAlias()
            })
          Button('手动检索')
            .fontSize(13)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
            .onClick(() => {
              logger.info('Manual search requested')
            })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.pluginStates[this.selectedPluginIndex].status === 'captcha') {
      Column() {
        Text('需要验证码验证')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 16 })
        Row() {
          Button('进行验证')
            .fontSize(13)
            .backgroundColor($r('app.color.button_info_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_button_info'), offsetY: 4 })
            .margin({ right: 12 })
            .onClick(() => {
              this.openCaptchaDialog()
            })
          Button('重试')
            .fontSize(13)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(18)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
            .onClick(() => {
              this.retryCurrentPlugin()
            })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.pluginStates[this.selectedPluginIndex].status === 'error') {
      Column() {
        Text(this.pluginStates[this.selectedPluginIndex].errorMessage.length > 0 ? this.pluginStates[this.selectedPluginIndex].errorMessage : '检索失败')
          .fontSize(15)
          .fontColor($r('app.color.text_error'))
          .margin({ bottom: 16 })
        Button('重试')
          .fontSize(13)
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(18)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .onClick(() => {
            this.retryCurrentPlugin()
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
  }

  private async startSearch(): Promise<void> {
    let keyword = this.animeName.length > 0 ? this.animeName : this.animeOriginalName
    if (keyword.length === 0) {
      return
    }
    this.isSearching = true
    this.resetRoadQueryState()
    await this.searchService.searchAll(keyword)
    if (!this.isClosed) {
      this.isSearching = false
    }
  }

  private async onSearchResultSelected(result: SearchResultRef): Promise<void> {
    if (this.isClosed) {
      return
    }
    const requestToken = ++this.roadsRequestToken
    const requestPluginIndex = this.selectedPluginIndex
    this.selectedResult = result
    this.isQueryingRoads = true
    this.queryRoadsError = ''
    try {
      const source = await this.searchService.queryRoads(result)
      if (this.isClosed || !this.isCurrentRoadsRequest(requestToken, requestPluginIndex)) {
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
      if (this.isClosed || !this.isCurrentRoadsRequest(requestToken, requestPluginIndex)) {
        return
      }
      this.queryRoadsError = err instanceof Error ? err.message : '获取线路异常'
      logger.error('Query roads exception: %{public}s', this.queryRoadsError)
    } finally {
      if (!this.isClosed && this.isCurrentRoadsRequest(requestToken, requestPluginIndex)) {
        this.isQueryingRoads = false
      }
    }
  }

  private async retryCurrentPlugin(): Promise<void> {
    if (this.isClosed) {
      return
    }
    this.resetRoadQueryState()
    let keyword = this.animeName.length > 0 ? this.animeName : this.animeOriginalName
    await this.searchService.retryPlugin(this.selectedPluginIndex, keyword)
  }

  private async retryWithAlias(): Promise<void> {
    if (this.animeOriginalName.length > 0 && this.animeOriginalName !== this.animeName) {
      this.isSearching = true
      this.resetRoadQueryState()
      await this.searchService.searchAll(this.animeOriginalName)
      if (!this.isClosed) {
        this.isSearching = false
      }
    }
  }

  private async openCaptchaDialog(): Promise<void> {
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
    this.roadsRequestToken++
    this.showCaptchaDialog = false
    this.searchService.cancel()
  }

  private onPluginSelected(index: number): void {
    if (index < 0 || index >= this.pluginStates.length) {
      return
    }
    if (this.selectedPluginIndex === index) {
      return
    }
    this.selectedPluginIndex = index
    this.resetRoadQueryState()
  }

  private resetRoadQueryState(): void {
    this.roadsRequestToken++
    this.selectedResult = null
    this.isQueryingRoads = false
    this.queryRoadsError = ''
  }

  private isCurrentRoadsRequest(requestToken: number, requestPluginIndex: number): boolean {
    return requestToken === this.roadsRequestToken && requestPluginIndex === this.selectedPluginIndex
  }
}
