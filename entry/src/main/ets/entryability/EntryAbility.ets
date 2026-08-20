import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import type { Callback } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { RdbManager } from '../store/RdbManager';

import { PreferencesStore } from '../store/PreferencesStore';
import { FileStore } from '../store/FileStore';
import { Logger } from '../utils/Logger';
import { SettingsChangeSignal } from '../store/SettingsChangeSignal';
import { UserDownloadFolder } from '../services/UserDownloadFolder';
import { VideoDownloadManager } from '../services/VideoDownloadManager';
import {
  ANTI_PEEP_ENABLED_DEFAULT,
  AntiPeepService,
  PREFS_KEY_ANTI_PEEP_ENABLED
} from '../services/AntiPeepService';
import {
  BOTTOM_TAB_ANIMATION_HIDDEN_KEY,
  BOTTOM_TAB_ANIMATION_TOKEN_KEY,
  BOTTOM_TAB_AUTO_HIDE_DEFAULT,
  BOTTOM_TAB_SHOW_ANIMATION_DEFAULT,
  PREFS_KEY_BOTTOM_TAB_AUTO_HIDE,
  PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION
} from '../utils/BottomTabAutoHide';
import {
  ADVANCED_OPTIONS_UNLOCKED_KEY,
  HIDE_LOCAL_PAGE_KEY,
  HIDE_LOCAL_PAGE_DEFAULT,
  PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY
} from '../utils/AdvancedOptionsUnlock';
import {
  PLAYER_AUTO_FULLSCREEN_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_FULLSCREEN
} from '../utils/PlayerAutoFullscreen';
import {
  PLAYER_AUTO_PIP_DEFAULT,
  PREFS_KEY_PLAYER_AUTO_PIP
} from '../utils/PlayerAutoPiP';
import {
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../utils/HdsPageStyle';
import {
  API26_MATERIAL_STYLE_DEFAULT,
  PREFS_KEY_API26_MATERIAL_STYLE
} from '../utils/ImmersiveMaterial';
import {
  MPV_DETAIL_ENHANCER_ENABLED_DEFAULT,
  MPV_DETAIL_ENHANCER_QUALITY_DEFAULT,
  PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED,
  PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY
} from '../utils/MpvSettings';
import {
  CONTINUATION_PAYLOAD_KEY,
  CONTINUATION_RESTORE_PAYLOAD_KEY,
  CONTINUATION_RESTORE_TOKEN_KEY,
  CONTINUATION_SUPPORT_PAGE_STACK_KEY,
  ContinuationState
} from '../utils/ContinuationState';

const logger = new Logger('EntryAbility');
const APP_PREFERENCES_READY_KEY: string = 'appPreferencesReady';
const APP_RDB_READY_KEY: string = 'appRdbReady';
const DOWNLOAD_NAVIGATION_TOKEN_KEY: string = 'downloadNavigationToken';

export default class EntryAbility extends UIAbility {
  private displayDensity: number = 3.0;
  private pendingContinuationPayload: string = '';
  private storesInitialized: boolean = false;
  private readonly antiPeepService: AntiPeepService = AntiPeepService.getInstance();


  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('currentTab', 0);
    AppStorage.set<number>('currentTab', 0);
    AppStorage.setOrCreate(APP_PREFERENCES_READY_KEY, false);
    AppStorage.set<boolean>(APP_PREFERENCES_READY_KEY, false);
    AppStorage.setOrCreate(APP_RDB_READY_KEY, false);
    AppStorage.set<boolean>(APP_RDB_READY_KEY, false);
    AppStorage.setOrCreate(DOWNLOAD_NAVIGATION_TOKEN_KEY, 0);
    AppStorage.setOrCreate('topSafeHeight', 0);
    AppStorage.setOrCreate('bottomSafeHeight', 0);
    AppStorage.setOrCreate('keyboardAvoidHeight', 0);
    AppStorage.setOrCreate('playerFullScreen', false);
    AppStorage.setOrCreate('playerPageActive', false);
    AppStorage.setOrCreate('appInForeground', true);
    AppStorage.setOrCreate('screenWidthVp', 0);
    AppStorage.setOrCreate('screenHeightVp', 0);
    AppStorage.setOrCreate('bottomTabAutoHide', BOTTOM_TAB_AUTO_HIDE_DEFAULT);
    AppStorage.setOrCreate('bottomTabShowAnimation', BOTTOM_TAB_SHOW_ANIMATION_DEFAULT);
    AppStorage.setOrCreate('playerAutoFullscreen', PLAYER_AUTO_FULLSCREEN_DEFAULT);
    AppStorage.setOrCreate(PREFS_KEY_ANTI_PEEP_ENABLED, ANTI_PEEP_ENABLED_DEFAULT);
    AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, HDS_MATERIAL_LEVEL_DEFAULT);
    AppStorage.setOrCreate('bottomTabOffset', 0);
    AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_TOKEN_KEY, 0);
    AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_HIDDEN_KEY, false);
    AppStorage.setOrCreate(ADVANCED_OPTIONS_UNLOCKED_KEY, true);
    AppStorage.setOrCreate(PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY, false);
    AppStorage.setOrCreate(HIDE_LOCAL_PAGE_KEY, HIDE_LOCAL_PAGE_DEFAULT);
    AppStorage.setOrCreate(CONTINUATION_PAYLOAD_KEY, '');
    AppStorage.setOrCreate(CONTINUATION_RESTORE_PAYLOAD_KEY, '');
    AppStorage.setOrCreate(CONTINUATION_RESTORE_TOKEN_KEY, 0);
    AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, MPV_DETAIL_ENHANCER_ENABLED_DEFAULT);
    AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, MPV_DETAIL_ENHANCER_QUALITY_DEFAULT);
    SettingsChangeSignal.initDanmakuVersion();
    this.captureContinuationPayload(want);
    this.handleDownloadWant(want);

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to set colorMode: %{public}s', msg);
    }
    logger.info('Ability onCreate');

    this.initStores();
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    logger.info('Ability onConfigurationUpdate colorMode: %{public}d', newConfig.colorMode ?? -1);
  }

  onDestroy(): void {
    VideoDownloadManager.getInstance().flushPersistence()
    logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Ability onWindowStageCreate');
    this.setupMainWindowStage(windowStage);
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    logger.info('Ability onWindowStageRestore');
    this.setupMainWindowStage(windowStage, true);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.info('Ability onNewWant launchReason: %{public}d', launchParam.launchReason ?? -1);
    this.captureContinuationPayload(want);
    this.handleDownloadWant(want);
    if (this.pendingContinuationPayload.length > 0) {
      ContinuationState.publishRestorePayload(this.pendingContinuationPayload);
      this.pendingContinuationPayload = '';
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    logger.info('Ability onContinue');
    try {
      const payload = ContinuationState.getPayloadJson();
      if (payload.length > 0) {
        wantParam[CONTINUATION_PAYLOAD_KEY] = payload;
      }
      wantParam[CONTINUATION_SUPPORT_PAGE_STACK_KEY] = false;
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Ability onContinue failed: %{public}s', msg);
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  private setupMainWindowStage(windowStage: window.WindowStage, restoreContinuation: boolean = false): void {
    const mainWindow = windowStage.getMainWindowSync();
    mainWindow.setWindowLayoutFullScreen(true);
    const sysBarProps: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      statusBarContentColor: '#000000',
      navigationBarColor: '#00000000',
      navigationBarContentColor: '#000000'
    };
    mainWindow.setWindowSystemBarProperties(sysBarProps);
    mainWindow.setWindowSystemBarEnable(['status', 'navigation']);

    this.updateDisplayMetricsAndOrientation(mainWindow);
    this.updateSystemSafeArea(mainWindow);
    mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate('topSafeHeight', data.area.topRect.height / this.displayDensity);
        AppStorage.setOrCreate('bottomSafeHeight', data.area.bottomRect.height / this.displayDensity);
      } else if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
        AppStorage.setOrCreate('keyboardAvoidHeight', data.area.bottomRect.height / this.displayDensity);
      }
    });

    try {
      const foldCallback: Callback<display.FoldStatus> = (foldStatus: display.FoldStatus) => {
        logger.info('Fold status changed: %{public}d', foldStatus);
        this.updateDisplayMetricsAndOrientation(mainWindow);
      };
      display.on('foldStatusChange', foldCallback);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warn('Failed to register foldStatusChange listener: %{public}s', msg);
    }

    mainWindow.on('windowSizeChange', (data: window.Size) => {
      logger.info('Window size changed: %{public}d x %{public}d', data.width, data.height);
      this.updateDisplayMetricsAndOrientation(mainWindow);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        logger.error('Failed to load content: %{public}s', err.message);
        return;
      }
      logger.info('Succeeded in loading content.');
      if (restoreContinuation && this.pendingContinuationPayload.length > 0) {
        ContinuationState.publishRestorePayload(this.pendingContinuationPayload);
        this.pendingContinuationPayload = '';
      }
    });
  }

  private updateDisplayMetricsAndOrientation(mainWindow: window.Window): void {
    const currentDisplay: display.Display = display.getDefaultDisplaySync();
    this.displayDensity = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 3.0;
    const displayWidthVp = currentDisplay.width / this.displayDensity;
    const displayHeightVp = currentDisplay.height / this.displayDensity;
    const shortSideVp = Math.min(displayWidthVp, displayHeightVp);
    const currentDeviceType = deviceInfo.deviceType;
    const isTabletDevice = currentDeviceType === 'tablet' || shortSideVp >= 600;
    const screenWidthVp = isTabletDevice ? displayWidthVp : shortSideVp;
    const screenHeightVp = isTabletDevice ? displayHeightVp : Math.max(displayWidthVp, displayHeightVp);
    logger.info('Layout deviceType: %{public}s, display: %{public}d x %{public}d vp, tablet: %{public}s',
      currentDeviceType, Math.round(displayWidthVp), Math.round(displayHeightVp), isTabletDevice ? 'true' : 'false');
    AppStorage.setOrCreate('screenWidthVp', screenWidthVp);
    AppStorage.setOrCreate('screenHeightVp', screenHeightVp);
    const playerFullScreen = AppStorage.get<boolean>('playerFullScreen') === true;
    const playerPageActive = AppStorage.get<boolean>('playerPageActive') === true;
    const playerAutoFullscreen = AppStorage.get<boolean>('playerAutoFullscreen') === true;
    if (playerFullScreen || (playerPageActive && playerAutoFullscreen)) {
      logger.info('Skip global orientation reset: fullscreen=%{public}s playerActive=%{public}s autoFullscreen=%{public}s',
        String(playerFullScreen), String(playerPageActive), String(playerAutoFullscreen));
      return;
    }
    if (!isTabletDevice) {
      mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT);
    } else {
      mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
    }
  }

  onWindowStageDestroy(): void {
    this.antiPeepService.stop();
    logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    logger.info('Ability onForeground');
    AppStorage.setOrCreate('appInForeground', true);
    this.antiPeepService.start(this.context);
  }

  onBackground(): void {
    logger.info('Ability onBackground');
    VideoDownloadManager.getInstance().flushPersistence()
    AppStorage.setOrCreate('appInForeground', false);
    this.antiPeepService.stop();
  }

  private async initStores(): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(this.context, 'kazumi_settings');
      PreferencesStore.getInstance().init(prefs);
      logger.info('Preferences initialized');

      const savedColorMode = await PreferencesStore.getInstance().getNumber('colorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      if (savedColorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
        this.context.getApplicationContext().setColorMode(savedColorMode);
        logger.info('Applied saved colorMode: %{public}d', savedColorMode);
      }

      const bottomTabAutoHide = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_BOTTOM_TAB_AUTO_HIDE,
        BOTTOM_TAB_AUTO_HIDE_DEFAULT
      );
      AppStorage.setOrCreate('bottomTabAutoHide', bottomTabAutoHide);
      const bottomTabShowAnimation = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_BOTTOM_TAB_SHOW_ANIMATION,
        BOTTOM_TAB_SHOW_ANIMATION_DEFAULT
      );
      AppStorage.setOrCreate('bottomTabShowAnimation', bottomTabShowAnimation);
      const playerAutoFullscreen = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_PLAYER_AUTO_FULLSCREEN,
        PLAYER_AUTO_FULLSCREEN_DEFAULT
      );
      AppStorage.setOrCreate('playerAutoFullscreen', playerAutoFullscreen);
      const playerAutoPiP = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_PLAYER_AUTO_PIP,
        PLAYER_AUTO_PIP_DEFAULT
      );
      AppStorage.setOrCreate(PREFS_KEY_PLAYER_AUTO_PIP, playerAutoPiP);
      const antiPeepEnabled = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_ANTI_PEEP_ENABLED,
        ANTI_PEEP_ENABLED_DEFAULT
      );
      AppStorage.setOrCreate(PREFS_KEY_ANTI_PEEP_ENABLED, antiPeepEnabled);
      this.antiPeepService.setEnabled(antiPeepEnabled);
      if (antiPeepEnabled && AppStorage.get<boolean>('appInForeground') === true) {
        this.antiPeepService.start(this.context);
      }
      const hdsMaterialLevel = await PreferencesStore.getInstance().getString(
        PREFS_KEY_HDS_MATERIAL_LEVEL,
        HDS_MATERIAL_LEVEL_DEFAULT
      );
      AppStorage.setOrCreate(PREFS_KEY_HDS_MATERIAL_LEVEL, hdsMaterialLevel);
      const api26MaterialStyle = await PreferencesStore.getInstance().getString(
        PREFS_KEY_API26_MATERIAL_STYLE,
        API26_MATERIAL_STYLE_DEFAULT
      );
      AppStorage.setOrCreate(PREFS_KEY_API26_MATERIAL_STYLE, api26MaterialStyle);
      AppStorage.setOrCreate('bottomTabOffset', 0);
      AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_TOKEN_KEY, 0);
      AppStorage.setOrCreate(BOTTOM_TAB_ANIMATION_HIDDEN_KEY, false);

      // Advanced settings are part of the normal application surface.
      // Keep the legacy preference key for compatibility, but no longer gate
      // pages or services behind a version-tap unlock gesture.
      AppStorage.setOrCreate(ADVANCED_OPTIONS_UNLOCKED_KEY, true);
      const playerDebugOptionsUnlocked = await PreferencesStore.getInstance().getBoolean(
        PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY,
        false
      );
      AppStorage.setOrCreate(PLAYER_DEBUG_OPTIONS_UNLOCKED_KEY, playerDebugOptionsUnlocked);
      const hideLocalPage = await PreferencesStore.getInstance().getBoolean(
        HIDE_LOCAL_PAGE_KEY,
        HIDE_LOCAL_PAGE_DEFAULT
      );
      AppStorage.setOrCreate(HIDE_LOCAL_PAGE_KEY, hideLocalPage);

      const detailEnhancerEnabled = await PreferencesStore.getInstance().getBoolean(
        PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED,
        MPV_DETAIL_ENHANCER_ENABLED_DEFAULT
      );
      const hasDetailEnhancerEnabled = await PreferencesStore.getInstance().has(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED);
      const hasOldQualityKey = await PreferencesStore.getInstance().has('mpvDetailEnhancerQuality');
      let detailEnhancerQuality = await PreferencesStore.getInstance().getNumber(
        PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY,
        2
      );
      let effectiveEnabled = detailEnhancerEnabled;
      if (!hasDetailEnhancerEnabled && hasOldQualityKey) {
        const oldQuality = await PreferencesStore.getInstance().getNumber('mpvDetailEnhancerQuality', -1);
        effectiveEnabled = oldQuality >= 0;
        detailEnhancerQuality = oldQuality >= 0 ? oldQuality : 2;
        await PreferencesStore.getInstance().setBoolean(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, effectiveEnabled);
        await PreferencesStore.getInstance().setNumber(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, detailEnhancerQuality);
      }
      if (detailEnhancerQuality < 1 || detailEnhancerQuality > 3) {
        detailEnhancerQuality = 2;
      }
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_ENABLED, effectiveEnabled);
      AppStorage.setOrCreate(PREFS_KEY_MPV_DETAIL_ENHANCER_QUALITY, detailEnhancerQuality);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to init Preferences: %{public}s', msg);
    }
    AppStorage.setOrCreate(APP_PREFERENCES_READY_KEY, true);
    AppStorage.set<boolean>(APP_PREFERENCES_READY_KEY, true);

    try {
      const rdbManager = RdbManager.getInstance();
      await rdbManager.init(this.context);
      AppStorage.setOrCreate(APP_RDB_READY_KEY, true);
      AppStorage.set<boolean>(APP_RDB_READY_KEY, true);
      logger.info('RDB initialized');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      AppStorage.setOrCreate(APP_RDB_READY_KEY, false);
      AppStorage.set<boolean>(APP_RDB_READY_KEY, false);
      logger.error('Failed to init RDB: %{public}s', msg);
    }

    try {
      FileStore.getInstance().init(this.context);
      logger.info('FileStore initialized');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to init FileStore: %{public}s', msg);
    }

    try {
      await UserDownloadFolder.ensureOwnFolder(this.context);
      await VideoDownloadManager.getInstance().initialize(this.context);
      logger.info('UserDownloadFolder initialized');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to init UserDownloadFolder: %{public}s', msg);
    }

    this.storesInitialized = true;
  }

  private updateSystemSafeArea(mainWindow: window.Window): void {
    try {
      const systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topSafeHeight', systemArea.topRect.height / this.displayDensity);
      AppStorage.setOrCreate('bottomSafeHeight', systemArea.bottomRect.height / this.displayDensity);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warn('Failed to update system safe area: %{public}s', msg);
    }
  }

  private captureContinuationPayload(want: Want): void {
    const params = want.parameters;
    if (params === undefined || params === null) {
      return;
    }
    const payload = params[CONTINUATION_PAYLOAD_KEY];
    if (typeof payload === 'string' && payload.length > 0) {
      this.pendingContinuationPayload = payload;
      logger.info('Captured continuation payload');
    }
  }

  private handleDownloadWant(want: Want): void {
    const params = want.parameters;
    if (params === undefined || params === null) {
      return;
    }
    const actionValue = params['downloadAction'];
    if (typeof actionValue !== 'string' || actionValue.length === 0) {
      return;
    }
    if (actionValue === 'open') {
      const currentToken = AppStorage.get<number>(DOWNLOAD_NAVIGATION_TOKEN_KEY) ?? 0;
      AppStorage.setOrCreate(DOWNLOAD_NAVIGATION_TOKEN_KEY, currentToken + 1);
      AppStorage.set<number>(DOWNLOAD_NAVIGATION_TOKEN_KEY, currentToken + 1);
      return;
    }
    const taskIdValue = params['downloadTaskId'];
    if (typeof taskIdValue !== 'string' || taskIdValue.length === 0) {
      return;
    }
    this.executeDownloadAction(taskIdValue, actionValue).catch((err: Object): void => {
      const message = err instanceof Error ? err.message : String(err);
      logger.warn('Notification download action failed: %{public}s', message);
    });
  }

  private async executeDownloadAction(taskId: string, action: string): Promise<void> {
    const manager = VideoDownloadManager.getInstance();
    await manager.initialize(this.context);
    if (action === 'pause') {
      await manager.pause(taskId);
    } else if (action === 'resume') {
      await manager.resume(taskId);
    } else if (action === 'cancel') {
      await manager.cancel(taskId);
    }
  }

}
