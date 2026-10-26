import { common } from '@kit.AbilityKit'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { BangumiSyncService } from '../../services/BangumiSyncService'
import { HistorySyncService } from '../../services/HistorySyncService'
import {
  getTopSpacerHeight, getBottomSpacerHeight, buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

@Entry
@Component
struct BangumiSyncPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State token: string = ''
  @State immediateToast: boolean = true
  @State priority: number = 0
  @State syncEnabled: boolean = false
  @State loaded: boolean = false
  @State busy: boolean = false
  @State syncing: boolean = false
  @State progressText: string = ''
  @State progressValue: number = 0
  @State progressTotal: number = 0
  private scroller: Scroller = new Scroller()
  private service: BangumiSyncService = BangumiSyncService.getInstance()

  aboutToAppear(): void {
    this.loadConfig()
  }

  onBackPress(): boolean {
    return this.busy
  }

  private async loadConfig(): Promise<void> {
    try {
      const config = await this.service.getConfig()
      this.token = config.token
      this.immediateToast = config.immediateToast
      this.priority = config.priority
      this.syncEnabled = config.enabled
      this.loaded = true
    } catch (err) {
      this.showError(err instanceof Error ? err.message : '配置加载失败')
    }
  }

  private showError(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  private async saveToken(): Promise<void> {
    if (this.busy || !this.loaded) return
    this.busy = true
    try {
      const username = await this.service.saveAndVerify(this.token)
      this.token = this.token.trim()
      this.showError('测试成功，用户名：' + username)
    } catch (err) {
      this.showError(err instanceof Error ? err.message : '验证失败')
    } finally {
      this.syncEnabled = (await this.service.getConfig()).enabled
      this.busy = false
    }
  }

  private async saveOptions(toast: boolean, priority: number): Promise<void> {
    if (this.busy || !this.loaded) return
    this.busy = true
    try {
      await this.service.setOptions(toast, priority)
      this.immediateToast = toast
      this.priority = priority
    } catch (err) {
      this.showError(err instanceof Error ? err.message : '保存失败')
    } finally {
      this.busy = false
    }
  }

  private async syncNow(): Promise<void> {
    if (this.busy || !this.loaded) return
    if (this.token.trim() !== (await this.service.getConfig()).token) {
      this.showError('请先保存并验证修改后的 Token')
      return
    }
    this.busy = true
    this.syncing = true
    this.progressValue = 0
    this.progressTotal = 0
    try {
      const count = await this.service.syncNow((text: string, current: number, total: number) => {
        this.progressText = text
        this.progressValue = current
        this.progressTotal = total
      })
      if (count > 0) HistorySyncService.getInstance().scheduleAutoUploadAfterLocalChange()
      this.showError(count > 0 ? 'Bangumi 同步完成，共处理 ' + count + ' 项状态' : '未发现状态差异，无需同步')
    } catch (err) {
      this.showError(err instanceof Error ? err.message : 'Bangumi 同步失败')
    } finally {
      this.syncing = false
      this.busy = false
    }
  }

  private async openTokenPage(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await context.openLink('https://next.bgm.tv/demo/access-token')
    } catch (err) {
      this.showError('无法打开 Bangumi Token 页面')
    }
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight))
          if (this.loaded) {
            this.AccountSection()
            this.OptionsSection()
            if (this.syncing) {
              Column({ space: 12 }) {
                Text(this.progressText)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                if (this.progressTotal > 0) {
                  Progress({ value: this.progressValue, total: this.progressTotal, type: ProgressType.Linear })
                    .width('100%')
                } else {
                  LoadingProgress().width(28).height(28)
                }
              }
              .width('100%')
              .padding(16)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_background'))
            }
            Button($r('app.string.bangumi_sync_now'))
              .width('100%')
              .enabled(!this.busy && this.syncEnabled)
              .onClick(() => { this.syncNow() })
            Text($r('app.string.bangumi_sync_scope'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          } else {
            LoadingProgress().width(32).height(32)
          }
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight))
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions(this.getUIContext().getHostContext()?.resourceManager
      .getStringSync($r('app.string.bangumi_config_title').id) ?? 'Bangumi', this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(this.busy)
    .backgroundColor($r('app.color.page_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  AccountSection(): void {
    Column({ space: 12 }) {
      Text($r('app.string.bangumi_token_title'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      TextInput({ text: this.token, placeholder: 'Access Token' })
        .type(InputType.Password)
        .enabled(!this.busy)
        .onChange((value: string) => { this.token = value })
      Button($r('app.string.bangumi_save_verify'))
        .enabled(!this.busy)
        .width('100%')
        .onClick(() => { this.saveToken() })
      Text($r('app.string.bangumi_get_token'))
        .fontSize(13)
        .fontColor($r('app.color.accent_blue'))
        .onClick(() => { this.openTokenPage() })
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  OptionsSection(): void {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.bangumi_toast_title')).fontSize(16).fontColor($r('app.color.text_primary'))
          Text($r('app.string.bangumi_toast_desc')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.immediateToast })
          .enabled(!this.busy)
          .onChange((value: boolean) => { this.saveOptions(value, this.priority) })
      }.width('100%')
      Divider().color($r('app.color.divider_color'))
      Text($r('app.string.bangumi_priority_title')).fontSize(16).fontColor($r('app.color.text_primary'))
      Text($r('app.string.bangumi_priority_desc')).fontSize(12).fontColor($r('app.color.text_secondary'))
      Row({ space: 12 }) {
        Button($r('app.string.bangumi_local_first'))
          .type(ButtonType.Normal)
          .backgroundColor(this.priority === 0 ? $r('app.color.accent_blue') : $r('app.color.card_background'))
          .fontColor(this.priority === 0 ? Color.White : $r('app.color.text_primary'))
          .layoutWeight(1)
          .enabled(!this.busy)
          .onClick(() => { this.saveOptions(this.immediateToast, 0) })
        Button($r('app.string.bangumi_remote_first'))
          .type(ButtonType.Normal)
          .backgroundColor(this.priority === 1 ? $r('app.color.accent_blue') : $r('app.color.card_background'))
          .fontColor(this.priority === 1 ? Color.White : $r('app.color.text_primary'))
          .layoutWeight(1)
          .enabled(!this.busy)
          .onClick(() => { this.saveOptions(this.immediateToast, 1) })
      }.width('100%')
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }
}
