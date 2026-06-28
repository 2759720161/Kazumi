import { RuleSource } from '../../models/RuleSource'
import { RuleRuntimeModel } from '../../models/RuleRuntimeModel'
import { PluginSearchState, SearchResultRef } from '../../models/PluginSearchState'
import { PlaybackRoad, PlaybackSource } from '../../models/PlaybackRoad'
import { RuleSourceStore } from '../../store/RuleSourceStore'
import { SearchExecutor } from './SearchExecutor'
import { RequestPolicyHandler } from './RequestPolicyHandler'
import { AntiCrawlHandler } from './AntiCrawlHandler'
import { Logger } from '../../utils/Logger'

const logger = new Logger('PluginSearchService')

const SEARCH_CONCURRENCY = 4

export class PluginSearchService {
  private ruleStore: RuleSourceStore = new RuleSourceStore()
  private searchExecutor: SearchExecutor = new SearchExecutor()
  private requestHandler: RequestPolicyHandler = new RequestPolicyHandler()
  private antiCrawlHandler: AntiCrawlHandler = new AntiCrawlHandler()
  private pluginStates: PluginSearchState[] = []
  private onStateChange: ((states: PluginSearchState[]) => void) | null = null
  private searchEpoch: number = 0

  setOnStateChange(callback: (states: PluginSearchState[]) => void): void {
    this.onStateChange = callback
  }

  cancel(): void {
    this.searchEpoch++
  }

  getPluginStates(): PluginSearchState[] {
    return this.pluginStates
  }

  async searchAll(keyword: string): Promise<void> {
    const currentEpoch = ++this.searchEpoch
    const enabledRules = await this.ruleStore.getEnabled()
    if (this.searchEpoch !== currentEpoch) {
      return
    }
    if (enabledRules.length === 0) {
      logger.warn('No enabled rule sources')
      this.pluginStates = []
      this.notifyStateChange(currentEpoch)
      return
    }

    this.pluginStates = []
    for (let i = 0; i < enabledRules.length; i++) {
      this.pluginStates.push(PluginSearchState.pending(enabledRules[i].id, enabledRules[i].name))
    }
    this.notifyStateChange(currentEpoch)

    let nextIndex = 0
    const runWorker = async (): Promise<void> => {
      while (this.searchEpoch === currentEpoch) {
        const idx = nextIndex++
        if (idx >= enabledRules.length) {
          return
        }
        await this.searchByPlugin(idx, enabledRules[idx], keyword, currentEpoch)
      }
    }
    const workers: Promise<void>[] = []
    const concurrency = Math.min(SEARCH_CONCURRENCY, enabledRules.length)
    for (let i = 0; i < concurrency; i++) {
      workers.push(runWorker())
    }
    await Promise.all(workers)

    if (this.searchEpoch !== currentEpoch) {
      return
    }
    this.sortCompletedStates()
    this.notifyStateChange(currentEpoch)
  }

  async searchByPlugin(stateIndex: number, rule: RuleSource, keyword: string, epoch: number): Promise<void> {
    if (this.searchEpoch !== epoch) {
      return
    }
    try {
      const runtime = new RuleRuntimeModel(rule)
      const html = await this.requestHandler.fetchWithRule(runtime, keyword)
      if (this.searchEpoch !== epoch) {
        return
      }

      if (runtime.hasAntiCrawler && this.antiCrawlHandler.isCaptchaResponse(html)) {
        logger.warn('Captcha detected for rule %{public}s', rule.name)
        this.updateState(stateIndex, PluginSearchState.captcha(rule.id, rule.name, '需要验证码验证'), epoch)
        return
      }

      const results = this.searchExecutor.parseSearchResults(html, runtime)
      if (this.searchEpoch !== epoch) {
        return
      }
      if (results.length === 0) {
        this.updateState(stateIndex, PluginSearchState.noResult(rule.id, rule.name), epoch)
        return
      }

      const refs: SearchResultRef[] = []
      for (let i = 0; i < results.length; i++) {
        const ref = new SearchResultRef()
        ref.name = results[i].name
        ref.url = results[i].url
        ref.sourceId = rule.id
        ref.sourceName = rule.name
        refs.push(ref)
      }
      this.updateState(stateIndex, PluginSearchState.success(rule.id, rule.name, refs), epoch)
    } catch (err) {
      if (this.searchEpoch !== epoch) {
        return
      }
      const msg = this.normalizeErrorMessage(err instanceof Error ? err.message : String(err))
      logger.error('Search failed for rule %{public}s: %{public}s', rule.name, msg)
      this.updateState(stateIndex, PluginSearchState.error(rule.id, rule.name, msg), epoch)
    }
  }

  async querySource(pluginId: number, keyword: string): Promise<void> {
    const currentEpoch = ++this.searchEpoch
    const stateIndex = this.pluginStates.findIndex((s: PluginSearchState) => s.pluginId === pluginId)
    if (stateIndex === -1) {
      return
    }
    const state = this.pluginStates[stateIndex]
    const rule = await this.ruleStore.getById(pluginId)
    if (this.searchEpoch !== currentEpoch) {
      return
    }
    if (rule === null) {
      this.updateState(stateIndex, PluginSearchState.error(pluginId, state.pluginName, '规则源不存在'), currentEpoch)
      return
    }
    this.updateState(stateIndex, PluginSearchState.pending(pluginId, state.pluginName), currentEpoch)
    await this.searchByPlugin(stateIndex, rule, keyword, currentEpoch)
  }

  async retryPlugin(stateIndex: number, keyword: string): Promise<void> {
    if (stateIndex < 0 || stateIndex >= this.pluginStates.length) {
      return
    }
    const currentEpoch = ++this.searchEpoch
    const state = this.pluginStates[stateIndex]
    const rule = await this.ruleStore.getById(state.pluginId)
    if (this.searchEpoch !== currentEpoch) {
      return
    }
    if (rule === null) {
      return
    }
    this.updateState(stateIndex, PluginSearchState.pending(rule.id, rule.name), currentEpoch)
    await this.searchByPlugin(stateIndex, rule, keyword, currentEpoch)
  }

  updatePluginError(index: number, message: string): void {
    if (index < 0 || index >= this.pluginStates.length) {
      return
    }
    const state = this.pluginStates[index]
    this.pluginStates[index] = PluginSearchState.error(state.pluginId, state.pluginName, message)
    this.notifyStateChange(this.searchEpoch)
  }

  async queryRoads(searchRef: SearchResultRef): Promise<PlaybackSource> {
    const currentEpoch = this.searchEpoch
    const source = new PlaybackSource()
    source.name = searchRef.sourceName
    source.sourceId = searchRef.sourceId
    source.animeUrl = searchRef.url
    source.status = 'pending'

    const rule = await this.ruleStore.getById(searchRef.sourceId)
    if (this.searchEpoch !== currentEpoch) {
      source.status = 'error'
      source.message = '请求已取消'
      return source
    }
    if (rule === null) {
      source.status = 'error'
      source.message = '规则源不存在'
      return source
    }

    try {
      const runtime = new RuleRuntimeModel(rule)
      const html = await this.requestHandler.fetchUrlWithRuleHeaders(runtime, searchRef.url)
      if (this.searchEpoch !== currentEpoch) {
        source.status = 'error'
        source.message = '请求已取消'
        return source
      }
      const roads = this.searchExecutor.parseRoads(html, runtime)

      if (roads.length === 0) {
        source.status = 'empty'
        source.message = '无剧集'
        return source
      }

      for (let i = 0; i < roads.length; i++) {
        for (let j = 0; j < roads[i].episodes.length; j++) {
          roads[i].episodes[j].sourceId = rule.id
          roads[i].episodes[j].sourceName = rule.name
          roads[i].episodes[j].animeUrl = searchRef.url
        }
      }

      source.roads = roads
      source.status = 'success'
    } catch (err) {
      if (this.searchEpoch !== currentEpoch) {
        source.status = 'error'
        source.message = '请求已取消'
        return source
      }
      source.status = 'error'
      source.message = this.normalizeErrorMessage(err instanceof Error ? err.message : '解析失败')
    }

    return source
  }

  private normalizeErrorMessage(message: string): string {
    const text = message.toLowerCase()
    if (text.indexOf('timeout') !== -1 ||
      text.indexOf('timed out') !== -1 ||
      text.indexOf('curl_code=28') !== -1 ||
      text.indexOf('2300028') !== -1 ||
      text.indexOf('http 0') !== -1) {
      return '搜索超时，可重试'
    }
    return message
  }

  private updateState(index: number, state: PluginSearchState, epoch: number): void {
    if (this.searchEpoch !== epoch) {
      return
    }
    if (index >= 0 && index < this.pluginStates.length) {
      this.pluginStates[index] = state
      this.notifyStateChange(epoch)
    }
  }

  private notifyStateChange(epoch: number): void {
    if (this.searchEpoch !== epoch) {
      return
    }
    if (this.onStateChange) {
      this.onStateChange(this.pluginStates.slice())
    }
  }

  private sortCompletedStates(): void {
    const originalStates = this.pluginStates.slice()
    this.pluginStates.sort((a: PluginSearchState, b: PluginSearchState): number => {
      const priorityDiff = this.getCompletedStatePriority(a) - this.getCompletedStatePriority(b)
      if (priorityDiff !== 0) {
        return priorityDiff
      }
      return originalStates.indexOf(a) - originalStates.indexOf(b)
    })
  }

  private getCompletedStatePriority(state: PluginSearchState): number {
    if (state.searchResults.length > 0) {
      return 0
    }
    if (state.status === 'captcha') {
      return 1
    }
    return 2
  }
}
