import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitle,
  TitleBarStyleOptions,
  TitleBarContentOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions
} from '@kit.UIDesignKit'
import {
  VideoDownloadKind,
  VideoDownloadListener,
  VideoDownloadSnapshot,
  VideoDownloadState
} from '../../models/VideoDownloadTask'
import { VideoDownloadManager } from '../../services/VideoDownloadManager'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildImmersiveTitleBarStyle,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'

class DownloadMenuIconContent {
  content: HdsNavigationIconOptions

  constructor(content: HdsNavigationIconOptions) {
    this.content = content
  }
}

@Entry
@Component
export struct DownloadPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State tasks: VideoDownloadSnapshot[] = []
  @State isEditMode: boolean = false
  @State selectedTaskIds: string[] = []
  @State showDeleteDialog: boolean = false
  private readonly manager: VideoDownloadManager = VideoDownloadManager.getInstance()
  private readonly scroller: Scroller = new Scroller()
  private listener: VideoDownloadListener | null = null

  aboutToAppear(): void {
    this.listener = (_snapshot: VideoDownloadSnapshot): void => {
      this.refreshTasks()
    }
    this.manager.addListener(this.listener)
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.manager.initialize(context).then(() => {
      this.refreshTasks()
    })
  }

  aboutToDisappear(): void {
    if (this.listener !== null) {
      this.manager.removeListener(this.listener)
      this.listener = null
    }
  }

  onPageShow(): void {
    this.refreshTasks()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() {
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            Blank()
              .height(getTopSpacerHeight(this.topSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)

            if (this.tasks.length === 0) {
              this.EmptyState()
            } else {
              Column({ space: 12 }) {
                ForEach(this.tasks, (task: VideoDownloadSnapshot) => {
                  DownloadTaskCard({
                    task: task,
                    isEditMode: this.isEditMode,
                    isSelected: this.selectedTaskIds.indexOf(task.taskId) >= 0,
                    onToggleSelect: (taskId: string): void => {
                      this.toggleTaskSelection(taskId)
                    },
                    onAction: (action: string, currentTask: VideoDownloadSnapshot): void => {
                      this.handleTaskAction(action, currentTask)
                    }
                  })
                }, (task: VideoDownloadSnapshot): string => task.taskId)
              }
              .width('100%')
            }

            Blank()
              .height(getBottomSpacerHeight(this.bottomSafeHeight))
              .width('100%')
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ left: 14, right: 14 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .titleBar(this.buildCustomTitleBarOptions())
      .bindToScrollable([this.scroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor(Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      if (this.showDeleteDialog) {
        this.DeleteConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private EmptyState(): void {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(86)
          .height(86)
          .fill($r('app.color.button_ghost_bg'))
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(44)
          .fontColor([$r('app.color.accent_blue')])
      }
      .margin({ bottom: 4 })
      Text('暂无下载任务')
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('在视频播放器的更多菜单中开始下载')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 36 })
  }

  private refreshTasks(): void {
    const latestTasks = this.manager.getAllSnapshots()
    const existingTasks: Map<string, VideoDownloadSnapshot> = new Map()
    for (let i = 0; i < this.tasks.length; i++) {
      existingTasks.set(this.tasks[i].taskId, this.tasks[i])
    }
    const nextTasks: VideoDownloadSnapshot[] = []
    let structureChanged: boolean = latestTasks.length !== this.tasks.length
    for (let i = 0; i < latestTasks.length; i++) {
      const latestTask = latestTasks[i]
      const existingTask = existingTasks.get(latestTask.taskId)
      if (existingTask === undefined) {
        nextTasks.push(latestTask)
        structureChanged = true
      } else {
        existingTask.updateFrom(latestTask)
        nextTasks.push(existingTask)
        if (this.tasks[i] === undefined || this.tasks[i].taskId !== latestTask.taskId) {
          structureChanged = true
        }
      }
    }
    if (structureChanged) {
      this.tasks = nextTasks
    }
    if (this.isEditMode) {
      const availableIds: string[] = []
      for (let i = 0; i < nextTasks.length; i++) {
        availableIds.push(nextTasks[i].taskId)
      }
      const validSelectedIds: string[] = []
      for (let i = 0; i < this.selectedTaskIds.length; i++) {
        if (availableIds.indexOf(this.selectedTaskIds[i]) >= 0) {
          validSelectedIds.push(this.selectedTaskIds[i])
        }
      }
      if (validSelectedIds.length !== this.selectedTaskIds.length) {
        this.selectedTaskIds = validSelectedIds
      }
    }
  }

  private handleTaskAction(action: string, task: VideoDownloadSnapshot): void {
    if (action === 'play') {
      this.playTask(task)
    } else if (action === 'pause') {
      this.pauseTask(task.taskId)
    } else if (action === 'resume') {
      this.resumeTask(task.taskId)
    } else if (action === 'retry') {
      this.retryTask(task.taskId)
    } else if (action === 'prioritize') {
      this.prioritizeTask(task.taskId)
    } else if (action === 'finishLive') {
      this.finishLiveTask(task.taskId)
    } else if (action === 'remove') {
      this.requestDeleteTask(task.taskId)
    } else if (action === 'select') {
      this.enterEditMode(task.taskId)
    }
  }

  private async pauseTask(taskId: string): Promise<void> {
    try {
      await this.manager.pause(taskId)
    } catch (err) {
      this.showToast('暂停失败：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private async resumeTask(taskId: string): Promise<void> {
    try {
      await this.manager.resume(taskId)
    } catch (err) {
      this.showToast('继续下载失败：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private enterEditMode(taskId?: string): void {
    this.isEditMode = true
    this.selectedTaskIds = taskId === undefined ? [] : [taskId]
  }

  private toggleTaskSelection(taskId: string): void {
    const index: number = this.selectedTaskIds.indexOf(taskId)
    if (index >= 0) {
      const nextIds: string[] = []
      for (let i = 0; i < this.selectedTaskIds.length; i++) {
        if (i !== index) {
          nextIds.push(this.selectedTaskIds[i])
        }
      }
      this.selectedTaskIds = nextIds
      return
    }
    this.selectedTaskIds = [...this.selectedTaskIds, taskId]
  }

  private handleSelectAllOrExit(): void {
    if (this.selectedTaskIds.length === this.tasks.length) {
      this.selectedTaskIds = []
      return
    }
    const allIds: string[] = []
    for (let i = 0; i < this.tasks.length; i++) {
      allIds.push(this.tasks[i].taskId)
    }
    this.selectedTaskIds = allIds
  }

  private exitEditMode(): void {
    this.isEditMode = false
    this.selectedTaskIds = []
  }

  onBackPress(): boolean {
    if (this.isEditMode) {
      this.exitEditMode()
      return true
    }
    return false
  }

  private requestDeleteTask(taskId: string): void {
    this.selectedTaskIds = [taskId]
    this.showDeleteDialog = true
  }

  private requestDeleteSelectedTasks(): void {
    if (this.selectedTaskIds.length > 0) {
      this.showDeleteDialog = true
    }
  }

  @Builder
  private DeleteConfirmDialog(): void {
    Column() {
      Column() {
        Text('是否删除此视频？')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 24 })

        Text(this.selectedTaskIds.length > 1 ?
          `确定要删除这 ${this.selectedTaskIds.length} 个下载任务吗？` : '确定要删除这个下载任务吗？')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(26)
          .width('100%')
          .margin({ bottom: 26 })

        Row() {
          Text('取消')
            .layoutWeight(1)
            .height(52)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.cancelDelete()
            })

          Divider()
            .vertical(true)
            .height(34)
            .color($r('app.color.divider_color'))
            .margin({ left: 4, right: 4 })

          Text('删除')
            .layoutWeight(1)
            .height(52)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.status_error'))
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.confirmDeleteSelected()
            })
        }
        .width('100%')
        .height(52)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 20 })
      .borderRadius(34)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0x66000000)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 20, right: 20, bottom: 28 })
    .zIndex(30)
    .onClick(() => {
      this.cancelDelete()
    })
  }

  private cancelDelete(): void {
    this.showDeleteDialog = false
    if (!this.isEditMode) {
      this.selectedTaskIds = []
    }
  }

  private async confirmDeleteSelected(): Promise<void> {
    this.showDeleteDialog = false
    const ids: string[] = [...this.selectedTaskIds]
    this.exitEditMode()
    if (ids.length === 0) {
      return
    }
    for (let i = 0; i < ids.length; i++) {
      try {
        await this.manager.remove(ids[i], true)
      } catch (err) {
        this.showToast('删除失败：' + (err instanceof Error ? err.message : String(err)))
        break
      }
    }
    this.refreshTasks()
  }

  private finishLiveTask(taskId: string): void {
    try {
      this.manager.finishLive(taskId)
    } catch (err) {
      this.showToast('结束录制失败：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private async prioritizeTask(taskId: string): Promise<void> {
    try {
      await this.manager.prioritize(taskId)
    } catch (err) {
      this.showToast('置顶失败：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private async retryTask(taskId: string): Promise<void> {
    try {
      await this.manager.retry(taskId)
      this.refreshTasks()
    } catch (err) {
      this.showToast('重试失败：' + (err instanceof Error ? err.message : String(err)))
    }
  }

  private playTask(task: VideoDownloadSnapshot): void {
    const uri = task.targetUri.length > 0 ? task.targetUri : task.localPlaylistUri
    if (uri.length === 0) {
      this.showToast('下载文件不存在')
      return
    }
    router.pushUrl({
      url: 'pages/player/LocalPlayerPage',
      params: {
        videoUri: uri,
        videoFileName: task.fileName,
        videoFileSize: task.processedBytes,
        historyPositionMs: 0,
        danmakuUri: task.danmakuUri,
        danmakuFileName: this.getFileName(task.danmakuPath),
        danmakuFormat: task.danmakuPath.endsWith('.json') ? 'json' : '',
        danmakuCount: task.danmakuCount,
        danmakuOffsetMs: 0,
        drmScheme: task.drmScheme,
        drmPluginName: task.drmPluginName,
        drmOfflineKeyId: task.drmOfflineKeyId
      }
    })
  }

  private getFileName(path: string): string {
    const normalized = path.replace(/\\/g, '/')
    const slash = normalized.lastIndexOf('/')
    return slash >= 0 ? normalized.substring(slash + 1) : normalized
  }

  private buildTitle(): HdsNavigationTitle {
    if (this.isEditMode) {
      return {
        mainTitle: '已选择' + String(this.selectedTaskIds.length) + '项',
        subTitle: ''
      }
    }
    return {
      mainTitle: '下载管理',
      subTitle: this.tasks.length > 0 ? '共 ' + String(this.tasks.length) + ' 项' : ''
    }
  }

  private buildMenu(): HdsNavigationMenuContentOptions {
    if (this.isEditMode) {
      const trashIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.trash'),
        label: 'delete',
        action: () => {
          this.requestDeleteSelectedTasks()
        }
      }
      const selectAllIcon: HdsNavigationIconOptions = {
        icon: $r('sys.symbol.checkmark_square_on_square'),
        label: 'selectAll',
        action: () => {
          this.handleSelectAllOrExit()
        }
      }
      return {
        value: [{ content: trashIcon }, { content: selectAllIcon }]
      }
    }
    if (this.tasks.length === 0) {
      return { value: [] }
    }
    const editIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.square_and_pencil'),
      label: 'edit',
      action: () => {
        this.enterEditMode()
      }
    }
    return {
      value: [new DownloadMenuIconContent(editIcon)]
    }
  }

  private buildTitleBarContent(): TitleBarContentOptions {
    return {
      title: this.buildTitle(),
      menu: this.buildMenu()
    }
  }

  private buildCustomTitleBarOptions(): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = buildImmersiveTitleBarStyle(this.hdsMaterialLevel)
    return {
      style: style,
      content: this.buildTitleBarContent(),
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true
    }
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message })
    } catch (_err) {
    }
  }
}

@Component
struct DownloadTaskCard {
  @ObjectLink task: VideoDownloadSnapshot
  @Prop isEditMode: boolean = false
  @Prop isSelected: boolean = false
  @State isActionMenuShown: boolean = false
  onToggleSelect: (taskId: string) => void = (_taskId: string): void => {}
  onAction: (action: string, task: VideoDownloadSnapshot) => void =
    (_action: string, _task: VideoDownloadSnapshot): void => {}

  build() {
    Column({ space: 6 }) {
      Row({ space: 12 }) {
        Image(this.task.coverUri.length > 0 ? this.task.coverUri :
          (this.task.animeCover.length > 0 ? this.task.animeCover : $r('app.media.ic_placeholder')))
          .draggable(false)
          .width(116)
          .height(72)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .opacity(this.task.coverUri.length > 0 || this.task.animeCover.length > 0 ? 1 : 0.82)

        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(this.task.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (!this.isEditMode && (this.task.state === VideoDownloadState.RUNNING ||
              this.task.state === VideoDownloadState.PREPARING ||
              this.task.state === VideoDownloadState.QUEUED)) {
              SymbolGlyph($r('sys.symbol.pause_fill'))
                .fontSize(17)
                .fontColor([$r('app.color.accent_blue')])
            } else if (!this.isEditMode && this.task.state === VideoDownloadState.PAUSED) {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(17)
                .fontColor([$r('app.color.accent_blue')])
            } else if (!this.isEditMode && this.task.state === VideoDownloadState.COMPLETED) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(17)
                .fontColor([$r('app.color.status_success')])
            }
          }
          .width('100%')

          Text(this.buildInfoText(this.task))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Progress({ value: this.task.progressPercent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(this.task.state === VideoDownloadState.PAUSED ? $r('app.color.text_secondary') :
              $r('app.color.loading_color'))
            .backgroundColor($r('app.color.button_ghost_bg'))

          Row() {
            Text(this.buildStateText(this.task))
              .fontSize(12)
              .fontColor(this.getStateColor(this.task.state))
              .layoutWeight(1)
            Text(String(this.task.progressPercent) + '%')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.isEditMode) {
          SymbolGlyph(this.isSelected ? $r('sys.symbol.checkmark_circle_fill') :
            $r('sys.symbol.checkmark_circle'))
            .fontSize(24)
            .fontColor([this.isSelected ? $r('sys.color.font_emphasize') : $r('app.color.text_secondary')])
            .margin({ left: 8 })
            .onClick(() => {
              this.onToggleSelect(this.task.taskId)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        if (this.isEditMode) {
          this.onToggleSelect(this.task.taskId)
          return
        }
        this.handleCardClick()
      })

      if (this.task.errorMessage.length > 0) {
        Text(this.task.errorMessage)
          .fontSize(12)
          .fontColor(this.task.state === VideoDownloadState.FAILED ? $r('app.color.status_error') :
            $r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.task.state === VideoDownloadState.FAILED || this.task.state === VideoDownloadState.QUEUED ||
        (this.task.isLive && (this.task.state === VideoDownloadState.RUNNING ||
          this.task.state === VideoDownloadState.PREPARING))) {
        Row({ space: 8 }) {
          if (this.task.state === VideoDownloadState.FAILED) {
            Button('重试')
              .height(32)
              .onClick(() => this.onAction('retry', this.task))
          }
          if (this.task.state === VideoDownloadState.QUEUED) {
            Button('置顶')
              .height(32)
              .onClick(() => this.onAction('prioritize', this.task))
          }
          if (this.task.isLive && (this.task.state === VideoDownloadState.RUNNING ||
            this.task.state === VideoDownloadState.PREPARING)) {
            Button('完成录制')
              .height(32)
              .onClick(() => this.onAction('finishLive', this.task))
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .bindMenu(this.isActionMenuShown, this.DownloadTaskMenuBuilder, {
      placement: Placement.Bottom,
      showInSubWindow: false,
      onDisappear: () => {
        this.isActionMenuShown = false
      }
    })
    .gesture(LongPressGesture({ duration: 500 })
      .onAction(() => {
        if (!this.isEditMode) {
          this.isActionMenuShown = true
        }
      })
    )
  }

  @Builder
  private DownloadTaskMenuBuilder(): void {
    Menu() {
      MenuItem({ content: '删除' })
        .onClick(() => {
          this.isActionMenuShown = false
          this.onAction('remove', this.task)
        })
      MenuItem({ content: '多选' })
        .onClick(() => {
          this.isActionMenuShown = false
          this.onAction('select', this.task)
        })
    }
    .width(120)
    .radius(16)
  }

  private handleCardClick(): void {
    if (this.task.state === VideoDownloadState.RUNNING ||
      this.task.state === VideoDownloadState.PREPARING ||
      this.task.state === VideoDownloadState.QUEUED) {
      this.onAction('pause', this.task)
    } else if (this.task.state === VideoDownloadState.PAUSED) {
      this.onAction('resume', this.task)
    } else if (this.task.state === VideoDownloadState.COMPLETED) {
      this.onAction('play', this.task)
    }
  }

  private buildInfoText(task: VideoDownloadSnapshot): string {
    let text = task.totalBytes > 0 ? this.formatBytes(task.totalBytes) : this.formatBytes(task.processedBytes)
    if (task.kind === VideoDownloadKind.HLS && task.totalSegments > 0) {
      text = String(task.completedSegments) + '/' + String(task.totalSegments) + ' 分片 · ' + text
    } else if (task.kind === VideoDownloadKind.DASH && task.videoTrackCount > 0) {
      text = 'DASH · ' + text
    }
    if (task.state === VideoDownloadState.RUNNING && task.speedBytesPerSecond > 0) {
      text += ' · ' + this.formatBytes(task.speedBytesPerSecond) + '/s'
    }
    return text
  }

  private buildStateText(task: VideoDownloadSnapshot): string {
    if (task.state === VideoDownloadState.QUEUED) return '排队中'
    if (task.state === VideoDownloadState.PREPARING) {
      if (task.errorMessage.indexOf('转封装') >= 0) return '转封装中'
      return '准备中'
    }
    if (task.state === VideoDownloadState.RUNNING) {
      if (task.isLive) return '直播录制中'
      return String(task.progressPercent) + '%'
    }
    if (task.state === VideoDownloadState.PAUSED) return '已暂停'
    if (task.state === VideoDownloadState.COMPLETED) return '已完成'
    if (task.state === VideoDownloadState.FAILED) return '失败'
    if (task.state === VideoDownloadState.CANCELLED) return '已取消'
    return '等待中'
  }

  private getStateColor(state: VideoDownloadState): ResourceColor {
    if (state === VideoDownloadState.COMPLETED) return $r('app.color.status_success')
    if (state === VideoDownloadState.FAILED) return $r('app.color.status_error')
    return $r('app.color.text_secondary')
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) return '0 B'
    if (bytes < 1024) return String(bytes) + ' B'
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB'
    return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB'
  }
}
