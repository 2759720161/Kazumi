import { HomePage } from './home/HomePage'
import { TimelinePage } from './timeline/TimelinePage'
import { FavoritePage } from './favorite/FavoritePage'
import { LocalPage } from './local/LocalPage'
import { SettingsPage } from './settings/SettingsPage'
import {
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  HdsAnimationMode,
  SystemMaterialParams,
  hdsMaterial
} from '@kit.UIDesignKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { Logger } from '../utils/Logger'
import {
  BOTTOM_TAB_ANIMATION_HIDDEN_KEY,
  BOTTOM_TAB_ANIMATION_TOKEN_KEY,
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
} from '../utils/BottomTabAutoHide'
import { ADVANCED_OPTIONS_UNLOCKED_KEY } from '../utils/AdvancedOptionsUnlock'

const logger = new Logger('Index')

@Entry
@Component
struct Index {
  @StorageLink('currentTab') currentTab: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('screenWidthVp') screenWidthVp: number = 0
  @StorageLink('bottomTabAutoHide') @Watch('onBottomTabAutoHideChanged') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabShowAnimation') bottomTabShowAnimation: boolean = BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink(BOTTOM_TAB_ANIMATION_TOKEN_KEY) @Watch('onBottomTabAnimationTokenChanged')
  bottomTabAnimationToken: number = 0
  @StorageLink(BOTTOM_TAB_ANIMATION_HIDDEN_KEY) bottomTabAnimationHidden: boolean = false
  @StorageLink(ADVANCED_OPTIONS_UNLOCKED_KEY) @Watch('onAdvancedOptionsUnlockedChanged')
  advancedOptionsUnlocked: boolean = false
  @State private hdsImmersiveMaterialSupported: boolean = true
  private tabsController: HdsTabsController = new HdsTabsController()
  private readonly hdsTabBarHeight: number = 66
  private readonly hdsTabBottomMargin: number = 24

  aboutToAppear(): void {
    this.refreshHdsMaterialSupport()
    this.normalizeCurrentTab()
  }

  build() {
    Column() {
      HdsTabs({ controller: this.tabsController }) {
        if (this.advancedOptionsUnlocked) {
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
          .tabBar(this.bottomTabStyle($r('sys.symbol.heart'), $r('sys.symbol.heart_fill'), '收藏'))
        }

        TabContent() {
          LocalPage({ isActive: this.currentTab === this.getLocalTabIndex() })
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.folder'), $r('sys.symbol.folder_fill'), '本地'))

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
        logger.info('Main tab changed: %{public}d', index)
        this.currentTab = index
        this.bottomTabOffset = 0
        this.applyBottomTabVisibilityAnimation(false)
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
        smallWidth: 332,
        mediumWidth: 380,
        largeWidth: 430
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

  private onBottomTabAutoHideChanged(): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      this.bottomTabAnimationHidden = false
    }
  }

  private onAdvancedOptionsUnlockedChanged(): void {
    this.normalizeCurrentTab()
  }

  private onBottomTabAnimationTokenChanged(): void {
    if (this.bottomTabAnimationToken === 0) {
      return
    }
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      this.bottomTabAnimationHidden = false
      return
    }
    this.applyBottomTabVisibilityAnimation(this.bottomTabAnimationHidden)
  }

  private applyBottomTabVisibilityAnimation(hidden: boolean): void {
    try {
      this.bottomTabAnimationHidden = hidden
      if (hidden) {
        this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)
      } else {
        if (!this.bottomTabShowAnimation) {
          return
        }
        this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Apply bottom tab HDS animation failed: %{public}s', msg)
    }
  }

  private bottomTabStyle(normal: Resource, selected: Resource, text: string): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(normal),
      selected: new SymbolGlyphModifier(selected)
    }, text)
  }

  private getLocalTabIndex(): number {
    return this.advancedOptionsUnlocked ? 3 : 0
  }

  private normalizeCurrentTab(): void {
    const maxIndex = this.advancedOptionsUnlocked ? 4 : 1
    if (this.currentTab < 0) {
      this.currentTab = 0
    } else if (this.currentTab > maxIndex) {
      this.currentTab = maxIndex
    }
  }
}
