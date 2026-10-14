import { promptAction } from '@kit.ArkUI'
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
import { WebDavConfig } from '../../network/WebDavClient'
import {
  HistorySyncService,
  WEBDAV_SYNC_AUTO_KEY,
  WEBDAV_SYNC_COLLECT_KEY,
  WEBDAV_SYNC_ENABLED_KEY,
  WEBDAV_SYNC_LAST_TIME_KEY
} from '../../services/HistorySyncService'
import { PreferencesStore } from '../../store/PreferencesStore'
import { Logger } from '../../utils/Logger'

const logger = new Logger('WebDavSyncPage')

@Entry
@Component
struct WebDavSyncPage {
  build() {
    Column() {
      WebDavSyncPageContent()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct WebDavSyncPageContent {
  @Prop embedded: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State syncEnabled: boolean = false
  @State autoSync: boolean = false
  @State collectSyncEnabled: boolean = true
  @State serverUrl: string = ''
  @State username: string = ''
  @State password: string = ''
  @State remoteDir: string = '/FanPlayer/'
  @State lastSyncTime: number = 0
  @State isBusy: boolean = false
  @State configLoaded: boolean = false
  private scroller: Scroller = new Scroller()
  private syncService: HistorySyncService = HistorySyncService.getInstance()

  aboutToAppear(): void {
    this.loadConfig()
  }

  aboutToDisappear(): void {
    this.saveConfigSilently()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          if (this.configLoaded) {
            this.StatusSection()
            this.AccountSection()
          } else {
            this.LoadingSection()
          }

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
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
    .titleBar(this.buildWebDavTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(this.embedded)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  StatusSection(): void {
    Column() {
      this.SectionHeader('同步')
      Column() {
        this.ToggleRow('启用 WebDAV 同步', '同步观看历史与收藏数据', this.syncEnabled, (isOn: boolean) => {
          this.setSyncEnabled(isOn)
        })
        this.ItemDivider()
        this.ToggleRow('自动同步', '进入历史或收藏页时自动同步', this.autoSync, (isOn: boolean) => {
          this.setAutoSync(isOn)
        })
        this.ItemDivider()
        this.ToggleRow('同步收藏', '同步想看、在看等收藏状态', this.collectSyncEnabled, (isOn: boolean) => {
          this.setCollectSyncEnabled(isOn)
        })
        this.ItemDivider()
        Row() {
          this.TitleBlock('上次同步', this.getLastSyncText())
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  LoadingSection(): void {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color($r('app.color.accent_blue'))
      Text('配置加载中')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
    }
    .width('100%')
    .height(220)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  AccountSection(): void {
    Column() {
      this.SectionHeader('WebDAV')
      Column() {
        this.InputRow('服务地址', 'https://dav.example.com/dav', this.serverUrl, (value: string) => {
          this.serverUrl = value
          this.saveConfigSilently()
        })
        this.ItemDivider()
        this.InputRow('用户名', 'WebDAV 用户名', this.username, (value: string) => {
          this.username = value
          this.saveConfigSilently()
        })
        this.ItemDivider()
        this.PasswordInputRow()
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  SectionHeader(title: string): void {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, right: 6, top: 18, bottom: 6 })
  }

  @Builder
  ToggleRow(title: string, desc: string, isOn: boolean, onChange: (isOn: boolean) => void): void {
    Row() {
      this.TitleBlock(title, desc)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => {
          onChange(value)
        })
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  InputRow(title: string, placeholder: string, value: string, onChange: (value: string) => void): void {
    Column() {
      Text(title)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .height(40)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PasswordInputRow(): void {
    Column() {
      Text('密码')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextInput({ placeholder: '应用密码', text: this.password })
        .height(40)
        .type(InputType.Password)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.password = value
          this.saveConfigSilently()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TitleBlock(title: string, desc: string): void {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(desc)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ItemDivider(): void {
    Row() {
      Divider()
        .layoutWeight(1)
        .color($r('app.color.divider_color'))
        .strokeWidth(0.5)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  private async loadConfig(): Promise<void> {
    this.configLoaded = false
    try {
      const config = await this.syncService.getConfig()
      this.syncEnabled = config.enabled
      this.autoSync = config.autoSync
      this.collectSyncEnabled = await PreferencesStore.getInstance().getBoolean(WEBDAV_SYNC_COLLECT_KEY, true)
      this.serverUrl = config.serverUrl
      this.username = config.username
      this.password = config.password
      this.remoteDir = config.remoteDir
      this.lastSyncTime = await PreferencesStore.getInstance().getNumber(WEBDAV_SYNC_LAST_TIME_KEY, 0)
    } catch (err) {
      logger.warn('Load WebDAV config failed: %{public}s', err instanceof Error ? err.message : String(err))
    } finally {
      this.configLoaded = true
    }
  }

  private buildConfig(): WebDavConfig {
    const config = new WebDavConfig()
    config.enabled = this.syncEnabled
    config.autoSync = this.autoSync
    config.serverUrl = this.serverUrl
    config.username = this.username
    config.password = this.password
    config.remoteDir = this.remoteDir
    return config
  }

  private saveConfigSilently(): void {
    if (!this.configLoaded) {
      return
    }
    this.syncService.saveConfig(this.buildConfig()).catch((err: Error) => {
      logger.warn('Save WebDAV config failed: %{public}s', err.message)
    })
  }

  private async setSyncEnabled(enabled: boolean): Promise<void> {
    this.syncEnabled = enabled
    try {
      await PreferencesStore.getInstance().setBoolean(WEBDAV_SYNC_ENABLED_KEY, enabled)
    } catch (err) {
      logger.warn('Save WebDAV enabled failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async setAutoSync(enabled: boolean): Promise<void> {
    this.autoSync = enabled
    try {
      await PreferencesStore.getInstance().setBoolean(WEBDAV_SYNC_AUTO_KEY, enabled)
    } catch (err) {
      logger.warn('Save WebDAV auto sync failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async setCollectSyncEnabled(enabled: boolean): Promise<void> {
    this.collectSyncEnabled = enabled
    try {
      await PreferencesStore.getInstance().setBoolean(WEBDAV_SYNC_COLLECT_KEY, enabled)
    } catch (err) {
      logger.warn('Save WebDAV collect sync failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }

  private async saveConfigAndTestConnection(): Promise<void> {
    if (this.isBusy) {
      return
    }
    if (!this.configLoaded) {
      promptAction.showToast({ message: '配置加载中' })
      return
    }
    this.isBusy = true
    try {
      const config = this.buildConfig()
      await this.syncService.saveConfig(config)
      await this.syncService.testConnection(config)
      promptAction.showToast({ message: '配置已保存，连接成功' })
      await this.loadConfig()
    } catch (err) {
      promptAction.showToast({ message: err instanceof Error ? err.message : '保存或连接失败' })
    } finally {
      this.isBusy = false
    }
  }

  private async syncNow(): Promise<void> {
    if (this.isBusy || !this.configLoaded) {
      return
    }
    this.isBusy = true
    try {
      await this.syncService.saveConfig(this.buildConfig())
      const result = await this.syncService.syncNow()
      this.lastSyncTime = await PreferencesStore.getInstance().getNumber(WEBDAV_SYNC_LAST_TIME_KEY, 0)
      promptAction.showToast({ message: result.message })
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      logger.warn('WebDAV sync failed: %{public}s', message)
      promptAction.showToast({ message: message.length > 0 ? message : '同步失败' })
    } finally {
      this.isBusy = false
    }
  }

  private buildSaveIcon(): HdsNavigationIconOptions {
    return {
      icon: this.isBusy ? $r('sys.symbol.hourglass') : $r('sys.symbol.checkmark'),
      label: '保存并测试',
      action: () => {
        this.saveConfigAndTestConnection()
      }
    }
  }

  private buildSyncIcon(): HdsNavigationIconOptions {
    return {
      icon: this.isBusy ? $r('sys.symbol.hourglass') : $r('sys.symbol.arrow_clockwise'),
      label: '立即同步',
      action: () => {
        this.syncNow()
      }
    }
  }

  private buildWebDavMenu(): HdsNavigationMenuContentOptions {
    return {
      value: [{ content: this.buildSyncIcon() }, { content: this.buildSaveIcon() }]
    }
  }

  private buildWebDavTitle(): HdsNavigationTitle {
    return {
      mainTitle: 'WebDAV 同步',
      subTitle: '同步历史、进度与收藏'
    }
  }

  private buildWebDavTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildWebDavTitle(),
      menu: this.buildWebDavMenu()
    }
  }

  private buildWebDavTitleBarOptions(): HdsNavigationTitleBarOptions {
    const base: HdsNavigationTitleBarOptions = buildTitleBarOptions('WebDAV 同步', this.hdsMaterialLevel)
    base.content = this.buildWebDavTitleBarContent()
    return base
  }

  private getLastSyncText(): string {
    if (this.lastSyncTime <= 0) {
      return '尚未同步'
    }
    const date = new Date(this.lastSyncTime)
    return String(date.getMonth() + 1) + '月' + String(date.getDate()) + '日 ' +
      this.padZero(date.getHours()) + ':' + this.padZero(date.getMinutes())
  }

  private padZero(value: number): string {
    return value < 10 ? '0' + String(value) : String(value)
  }
}
