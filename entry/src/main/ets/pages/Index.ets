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
import { setHomePreloadEnabled } from '../utils/HomePreloadGate'
import { PreferencesStore } from '../store/PreferencesStore'
import {
  THIRD_LAUNCH_NOTICE_ACKNOWLEDGED_PREF_KEY,
  THIRD_LAUNCH_NOTICE_PENDING_KEY
} from '../utils/ThirdLaunchNotice'

const logger = new Logger('Index')
const APP_PREFERENCES_READY_KEY: string = 'appPreferencesReady'
const DOWNLOAD_NAVIGATION_TOKEN_KEY: string = 'downloadNavigationToken'

@CustomDialog
struct ThirdLaunchSupportDialog {
  controller?: CustomDialogController
  onAcknowledge: () => void = (): void => {}
  @State private remainingSeconds: number = 5
  private countdownTimer: number = -1

  aboutToAppear(): void {
    this.remainingSeconds = 5
    this.stopCountdown()
    this.countdownTimer = setInterval((): void => {
      if (this.remainingSeconds <= 1) {
        this.remainingSeconds = 0
        this.stopCountdown()
        return
      }
      this.remainingSeconds -= 1
    }, 1000)
  }

  aboutToDisappear(): void {
    this.stopCountdown()
  }

  private stopCountdown(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = -1
    }
  }

  build() {
    Column() {
      Text('支持作者')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      Text('由于该应用无法上架应用商店（曾经上架过，但是被下架并封号），如果您对该应用感到满意，可以在应用市场下载“影匣”，并打开使用两分钟（可以的话，隔一两天打开一次）。影匣也会不断更新迭代，您的支持是对作者最大的鼓励。')
        .fontSize(16)
        .fontWeight(FontWeight.Regular)
        .fontColor($r('app.color.text_body'))
        .lineHeight(25)
        .textAlign(TextAlign.Start)
        .width('100%')

      Button(this.remainingSeconds > 0 ? `我已知晓（${this.remainingSeconds}）` : '我已知晓')
        .width('100%')
        .height(48)
        .margin({ top: 22 })
        .borderRadius(24)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_primary'))
        .backgroundColor(this.remainingSeconds > 0 ? $r('app.color.status_default') : $r('app.color.accent_blue'))
        .enabled(this.remainingSeconds === 0)
        .onClick((): void => {
          this.onAcknowledge()
          this.controller?.close()
        })
    }
    .width('86%')
    .constraintSize({ maxWidth: 430 })
    .padding({ left: 24, right: 24, top: 26, bottom: 24 })
    .borderRadius(26)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Center)
  }
}

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
  @StorageLink(THIRD_LAUNCH_NOTICE_PENDING_KEY) @Watch('onThirdLaunchNoticePendingChanged')
  thirdLaunchNoticePending: boolean = false
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
  private thirdLaunchNoticeOpening: boolean = false
  private thirdLaunchNoticeController: CustomDialogController | null = new CustomDialogController({
    builder: ThirdLaunchSupportDialog({
      onAcknowledge: (): void => {
        this.acknowledgeThirdLaunchNotice()
      }
    }),
    customStyle: true,
    autoCancel: false,
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_modal_bg')
  })

  aboutToAppear(): void {
    setHomePreloadEnabled(true)
    this.refreshHdsMaterialSupport()
    this.normalizeCurrentTab()
    ContinuationState.markIndex(this.currentTab)
    this.restoreContinuationIfNeeded()
    this.openDownloadPageIfNeeded()
    this.openThirdLaunchNoticeIfNeeded()
  }

  onPageShow(): void {
    setHomePreloadEnabled(true)
    logger.info('Index page visible, resume home preload')
    this.openThirdLaunchNoticeIfNeeded()
  }

  onPageHide(): void {
    setHomePreloadEnabled(false)
    logger.info('Index page hidden, pause home preload')
  }

  private onDownloadNavigationTokenChanged(): void {
    this.openDownloadPageIfNeeded()
  }

  private onThirdLaunchNoticePendingChanged(): void {
    this.openThirdLaunchNoticeIfNeeded()
  }

  private onAppPreferencesReadyChanged(): void {
    this.openThirdLaunchNoticeIfNeeded()
  }

  private openThirdLaunchNoticeIfNeeded(): void {
    if (!this.appPreferencesReady || !this.thirdLaunchNoticePending || this.thirdLaunchNoticeOpening) {
      return
    }
    this.thirdLaunchNoticeOpening = true
    setTimeout((): void => {
      if (!this.thirdLaunchNoticePending) {
        this.thirdLaunchNoticeOpening = false
        return
      }
      try {
        this.thirdLaunchNoticeController?.open()
      } catch (err) {
        this.thirdLaunchNoticeOpening = false
        const msg = err instanceof Error ? err.message : String(err)
        logger.warn('Open third-launch notice failed: %{public}s', msg)
      }
    }, 240)
  }

  private acknowledgeThirdLaunchNotice(): void {
    this.thirdLaunchNoticePending = false
    this.thirdLaunchNoticeOpening = false
    PreferencesStore.getInstance().setBoolean(
      THIRD_LAUNCH_NOTICE_ACKNOWLEDGED_PREF_KEY,
      true
    ).catch((err: Object): void => {
      logger.warn('Persist third-launch notice acknowledgement failed: %{public}s',
        err instanceof Error ? err.message : String(err))
    })
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

  build() {
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
