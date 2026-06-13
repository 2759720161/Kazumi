export enum BreakpointType {
  SM = 'sm',
  MD = 'md',
  LG = 'lg'
}

export class BreakpointHelper {
  static readonly SM_MAX_VP: number = 600
  static readonly MD_MAX_VP: number = 840

  static classify(widthVp: number): BreakpointType {
    if (widthVp < BreakpointHelper.SM_MAX_VP) {
      return BreakpointType.SM;
    } else if (widthVp < BreakpointHelper.MD_MAX_VP) {
      return BreakpointType.MD;
    } else {
      return BreakpointType.LG;
    }
  }

  static isSm(widthVp: number): boolean {
    return widthVp < BreakpointHelper.SM_MAX_VP;
  }

  static isMd(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.SM_MAX_VP && widthVp < BreakpointHelper.MD_MAX_VP;
  }

  static isLg(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.MD_MAX_VP;
  }
}