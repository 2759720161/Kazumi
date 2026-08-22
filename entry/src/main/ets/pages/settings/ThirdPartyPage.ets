import {
  HdsNavigation,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit'
import {
  getTopSpacerHeight,
  getBottomSpacerHeight,
  buildTitleBarOptions,
  HDS_MATERIAL_LEVEL_DEFAULT,
  PREFS_KEY_HDS_MATERIAL_LEVEL
} from '../../utils/HdsPageStyle'
import { RuleCatalogService } from '../../services/RuleCatalogService'

@Entry
@Component
struct ThirdPartyPage {
  @StorageLink('topSafeHeight') topSafeHeight: number = 0
  @StorageLink('bottomSafeHeight') bottomSafeHeight: number = 0
  @StorageLink(PREFS_KEY_HDS_MATERIAL_LEVEL) hdsMaterialLevel: string = HDS_MATERIAL_LEVEL_DEFAULT
  @State showRuleRepository: boolean = false
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.loadRuleRepositoryVisibility()
  }

  onPageShow(): void {
    this.loadRuleRepositoryVisibility()
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column() {
          Blank()
            .height(getTopSpacerHeight(this.topSafeHeight))
            .width('100%')

          this.SectionHeader('三方库')
          this.LinkCard(
            'libmpv-ohos-build',
            'mpv HarmonyOS 构建产物',
            'https://github.com/ErBWs/libmpv-ohos-build'
          )
          this.LinkCard(
            'mpv',
            '播放器核心项目',
            'https://github.com/dex2oat/mpv'
          )

          this.SectionHeader('服务')
          if (this.showRuleRepository) {
            this.LinkCard(
              'KazumiRules',
              '规则仓库',
              'https://github.com/Predidit/KazumiRules'
            )
          }
          this.SourceAttributionCard()

          Blank()
            .height(getBottomSpacerHeight(this.bottomSafeHeight))
            .width('100%')
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleBar(buildTitleBarOptions('三方库与服务', this.hdsMaterialLevel))
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .backgroundColor(Color.Transparent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  private async loadRuleRepositoryVisibility(): Promise<void> {
    try {
      const repositoryUrl = await RuleCatalogService.getSavedRepositoryUrl()
      this.showRuleRepository = repositoryUrl.length > 0
    } catch (_) {
      this.showRuleRepository = false
    }
  }

  @Builder
  private SectionHeader(title: string): void {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, right: 6, top: 18, bottom: 6 })
  }

  @Builder
  private LinkCard(title: string, desc: string, url: string): void {
    Row() {
      SymbolGlyph($r('sys.symbol.link'))
        .fontSize(24)
        .fontColor([$r('app.color.accent_blue')])
        .width(34)
        .margin({ right: 12 })

      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })

        Text(url)
          .fontSize(12)
          .fontColor($r('app.color.accent_blue'))
          .width('100%')
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ minHeight: 88 })
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
  }

  @Builder
  private SourceAttributionCard(): void {
    Row() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(24)
        .fontColor([$r('app.color.accent_blue')])
        .width(34)
        .margin({ right: 12 })

      Column() {
        Text('弹幕数据支持')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('数据来源：弹弹play')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 0.5, color: $r('app.color.card_specular_border') })
    .shadow({ radius: 10, color: $r('app.color.shadow_surface'), offsetY: 3 })
    .margin({ bottom: 8 })
  }
}
