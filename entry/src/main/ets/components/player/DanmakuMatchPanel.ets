import { DanmakuSearchService, DanmakuSearchResult } from '../../core/danmaku/DanmakuSearchService'
import { DanmakuEpisodeInfo } from '../../core/danmaku/DanmakuEpisodeResolver'
import { Logger } from '../../utils/Logger'

const logger = new Logger('DanmakuMatchPanel')

@Component
export struct DanmakuMatchPanel {
  @Prop animeName: string = ''
  @Prop bangumiId: number = 0
  @Prop episodeNo: number = 0
  @Prop currentMappingText: string = ''
  @Prop hasCurrentMapping: boolean = false
  onEpisodeSelected?: (episodeId: number, animeId: number, animeTitle: string, episodeTitle: string) => Promise<boolean>
  onClearCurrentMapping?: () => Promise<boolean>
  onPanelClosed?: () => void

  @State searchKeyword: string = ''
  @State searchResults: DanmakuSearchResult[] = []
  @State episodes: DanmakuEpisodeInfo[] = []
  @State selectedAnimeId: number = 0
  @State selectedAnimeTitle: string = ''
  @State isSearching: boolean = false
  @State isLoadingEpisodes: boolean = false
  @State isLoadingDanmaku: boolean = false
  @State errorMessage: string = ''
  private searchDebounceTimer: number = -1

  aboutToAppear(): void {
    this.searchKeyword = this.animeName
  }

  aboutToDisappear(): void {
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer)
      this.searchDebounceTimer = -1
    }
  }

  build() {
    Column() {
      Row() {
        Text('弹幕匹配')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.hasCurrentMapping) {
        Row() {
          Column() {
            Text('当前手动匹配')
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
            Text(this.currentMappingText)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button('清除')
            .height(32)
            .fontSize(13)
            .margin({ left: 10 })
            .onClick(() => {
              this.clearCurrentMapping()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 10 })
      }

      Row() {
        TextInput({ text: this.searchKeyword, placeholder: '搜索番剧名称' })
          .layoutWeight(1)
          .height(40)
          .onChange((value: string) => {
            this.searchKeyword = value
            this.scheduleSearch(value)
          })
          .onSubmit(() => {
            this.performSearch(this.searchKeyword)
          })

        Button(this.isSearching ? '搜索中' : '搜索')
          .height(40)
          .fontSize(14)
          .padding({ left: 16, right: 16 })
          .enabled(!this.isSearching && this.searchKeyword.trim().length > 0)
          .margin({ left: 8 })
          .onClick(() => {
            this.performSearch(this.searchKeyword)
          })
      }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 8 })

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ bottom: 8 })
      }

      if (this.selectedAnimeId > 0) {
        this.buildEpisodeListView()
      } else {
        this.buildSearchResultView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background_media'))
  }

  @Builder
  buildSearchResultView() {
    if (this.isSearching) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('sys.color.icon_secondary'))
      }
      .width('100%')
      .height(120)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.searchResults.length > 0) {
      List() {
        ForEach(this.searchResults, (item: DanmakuSearchResult, index?: number) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.animeTitle)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.animeType.length > 0) {
                  Text(item.animeType)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .margin({ top: 2 })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.onAnimeSelected(item.animeId, item.animeTitle)
            })
          }
        }, (item: DanmakuSearchResult, index?: number) => `search_${item.animeId}_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider') })
    }
  }

  @Builder
  buildEpisodeListView() {
    Column() {
      Row() {
        Text('< 返回')
          .fontSize(15)
          .fontColor($r('sys.color.font_emphasize'))
          .onClick(() => {
            this.onBackToSearch()
          })
        Text(this.selectedAnimeTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.isLoadingEpisodes) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('sys.color.icon_secondary'))
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.episodes.length > 0) {
        List() {
          ForEach(this.episodes, (item: DanmakuEpisodeInfo, index?: number) => {
            ListItem() {
              Row() {
                Text(item.episodeTitle.length > 0 ? item.episodeTitle : `第${(index ?? 0) + 1}集`)
                  .fontSize(15)
                  .fontColor(item.episodeId > 0 ? $r('sys.color.font_primary') : $r('app.color.text_hint'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (this.isLoadingDanmaku) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color($r('sys.color.icon_secondary'))
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .enabled(item.episodeId > 0 && !this.isLoadingDanmaku)
              .opacity(item.episodeId > 0 ? 1.0 : 0.4)
              .onClick(() => {
                if (item.episodeId > 0 && !this.isLoadingDanmaku) {
                  this.onEpisodeItemClick(item.episodeId, item.episodeTitle)
                }
              })
            }
          }, (item: DanmakuEpisodeInfo, index?: number) => `ep_${item.episodeId}_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider') })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  private scheduleSearch(keyword: string): void {
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer)
      this.searchDebounceTimer = -1
    }
    const trimmed: string = keyword.trim()
    if (trimmed.length === 0) {
      this.searchResults = []
      this.errorMessage = ''
      return
    }
    this.searchDebounceTimer = setTimeout(() => {
      this.performSearch(trimmed)
    }, 500)
  }

  private async performSearch(keyword: string): Promise<void> {
    const trimmed: string = keyword.trim()
    if (trimmed.length === 0 || this.isSearching) {
      return
    }
    this.isSearching = true
    this.errorMessage = ''
    try {
      const results: DanmakuSearchResult[] = await DanmakuSearchService.getInstance().searchAnime(trimmed)
      this.searchResults = results
      if (results.length === 0) {
        this.errorMessage = '未找到相关番剧，请尝试其他关键词'
      }
    } catch (_err) {
      this.searchResults = []
      this.errorMessage = '搜索失败，请检查网络后重试'
    } finally {
      this.isSearching = false
    }
  }

  private async onAnimeSelected(animeId: number, animeTitle: string): Promise<void> {
    this.selectedAnimeId = animeId
    this.selectedAnimeTitle = animeTitle
    this.isLoadingEpisodes = true
    this.errorMessage = ''
    try {
      const episodes: DanmakuEpisodeInfo[] = await DanmakuSearchService.getInstance().fetchEpisodes(animeId)
      this.episodes = episodes
      if (episodes.length === 0) {
        this.errorMessage = '该番剧暂无分集信息'
      }
    } catch (_err) {
      this.errorMessage = '获取分集列表失败，请重试'
      this.selectedAnimeId = 0
    } finally {
      this.isLoadingEpisodes = false
    }
  }

  private async onEpisodeItemClick(episodeId: number, episodeTitle: string): Promise<void> {
    this.isLoadingDanmaku = true
    this.errorMessage = ''
    if (this.onEpisodeSelected) {
      const success = await this.onEpisodeSelected(episodeId, this.selectedAnimeId, this.selectedAnimeTitle, episodeTitle)
      if (!success) {
        this.errorMessage = '弹幕加载失败，请选择其他分集'
        this.isLoadingDanmaku = false
      }
    } else {
      this.isLoadingDanmaku = false
    }
  }

  private async clearCurrentMapping(): Promise<void> {
    if (this.onClearCurrentMapping) {
      const success = await this.onClearCurrentMapping()
      if (!success) {
        this.errorMessage = '清除当前匹配失败'
      }
    }
  }

  private onBackToSearch(): void {
    this.selectedAnimeId = 0
    this.episodes = []
    this.errorMessage = ''
  }

  resetState(): void {
    this.searchKeyword = this.animeName
    this.searchResults = []
    this.episodes = []
    this.selectedAnimeId = 0
    this.selectedAnimeTitle = ''
    this.isSearching = false
    this.isLoadingEpisodes = false
    this.isLoadingDanmaku = false
    this.errorMessage = ''
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer)
      this.searchDebounceTimer = -1
    }
  }
}
