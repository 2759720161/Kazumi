import { HomePage } from './home/HomePage'
import { FavoritePage } from './favorite/FavoritePage'
import { HistoryPage } from './history/HistoryPage'
import { SettingsPage } from './settings/SettingsPage'
import { PreferencesStore } from '../store/PreferencesStore'
import { RuleSourceSeeder } from '../store/RuleSourceSeeder'
import { common } from '@kit.AbilityKit'
import {
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  SystemMaterialParams,
  hdsMaterial
} from '@kit.UIDesignKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'

@Entry
@Component
struct Index {
  @StorageLink('currentTab') currentTab: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @State showDisclaimer: boolean = false
  @State isSeeding: boolean = false
  @State private hdsImmersiveMaterialSupported: boolean = true
  private tabsController: HdsTabsController = new HdsTabsController()
  private readonly hdsTabBarHeight: number = 66
  private readonly hdsTabBottomMargin: number = 24

  aboutToAppear(): void {
    this.refreshHdsMaterialSupport()
    this.purgeRemovedUpstreamRules()
    this.checkDisclaimer()
  }

  build() {
    Column() {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.house'), $r('sys.symbol.house_fill'), '首页'))

        TabContent() {
          FavoritePage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.heart'), $r('sys.symbol.heart_fill'), '收藏'))

        TabContent() {
          HistoryPage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.clock'), $r('sys.symbol.clock_fill'), '历史'))

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.gearshape'), $r('sys.symbol.gearshape_fill'), '设置'))
      }
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .barHeight(this.getHdsTabBarHeight())
      .barFloatingStyle(this.buildHdsTabFloatingStyle())
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentTab = index
      })
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background($r('app.color.page_background'))
    .bindContentCover($$this.showDisclaimer, this.DisclaimerContent(), {
      modalTransition: ModalTransition.NONE
    })
  }

  private isWideHdsTabsLayout(): boolean {
    return this.screenWidthVp >= 600
  }

  private getHdsTabBarHeight(): number {
    return this.isWideHdsTabsLayout() ? 64 : this.hdsTabBarHeight
  }

  private getHdsTabBarBottomMargin(): number {
    return this.isWideHdsTabsLayout() ? 18 : this.hdsTabBottomMargin
  }

  private getHdsGradientMaskHeight(): number {
    return this.getHdsTabBarHeight() + this.getHdsTabBarBottomMargin() + 28
  }

  private buildHdsTabFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barWidth: {
        smallWidth: 280,
        mediumWidth: 320,
        largeWidth: 360
      },
      barBottomMargin: this.bottomSafeHeight + this.getHdsTabBarBottomMargin(),
      gradientMask: {
        maskColor: $r('app.color.hds_tab_gradient_mask'),
        maskHeight: this.getHdsGradientMaskHeight()
      },
      thermoCtrl: true,
      systemMaterialEffect: this.buildAdaptiveMaterialEffect()
    }
  }

  private refreshHdsMaterialSupport(): void {
    try {
      const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
      this.hdsImmersiveMaterialSupported = materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0
    } catch (_) {
      this.hdsImmersiveMaterialSupported = false
    }
  }

  private buildAdaptiveMaterialEffect(): SystemMaterialParams {
    return {
      materialType: this.hdsImmersiveMaterialSupported ? hdsMaterial.MaterialType.IMMERSIVE :
        hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: this.hdsImmersiveMaterialSupported ? hdsMaterial.MaterialLevel.EXQUISITE :
        hdsMaterial.MaterialLevel.ADAPTIVE
    }
  }

  private bottomTabStyle(normal: Resource, selected: Resource, text: string): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(normal),
      selected: new SymbolGlyphModifier(selected)
    }, text)
  }

  @Builder
  private DisclaimerContent() {
    Column() {
      Column() {
        Text('免责声明')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 20 })

        Scroll() {
          Text('本应用仅供学习交流使用，所有视频资源均来自第三方网站，本应用不提供、不存储任何视频内容。\n\n使用本应用即表示您了解并同意以下内容：\n\n1. 本应用不对任何视频资源的合法性、安全性、完整性做出保证。\n\n2. 使用本应用获取的内容可能涉及版权，请确保您在合法范围内使用。\n\n3. 本应用不对因使用本应用而导致的任何损失承担责任。\n\n4. 规则源由社区维护，本应用不对规则源的内容和安全性负责。\n\n5. 请遵守您所在地区的法律法规，合理使用本应用。')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(24)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ bottom: 20 })

        Row() {
          Button('不同意')
            .fontSize(16)
            .backgroundColor($r('app.color.button_ghost_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_secondary'))
            .borderRadius(24)
            .border({ width: 0.5, color: $r('app.color.border_subtle') })
            .shadow({ radius: 12, color: $r('app.color.shadow_surface'), offsetY: 4 })
            .layoutWeight(1)
            .height(48)
            .onClick(() => {
              this.showDisclaimer = false
            })

          Button('同意并继续')
            .fontSize(16)
            .backgroundColor($r('app.color.button_accent_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .fontColor($r('app.color.text_on_primary'))
            .borderRadius(24)
            .border({ width: 0.5, color: $r('app.color.border_specular') })
            .shadow({ radius: 16, color: $r('app.color.shadow_button_accent'), offsetY: 5 })
            .layoutWeight(1)
            .height(48)
            .margin({ left: 12 })
            .enabled(!this.isSeeding)
            .onClick(() => {
              this.onDisclaimerAgreed()
            })
        }
        .width('100%')
      }
      .padding({ left: 24, right: 24, top: 40, bottom: 24 })
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay_modal_bg'))
    .justifyContent(FlexAlign.Center)
  }

  private async checkDisclaimer(): Promise<void> {
    try {
      const prefs = PreferencesStore.getInstance()
      const agreed = await prefs.getBoolean('disclaimer_agreed', false)
      if (!agreed) {
        this.showDisclaimer = true
      }
    } catch (err) {
      this.showDisclaimer = true
    }
  }

  private async purgeRemovedUpstreamRules(): Promise<void> {
    try {
      await RuleSourceSeeder.purgeRemovedUpstreamRules()
    } catch (_) {
    }
  }

  private async onDisclaimerAgreed(): Promise<void> {
    this.isSeeding = true
    try {
      const prefs = PreferencesStore.getInstance()
      await prefs.setBoolean('disclaimer_agreed', true)
      const context = getContext(this) as common.UIAbilityContext
      await RuleSourceSeeder.seedIfEmpty(context)
      this.showDisclaimer = false
    } catch (err) {
      this.showDisclaimer = false
    } finally {
      this.isSeeding = false
    }
  }
}
