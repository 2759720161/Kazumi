export class DanmakuItem {
  content: string = ''
  timeMs: number = 0
  color: string = '#FFFFFF'
  fontSize: number = 25
  type: number = 0
  trackIndex: number = -1
  x: number = 0
  isAlive: boolean = true
  textWidth: number = 0

  constructor(content: string, timeMs: number, color: string,
              fontSize: number, type: number) {
    this.content = content.length > 100 ? content.substring(0, 100) : content
    this.timeMs = timeMs
    this.color = color
    this.fontSize = Math.max(12, Math.min(36, fontSize))
    this.type = type
  }
}