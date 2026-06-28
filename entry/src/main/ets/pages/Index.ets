import { HomePage } from './home/HomePage'
import { TimelinePage } from './timeline/TimelinePage'
import { FavoritePage } from './favorite/FavoritePage'
import { SettingsPage } from './settings/SettingsPage'
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
  @State private hdsImmersiveMaterialSupported: boolean = true
  private tabsController: HdsTabsController = new HdsTabsController()
  private readonly hdsTabBarHeight: number = 66
  private readonly hdsTabBottomMargin: number = 24

  aboutToAppear(): void {
    this.refreshHdsMaterialSupport()
  }

  build() {
    Column() {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.house'), $r('sys.symbol.house_fill'), '首页'))

        TabContent() {
          TimelinePage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.calendar'), $r('sys.symbol.calendar'), '时间表'))

        TabContent() {
          FavoritePage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.heart'), $r('sys.symbol.heart_fill'), '片库'))

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.person'), $r('sys.symbol.person_fill'), '我的'))
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
}
