#include <cstring>
#include <string>
#include <mutex>
#include <unordered_map>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"
#include "napi/native_api.h"

static const char *TAG = "MpvClientWrapper";

struct MpvContext {
    mpv_handle *handle;
    bool initialized;
};

static std::unordered_map<int64_t, MpvContext *> g_contexts;
static int64_t g_next_id = 1;
static std::mutex g_mutex;

static MpvContext *find_context(int64_t id)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(id);
    if (it != g_contexts.end()) {
        return it->second;
    }
    return nullptr;
}

static int64_t store_context(MpvContext *ctx)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    int64_t id = g_next_id++;
    g_contexts[id] = ctx;
    return id;
}

static void remove_context(int64_t id)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(id);
    if (it != g_contexts.end()) {
        if (it->second->handle) {
            mpv_terminate_destroy(it->second->handle);
        }
        delete it->second;
        g_contexts.erase(it);
    }
}

extern "C" int64_t mpv_wrapper_create()
{
    mpv_handle *handle = mpv_create();
    if (!handle) {
        return -1;
    }

    MpvContext *ctx = new MpvContext();
    ctx->handle = handle;
    ctx->initialized = false;

    int64_t id = store_context(ctx);
    return id;
}

extern "C" int mpv_wrapper_initialize(int64_t ctxId)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }

    int err = mpv_initialize(ctx->handle);
    if (err >= 0) {
        ctx->initialized = true;
    }
    return err;
}

extern "C" int mpv_wrapper_command(int64_t ctxId, const char **args)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_command(ctx->handle, args);
}

extern "C" int mpv_wrapper_command_string(int64_t ctxId, const char *args)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_command_string(ctx->handle, args);
}

extern "C" int mpv_wrapper_set_property_string(int64_t ctxId, const char *name, const char *value)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_set_property_string(ctx->handle, name, value);
}

extern "C" char *mpv_wrapper_get_property_string(int64_t ctxId, const char *name)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return nullptr;
    }
    return mpv_get_property_string(ctx->handle, name);
}

extern "C" int mpv_wrapper_observe_property(int64_t ctxId, uint64_t reply_userdata, const char *name, mpv_format format)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_observe_property(ctx->handle, reply_userdata, name, format);
}

extern "C" int mpv_wrapper_unobserve_property(int64_t ctxId, uint64_t reply_userdata)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_unobserve_property(ctx->handle, reply_userdata);
}

extern "C" int mpv_wrapper_request_log_messages(int64_t ctxId, const char *minLevel)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle || !minLevel) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_request_log_messages(ctx->handle, minLevel);
}

extern "C" mpv_event *mpv_wrapper_wait_event(int64_t ctxId, double timeout)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return nullptr;
    }
    return mpv_wait_event(ctx->handle, timeout);
}

extern "C" void mpv_wrapper_wakeup(int64_t ctxId)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return;
    }
    mpv_wakeup(ctx->handle);
}

extern "C" void mpv_wrapper_set_wakeup_callback(int64_t ctxId, void (*cb)(void *), void *userData)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return;
    }
    mpv_set_wakeup_callback(ctx->handle, cb, userData);
}

extern "C" void mpv_wrapper_destroy(int64_t ctxId)
{
    remove_context(ctxId);
}

extern "C" unsigned long mpv_wrapper_client_api_version()
{
    return mpv_client_api_version();
}

extern "C" const char *mpv_wrapper_error_string(int error)
{
    return mpv_error_string(error);
}
