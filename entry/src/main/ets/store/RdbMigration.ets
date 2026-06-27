import { RdbManager } from './RdbManager';
import { RdbSchema } from './RdbSchema';
import { RdbConstants } from '../constants/RdbConstants';
import { Logger } from '../utils/Logger';

const logger = new Logger('RdbMigration');

interface MigrationStep {
  version: number;
  migrate: (rdbManager: RdbManager) => Promise<void>;
}

export class RdbMigration {
  private static migrations: MigrationStep[] = [
    {
      version: 1,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        const sqls = RdbSchema.getAllCreateSql();
        for (let i = 0; i < sqls.length; i++) {
          await rdbManager.executeSql(sqls[i]);
        }
        logger.info('Migration v1: tables created');
      }
    },
    {
      version: 2,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v2: anime_url column already exists in favorite, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1`
          );
        } catch (_err) {
          logger.info('Migration v2: source_id column already exists in favorite, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_WATCH_HISTORY} ADD COLUMN ${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v2: anime_url column already exists in watch_history, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_WATCH_HISTORY} ADD COLUMN ${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1`
          );
        } catch (_err) {
          logger.info('Migration v2: source_id column already exists in watch_history, skipping');
        }
        logger.info('Migration v2: added anime_url and source_id columns');
      }
    },
    {
      version: 3,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_COLLECT_TYPE} INTEGER NOT NULL DEFAULT 1`
          );
        } catch (_err) {
          logger.info('Migration v3: collect_type column already exists, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_BANGUMI_ID} INTEGER NOT NULL DEFAULT -1`
          );
        } catch (_err) {
          logger.info('Migration v3: bangumi_id column already exists, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_BANGUMI_COVER} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v3: bangumi_cover column already exists, skipping');
        }
        try {
          await rdbManager.executeSql(
            `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_COVER_FALLBACK} TEXT NOT NULL DEFAULT ''`
          );
        } catch (_err) {
          logger.info('Migration v3: cover_fallback column already exists, skipping');
        }
        await rdbManager.executeSql(
          RdbSchema.getCreateCollectChangeTable()
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_collect_change_bangumi_id ON ${RdbConstants.TABLE_COLLECT_CHANGE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_collect_type ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_COLLECT_TYPE})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_bangumi_id ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        logger.info('Migration v3: added collect_type, bangumi_id, bangumi_cover, cover_fallback columns and collect_change table');
      }
    },
    {
      version: 4,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.ensureFavoriteCollectColumns(rdbManager);
        await rdbManager.executeSql(
          RdbSchema.getCreateCollectChangeTable()
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_collect_change_bangumi_id ON ${RdbConstants.TABLE_COLLECT_CHANGE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_collect_type ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_COLLECT_TYPE})`
        );
        await rdbManager.executeSql(
          `CREATE INDEX IF NOT EXISTS idx_favorite_bangumi_id ON ${RdbConstants.TABLE_FAVORITE}(${RdbConstants.COL_BANGUMI_ID})`
        );
        logger.info('Migration v4: repaired favorite collect schema');
      }
    },
    {
      version: 5,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_WATCH_HISTORY,
          RdbConstants.COL_ROAD_INDEX,
          'INTEGER NOT NULL DEFAULT -1');
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_WATCH_HISTORY,
          RdbConstants.COL_EPISODE_INDEX,
          'INTEGER NOT NULL DEFAULT -1');
        logger.info('Migration v5: added road_index and episode_index to watch_history');
      }
    },
    {
      version: 6,
      migrate: async (rdbManager: RdbManager): Promise<void> => {
        await RdbMigration.addColumnIfMissing(rdbManager,
          RdbConstants.TABLE_RULE_SOURCE,
          RdbConstants.COL_SORT_ORDER,
          'INTEGER NOT NULL DEFAULT 0');
        logger.info('Migration v6: added sort_order to rule_source');
      }
    }
  ];

  private static async ensureFavoriteCollectColumns(rdbManager: RdbManager): Promise<void> {
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_ANIME_URL, 'TEXT NOT NULL DEFAULT \'\'');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_SOURCE_ID, 'INTEGER NOT NULL DEFAULT -1');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_COLLECT_TYPE, 'INTEGER NOT NULL DEFAULT 1');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_BANGUMI_ID, 'INTEGER NOT NULL DEFAULT -1');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_BANGUMI_COVER, 'TEXT NOT NULL DEFAULT \'\'');
    await RdbMigration.addColumnIfMissing(rdbManager, RdbConstants.TABLE_FAVORITE,
      RdbConstants.COL_COVER_FALLBACK, 'TEXT NOT NULL DEFAULT \'\'');
  }

  private static async addColumnIfMissing(rdbManager: RdbManager, table: string, column: string,
    definition: string): Promise<void> {
    try {
      await rdbManager.executeSql(
        `ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`
      );
      logger.info('Added column %{public}s.%{public}s', table, column);
    } catch (_err) {
      logger.info('Column %{public}s.%{public}s already exists, skipping', table, column);
    }
  }

  static async migrateToVersion(rdbManager: RdbManager, targetVersion: number, currentVersion: number = 0): Promise<void> {
    logger.info('Starting migration from version %{public}d to version %{public}d', currentVersion, targetVersion);

    for (let i = 0; i < RdbMigration.migrations.length; i++) {
      const migration = RdbMigration.migrations[i];
      if (migration.version <= currentVersion) {
        continue;
      }
      if (migration.version > targetVersion) {
        break;
      }

      try {
        rdbManager.beginTransaction();
        await migration.migrate(rdbManager);
        rdbManager.commit();
        logger.info('Migration v%{public}d completed', migration.version);
      } catch (err) {
        rdbManager.rollBack();
        const msg = err instanceof Error ? err.message : String(err);
        logger.error('Migration v%{public}d failed, rolled back: %{public}s',
          migration.version, msg);
        throw new Error(msg);
      }
    }

    logger.info('Migration to version %{public}d completed', targetVersion);
  }

  static getCurrentVersion(): number {
    return RdbConstants.DB_VERSION;
  }
}
