import {
  HdsNavigationTitleBarOptions,
  TitleBarStyleOptions,
  ScrollEffectType,
  SystemMaterialParams,
  hdsMaterial
} from '@kit.UIDesignKit'
import { LengthMetrics } from '@kit.ArkUI'

export const DEFAULT_TOP_SAFE_HEIGHT: number = 36
export const MINI_TITLE_BAR_CONTENT_HEIGHT: number = 72
export const HDS_FLOATING_TAB_CONTENT_SPACER: number = 96
export const TIMELINE_WEEKDAY_BAR_HEIGHT: number = 56

export function getEffectiveTopSafeHeight(topSafeHeight: number): number {
  return topSafeHeight > 0 ? topSafeHeight : DEFAULT_TOP_SAFE_HEIGHT
}

export function getTopSpacerHeight(topSafeHeight: number): number {
  return getEffectiveTopSafeHeight(topSafeHeight) + MINI_TITLE_BAR_CONTENT_HEIGHT
}

export function getBottomSpacerHeight(bottomSafeHeight: number): number {
  return bottomSafeHeight + HDS_FLOATING_TAB_CONTENT_SPACER
}

export function buildAdaptiveMaterialEffect(): SystemMaterialParams {
  let immersiveSupported: boolean = false
  try {
    const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
    immersiveSupported = materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0
  } catch (_) {
    immersiveSupported = false
  }
  return {
    materialType: immersiveSupported ? hdsMaterial.MaterialType.IMMERSIVE :
      hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: immersiveSupported ? hdsMaterial.MaterialLevel.EXQUISITE :
      hdsMaterial.MaterialLevel.ADAPTIVE
  }
}

export function buildImmersiveTitleBarStyle(): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(36),
      enableRefreshOffsetChange: false
    },
    originalStyle: {
      backgroundStyle: {
        backgroundColor: Color.Transparent,
        blurRadius: 28
      },
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('sys.color.font_primary'),
          subTitleColor: $r('sys.color.font_secondary')
        },
        menuStyle: {
          backgroundColor: $r('sys.color.comp_background_tertiary'),
          iconColor: $r('sys.color.icon_primary')
        },
        backIconStyle: {
          backgroundColor: $r('sys.color.comp_background_tertiary'),
          iconColor: $r('sys.color.icon_primary')
        },
        dividerStyle: {
          dividerColor: Color.Transparent
        }
      }
    },
    scrollEffectStyle: {
      backgroundStyle: {
        backgroundColor: Color.Transparent,
        blurRadius: 28
      },
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('sys.color.font_primary'),
          subTitleColor: $r('sys.color.font_secondary')
        },
        menuStyle: {
          backgroundColor: $r('sys.color.comp_background_tertiary'),
          iconColor: $r('sys.color.icon_primary')
        },
        backIconStyle: {
          backgroundColor: $r('sys.color.comp_background_tertiary'),
          iconColor: $r('sys.color.icon_primary')
        },
        dividerStyle: {
          dividerColor: Color.Transparent
        }
      }
    },
    thermoCtrl: true,
    systemMaterialEffect: buildAdaptiveMaterialEffect()
  }
}

export function buildTitleBarOptions(title: string): HdsNavigationTitleBarOptions {
  return {
    style: buildImmersiveTitleBarStyle(),
    content: {
      title: {
        mainTitle: title
      }
    },
    enableComponentSafeArea: false,
    avoidLayoutSafeArea: true
  }
}

export function buildTimelineTitleBarStyle(): TitleBarStyleOptions {
  const base: TitleBarStyleOptions = buildImmersiveTitleBarStyle()
  if (base.originalStyle?.backgroundStyle) {
    base.originalStyle.backgroundStyle.maskExtraHeight = TIMELINE_WEEKDAY_BAR_HEIGHT
  }
  if (base.scrollEffectStyle?.backgroundStyle) {
    base.scrollEffectStyle.backgroundStyle.maskExtraHeight = TIMELINE_WEEKDAY_BAR_HEIGHT
  }
  return base
}