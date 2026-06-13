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
        await rdbManager.executeSql(
          `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT ''`
        );
        await rdbManager.executeSql(
          `ALTER TABLE ${RdbConstants.TABLE_FAVORITE} ADD COLUMN ${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1`
        );
        await rdbManager.executeSql(
          `ALTER TABLE ${RdbConstants.TABLE_WATCH_HISTORY} ADD COLUMN ${RdbConstants.COL_ANIME_URL} TEXT NOT NULL DEFAULT ''`
        );
        await rdbManager.executeSql(
          `ALTER TABLE ${RdbConstants.TABLE_WATCH_HISTORY} ADD COLUMN ${RdbConstants.COL_SOURCE_ID} INTEGER NOT NULL DEFAULT -1`
        );
        logger.info('Migration v2: added anime_url and source_id columns');
      }
    }
  ];

  static async migrateToVersion(rdbManager: RdbManager, targetVersion: number): Promise<void> {
    logger.info('Starting migration to version %{public}d', targetVersion);

    for (let i = 0; i < RdbMigration.migrations.length; i++) {
      const migration = RdbMigration.migrations[i];
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