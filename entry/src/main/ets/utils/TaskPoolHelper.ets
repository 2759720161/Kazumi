import { taskpool } from '@kit.ArkTS';
import { Logger } from './Logger';

const logger = new Logger('TaskPoolHelper');

export class TaskPoolHelper {
  static execute<T>(task: taskpool.Task): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      taskpool.execute(task).then((result: Object) => {
        resolve(result as T);
      }).catch((err: Error) => {
        logger.error('TaskPool task failed: %{public}s', JSON.stringify(err));
        reject(err);
      });
    });
  }

  static executeGroup(tasks: taskpool.Task[]): Promise<Object[]> {
    return new Promise<Object[]>((resolve, reject) => {
      taskpool.executeInSequence(tasks).then((results: Object[]) => {
        resolve(results);
      }).catch((err: Error) => {
        logger.error('TaskPool group failed: %{public}s', JSON.stringify(err));
        reject(err);
      });
    });
  }

  static cancel(task: taskpool.Task): void {
    try {
      taskpool.cancel(task);
    } catch (err) {
      logger.warn('TaskPool cancel failed: %{public}s', JSON.stringify(err));
    }
  }
}
