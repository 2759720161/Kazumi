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
import { promptAction, router, SymbolGlyphModifier, window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'
import {
  BOTTOM_TAB_ANIMATION_HIDDEN_KEY,
  BOTTOM_TAB_ANIMATION_TOKEN_KEY,
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
} from '../utils/BottomTabAutoHide'
import { ADVANCED_OPTIONS_UNLOCKED_KEY, HIDE_LOCAL_PAGE_KEY } from '../utils/AdvancedOptionsUnlock'
import {
  CONTINUATION_RESTORE_PAYLOAD_KEY,
  CONTINUATION_RESTORE_TOKEN_KEY,
  ContinuationPayload,
  ContinuationState
} from '../utils/ContinuationState'
import {
  buildAdaptiveMaterialEffect as buildSharedAdaptiveMaterialEffect,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../utils/HdsPageStyle'

const logger = new Logger('Index')

@Entry
@Component
struct Index {
  @StorageLink('currentTab') currentTab: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink('playerFullScreen') playerFullScreen: boolean = false
  @StorageLink('screenWidthVp') @Watch('onScreenSizeChanged') screenWidthVp: number = 0
  @StorageLink('bottomTabAutoHide') @Watch('onBottomTabAutoHideChanged') bottomTabAutoHide: boolean = BOTTOM_TAB_AUTO_HIDE_DEFAULT
  @StorageLink('bottomTabShowAnimation') bottomTabShowAnimation: boolean = BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
  @StorageLink('bottomTabOffset') bottomTabOffset: number = 0
  @StorageLink(BOTTOM_TAB_ANIMATION_TOKEN_KEY) @Watch('onBottomTabAnimationTokenChanged')
  bottomTabAnimationToken: number = 0
  @StorageLink(BOTTOM_TAB_ANIMATION_HIDDEN_KEY) bottomTabAnimationHidden: boolean = false
  @StorageLink(ADVANCED_OPTIONS_UNLOCKED_KEY) @Watch('onAdvancedOptionsUnlockedChanged')
  advancedOptionsUnlocked: boolean = false
  @StorageLink(HIDE_LOCAL_PAGE_KEY) @Watch('onHideLocalPageChanged')
  hideLocalPage: boolean = false
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(CONTINUATION_RESTORE_PAYLOAD_KEY) continuationRestorePayload: string = ''
  @StorageLink(CONTINUATION_RESTORE_TOKEN_KEY) @Watch('onContinuationRestoreTokenChanged')
  continuationRestoreToken: number = 0
  @State private hdsImmersiveMaterialSupported: boolean = true
  private tabsController: HdsTabsController = new HdsTabsController()
  private bottomTabControllerHidden: boolean = false
  private readonly hdsTabBarHeight: number = 54
  private readonly hdsTabBottomMargin: number = 26
  private readonly backExitIntervalMs: number = 2000
  private lastBackPressTime: number = 0
  private handledContinuationRestoreToken: number = -1

  aboutToAppear(): void {
    this.refreshHdsMaterialSupport()
    this.normalizeCurrentTab()
    ContinuationState.markIndex(this.currentTab)
    this.restoreContinuationIfNeeded()
  }

  private onScreenSizeChanged(): void {
    this.ensurePortraitOrientation()
  }

  onBackPress(): boolean {
    const now = Date.now()
    if (now - this.lastBackPressTime > this.backExitIntervalMs) {
      this.lastBackPressTime = now
      promptAction.showToast({ message: '再滑一次退出' })
      return true
    }

    const context = getContext(this) as common.UIAbilityContext
    context.terminateSelf().catch((err: Error) => {
      const msg = err instanceof Error ? err.message : String(err)
      logger.warn('Terminate app failed: %{public}s', msg)
    })
    return true
  }

  private async ensurePortraitOrientation(): Promise<void> {
    if (this.playerFullScreen) {
      return
    }
    if (this.screenWidthVp >= 600) {
      return
    }
    try {
      const context = getContext(this)
      const mainWindow = await window.getLastWindow(context)
      await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT)
    } catch (_err) {
      logger.warn('Failed to set portrait orientation')
    }
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

        if (!this.hideLocalPage) {
          TabContent() {
            LocalPage({ isActive: this.currentTab === this.getLocalTabIndex() })
          }
          .tabBar(this.bottomTabStyle($r('sys.symbol.folder'), $r('sys.symbol.folder_fill'), '本地'))
        }

        TabContent() {
          SettingsPage()
        }
        .tabBar(this.bottomTabStyle($r('sys.symbol.person'), $r('sys.symbol.person_fill'), '我的'))
      }
      .barOverlap(true)
      .vertical(false)
      .scrollable(false)
      .barPosition(BarPosition.End)
      .barHeight(this.getHdsTabBarHeight())
      .barFloatingStyle(this.buildHdsTabFloatingStyle())
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        logger.info('Main tab changed: %{public}d', index)
        this.currentTab = index
        ContinuationState.markIndex(index)
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

  private getSettingsTabIndex(): number {
    if (this.advancedOptionsUnlocked) {
      return this.hideLocalPage ? 3 : 4
    }
    return this.hideLocalPage ? 0 : 1
  }

  private getHdsTabBarHeight(): number {
    return this.isWideHdsTabsLayout() ? 54 : this.hdsTabBarHeight
  }

  private getHdsTabBarBottomMargin(): number {
    return this.isWideHdsTabsLayout() ? 20 : this.hdsTabBottomMargin
  }

  private getHdsGradientMaskHeight(): number {
    return this.getHdsTabBarHeight() + this.getHdsTabBarBottomMargin() + 28
  }

  private buildHdsTabFloatingStyle(): HdsTabsFloatingStyle {
    const tabCount = this.getTabCount()
    if (tabCount <= 2) {
      return {
        barWidth: { smallWidth: 133, mediumWidth: 152, largeWidth: 172 },
        barBottomMargin: this.bottomSafeHeight + this.getHdsTabBarBottomMargin(),
        gradientMask: {
          maskColor: $r('app.color.hds_tab_gradient_mask'),
          maskHeight: this.getHdsGradientMaskHeight()
        },
        thermoCtrl: true,
        systemMaterialEffect: this.buildAdaptiveMaterialEffect()
      }
    }
    if (tabCount <= 4) {
      return {
        barWidth: { smallWidth: 266, mediumWidth: 304, largeWidth: 344 },
        barBottomMargin: this.bottomSafeHeight + this.getHdsTabBarBottomMargin(),
        gradientMask: {
          maskColor: $r('app.color.hds_tab_gradient_mask'),
          maskHeight: this.getHdsGradientMaskHeight()
        },
        thermoCtrl: true,
        systemMaterialEffect: this.buildAdaptiveMaterialEffect()
      }
    }
    return {
      barWidth: { smallWidth: 332, mediumWidth: 380, largeWidth: 430 },
      barBottomMargin: this.bottomSafeHeight + this.getHdsTabBarBottomMargin(),
      gradientMask: {
        maskColor: $r('app.color.hds_tab_gradient_mask'),
        maskHeight: this.getHdsGradientMaskHeight()
      },
      thermoCtrl: true,
      systemMaterialEffect: this.buildAdaptiveMaterialEffect()
    }
  }

  private getTabCount(): number {
    if (this.advancedOptionsUnlocked) {
      return this.hideLocalPage ? 4 : 5
    }
    return this.hideLocalPage ? 1 : 2
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
    return buildSharedAdaptiveMaterialEffect(this.hdsMaterialLevel)
  }

  private onBottomTabAutoHideChanged(): void {
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      this.applyBottomTabVisibilityAnimation(false, true)
    }
  }

  private onAdvancedOptionsUnlockedChanged(): void {
    // Settings is always the last tab; if user was on it, stay on it
    this.currentTab = this.getSettingsTabIndex()
  }

  private onHideLocalPageChanged(): void {
    // If current tab exceeds new range, clamp to settings (last tab)
    const maxIndex = this.getSettingsTabIndex()
    if (this.currentTab > maxIndex) {
      this.currentTab = maxIndex
    }
  }

  private onBottomTabAnimationTokenChanged(): void {
    if (this.bottomTabAnimationToken === 0) {
      return
    }
    if (!this.bottomTabAutoHide) {
      this.bottomTabOffset = 0
      this.applyBottomTabVisibilityAnimation(false, true)
      return
    }
    this.applyBottomTabVisibilityAnimation(this.bottomTabAnimationHidden)
  }

  private applyBottomTabVisibilityAnimation(hidden: boolean, forceShow: boolean = false): void {
    try {
      this.bottomTabAnimationHidden = hidden
      if (hidden) {
        this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)
        this.bottomTabControllerHidden = true
      } else {
        if (!forceShow && !this.bottomTabControllerHidden && !this.bottomTabShowAnimation) {
          return
        }
        this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
        this.bottomTabControllerHidden = false
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
    if (this.hideLocalPage) {
      return -1
    }
    return this.advancedOptionsUnlocked ? 3 : 0
  }

  private normalizeCurrentTab(): void {
    const maxIndex = this.getSettingsTabIndex()
    if (this.currentTab < 0) {
      this.currentTab = 0
    } else if (this.currentTab > maxIndex) {
      this.currentTab = maxIndex
    }
  }

  private onContinuationRestoreTokenChanged(): void {
    this.restoreContinuationIfNeeded()
  }

  private restoreContinuationIfNeeded(): void {
    if (this.continuationRestoreToken === this.handledContinuationRestoreToken) {
      return
    }
    if (this.continuationRestorePayload.length === 0) {
      return
    }
    this.handledContinuationRestoreToken = this.continuationRestoreToken
    const payload = ContinuationState.parsePayload(this.continuationRestorePayload)
    if (payload === null) {
      logger.warn('Invalid continuation payload')
      return
    }
    this.applyContinuationPayload(payload)
  }

  private applyContinuationPayload(payload: ContinuationPayload): void {
    logger.info('Restore continuation route=%{public}s tab=%{public}d', payload.route, payload.currentTab)
    if (payload.currentTab >= 0) {
      this.currentTab = payload.currentTab
      this.normalizeCurrentTab()
    }
    if (payload.route === 'index') {
      ContinuationState.markIndex(this.currentTab)
      return
    }
    let params = ContinuationState.parseParams(payload.paramsJson)
    if (payload.route === 'player') {
      const playerParams = ContinuationState.parsePlayerParams(payload.paramsJson)
      if (payload.positionMs > 0) {
        playerParams.historyPositionMs = payload.positionMs
      }
      params = playerParams
    }
    const url = this.getContinuationRouteUrl(payload.route)
    if (url.length === 0) {
      return
    }
    setTimeout(() => {
      router.pushUrl({ url: url, params: params }).catch((err: Error) => {
        logger.warn('Restore continuation route failed: %{public}s', err.message)
      })
    }, 120)
  }

  private getContinuationRouteUrl(route: string): string {
    if (route === 'detail') {
      return 'pages/detail/DetailPage'
    }
    if (route === 'player') {
      return 'pages/player/PlayerPage'
    }
    return ''
  }
}
