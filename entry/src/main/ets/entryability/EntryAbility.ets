 import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { RdbManager } from '../store/RdbManager';

import { PreferencesStore } from '../store/PreferencesStore';
import { FileStore } from '../store/FileStore';
import { Logger } from '../utils/Logger';
import { SettingsChangeSignal } from '../store/SettingsChangeSignal';

const logger = new Logger('EntryAbility');

export default class EntryAbility extends UIAbility {
  private displayDensity: number = 3.0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('topSafeHeight', 0);
    AppStorage.setOrCreate('bottomSafeHeight', 0);
    AppStorage.setOrCreate('keyboardAvoidHeight', 0);
    AppStorage.setOrCreate('screenWidthVp', 0);
    AppStorage.setOrCreate('screenHeightVp', 0);
    SettingsChangeSignal.initDanmakuVersion();

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
    logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Ability onWindowStageCreate');

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

    const currentDisplay: display.Display = display.getDefaultDisplaySync();
    this.displayDensity = currentDisplay.densityPixels > 0 ? currentDisplay.densityPixels : 3.0;
    AppStorage.setOrCreate('screenWidthVp', currentDisplay.width / this.displayDensity);
    AppStorage.setOrCreate('screenHeightVp', currentDisplay.height / this.displayDensity);
    this.updateSystemSafeArea(mainWindow);
    mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        AppStorage.setOrCreate('topSafeHeight', data.area.topRect.height / this.displayDensity);
        AppStorage.setOrCreate('bottomSafeHeight', data.area.bottomRect.height / this.displayDensity);
      } else if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
        AppStorage.setOrCreate('keyboardAvoidHeight', data.area.bottomRect.height / this.displayDensity);
      }
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        logger.error('Failed to load content: %{public}s', err.message);
        return;
      }
      logger.info('Succeeded in loading content.');
    });
  }

  onWindowStageDestroy(): void {
    logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    logger.info('Ability onBackground');
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
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to init Preferences: %{public}s', msg);
    }

    try {
      const rdbManager = RdbManager.getInstance();
      await rdbManager.init(this.context);
      logger.info('RDB initialized');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to init RDB: %{public}s', msg);
    }

    try {

      FileStore.getInstance().init(this.context);
      logger.info('FileStore initialized');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to init FileStore: %{public}s', msg);
    }
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

}
