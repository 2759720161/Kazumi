export enum ResolveErrorCode {
  Cancelled,
  Timeout,
  NotFound,
  Captcha,
  Network,
  WrapperOnly,
  NoSupportedFormat   // 嗅探到候选但全部格式不支持（如全部为 DASH）
}
