import { common } from '@kit.AbilityKit'
import { RuleSourceStore } from './RuleSourceStore';
import { BundledRuleSourceLoader } from './BundledRuleSourceLoader';
import { PreferencesStore } from './PreferencesStore';
import { Logger } from '../utils/Logger';

const logger = new Logger('RuleSourceSeeder');

const PREFS_KEY_SEEDED = 'bundled_rules_seeded';

export class RuleSourceSeeder {
  static async seedIfEmpty(context: common.UIAbilityContext): Promise<void> {
    const prefs = PreferencesStore.getInstance();
    await RuleSourceSeeder.purgeRemovedUpstreamRules();

    const alreadySeeded = await prefs.getBoolean(PREFS_KEY_SEEDED, false);
    if (alreadySeeded) {
      logger.info('Bundled rules already seeded, skip');
      return;
    }

    const store = new RuleSourceStore();
    const count = await store.count();
    if (count > 0) {
      logger.info('RDB has existing rules (%{public}d), skip seed', count);
      await prefs.setBoolean(PREFS_KEY_SEEDED, true);
      return;
    }

    const bundledRules = await BundledRuleSourceLoader.loadAll(context);
    if (bundledRules.length === 0) {
      logger.warn('No bundled rules found in rawfile');
      return;
    }

    for (let i = 0; i < bundledRules.length; i++) {
      await store.insert(bundledRules[i]);
    }
    await prefs.setBoolean(PREFS_KEY_SEEDED, true);
    logger.info('Seeded %{public}d bundled rule sources', bundledRules.length);
  }

  static async restoreBundledRules(context: common.UIAbilityContext): Promise<number> {
    const store = new RuleSourceStore();
    await RuleSourceSeeder.purgeRemovedUpstreamRules();

    const bundledRules = await BundledRuleSourceLoader.loadAll(context);
    let restored = 0;
    for (let i = 0; i < bundledRules.length; i++) {
      const existing = await store.getByName(bundledRules[i].name);
      if (existing === null) {
        await store.insert(bundledRules[i]);
        restored++;
      } else {
        bundledRules[i].id = existing.id;
        bundledRules[i].enabled = existing.enabled;
        await store.update(bundledRules[i]);
        restored++;
      }
    }
    logger.info('Restored/updated %{public}d bundled rules', restored);
    return restored;
  }

  static async purgeRemovedUpstreamRules(): Promise<void> {
    const store = new RuleSourceStore();
    const deleted = await store.deleteLegacyGugu3Sources();
    if (deleted > 0) {
      logger.info('Removed %{public}d legacy gugu3 rule sources to match upstream bundled sources', deleted);
    }
  }
}
