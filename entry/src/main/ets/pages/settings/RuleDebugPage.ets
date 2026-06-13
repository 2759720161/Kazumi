import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { SearchExecutor } from '../../core/engine/SearchExecutor'
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel'
import { AnimeItem } from '../../models/AnimeItem'
import { HttpClient } from '../../network/HttpClient'
import { RequestConfig } from '../../network/RequestConfig'
import { Logger } from '../../utils/Logger'
import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'

const logger = new Logger('RuleDebugPage')

@Entry
@Component
export struct RuleDebugPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State rules: RuleSource[] = []
  @State selectedRuleIndex: number = -1
  @State testKeyword: string = ''
  @State debugLog: string = ''
  @State isRunning: boolean = false
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private searchExecutor: SearchExecutor = new SearchExecutor()
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

          this.RuleSelectorSection()
          this.TestInputSection()
          this.ActionSection()
          this.LogSection()

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .titleBar(buildTitleBarOptions('规则调试'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private RuleSelectorSection() {
    Column() {
      Text('选择规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      if (this.rules.length === 0) {
        Text('暂无可用规则')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 16, bottom: 8 })
      } else {
        List() {
          ForEach(this.rules, (rule: RuleSource, index?: number) => {
            ListItem() {
              Row() {
                Radio({ value: String(rule.id), group: 'ruleSelect' })
                  .checked(index === this.selectedRuleIndex)
                  .onChange((isChecked: boolean) => {
                    if (isChecked && index !== undefined) {
                      this.selectedRuleIndex = index
                    }
                  })

                Column() {
                  Text(rule.name)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))

                  Text(rule.baseUrl)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .margin({ left: 8 })

                Text(rule.enabled ? '启用' : '禁用')
                  .fontSize(11)
                  .fontColor(rule.enabled ? $r('app.color.status_success') : $r('app.color.text_secondary'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            }
          }, (rule: RuleSource) => String(rule.id))
        }
        .width('100%')
        .height(Math.min(this.rules.length * 56, 280))
      }
    }
    .width('100%')
  }

  @Builder
  private TestInputSection() {
    Column() {
      Text('测试关键词')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      TextInput({ placeholder: '输入搜索关键词', text: this.testKeyword })
        .width('100%')
        .height(40)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.testKeyword = value
        })
        .onSubmit(() => {
          this.runTest()
        })
    }
    .width('100%')
  }

  @Builder
  private ActionSection() {
    Row() {
      Button(this.isRunning ? '测试中...' : '运行测试')
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.button_primary_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .shadow({ radius: 12, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
        .enabled(!this.isRunning && this.selectedRuleIndex >= 0 && this.testKeyword.trim().length > 0)
        .layoutWeight(1)
        .onClick(() => {
          this.runTest()
        })

      Button('清空日志')
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.button_ghost_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .margin({ left: 8 })
        .onClick(() => {
          this.debugLog = ''
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private LogSection() {
    Column() {
      Text('调试日志')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Scroll() {
        Text(this.debugLog.length > 0 ? this.debugLog : '暂无日志')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .fontFamily('monospace')
          .width('100%')
          .padding(12)
      }
      .width('100%')
      .height(300)
      .borderRadius(8)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
      .margin({ left: 16, right: 16 })
    }
    .width('100%')
  }

  private async loadRules(): Promise<void> {
    try {
      this.rules = await this.ruleSourceStore.getAll()
      if (this.rules.length > 0) {
        this.selectedRuleIndex = 0
      }
    } catch (err) {
      logger.error('Load rules failed: %{public}s', JSON.stringify(err))
    }
  }

  private appendLog(msg: string): void {
    const timestamp = new Date().toLocaleTimeString()
    this.debugLog = this.debugLog + `[${timestamp}] ${msg}\n`
  }

  private async runTest(): Promise<void> {
    if (this.selectedRuleIndex < 0 || this.selectedRuleIndex >= this.rules.length) {
      return
    }
    const keyword = this.testKeyword.trim()
    if (keyword.length === 0) {
      return
    }

    this.isRunning = true
    this.debugLog = ''
    const rule = this.rules[this.selectedRuleIndex]
    this.appendLog(`开始测试规则: ${rule.name}`)
    this.appendLog(`BaseURL: ${rule.baseUrl}`)
    this.appendLog(`SearchURL: ${rule.searchURL}`)
    this.appendLog(`Keyword: ${keyword}`)

    try {
      const runtime = new RuleRuntimeModel(rule)
      const searchUrl = runtime.buildSearchUrl(keyword)
      this.appendLog(`FullSearchURL: ${searchUrl}`)

      this.appendLog('正在请求搜索页面...')
      const client = new HttpClient()
      const headers = runtime.getSearchHeaders()
      const config = RequestConfig.createGet(searchUrl, headers)
      config.timeout = 15000
      const response = await client.request(config)
      this.appendLog(`HTTP响应: ${response.statusCode}, body长度: ${response.body.length}`)

      if (!response.isSuccessful) {
        this.appendLog(`请求失败: HTTP ${response.statusCode}`)
        return
      }

      this.appendLog('正在解析搜索结果...')
      const results: AnimeItem[] = this.searchExecutor.parseSearchResults(response.body, runtime)

      this.appendLog(`搜索完成，找到 ${results.length} 个结果`)
      for (let i = 0; i < Math.min(results.length, 5); i++) {
        const item = results[i]
        this.appendLog(`  [${i + 1}] ${item.name} | ${item.url}`)
      }
      if (results.length > 5) {
        this.appendLog(`  ... 还有 ${results.length - 5} 个结果`)
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.appendLog(`搜索失败: ${msg}`)
      logger.error('Rule debug test failed: %{public}s', msg)
    } finally {
      this.isRunning = false
    }
  }
}