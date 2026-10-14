import { promptAction } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { ImageProxyConfig, ImageProxyType } from '../../models/ImageProxyConfig'
import { IMAGE_ACTIVE_PROXY_KEY, IMAGE_NETWORK_VERSION_KEY, ImageNetworkSettings } from '../../store/ImageNetworkSettings'
import { buildTitleBarOptions, getBottomSpacerHeight, getTopSpacerHeight,
  HDS_MATERIAL_LEVEL_DEFAULT, PREFS_KEY_HDS_MATERIAL_LEVEL } from '../../utils/HdsPageStyle'
import { API26_MATERIAL_STYLE_DEFAULT, PREFS_KEY_API26_MATERIAL_STYLE } from '../../utils/ImmersiveMaterial'
import { ImmersiveSelectModifier } from '../../utils/ImmersiveSelectModifier'

@Entry
@Component
struct ImageProxySettingsPage {
  build() {
    Column() {
      ImageProxySettingsPageContent()
    }.width('100%').height('100%')
  }
}

@Component
export struct ImageProxySettingsPageContent {
  @Prop embedded: boolean = false
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(PREFS_KEY_API26_MATERIAL_STYLE) api26MaterialStyle: string = API26_MATERIAL_STYLE_DEFAULT
  @StorageLink(IMAGE_NETWORK_VERSION_KEY) @Watch('refreshConfig') networkVersion: number = 0
  @StorageLink(IMAGE_ACTIVE_PROXY_KEY) @Watch('refreshConfig') activeProxyId: string = ''
  @State proxyEnabled: boolean = false
  @State autoFailover: boolean = true
  @State proxies: ImageProxyConfig[] = []
  @State selectedId: string = ''
  @State editing: boolean = false
  @State busy: boolean = false
  @State name: string = ''
  @State proxyType: ImageProxyType = ImageProxyType.HTTP
  @State host: string = ''
  @State port: string = '8080'
  @State username: string = ''
  @State password: string = ''
  @State exclusions: string = ''
  private editingId: string = ''
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.refreshConfig()
  }

  private refreshConfig(): void {
    const config = ImageNetworkSettings.getConfig()
    this.proxyEnabled = config.proxyEnabled
    this.autoFailover = config.autoFailover
    this.proxies = config.proxies
    this.selectedId = config.selectedProxyId
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Blank().height(getTopSpacerHeight(this.topSafeHeight)).width('100%')
          this.ModeCard()
          if (this.editing) {
            this.EditorCard()
          }
          Row() {
            Text($r('app.string.image_proxy_saved'))
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Button($r('app.string.image_proxy_add'))
              .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
              .enabled(!this.busy)
              .onClick(() => { this.openEditor(null) })
          }.width('100%')
          if (this.proxies.length === 0) {
            Text($r('app.string.image_proxy_empty'))
              .fontSize(15).fontColor($r('app.color.text_secondary')).width('100%')
              .textAlign(TextAlign.Center).padding({ top: 32, bottom: 32 })
          } else {
            ForEach(this.proxies, (proxy: ImageProxyConfig) => {
              this.ProxyCard(proxy)
            }, (proxy: ImageProxyConfig) => proxy.id)
          }
          Blank().height(getBottomSpacerHeight(this.bottomSafeHeight)).width('100%')
        }
        .width('100%').padding({ left: 16, right: 16 })
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)
    }
    .width('100%').height('100%').mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions(this.resourceText($r('app.string.image_proxy_title')), this.hdsMaterialLevel))
    .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(this.embedded)
    .bindToScrollable([this.scroller]).backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private ModeCard(): void {
    Column({ space: 18 }) {
      this.ToggleRow($r('app.string.image_proxy_enable'),
        this.proxyEnabled ? $r('app.string.image_proxy_proxy_desc') : $r('app.string.image_proxy_direct_desc'),
        this.proxyEnabled, (enabled: boolean) => { this.changeMode(enabled) })
      if (this.proxyEnabled) {
        Text(this.selectedProxyName())
          .fontSize(14).fontColor($r('app.color.accent_blue')).width('100%')
      }
      this.ToggleRow($r('app.string.image_proxy_failover'), $r('app.string.image_proxy_failover_desc'),
        this.autoFailover, (enabled: boolean) => {
          ImageNetworkSettings.setAutoFailover(enabled).catch(() => { this.showMessage($r('app.string.image_proxy_save_failed')) })
        })
      Text($r('app.string.image_proxy_scope'))
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(20)
    }
    .width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
  }

  @Builder
  private ToggleRow(title: Resource, desc: Resource, enabled: boolean,
    onChange: (value: boolean) => void): void {
    Row({ space: 16 }) {
      Column({ space: 6 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(desc).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(20)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: enabled }).enabled(!this.busy).onChange(onChange)
    }.width('100%')
  }

  @Builder
  private ProxyCard(proxy: ImageProxyConfig): void {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(proxy.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(proxy.type + ' · ' + proxy.host + ':' + proxy.port.toString())
            .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.selectedId === proxy.id ? $r('app.string.image_proxy_selected') : $r('app.string.image_proxy_select'))
          .fontSize(13).fontColor($r('app.color.accent_blue')).backgroundColor(Color.Transparent)
          .enabled(!this.busy && this.selectedId !== proxy.id)
          .onClick(() => {
            ImageNetworkSettings.selectProxy(proxy.id).catch(() => { this.showMessage($r('app.string.image_proxy_save_failed')) })
          })
      }.width('100%')
      Row({ space: 12 }) {
        Button($r('app.string.image_proxy_edit')).fontSize(13)
          .fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent).enabled(!this.busy)
          .onClick(() => { this.openEditor(proxy) })
        Button($r('app.string.image_proxy_delete')).fontSize(13)
          .fontColor($r('app.color.text_secondary')).backgroundColor(Color.Transparent).enabled(!this.busy)
          .onClick(() => {
            ImageNetworkSettings.deleteProxy(proxy.id).catch(() => { this.showMessage($r('app.string.image_proxy_save_failed')) })
          })
      }.width('100%').justifyContent(FlexAlign.End)
    }
    .width('100%').padding(16).borderRadius(16).backgroundColor($r('app.color.card_background'))
    .border({ width: this.selectedId === proxy.id ? 1 : 0.5,
      color: this.selectedId === proxy.id ? $r('app.color.accent_blue') : $r('app.color.card_specular_border') })
  }

  @Builder
  private EditorCard(): void {
    Column({ space: 16 }) {
      Row() {
        Text(this.editingId.length > 0 ? $r('app.string.image_proxy_edit') : $r('app.string.image_proxy_add'))
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button($r('app.string.image_proxy_cancel')).fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent).enabled(!this.busy).onClick(() => { this.editing = false })
      }.width('100%')
      this.InputRow($r('app.string.image_proxy_name'), $r('app.string.image_proxy_name_hint'),
        this.name, (value: string) => { this.name = value })
      Column({ space: 8 }) {
        Text($r('app.string.image_proxy_type')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Select([{ value: $r('app.string.image_proxy_http') }, { value: $r('app.string.image_proxy_socks5') }])
          .selected(this.proxyType === ImageProxyType.SOCKS5 ? 1 : 0)
          .value(this.proxyType).font({ size: 16 }).fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor($r('app.color.accent_blue'))
          .optionFontColor($r('app.color.text_primary'))
          .optionFont({ size: 16, weight: FontWeight.Medium })
          .selectedOptionFont({ size: 16, weight: FontWeight.Medium })
          .selectedOptionBgColor(Color.Transparent)
          .optionBgColor(Color.Transparent)
          .attributeModifier(new ImmersiveSelectModifier(this.api26MaterialStyle))
          .borderRadius(20).enabled(!this.busy)
          .onSelect((index: number) => { this.selectType(index) })
        if (this.proxyType === ImageProxyType.SOCKS5 && !ImageNetworkSettings.isSocks5Supported()) {
          Text($r('app.string.image_proxy_socks5_unsupported'))
            .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').lineHeight(20)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
      this.InputRow($r('app.string.image_proxy_host'), $r('app.string.image_proxy_host_hint'),
        this.host, (value: string) => { this.host = value })
      this.InputRow($r('app.string.image_proxy_port'), $r('app.string.image_proxy_port_hint'),
        this.port, (value: string) => { this.port = value }, InputType.Number)
      this.InputRow($r('app.string.image_proxy_username'), $r('app.string.image_proxy_optional'),
        this.username, (value: string) => { this.username = value })
      this.InputRow($r('app.string.image_proxy_password'), $r('app.string.image_proxy_optional'),
        this.password, (value: string) => { this.password = value }, InputType.Password)
      this.InputRow($r('app.string.image_proxy_exclusions'), $r('app.string.image_proxy_exclusions_hint'),
        this.exclusions, (value: string) => { this.exclusions = value })
      Button($r('app.string.image_proxy_save')).width('100%').height(48).enabled(!this.busy)
        .fontColor($r('app.color.text_on_primary')).backgroundColor($r('app.color.accent_blue'))
        .onClick(() => { this.saveEditor() })
    }
    .width('100%').padding(20).borderRadius(20).backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private InputRow(title: Resource, hint: Resource, value: string,
    onChange: (value: string) => void, type: InputType = InputType.Normal): void {
    Column({ space: 8 }) {
      Text(title).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ placeholder: hint, text: value }).height(48).type(type).enabled(!this.busy)
        .fontSize(16).fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.page_background'))
        .borderRadius(12).onChange(onChange)
    }.width('100%')
  }

  private selectedProxyName(): string {
    const proxy = this.proxies.find((value: ImageProxyConfig) => value.id === this.selectedId)
    return proxy !== undefined ? proxy.type + ' · ' + proxy.name : ''
  }

  private openEditor(proxy: ImageProxyConfig | null): void {
    this.editingId = proxy !== null ? proxy.id : ''
    this.name = proxy !== null ? proxy.name : ''
    this.proxyType = proxy !== null ? proxy.type : ImageProxyType.HTTP
    this.host = proxy !== null ? proxy.host : ''
    this.port = proxy !== null ? proxy.port.toString() : '8080'
    this.username = proxy !== null ? proxy.username : ''
    this.password = proxy !== null ? proxy.password : ''
    this.exclusions = proxy !== null ? proxy.exclusionList.join(', ') : ''
    this.editing = true
    this.scroller.scrollEdge(Edge.Top)
  }

  private selectType(index: number): void {
    const type = index === 1 ? ImageProxyType.SOCKS5 : ImageProxyType.HTTP
    if (this.editingId.length === 0 && Number(this.port) === ImageProxyConfig.getDefaultPort(this.proxyType)) {
      this.port = ImageProxyConfig.getDefaultPort(type).toString()
    }
    this.proxyType = type
  }

  private async changeMode(enabled: boolean): Promise<void> {
    this.proxyEnabled = enabled
    this.busy = true
    try {
      const changed = await ImageNetworkSettings.setProxyEnabled(enabled)
      if (!changed) {
        this.showMessage($r('app.string.image_proxy_required'))
      }
      this.refreshConfig()
    } catch (_) {
      this.showMessage($r('app.string.image_proxy_save_failed'))
    } finally {
      this.busy = false
    }
  }

  private async saveEditor(): Promise<void> {
    const proxy = new ImageProxyConfig()
    proxy.type = this.proxyType
    if (proxy.type === ImageProxyType.SOCKS5 && !ImageNetworkSettings.isSocks5Supported()) {
      this.showMessage($r('app.string.image_proxy_socks5_unsupported'))
      return
    }
    proxy.id = this.editingId.length > 0 ? this.editingId : Date.now().toString(36) + '-' + Math.random().toString(36).slice(2)
    proxy.host = ImageProxyConfig.normalizeHost(this.host, proxy.type)
    if (!ImageProxyConfig.isValidHost(proxy.host)) {
      this.showMessage($r('app.string.image_proxy_invalid_host'))
      return
    }
    if (!/^\d+$/.test(this.port.trim()) || Number(this.port) < 1 || Number(this.port) > 65535) {
      this.showMessage($r('app.string.image_proxy_invalid_port'))
      return
    }
    proxy.port = Number(this.port)
    proxy.name = this.name.trim().length > 0 ? this.name.trim() : proxy.host + ':' + proxy.port.toString()
    proxy.username = this.username.trim()
    proxy.password = this.password
    if ((proxy.username.length === 0) !== (proxy.password.length === 0)) {
      this.showMessage($r('app.string.image_proxy_invalid_auth'))
      return
    }
    proxy.exclusionList = ImageProxyConfig.parseExclusions(this.exclusions)
    if (proxy.exclusionList.some((host: string) => host !== '*' && !ImageProxyConfig.isValidHost(host)) ||
      (proxy.exclusionList.includes('*') && proxy.exclusionList.length > 1)) {
      this.showMessage($r('app.string.image_proxy_invalid_exclusions'))
      return
    }
    this.busy = true
    try {
      await ImageNetworkSettings.saveProxy(proxy)
      this.editing = false
      this.password = ''
      this.refreshConfig()
      this.showMessage($r('app.string.image_proxy_saved_message'))
    } catch (_) {
      this.showMessage($r('app.string.image_proxy_save_failed'))
    } finally {
      this.busy = false
    }
  }

  private resourceText(resource: Resource): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id) ?? ''
  }

  private showMessage(resource: Resource): void {
    promptAction.showToast({ message: this.resourceText(resource) })
  }
}
