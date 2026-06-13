import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { RuleSource } from '../models/RuleSource'
import { Logger } from '../utils/Logger'

const logger = new Logger('BundledRuleSourceLoader')

const BUNDLED_PLUGIN_FILES: string[] = [
  'plugins/AGE.json',
  'plugins/DM84.json',
  'plugins/aafun.json'
]

export class BundledRuleSourceLoader {
  static async loadAll(context: common.UIAbilityContext): Promise<RuleSource[]> {
    const rules: RuleSource[] = []
    for (let i = 0; i < BUNDLED_PLUGIN_FILES.length; i++) {
      try {
        const rule = await BundledRuleSourceLoader.loadOne(context, BUNDLED_PLUGIN_FILES[i])
        if (rule !== null) {
          rules.push(rule)
        }
      } catch (err) {
        logger.warn('Failed to load bundled plugin %{public}s: %{public}s',
          BUNDLED_PLUGIN_FILES[i], err instanceof Error ? err.message : String(err))
      }
    }
    logger.info('Loaded %{public}d bundled rule sources', rules.length)
    return rules
  }

  static async loadOne(context: common.UIAbilityContext, filePath: string): Promise<RuleSource | null> {
    const rawContent = await context.resourceManager.getRawFileContent(filePath)
    const textDecoder = util.TextDecoder.create('utf-8')
    const jsonStr = textDecoder.decodeToString(rawContent)
    const parsed = JSON.parse(jsonStr) as Record<string, Object>
    const rule = RuleSource.fromJSON(parsed)
    rule.enabled = true
    logger.info('Loaded bundled plugin: %{public}s v%{public}s', rule.name, rule.version)
    return rule
  }
}
