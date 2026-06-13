declare module 'libmpv_napi.so' {
  export interface MpvEventData {
    eventId: number
    errorCode: number
    propertyName: string
    propertyValueStr: string
    propertyValueDouble: number
    reason: number
    logPrefix: string
    logLevel: string
    logText: string
  }

  export interface MpvNapiModule {
    nativeCreate: () => number
    nativeInitialize: (ctxId: number) => number
    nativeCommand: (ctxId: number, args: string[]) => number
    nativeSetProperty: (ctxId: number, name: string, value: string) => number
    nativeGetProperty: (ctxId: number, name: string) => string | null
    nativeObserveProperty: (ctxId: number, replyUserdata: number, name: string, format: number) => number
    nativeDestroy: (ctxId: number) => void
    nativeSetSurfaceId: (ctxId: number, surfaceId: string) => number
    nativeApiVersion: () => number
    nativeOnEvent: (ctxId: number, callback: (event: MpvEventData) => void) => number
  }

  const mpvNapi: MpvNapiModule
  export default mpvNapi

  export const nativeCreate: () => number
  export const nativeInitialize: (ctxId: number) => number
  export const nativeCommand: (ctxId: number, args: string[]) => number
  export const nativeSetProperty: (ctxId: number, name: string, value: string) => number
  export const nativeGetProperty: (ctxId: number, name: string) => string | null
  export const nativeObserveProperty: (ctxId: number, replyUserdata: number, name: string, format: number) => number
  export const nativeDestroy: (ctxId: number) => void
  export const nativeSetSurfaceId: (ctxId: number, surfaceId: string) => number
  export const nativeApiVersion: () => number
  export const nativeOnEvent: (ctxId: number, callback: (event: MpvEventData) => void) => number
}
