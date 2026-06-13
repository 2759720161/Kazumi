import { RuleSourceStore } from '../../store/RuleSourceStore'
import { RuleSource } from '../../models/RuleSource'
import { PreferencesStore } from '../../store/PreferencesStore'
import { SecurityPolicy } from '../../network/SecurityPolicy'
import { DefaultRuleSourceInitializer } from '../../utils/DefaultRuleSourceInitializer'
import { DataMigration, AppDataBundle } from '../../store/DataMigration'
import { RuleSourceSeeder } from '../../store/RuleSourceSeeder'
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { picker } from '@kit.CoreFileKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { Logger } from '../../utils/Logger'
import { router } from '@kit.ArkUI'
import { DandanCredentialStore } from '../../core/danmaku/DandanCredentialStore'
import { DandanApiClient } from '../../core/danmaku/DandanApiClient'
import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions
} from '../../utils/HdsPageStyle'

const logger = new Logger('SettingsPage')

@Component
export struct SettingsPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @State ruleCount: number = 0
  @State enabledRuleCount: number = 0
  @State allowHttpRequests: boolean = false
  @State defaultPlayerEngine: string = 'avplayer'
  @State mpvHwdecMode: string = 'ohcodec'
  @State mpvHlsAdFilter: boolean = true
  @State mpvSegAllowImg: boolean = true
  @State snifferTimeout: number = 15
  @State importUrl: string = ''
  @State isImporting: boolean = false
  @State importMessage: string = ''
  @State rules: RuleSource[] = []
  private ruleSourceStore: RuleSourceStore = new RuleSourceStore()
  private scroller: Scroller = new Scroller()

  @State isRestoring: boolean = false
  @State colorMode: number = -1
  @State isExporting: boolean = false
  @State isFileImporting: boolean = false
  @State isDataExporting: boolean = false
  @State isDataImporting: boolean = false

  @State dandanAppId: string = ''
  @State dandanAppSecret: string = ''
  @State isDanmakuCredentialConfigured: boolean = false
  @State isTestingConnection: boolean = false
  @State testConnectionMessage: string = ''

  aboutToAppear(): void {
    this.loadSettings()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          this.RuleSourceSection()
          this.DanmakuSourceSection()
          this.ImportSection()
          this.RuleListSection()
          this.PlayerSection()
          this.AppearanceSection()
          this.SecuritySection()
          this.SnifferSection()
          this.DeveloperSection()
          this.AboutSection()

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
    .titleBar(buildTitleBarOptions('设置'))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  RuleSourceSection(): void {
    Column() {
      Text('规则源管理')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text(`已启用: ${this.enabledRuleCount} / ${this.ruleCount}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      Button(this.isRestoring ? '恢复中...' : '恢复内置规则')
        .fontSize(14)
        .height(36)
        .width('100%')
        .backgroundColor($r('app.color.button_accent_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .fontColor($r('app.color.text_on_primary'))
        .borderRadius(18)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
        .enabled(!this.isRestoring)
        .margin({ left: 16, right: 16, bottom: 8 })
        .onClick(() => {
          this.restoreBundledRules()
        })
    }
    .width('100%')
  }

  @Builder
  ImportSection(): void {
    Column() {
      Text('导入规则源')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        TextInput({ placeholder: '输入规则源JSON URL', text: this.importUrl })
          .layoutWeight(1)
          .height(40)
          .onChange((value: string) => {
            this.importUrl = value
          })

        Button(this.isImporting ? '导入中...' : '导入')
          .height(40)
          .padding({ left: 18, right: 18 })
          .borderRadius(20)
          .backgroundColor($r('app.color.button_primary_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .shadow({ radius: 12, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
          .margin({ left: 8 })
          .enabled(!this.isImporting)
          .onClick(() => {
            this.importFromUrl()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 4 })

      Button(this.isImporting ? 'Importing...' : 'Import KazumiRules')
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.button_primary_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .border({ width: 0.5, color: $r('app.color.border_specular') })
        .shadow({ radius: 12, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
        .enabled(!this.isImporting)
        .width('100%')
        .margin({ left: 16, right: 16, bottom: 4 })
        .onClick(() => {
          this.importKazumiRulesCatalog()
        })

      Row() {
        Button(this.isFileImporting ? '导入中...' : '从文件导入')
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .enabled(!this.isFileImporting)
          .layoutWeight(1)
          .onClick(() => {
            this.importFromFile()
          })

        Button(this.isExporting ? '导出中...' : '导出规则')
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .enabled(!this.isExporting)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.exportRules()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 4 })

      if (this.importMessage.length > 0) {
        Text(this.importMessage)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 16, right: 16, bottom: 8 })
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  RuleListSection(): void {
    Column() {
      if (this.rules.length > 0) {
        ForEach(this.rules, (rule: RuleSource) => {
          Row() {
            Text(rule.name)
              .fontSize(14)
              .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
              .onChange((isOn: boolean) => {
                this.toggleRule(rule, isOn)
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        }, (rule: RuleSource) => String(rule.id))
      }
    }
    .width('100%')
  }

  @Builder
  PlayerSection(): void {
    Column() {
      Text('播放设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text('默认播放引擎')
          .fontSize(14)
          .layoutWeight(1)

        Row() {
          ForEach([
            { label: 'AVPlayer', value: 'avplayer' },
            { label: 'mpv', value: 'mpv' }
          ], (item: Record<string, Object>) => {
            Text(item.label as string)
              .fontSize(12)
              .fontColor(this.defaultPlayerEngine === (item.value as string) ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
              .backgroundColor(this.defaultPlayerEngine === (item.value as string) ? $r('app.color.button_primary_bg') : $r('app.color.card_background'))
              .borderRadius(12)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ left: 4 })
              .onClick(() => {
                this.setPlayerEngine(item.value as string)
              })
          }, (item: Record<string, Object>) => String(item.value))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })

      if (this.defaultPlayerEngine === 'mpv') {
        Column() {
          Row() {
            Text('硬件解码模式')
              .fontSize(14)
              .layoutWeight(1)

            Row() {
              ForEach([
                { label: 'OHCodec', value: 'ohcodec' },
                { label: '自动', value: 'auto' },
                { label: '关闭', value: 'no' }
              ], (item: Record<string, Object>) => {
                Text(item.label as string)
                  .fontSize(12)
                  .fontColor(this.mpvHwdecMode === (item.value as string) ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
                  .backgroundColor(this.mpvHwdecMode === (item.value as string) ? $r('app.color.button_primary_bg') : $r('app.color.card_background'))
                  .borderRadius(12)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .margin({ left: 4 })
                  .onClick(() => {
                    this.setMpvHwdecMode(item.value as string)
                  })
              }, (item: Record<string, Object>) => String(item.value))
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })

          Row() {
            Text('HLS广告跳过')
              .fontSize(14)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.mpvHlsAdFilter })
              .onChange((isOn: boolean) => {
                this.setMpvHlsAdFilter(isOn)
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })

          Row() {
            Text('伪装分片处理')
              .fontSize(14)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.mpvSegAllowImg })
              .onChange((isOn: boolean) => {
                this.setMpvSegAllowImg(isOn)
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  AppearanceSection(): void {
    Column() {
      Text('外观设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text('深色模式')
          .fontSize(14)
          .layoutWeight(1)

        Row() {
          ForEach([
            { label: '跟随系统', value: -1 },
            { label: '始终浅色', value: 1 },
            { label: '始终深色', value: 0 }
          ], (item: Record<string, Object>) => {
            Text(item.label as string)
              .fontSize(12)
              .fontColor(this.colorMode === (item.value as number) ? $r('app.color.text_on_primary') : $r('app.color.text_secondary'))
              .backgroundColor(this.colorMode === (item.value as number) ? $r('app.color.button_primary_bg') : $r('app.color.card_background'))
              .borderRadius(12)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ left: 4 })
              .onClick(() => {
                this.setColorMode(item.value as number)
              })
          }, (item: Record<string, Object>) => String(item.value))
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    }
    .width('100%')
  }

  @Builder
  SecuritySection(): void {
    Column() {
      Text('安全设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text('允许非HTTPS请求')
          .fontSize(14)
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.allowHttpRequests })
          .onChange((isOn: boolean) => {
            this.allowHttpRequests = isOn
            SecurityPolicy.getInstance().setAllowHttpRequests(isOn)
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    }
    .width('100%')
  }

  @Builder
  SnifferSection(): void {
    Column() {
      Text('嗅探设置')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text('嗅探超时(秒)')
          .fontSize(14)
          .layoutWeight(1)

        Text(`${this.snifferTimeout}s`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    }
    .width('100%')
  }

  @Builder
  DeveloperSection(): void {
    Column() {
      Text('开发者')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text('规则调试')
          .fontSize(14)
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/settings/RuleDebugPage' })
      })
    }
    .width('100%')
  }

  @Builder
  AboutSection(): void {
    Column() {
      Text('关于')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Text('版本')
          .fontSize(14)
          .layoutWeight(1)

        Text('1.0.0')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })

      Text('数据迁移')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Row() {
        Button(this.isDataExporting ? '导出中...' : '导出全部数据')
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .enabled(!this.isDataExporting)
          .layoutWeight(1)
          .onClick(() => {
            this.exportAllData()
          })

        Button(this.isDataImporting ? '导入中...' : '导入全部数据')
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.button_ghost_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .enabled(!this.isDataImporting)
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.importAllData()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
  }

  private async loadSettings(): Promise<void> {
    try {
      this.rules = await this.ruleSourceStore.getAll()
      this.ruleCount = this.rules.length
      this.enabledRuleCount = this.rules.filter((r: RuleSource) => r.enabled).length

      const prefs = PreferencesStore.getInstance()
      this.allowHttpRequests = await prefs.getBoolean('allow_http_requests', false)
      this.defaultPlayerEngine = await prefs.getString('defaultPlayerEngine', 'avplayer')
      this.mpvHwdecMode = await prefs.getString('mpvHwdecMode', 'ohcodec')
      this.mpvHlsAdFilter = await prefs.getBoolean('mpvHlsAdFilter', true)
      this.mpvSegAllowImg = await prefs.getBoolean('mpvSegAllowImg', true)
      this.snifferTimeout = await prefs.getNumber('snifferTimeoutMs', 15000) / 1000
      this.colorMode = await prefs.getNumber('colorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)

      const credStore = DandanCredentialStore.getInstance()
      this.isDanmakuCredentialConfigured = credStore.hasCredentials()
      if (this.isDanmakuCredentialConfigured) {
        this.dandanAppId = credStore.getAppId()
        this.dandanAppSecret = credStore.getAppSecret()
      }
    } catch (err) {
      logger.error('Load settings failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setPlayerEngine(engine: string): Promise<void> {
    this.defaultPlayerEngine = engine
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString('defaultPlayerEngine', engine)
    } catch (err) {
      logger.error('Set player engine failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setMpvHwdecMode(mode: string): Promise<void> {
    this.mpvHwdecMode = mode
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setString('mpvHwdecMode', mode)
    } catch (err) {
      logger.error('Set mpv hwdec mode failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setMpvHlsAdFilter(enabled: boolean): Promise<void> {
    this.mpvHlsAdFilter = enabled
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean('mpvHlsAdFilter', enabled)
    } catch (err) {
      logger.error('Set mpv hls ad filter failed: %{public}s', JSON.stringify(err))
    }
  }

  private async setMpvSegAllowImg(enabled: boolean): Promise<void> {
    this.mpvSegAllowImg = enabled
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean('mpvSegAllowImg', enabled)
    } catch (err) {
      logger.error('Set mpv seg allow img failed: %{public}s', JSON.stringify(err))
    }
  }

  private async importFromUrl(): Promise<void> {
    if (this.importUrl.trim().length === 0) {
      this.importMessage = '请输入URL'
      return
    }
    this.isImporting = true
    this.importMessage = '正在导入...'
    try {
      const count = await DefaultRuleSourceInitializer.importFromUrl(this.importUrl.trim())
      this.importMessage = `成功导入 ${count} 个规则源`
      await this.loadSettings()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `导入失败: ${msg}`
      logger.error('Import failed: %{public}s', msg)
    } finally {
      this.isImporting = false
    }
  }

  private async importKazumiRulesCatalog(): Promise<void> {
    if (this.isImporting) {
      return
    }
    this.isImporting = true
    this.importMessage = 'Importing Predidit/KazumiRules...'
    try {
      const count = await DefaultRuleSourceInitializer.importFromKazumiRulesCatalog()
      this.importMessage = `Imported ${count} rules from KazumiRules`
      await this.loadSettings()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `Import failed: ${msg}`
      logger.error('KazumiRules import failed: %{public}s', msg)
    } finally {
      this.isImporting = false
    }
  }

  private async toggleRule(rule: RuleSource, enabled: boolean): Promise<void> {
    try {
      await this.ruleSourceStore.setEnabled(rule.id, enabled)
      await this.loadSettings()
    } catch (err) {
      logger.error('Toggle rule failed: %{public}s', JSON.stringify(err))
    }
  }

  private async restoreBundledRules(): Promise<void> {
    this.isRestoring = true
    try {
      const context = getContext(this) as common.UIAbilityContext
      const count = await RuleSourceSeeder.restoreBundledRules(context)
      this.importMessage = `已恢复/更新 ${count} 条内置规则`
      await this.loadSettings()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `恢复失败: ${msg}`
      logger.error('Restore bundled rules failed: %{public}s', msg)
    } finally {
      this.isRestoring = false
    }
  }

  private async setColorMode(mode: number): Promise<void> {
    this.colorMode = mode
    try {
      const context = getContext(this) as common.UIAbilityContext
      if (mode === -1) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      } else if (mode === 0) {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
      } else {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      }
      const prefs = PreferencesStore.getInstance()
      await prefs.setNumber('colorMode', mode)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.error('Set colorMode failed: %{public}s', msg)
    }
  }

  private async exportRules(): Promise<void> {
    this.isExporting = true
    this.importMessage = '正在导出...'
    try {
      const rules = await this.ruleSourceStore.getAll()
      if (rules.length === 0) {
        this.importMessage = '没有可导出的规则'
        return
      }
      const jsonArr: Object[] = []
      for (let i = 0; i < rules.length; i++) {
        jsonArr.push(rules[i].toJSON())
      }
      const jsonStr = JSON.stringify(jsonArr)
      const context = getContext(this) as common.UIAbilityContext
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.newFileNames = ['kazumi_rules.json']
      const docViewPicker = new picker.DocumentViewPicker(context)
      const uris: Array<string> = await docViewPicker.save(documentSaveOptions)
      if (uris.length > 0) {
        const file = fs.openSync(uris[0], fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
        fs.writeSync(file.fd, jsonStr)
        fs.closeSync(file)
        this.importMessage = `已导出 ${rules.length} 条规则`
      } else {
        this.importMessage = '导出已取消'
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `导出失败: ${msg}`
      logger.error('Export rules failed: %{public}s', msg)
    } finally {
      this.isExporting = false
    }
  }

  private async importFromFile(): Promise<void> {
    this.isFileImporting = true
    this.importMessage = '请选择JSON文件...'
    try {
      const context = getContext(this) as common.UIAbilityContext
      const docViewPicker = new picker.DocumentViewPicker(context)
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      const uris: Array<string> = await docViewPicker.select(documentSelectOptions)
      if (uris.length === 0) {
        this.importMessage = '未选择文件'
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
      this.importMessage = `从文件导入 ${count} 条规则`
      await this.loadSettings()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `文件导入失败: ${msg}`
      logger.error('File import failed: %{public}s', msg)
    } finally {
      this.isFileImporting = false
    }
  }

  private async exportAllData(): Promise<void> {
    this.isDataExporting = true
    this.importMessage = '正在导出全部数据...'
    try {
      const bundle = await DataMigration.exportAll()
      const jsonStr = JSON.stringify(bundle.toJSON())
      const context = getContext(this) as common.UIAbilityContext
      const documentSaveOptions = new picker.DocumentSaveOptions()
      documentSaveOptions.newFileNames = ['kazumi_backup.json']
      const docViewPicker = new picker.DocumentViewPicker(context)
      const uris: Array<string> = await docViewPicker.save(documentSaveOptions)
      if (uris.length > 0) {
        const file = fs.openSync(uris[0], fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
        fs.writeSync(file.fd, jsonStr)
        fs.closeSync(file)
        this.importMessage = `已导出全部数据 (${bundle.rules.length}规则, ${bundle.favorites.length}收藏, ${bundle.watchHistory.length}历史)`
      } else {
        this.importMessage = '导出已取消'
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `导出全部数据失败: ${msg}`
      logger.error('Export all data failed: %{public}s', msg)
    } finally {
      this.isDataExporting = false
    }
  }

  private async importAllData(): Promise<void> {
    this.isDataImporting = true
    this.importMessage = '请选择备份文件...'
    try {
      const context = getContext(this) as common.UIAbilityContext
      const docViewPicker = new picker.DocumentViewPicker(context)
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 1
      const uris: Array<string> = await docViewPicker.select(documentSelectOptions)
      if (uris.length === 0) {
        this.importMessage = '未选择文件'
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
      const parsed: Object = JSON.parse(jsonStr)
      const bundle = AppDataBundle.fromJSON(parsed as Record<string, Object>)
      await DataMigration.importAll(bundle)
      this.importMessage = `已导入全部数据 (${bundle.rules.length}规则, ${bundle.favorites.length}收藏, ${bundle.watchHistory.length}历史)`
      await this.loadSettings()
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      this.importMessage = `导入全部数据失败: ${msg}`
      logger.error('Import all data failed: %{public}s', msg)
    } finally {
      this.isDataImporting = false
    }
  }

  @Builder
  DanmakuSourceSection(): void {
    Column() {
      Row() {
        Text('弹幕源设置')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Text(this.isDanmakuCredentialConfigured ? '已配置' : '未配置')
          .fontSize(12)
          .fontColor(this.isDanmakuCredentialConfigured ? '#4CAF50' : '#FF9800')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Text('AppId')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 4, bottom: 2 })

      TextInput({ placeholder: '输入Dandanplay AppId', text: this.dandanAppId })
        .width('100%')
        .height(40)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.dandanAppId = value
        })
        .onBlur(() => {
          this.saveDanmakuCredentials()
        })

      Text('AppSecret')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 8, bottom: 2 })

      TextInput({ placeholder: '输入Dandanplay AppSecret', text: this.dandanAppSecret })
        .width('100%')
        .height(40)
        .type(InputType.Password)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.dandanAppSecret = value
        })
        .onBlur(() => {
          this.saveDanmakuCredentials()
        })

      Row() {
        Button(this.isTestingConnection ? '测试中...' : '测试连接')
          .fontSize(14)
          .height(36)
          .backgroundColor($r('app.color.button_primary_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(18)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .shadow({ radius: 12, color: $r('app.color.shadow_button_primary'), offsetY: 4 })
          .enabled(!this.isTestingConnection && this.dandanAppId.length > 0 && this.dandanAppSecret.length > 0)
          .layoutWeight(1)
          .margin({ right: 8 })
          .onClick(() => {
            this.testDanmakuConnection()
          })

        Button('清除凭据')
          .fontSize(14)
          .height(36)
          .backgroundColor($r('app.color.button_accent_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .fontColor($r('app.color.text_on_primary'))
          .borderRadius(18)
          .border({ width: 0.5, color: $r('app.color.border_specular') })
          .shadow({ radius: 12, color: $r('app.color.shadow_button_accent'), offsetY: 4 })
          .layoutWeight(1)
          .margin({ left: 8 })
          .onClick(() => {
            this.clearDanmakuCredentials()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })

      if (this.testConnectionMessage.length > 0) {
        Text(this.testConnectionMessage)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, top: 4, bottom: 8 })
      }
    }
    .width('100%')
  }

  private async saveDanmakuCredentials(): Promise<void> {

    try {
      const store = DandanCredentialStore.getInstance()
      await store.setCredentials(this.dandanAppId, this.dandanAppSecret)
      this.isDanmakuCredentialConfigured = store.hasCredentials()
    } catch (_err) {
      logger.error('保存弹幕凭据失败')
    }
  }

  private async testDanmakuConnection(): Promise<void> {
    this.isTestingConnection = true
    this.testConnectionMessage = '正在测试连接...'
    try {
      await this.saveDanmakuCredentials()
      const client = DandanApiClient.getInstance()
      const queryParameters: Record<string, string> = {}
      queryParameters['keyword'] = 'test'
      const result = await client.get('/api/v2/search/anime', queryParameters)
      if (result.isSuccessful) {
        this.testConnectionMessage = '连接成功'
      } else if (result.statusCode === 403) {
        this.testConnectionMessage = '连接失败: HTTP 403 (鉴权失败)'
      } else {
        this.testConnectionMessage = `连接失败: HTTP ${result.statusCode}`
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      if (msg.toLowerCase().indexOf('timeout') >= 0) {
        this.testConnectionMessage = '连接失败: 请求超时'
      } else {
        this.testConnectionMessage = '连接失败: 网络错误'
      }
    } finally {
      this.isTestingConnection = false
    }
  }

  private async clearDanmakuCredentials(): Promise<void> {
    try {
      const store = DandanCredentialStore.getInstance()
      await store.clearCredentials()
      this.dandanAppId = ''
      this.dandanAppSecret = ''
      this.isDanmakuCredentialConfigured = false
      this.testConnectionMessage = '凭据已清除'
    } catch (_err) {
      this.dandanAppId = ''
      this.dandanAppSecret = ''
      this.isDanmakuCredentialConfigured = false
      this.testConnectionMessage = '清除可能不完整'
    }
  }
}
