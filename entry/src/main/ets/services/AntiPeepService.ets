import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { dlpAntiPeep } from '@kit.DeviceSecurityKit'
import { Logger, extractErrorMsg } from '../utils/Logger'

const logger = new Logger('AntiPeepService')

export const PREFS_KEY_ANTI_PEEP_ENABLED: string = 'antiPeepEnabled'
export const ANTI_PEEP_ENABLED_DEFAULT: boolean = false

/**
 * Bridges HarmonyOS DlpAntiPeep to the application lifecycle.
 * The mask is created by the system, so no ArkUI overlay is needed here.
 */
export class AntiPeepService {
  private static instance: AntiPeepService | null = null
  private context: common.UIAbilityContext | null = null
  private listening: boolean = false
  private starting: boolean = false
  private hasShownMask: boolean = false
  private enabled: boolean = ANTI_PEEP_ENABLED_DEFAULT

  private readonly onStatusChange = async (status: dlpAntiPeep.DlpAntiPeepStatus): Promise<void> => {
    if (status === dlpAntiPeep.DlpAntiPeepStatus.PASS) {
      this.hasShownMask = false
      logger.debug('System anti-peep status: PASS')
      return
    }
    if (status === dlpAntiPeep.DlpAntiPeepStatus.HIDE) {
      logger.info('System anti-peep status: HIDE')
      if (!this.hasShownMask) {
        await this.showSystemMask()
      }
    }
  }

  private constructor() {
  }

  static getInstance(): AntiPeepService {
    if (AntiPeepService.instance === null) {
      AntiPeepService.instance = new AntiPeepService()
    }
    return AntiPeepService.instance
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled
    if (!enabled) {
      this.stop()
    }
  }

  async enable(context: common.UIAbilityContext): Promise<boolean> {
    this.enabled = true
    try {
      const isOpen = await dlpAntiPeep.isDlpAntiPeepSwitchOn()
      if (!isOpen) {
        const result = await dlpAntiPeep.requestAntiPeepOptions(context)
        if (result !== dlpAntiPeep.AntiPeepOptionsResult.SUCCESS &&
          result !== dlpAntiPeep.AntiPeepOptionsResult.ALREADY_ON) {
          this.enabled = false
          return false
        }
      }
      await this.start(context)
      return true
    } catch (err) {
      this.enabled = false
      logger.warn('Failed to enable system anti-peep: %{public}s', extractErrorMsg(err))
      return false
    }
  }

  async start(context: common.UIAbilityContext): Promise<void> {
    this.context = context
    if (!this.enabled) {
      return
    }
    if (this.listening || this.starting) {
      return
    }

    this.starting = true
    try {
      const enabled = await dlpAntiPeep.isDlpAntiPeepSwitchOn()
      if (!enabled) {
        logger.info('System anti-peep is disabled for this application')
        return
      }

      dlpAntiPeep.on('dlpAntiPeep', this.onStatusChange)
      this.listening = true
      this.hasShownMask = false

      const status = dlpAntiPeep.getDlpAntiPeepInfo()
      await this.onStatusChange(status)
      logger.info('System anti-peep listener registered')
    } catch (err) {
      logger.warn('System anti-peep unavailable: %{public}s', extractErrorMsg(err))
    } finally {
      this.starting = false
    }
  }

  stop(): void {
    if (this.listening) {
      try {
        dlpAntiPeep.off('dlpAntiPeep', this.onStatusChange)
      } catch (err) {
        logger.warn('Failed to unregister system anti-peep listener: %{public}s', extractErrorMsg(err))
      }
    }
    this.listening = false
    this.starting = false
    this.hasShownMask = false
    this.context = null
  }

  private async showSystemMask(): Promise<void> {
    if (this.context === null || this.hasShownMask) {
      return
    }
    try {
      const currentWindow = await window.getLastWindow(this.context)
      const windowId = currentWindow.getWindowProperties().id
      await dlpAntiPeep.setAntiPeepMaskLayer(windowId)
      this.hasShownMask = true
      logger.info('System anti-peep mask shown, windowId=%{public}d', windowId)
    } catch (err) {
      logger.warn('Failed to show system anti-peep mask: %{public}s', extractErrorMsg(err))
    }
  }
}
