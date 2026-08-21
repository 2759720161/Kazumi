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
import { PreferencesStore } from '../store/PreferencesStore'
import { QixiAudioService } from '../services/QixiAudioService'
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
import { setHomePreloadEnabled } from '../utils/HomePreloadGate'

const logger = new Logger('Index')
const APP_PREFERENCES_READY_KEY: string = 'appPreferencesReady'
const DOWNLOAD_NAVIGATION_TOKEN_KEY: string = 'downloadNavigationToken'
const QIXI_AUDIO_PROMPT_HANDLED_KEY: string = 'qixiAudioPromptHandled_1_0_8'

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
  advancedOptionsUnlocked: boolean = true
  @StorageLink(HIDE_LOCAL_PAGE_KEY) @Watch('onHideLocalPageChanged')
  hideLocalPage: boolean = false
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @StorageLink(CONTINUATION_RESTORE_PAYLOAD_KEY) continuationRestorePayload: string = ''
  @StorageLink(CONTINUATION_RESTORE_TOKEN_KEY) @Watch('onContinuationRestoreTokenChanged')
  continuationRestoreToken: number = 0
  @StorageLink(APP_PREFERENCES_READY_KEY) @Watch('onAppPreferencesReadyChanged')
  appPreferencesReady: boolean = false
  @StorageLink(DOWNLOAD_NAVIGATION_TOKEN_KEY) @Watch('onDownloadNavigationTokenChanged')
  downloadNavigationToken: number = 0
  @State private showQixiAudioDialog: boolean = false
  @State private hdsImmersiveMaterialSupported: boolean = true
  private tabsController: HdsTabsController = new HdsTabsController()
  private bottomTabControllerHidden: boolean = false
  private readonly hdsTabBarHeight: number = 54
  private readonly hdsTabBottomMargin: number = 26
  private readonly backExitIntervalMs: number = 2000
  private lastBackPressTime: number = 0
  private handledContinuationRestoreToken: number = -1
  private pendingMainTabIndex: number = -1
  private handledDownloadNavigationToken: number = 0
  private qixiAudioPromptChecked: boolean = false
  private qixiAudioPromptHandling: boolean = false
  private readonly qixiAudioService: QixiAudioService = QixiAudioService.getInstance()

  aboutToAppear(): void {
    setHomePreloadEnabled(true)
    this.refreshHdsMaterialSupport()
    this.normalizeCurrentTab()
    ContinuationState.markIndex(this.currentTab)
    this.restoreContinuationIfNeeded()
    this.openDownloadPageIfNeeded()
    this.checkQixiAudioPrompt()
  }

  onPageShow(): void {
    setHomePreloadEnabled(true)
    logger.info('Index page visible, resume home preload')
  }

  onPageHide(): void {
    setHomePreloadEnabled(false)
    logger.info('Index page hidden, pause home preload')
  }

  private onAppPreferencesReadyChanged(): void {
    this.checkQixiAudioPrompt()
  }

  private async checkQixiAudioPrompt(): Promise<void> {
    if (!this.appPreferencesReady || this.qixiAudioPromptChecked || !this.isQixiAudioPromptAvailable()) {
      return
    }
    this.qixiAudioPromptChecked = true
    const handled = await PreferencesStore.getInstance().getBoolean(QIXI_AUDIO_PROMPT_HANDLED_KEY, false)
    if (!handled) {
      this.showQixiAudioDialog = true
    }
  }

  private isQixiAudioPromptAvailable(): boolean {
    const now = new Date()
    const currentYear = now.getFullYear()
    const currentMonth = now.getMonth() + 1
    const currentDay = now.getDate()
    if (currentYear !== 2026) {
      return currentYear > 2026
    }
    if (currentMonth !== 8) {
      return currentMonth > 8
    }
    return currentDay >= 19
  }

  private async handleQixiAudioPrompt(playAudio: boolean): Promise<void> {
    if (this.qixiAudioPromptHandling) {
      return
    }
    this.qixiAudioPromptHandling = true
    this.showQixiAudioDialog = false
    await PreferencesStore.getInstance().setBoolean(QIXI_AUDIO_PROMPT_HANDLED_KEY, true)
    if (!playAudio) {
      return
    }
    try {
      await this.qixiAudioService.play(getContext(this) as common.UIAbilityContext)
    } catch (_err) {
      promptAction.showToast({ message: '音频播放失败' })
    }
  }

  private onDownloadNavigationTokenChanged(): void {
    this.openDownloadPageIfNeeded()
  }

  private openDownloadPageIfNeeded(): void {
    if (this.downloadNavigationToken <= 0 ||
      this.downloadNavigationToken === this.handledDownloadNavigationToken) {
      return
    }
    this.handledDownloadNavigationToken = this.downloadNavigationToken
    router.pushUrl({ url: 'pages/download/DownloadPage' }).catch((err: Object): void => {
      logger.warn('Open download page failed: %{public}s', err instanceof Error ? err.message : String(err))
    })
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

  @Builder
  private QixiAudioDialog(): void {
    Column() {
      Column() {
        Text('七夕神秘小音频')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Text('注：取消后无法通过应用内再次打开播放')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 14 })
        Row() {
          Text('取消')
            .fontSize(17)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(52)
            .onClick(() => {
              this.handleQixiAudioPrompt(false)
            })
          Divider()
            .vertical(true)
            .height(24)
            .color($r('app.color.card_specular_border'))
          Text('播放')
            .fontSize(17)
            .fontColor($r('app.color.tab_icon_selected'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(52)
            .onClick(() => {
              this.handleQixiAudioPrompt(true)
            })
        }
        .width('100%')
        .margin({ top: 22 })
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 20 })
      .borderRadius(34)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0x66000000)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20, bottom: 28 })
    .onClick(() => {
      // Keep the prompt open until the user explicitly chooses Cancel or Play.
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      HdsTabs({
        controller: this.tabsController,
        index: this.currentTab
      }) {
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
            .tabBar(this.bottomTabStyle($r('sys.symbol.arrow_down_circle'),
              $r('sys.symbol.arrowshape_down_to_line_fill'), '下载'))
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
      .animationDuration(300)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
          if (this.pendingMainTabIndex >= 0 && index !== this.pendingMainTabIndex) {
            logger.info('Ignore stale main tab index during rebuild: %{public}d', index)
            return
          }
          if (index === this.pendingMainTabIndex) {
            this.pendingMainTabIndex = -1
          }
          logger.info('Main tab changed: %{public}d', index)
          this.currentTab = index
          ContinuationState.markIndex(index)
          this.bottomTabOffset = 0
          this.applyBottomTabVisibilityAnimation(false)
      })
    }
      .width('100%')
      .height(LayoutPolicy.matchParent)
      .backgroundColor($r('app.color.page_background'))

      if (this.showQixiAudioDialog) {
        this.QixiAudioDialog()
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
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

  private getLocalTabIndex(): number {
    if (this.hideLocalPage) {
      return -1
    }
    return this.advancedOptionsUnlocked ? 3 : 0
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
    if (!this.appPreferencesReady) {
      logger.info('Restore advanced tabs during startup; keep Home selected')
      this.switchMainTabAfterStructureChange(0)
      return
    }
    // Unlocking inserts three tabs before Settings. Switch by page identity instead
    // of retaining the old numeric index, which would now point to Timeline.
    this.switchMainTabAfterStructureChange(this.getSettingsTabIndex())
  }

  private switchMainTabAfterStructureChange(targetIndex: number): void {
    this.pendingMainTabIndex = targetIndex
    this.currentTab = targetIndex
    ContinuationState.markIndex(targetIndex)
    this.synchronizeMainTabAfterRebuild(targetIndex)
  }

  private synchronizeMainTabAfterRebuild(targetIndex: number, attempt: number = 0): void {
    const delayMs = attempt === 0 ? 32 : 80
    setTimeout(() => {
      if (this.pendingMainTabIndex !== targetIndex) {
        return
      }
      try {
        this.tabsController.changeIndex(targetIndex)
      } catch (err) {
        this.pendingMainTabIndex = -1
        const msg = err instanceof Error ? err.message : String(err)
        logger.warn('Synchronize main tab after rebuild failed: %{public}s', msg)
        return
      }
      if (this.pendingMainTabIndex === targetIndex && attempt < 2) {
        this.synchronizeMainTabAfterRebuild(targetIndex, attempt + 1)
      }
    }, delayMs)
  }

  private onHideLocalPageChanged(): void {
    const previousSettingsIndex = this.advancedOptionsUnlocked
      ? (this.hideLocalPage ? 4 : 3)
      : (this.hideLocalPage ? 1 : 0)
    const previousLocalIndex = this.advancedOptionsUnlocked ? 3 : 0

    if (this.currentTab === previousSettingsIndex ||
      (this.hideLocalPage && this.currentTab === previousLocalIndex)) {
      this.switchMainTabAfterStructureChange(this.getSettingsTabIndex())
      return
    }

    const maxIndex = this.getSettingsTabIndex()
    const targetIndex = Math.min(Math.max(this.currentTab, 0), maxIndex)
    this.switchMainTabAfterStructureChange(targetIndex)
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
