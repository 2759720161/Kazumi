import { common } from '@kit.AbilityKit'
import { PreferencesStore } from './PreferencesStore';
import { Logger } from '../utils/Logger';

const logger = new Logger('RuleSourceSeeder');

const PREFS_KEY_SEEDED = 'bundled_rules_seeded';

export class RuleSourceSeeder {
  static async seedIfEmpty(context: common.UIAbilityContext): Promise<void> {
    const prefs = PreferencesStore.getInstance();
    await RuleSourceSeeder.purgeRemovedUpstreamRules();
    await prefs.setBoolean(PREFS_KEY_SEEDED, true);
    logger.info('Bundled rule seeding disabled; rules must be installed from repository or imported by user');
  }

  static async restoreBundledRules(context: common.UIAbilityContext): Promise<number> {
    await RuleSourceSeeder.purgeRemovedUpstreamRules();
    logger.info('Bundled rule restore disabled; use rule repository import actions instead');
    return 0;
  }

  static async purgeRemovedUpstreamRules(): Promise<void> {
    logger.info('Bundled rule cleanup skipped; online rule shop entries must remain user-installable');
  }
}
