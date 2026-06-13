export enum PlayerStateEnum {
  IDLE = 'idle',
  INITIALIZED = 'initialized',
  PREPARING = 'preparing',
  PREPARED = 'prepared',
  PLAYING = 'playing',
  PAUSED = 'paused',
  STOPPED = 'stopped',
  COMPLETED = 'completed',
  ERROR = 'error',
  RELEASED = 'released'
}

export class PlayerState {
  state: PlayerStateEnum = PlayerStateEnum.IDLE;
  positionMs: number = 0;
  durationMs: number = 0;
  bufferMs: number = 0;
  volume: number = 1.0;
  speed: number = 1.0;
  errorMessage: string = '';

  get isPlaying(): boolean {
    return this.state === PlayerStateEnum.PLAYING;
  }

  get isPaused(): boolean {
    return this.state === PlayerStateEnum.PAUSED;
  }

  get isPrepared(): boolean {
    return this.state === PlayerStateEnum.PREPARED;
  }

  get isCompleted(): boolean {
    return this.state === PlayerStateEnum.COMPLETED;
  }

  get isError(): boolean {
    return this.state === PlayerStateEnum.ERROR;
  }

  getProgressPercent(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    return Math.min(100, Math.floor(this.positionMs * 100 / this.durationMs));
  }
}