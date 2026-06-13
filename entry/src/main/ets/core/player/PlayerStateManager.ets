import { PlayerState } from '../../models/PlayerState';
import { PlayerStateEnum } from '../../models/PlayerState';
import { Logger } from '../../utils/Logger';

const logger = new Logger('PlayerStateManager');

export class PlayerStateManager {
  private static readonly STATE_KEY = 'playerState';
  private static instance: PlayerStateManager | null = null;
  private state: PlayerState = new PlayerState();

  private constructor() {
    this.updateAppStorage();
  }

  static getInstance(): PlayerStateManager {
    if (PlayerStateManager.instance === null) {
      PlayerStateManager.instance = new PlayerStateManager();
    }
    return PlayerStateManager.instance;
  }

  getState(): PlayerState {
    return this.state;
  }

  updateState(partial: PartialPlayerState): void {
    if (partial.positionMs >= 0) {
      this.state.positionMs = partial.positionMs;
    }
    if (partial.durationMs >= 0) {
      this.state.durationMs = partial.durationMs;
    }
    if (partial.bufferMs >= 0) {
      this.state.bufferMs = partial.bufferMs;
    }
    if (partial.volume >= 0) {
      this.state.volume = partial.volume;
    }
    if (partial.speed >= 0) {
      this.state.speed = partial.speed;
    }
    if (partial.errorMessage.length > 0) {
      this.state.errorMessage = partial.errorMessage;
    }
    this.updateAppStorage();
  }

  reset(): void {
    this.state = new PlayerState();
    this.updateAppStorage();
  }

  private updateAppStorage(): void {
    AppStorage.setOrCreate<string>('playerStateName', this.state.state);
    AppStorage.setOrCreate<number>('playerPositionMs', this.state.positionMs);
    AppStorage.setOrCreate<number>('playerDurationMs', this.state.durationMs);
    AppStorage.setOrCreate<boolean>('playerIsPlaying', this.state.isPlaying);
    AppStorage.setOrCreate<boolean>('playerIsBuffering', this.state.state === PlayerStateEnum.PLAYING);
  }
}

export class PartialPlayerState {
  state: PlayerStateEnum = PlayerStateEnum.IDLE;
  positionMs: number = -1;
  durationMs: number = -1;
  bufferMs: number = -1;
  volume: number = -1;
  speed: number = -1;
  errorMessage: string = '';
}