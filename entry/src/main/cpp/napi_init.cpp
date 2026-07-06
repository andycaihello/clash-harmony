#include "napi/native_api.h"
#include "mihomo_adapter.h"
#include "tun_forwarder.h"
#include "socket_protector.h"
#include "health_monitor.h"

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>
#include <unistd.h>

namespace {

struct RuntimeState {
    bool running = false;
    int32_t tunFd = -1;
    int32_t nativeFd = -1;
    int32_t startCount = 0;
    int32_t stopCount = 0;
    bool controllerReady = false;
    bool controllerOnly = false;
    bool tunAttached = false;
    bool supportsControllerOnly = false;
    bool supportsTunAttach = false;
    bool realConnectionReady = false;
    std::string configPath;
    std::string coreMode = "idle";
    std::string adapterMode = "unloaded";
    std::string adapterKind = "unknown";
    std::string adapterInfo;
    std::string adapterLoadError;
    std::string adapterVersion;
    std::string controllerVersion;
    std::string version;
    std::string lastError;
};

std::mutex g_stateMutex;
RuntimeState g_state;
TunForwarder g_forwarder;

napi_value CreateString(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

void SetBoolean(napi_env env, napi_value object, const char* name, bool value)
{
    napi_value napiValue = nullptr;
    napi_get_boolean(env, value, &napiValue);
    napi_set_named_property(env, object, name, napiValue);
}

void SetInt32(napi_env env, napi_value object, const char* name, int32_t value)
{
    napi_value napiValue = nullptr;
    napi_create_int32(env, value, &napiValue);
    napi_set_named_property(env, object, name, napiValue);
}

void SetInt64(napi_env env, napi_value object, const char* name, uint64_t value)
{
    napi_value napiValue = nullptr;
    napi_create_int64(env, static_cast<int64_t>(value), &napiValue);
    napi_set_named_property(env, object, name, napiValue);
}

void SetString(napi_env env, napi_value object, const char* name, const std::string& value)
{
    napi_set_named_property(env, object, name, CreateString(env, value));
}

void CloseNativeFdLocked()
{
    if (g_state.nativeFd >= 0) {
        close(g_state.nativeFd);
        g_state.nativeFd = -1;
    }
}

void RefreshAdapterStateLocked()
{
    g_state.adapterMode = MihomoAdapterMode();
    g_state.adapterKind = MihomoAdapterKind();
    g_state.adapterInfo = MihomoAdapterInfo();
    g_state.adapterLoadError = MihomoAdapterLoadError();
    g_state.supportsControllerOnly = MihomoSupportsControllerOnly();
    g_state.supportsTunAttach = MihomoSupportsTunAttach();
}

napi_value CreateStateObject(napi_env env)
{
    RuntimeState snapshot;
    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        snapshot = g_state;
    }

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetBoolean(env, result, "running", snapshot.running);
    SetInt32(env, result, "tunFd", snapshot.tunFd);
    SetInt32(env, result, "nativeFd", snapshot.nativeFd);
    SetInt32(env, result, "startCount", snapshot.startCount);
    SetInt32(env, result, "stopCount", snapshot.stopCount);
    SetBoolean(env, result, "controllerReady", snapshot.controllerReady);
    SetBoolean(env, result, "controllerOnly", snapshot.controllerOnly);
    SetBoolean(env, result, "tunAttached", snapshot.tunAttached);
    SetBoolean(env, result, "supportsControllerOnly", snapshot.supportsControllerOnly);
    SetBoolean(env, result, "supportsTunAttach", snapshot.supportsTunAttach);
    SetBoolean(env, result, "realConnectionReady", snapshot.realConnectionReady);
    SetString(env, result, "configPath", snapshot.configPath);
    SetString(env, result, "coreMode", snapshot.coreMode);
    SetString(env, result, "adapterMode", snapshot.adapterMode);
    SetString(env, result, "adapterKind", snapshot.adapterKind);
    SetString(env, result, "adapterInfo", snapshot.adapterInfo);
    SetString(env, result, "adapterLoadError", snapshot.adapterLoadError);
    SetString(env, result, "adapterVersion", snapshot.adapterVersion);
    SetString(env, result, "controllerVersion", snapshot.controllerVersion);
    SetString(env, result, "version", snapshot.version);
    SetString(env, result, "lastError", snapshot.lastError);

    ForwarderStatsSnapshot fwdStats = g_forwarder.GetStats();
    SetInt64(env, result, "packetsRead", fwdStats.packetsRead);
    SetInt64(env, result, "packetsWritten", fwdStats.packetsWritten);
    SetInt64(env, result, "bytesRead", fwdStats.bytesRead);
    SetInt64(env, result, "bytesWritten", fwdStats.bytesWritten);
    SetInt64(env, result, "readErrors", fwdStats.readErrors);
    SetInt64(env, result, "writeErrors", fwdStats.writeErrors);
    SetBoolean(env, result, "forwarderActive", g_forwarder.IsActive());

    return result;
}

bool ReadStringArg(napi_env env, napi_value value, std::string& output)
{
    size_t length = 0;
    napi_status status = napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    if (status != napi_ok) {
        return false;
    }

    std::vector<char> buffer(length + 1);
    size_t copied = 0;
    status = napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied);
    if (status != napi_ok) {
        return false;
    }
    output.assign(buffer.data(), copied);
    return true;
}

napi_value StartTun(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string configPath;
    int32_t tunFd = -1;
    bool ok = argc >= 2 && ReadStringArg(env, args[0], configPath) &&
              napi_get_value_int32(env, args[1], &tunFd) == napi_ok;

    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_state.startCount += 1;
        g_state.configPath = configPath;
        g_state.tunFd = tunFd;
        g_state.controllerReady = false;
        g_state.controllerOnly = false;
        g_state.tunAttached = false;
        g_state.realConnectionReady = false;
        g_state.adapterVersion.clear();
        g_state.controllerVersion.clear();
        g_state.version.clear();
        RefreshAdapterStateLocked();

        CloseNativeFdLocked();
        if (!ok || configPath.empty() || tunFd < 0) {
            g_state.running = false;
            g_state.coreMode = "error";
            g_state.lastError = "invalid configPath or tunFd";
        } else {
            int32_t duplicateFd = dup(tunFd);
            if (duplicateFd < 0) {
                g_state.running = false;
                g_state.coreMode = "error";
                g_state.lastError = std::string("dup tunFd failed: ") + strerror(errno);
            } else {
                g_state.nativeFd = duplicateFd;
                int startResult = MihomoStart(configPath.c_str(), g_state.nativeFd);
                if (startResult == 0) {
                    g_state.running = true;
                    g_state.controllerOnly = false;
                    g_state.tunAttached = true;
                    RefreshAdapterStateLocked();
                    g_state.adapterVersion = MihomoVersion();
                    g_state.version = g_state.adapterVersion;
                    g_state.lastError.clear();
                    if (g_state.adapterMode == "real" && g_state.adapterKind == "mihomo") {
                        // 真实 mihomo adapter 已加载，由 adapter 自行处理 TUN I/O
                        g_state.coreMode = "mihomo-adapter";
                        g_state.realConnectionReady = true;
                    } else {
                        // stub 模式：启动内建转发器处理 TUN I/O
                        g_state.coreMode = "adapter-stub";
                        g_state.realConnectionReady = false;
                        g_forwarder.Start(g_state.nativeFd, nullptr, SocketProtector::Protect);
                    }
                } else {
                    CloseNativeFdLocked();
                    g_state.running = false;
                    g_state.controllerOnly = false;
                    g_state.tunAttached = false;
                    g_state.realConnectionReady = false;
                    RefreshAdapterStateLocked();
                    g_state.coreMode = "error";
                    g_state.lastError = MihomoLastError();
                }
            }
        }
    }

    return CreateStateObject(env);
}

napi_value StopTun(napi_env env, napi_callback_info info)
{
    (void)info;
    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_forwarder.Stop();
        MihomoStop();
        CloseNativeFdLocked();
        g_state.running = false;
        g_state.tunFd = -1;
        g_state.controllerReady = false;
        g_state.controllerOnly = false;
        g_state.tunAttached = false;
        g_state.realConnectionReady = false;
        g_state.adapterVersion.clear();
        g_state.controllerVersion.clear();
        g_state.version.clear();
        RefreshAdapterStateLocked();
        g_state.coreMode = "stopped";
        g_state.stopCount += 1;
    }
    return CreateStateObject(env);
}

napi_value StartCore(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string configPath;
    bool ok = argc >= 1 && ReadStringArg(env, args[0], configPath);

    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_state.startCount += 1;
        g_state.configPath = configPath;
        g_state.tunFd = -1;
        g_state.controllerReady = false;
        g_state.controllerOnly = false;
        g_state.tunAttached = false;
        g_state.realConnectionReady = false;
        g_state.adapterVersion.clear();
        g_state.controllerVersion.clear();
        g_state.version.clear();
        CloseNativeFdLocked();
        RefreshAdapterStateLocked();

        if (!ok || configPath.empty()) {
            g_state.running = false;
            g_state.coreMode = "error";
            g_state.lastError = "invalid configPath";
        } else {
            int startResult = MihomoStartCore(configPath.c_str());
            if (startResult == 0) {
                g_state.running = true;
                g_state.controllerOnly = true;
                g_state.tunAttached = false;
                g_state.realConnectionReady = false;
                RefreshAdapterStateLocked();
                g_state.adapterVersion = MihomoVersion();
                g_state.version = g_state.adapterVersion;
                g_state.coreMode = "mihomo-controller";
                g_state.lastError.clear();
            } else {
                g_state.running = false;
                g_state.controllerOnly = false;
                g_state.tunAttached = false;
                g_state.realConnectionReady = false;
                RefreshAdapterStateLocked();
                g_state.coreMode = "error";
                g_state.lastError = MihomoLastError();
            }
        }
    }

    return CreateStateObject(env);
}

napi_value StopCore(napi_env env, napi_callback_info info)
{
    (void)info;
    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        g_forwarder.Stop();
        MihomoStop();
        CloseNativeFdLocked();
        g_state.running = false;
        g_state.tunFd = -1;
        g_state.controllerReady = false;
        g_state.controllerOnly = false;
        g_state.tunAttached = false;
        g_state.realConnectionReady = false;
        g_state.adapterVersion.clear();
        g_state.controllerVersion.clear();
        g_state.version.clear();
        RefreshAdapterStateLocked();
        g_state.coreMode = "stopped";
        g_state.stopCount += 1;
    }
    return CreateStateObject(env);
}

napi_value SetControllerReady(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool ready = false;
    std::string version;
    bool ok = argc >= 2 &&
              napi_get_value_bool(env, args[0], &ready) == napi_ok &&
              ReadStringArg(env, args[1], version);

    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        if (!ok) {
            g_state.controllerReady = false;
            g_state.controllerVersion.clear();
            g_state.version.clear();
            g_state.lastError = "invalid controllerReady or version";
        } else if (!ready) {
            g_state.controllerReady = false;
            g_state.controllerVersion.clear();
            g_state.version.clear();
        } else {
            g_state.controllerReady = true;
            g_state.controllerVersion = version;
            g_state.version = version;
            if (!g_state.running) {
                g_state.coreMode = "external-controller";
            }
            g_state.lastError.clear();
        }
    }

    return CreateStateObject(env);
}

napi_value GetState(napi_env env, napi_callback_info info)
{
    (void)info;
    {
        std::lock_guard<std::mutex> lock(g_stateMutex);
        RefreshAdapterStateLocked();
    }
    return CreateStateObject(env);
}

napi_value ProtectSocket(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t fd = -1;
    if (argc >= 1 && napi_get_value_int32(env, args[0], &fd) == napi_ok) {
        SocketProtector::Protect(fd);
    }

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value SetProtectCallback(napi_env env, napi_callback_info info)
{
    (void)env;
    (void)info;
    // Placeholder: stores the callback reference for future use
    // In a real implementation this would use napi_create_threadsafe_function
    // to allow the native layer to call back into the JS thread safely.
    // For now, the protect function is registered directly through the
    // TunForwarder::ProtectFunc type set at StartTun().
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value GetForwarderStats(napi_env env, napi_callback_info info)
{
    (void)info;
    ForwarderStatsSnapshot stats = g_forwarder.GetStats();

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetInt64(env, result, "packetsRead", stats.packetsRead);
    SetInt64(env, result, "packetsWritten", stats.packetsWritten);
    SetInt64(env, result, "bytesRead", stats.bytesRead);
    SetInt64(env, result, "bytesWritten", stats.bytesWritten);
    SetInt64(env, result, "readErrors", stats.readErrors);
    SetInt64(env, result, "writeErrors", stats.writeErrors);
    SetBoolean(env, result, "active", g_forwarder.IsActive());
    return result;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "startTun", nullptr, StartTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopTun", nullptr, StopTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startCore", nullptr, StartCore, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopCore", nullptr, StopCore, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setControllerReady", nullptr, SetControllerReady, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getState", nullptr, GetState, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "protectSocket", nullptr, ProtectSocket, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setProtectCallback", nullptr, SetProtectCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getForwarderStats", nullptr, GetForwarderStats, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module clashCoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&clashCoreModule);
}
