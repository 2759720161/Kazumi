#include "napi/native_api.h"

#ifndef EXTERN_C_START
#ifdef __cplusplus
#define EXTERN_C_START extern "C" {
#define EXTERN_C_END }
#else
#define EXTERN_C_START
#define EXTERN_C_END
#endif
#endif

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    return exports;
}
EXTERN_C_END

static napi_module _module = {
    1,
    0,
    nullptr,
    Init,
    "mpv_napi",
    nullptr,
    {0},
};

extern "C" __attribute__((constructor)) void RegisterModule(void)
{
    napi_module_register(&_module);
}
