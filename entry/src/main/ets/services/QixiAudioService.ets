import { media } from '@kit.MediaKit'
import { common } from '@kit.AbilityKit'
import { Logger } from '../utils/Logger'

const AUDIO_RESOURCE_NAME: string = 'TikVideo.App_7674922358881326058.mp3'

/** Plays the one-time 2026 Qixi audio from the bundled rawfile resource. */
export class QixiAudioService {
  private static instance: QixiAudioService | null = null
  private readonly logger: Logger = new Logger('QixiAudioService')
  private player: media.AVPlayer | null = null
  private generation: number = 0

  static getInstance(): QixiAudioService {
    if (QixiAudioService.instance === null) {
      QixiAudioService.instance = new QixiAudioService()
    }
    return QixiAudioService.instance
  }

  async play(context: common.UIAbilityContext): Promise<void> {
    await this.stop()
    const generation = ++this.generation
    const player = await media.createAVPlayer()
    if (generation !== this.generation) {
      this.releasePlayer(player)
      return
    }

    this.player = player
    player.on('stateChange', (state: string) => {
      if (this.player !== player) {
        return
      }
      if (state === 'initialized') {
        player.prepare().catch((err: Error) => {
          this.logger.warn('Qixi audio prepare failed: %{public}s', err.message)
          this.releasePlayer(player)
        })
      } else if (state === 'prepared') {
        player.play().catch((err: Error) => {
          this.logger.warn('Qixi audio play failed: %{public}s', err.message)
          this.releasePlayer(player)
        })
      } else if (state === 'completed' || state === 'error') {
        this.releasePlayer(player)
      }
    })
    player.on('error', (err: Error) => {
      this.logger.warn('Qixi audio error: %{public}s', err.message)
      this.releasePlayer(player)
    })

    try {
      const fileDescriptor = await context.resourceManager.getRawFd(AUDIO_RESOURCE_NAME)
      if (generation !== this.generation || this.player !== player) {
        this.releasePlayer(player)
        return
      }
      player.fdSrc = fileDescriptor
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      this.logger.warn('Qixi audio resource unavailable: %{public}s', message)
      this.releasePlayer(player)
      throw new Error(message)
    }
  }

  async stop(): Promise<void> {
    this.generation++
    const player = this.player
    this.player = null
    if (player !== null) {
      this.releasePlayer(player)
    }
  }

  private releasePlayer(player: media.AVPlayer): void {
    if (this.player === player) {
      this.player = null
      this.generation++
    }
    try {
      player.release()
    } catch (err) {
      this.logger.warn('Qixi audio release failed: %{public}s', err instanceof Error ? err.message : String(err))
    }
  }
}
