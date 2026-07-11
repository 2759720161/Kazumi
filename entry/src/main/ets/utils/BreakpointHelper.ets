export enum BreakpointType {
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  XL = 'xl'
}

export class BreakpointHelper {
  static readonly SM_MAX_VP: number = 600
  static readonly MD_MAX_VP: number = 840
  static readonly LG_MAX_VP: number = 1200

  static classify(widthVp: number): BreakpointType {
    if (widthVp < BreakpointHelper.SM_MAX_VP) {
      return BreakpointType.SM;
    } else if (widthVp < BreakpointHelper.MD_MAX_VP) {
      return BreakpointType.MD;
    } else if (widthVp < BreakpointHelper.LG_MAX_VP) {
      return BreakpointType.LG;
    } else {
      return BreakpointType.XL;
    }
  }

  static isSm(widthVp: number): boolean {
    return widthVp < BreakpointHelper.SM_MAX_VP;
  }

  static isMd(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.SM_MAX_VP && widthVp < BreakpointHelper.MD_MAX_VP;
  }

  static isLg(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.MD_MAX_VP && widthVp < BreakpointHelper.LG_MAX_VP;
  }

  static isXl(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.LG_MAX_VP;
  }

  static isTabletLayout(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.SM_MAX_VP;
  }

  static getContentMaxWidth(widthVp: number): number {
    if (widthVp >= BreakpointHelper.LG_MAX_VP) {
      return 1000;
    }
    if (widthVp >= BreakpointHelper.MD_MAX_VP) {
      return 840;
    }
    if (widthVp >= BreakpointHelper.SM_MAX_VP) {
      return 720;
    }
    return 0;
  }

  static getSideBarWidth(widthVp: number): number {
    if (widthVp >= BreakpointHelper.LG_MAX_VP) {
      return 320;
    }
    if (widthVp >= BreakpointHelper.MD_MAX_VP) {
      return 280;
    }
    return 240;
  }

  static isWideDetailLayout(widthVp: number): boolean {
    return widthVp >= BreakpointHelper.SM_MAX_VP;
  }
}