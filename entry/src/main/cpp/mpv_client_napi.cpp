#include <cstring>
#include <string>
#include <thread>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"
#include "ohos_surface_helper.h"
#include "mpv_event_handler.h"
#include "napi/native_api.h"

#ifndef DECLARE_NAPI_FUNCTION
#define DECLARE_NAPI_FUNCTION(name, func) \
    { (name), nullptr, (func), nullptr, nullptr, nullptr, napi_default, nullptr }
#endif

#ifndef EXTERN_C_START
#ifdef __cplusplus
#define EXTERN_C_START extern "C" {
#define EXTERN_C_END }
#else
#define EXTERN_C_START
#define EXTERN_C_END
#endif
#endif

static const char *TAG = "MpvClientNapi";

static napi_value NativeCreate(napi_env env, napi_callback_info info)
{
    napi_value result;
    int64_t ctxId = mpv_wrapper_create();
    napi_create_int32(env, static_cast<int32_t>(ctxId), &result);
    return result;
}

static napi_value NativeInitialize(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    int err = mpv_wrapper_initialize(ctxId);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeCommand(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    napi_value cmd_array = args[1];
    uint32_t cmd_count;
    napi_get_array_length(env, cmd_array, &cmd_count);

    const char **cmd_args = new const char *[cmd_count + 1];
    for (uint32_t i = 0; i < cmd_count; i++) {
        napi_value elem;
        napi_get_element(env, cmd_array, i, &elem);
        size_t len = 0;
        napi_get_value_string_utf8(env, elem, nullptr, 0, &len);
        cmd_args[i] = new char[len + 1];
        napi_get_value_string_utf8(env, elem, const_cast<char *>(cmd_args[i]), len + 1, &len);
    }
    cmd_args[cmd_count] = nullptr;

    int err = mpv_wrapper_command(ctxId, cmd_args);

    for (uint32_t i = 0; i < cmd_count; i++) {
        delete[] cmd_args[i];
    }
    delete[] cmd_args;

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeSetProperty(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    char name[256] = {0};
    napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);

    char value[1024] = {0};
    napi_get_value_string_utf8(env, args[2], value, sizeof(value), nullptr);

    int err = mpv_wrapper_set_property_string(ctxId, name, value);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeGetProperty(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    char name[256] = {0};
    napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);

    char *value = mpv_wrapper_get_property_string(ctxId, name);

    napi_value result;
    if (value) {
        napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
        mpv_free(value);
    } else {
        napi_get_null(env, &result);
    }
    return result;
}

static napi_value NativeObserveProperty(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    double reply_userdata;
    napi_get_value_double(env, args[1], &reply_userdata);

    char name[256] = {0};
    napi_get_value_string_utf8(env, args[2], name, sizeof(name), nullptr);

    int32_t format;
    napi_get_value_int32(env, args[3], &format);

    int err = mpv_wrapper_observe_property(ctxId, static_cast<uint64_t>(reply_userdata), name, static_cast<mpv_format>(format));

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeDestroy(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    mpv_event_handler_destroy();

    std::thread([ctxId]() {
        mpv_wrapper_destroy(ctxId);
    }).detach();

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value NativeSetSurfaceId(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    char surfaceId[256] = {0};
    napi_get_value_string_utf8(env, args[1], surfaceId, sizeof(surfaceId), nullptr);

    int err = ohos_surface_set_surface_id(ctxId, surfaceId);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeApiVersion(napi_env env, napi_callback_info info)
{
    unsigned long version = mpv_wrapper_client_api_version();
    napi_value result;
    napi_create_double(env, static_cast<double>(version), &result);
    return result;
}

static napi_value NativeOnEvent(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    napi_value callback = args[1];

    int err = mpv_event_handler_init(env, callback, ctxId);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        DECLARE_NAPI_FUNCTION("nativeCreate", NativeCreate),
        DECLARE_NAPI_FUNCTION("nativeInitialize", NativeInitialize),
        DECLARE_NAPI_FUNCTION("nativeCommand", NativeCommand),
        DECLARE_NAPI_FUNCTION("nativeSetProperty", NativeSetProperty),
        DECLARE_NAPI_FUNCTION("nativeGetProperty", NativeGetProperty),
        DECLARE_NAPI_FUNCTION("nativeObserveProperty", NativeObserveProperty),
        DECLARE_NAPI_FUNCTION("nativeDestroy", NativeDestroy),
        DECLARE_NAPI_FUNCTION("nativeSetSurfaceId", NativeSetSurfaceId),
        DECLARE_NAPI_FUNCTION("nativeApiVersion", NativeApiVersion),
        DECLARE_NAPI_FUNCTION("nativeOnEvent", NativeOnEvent),
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
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
