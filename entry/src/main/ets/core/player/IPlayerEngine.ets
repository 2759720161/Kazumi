export interface IPlayerEngine {
  prepare(options: PlaybackOptions): void
  play(): void
  pause(): void
  stop(): void
  seek(positionMs: number): void
  setSpeed(speed: number): void
  setVolume(volume: number): void
  getState(): PlayerState
  onStateChange(callback: (state: PlayerState) => void): void
  release(): void
}

export class PlaybackOptions {
  url: string = ''
  headers: Record<string, string> = {}
  startPositionMs: number = 0
  referer: string = ''
  userAgent: string = ''
  proxy: string = ''
}

export class PlayerState {
  playing: boolean = false
  buffering: boolean = false
  positionMs: number = 0
  durationMs: number = 0
  bufferMs: number = 0
  volume: number = 1.0
  speed: number = 1.0
  completed: boolean = false
  error: string = ''
  stateName: string = 'idle'
}