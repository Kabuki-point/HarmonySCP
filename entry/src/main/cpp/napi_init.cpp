#include "napi/native_api.h"
#include "ssh_client.h"
#include <vector>

static SshClient client;
static bool String(napi_env env, napi_value value, std::string &out, size_t limit) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok || size > limit) return false;
    std::vector<char> buffer(size + 1);
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &size) != napi_ok) return false;
    out.assign(buffer.data(), size);
    volatile char *p = buffer.data(); for (size_t i = 0; i < buffer.size(); ++i) p[i] = 0;
    return true;
}
static napi_value Bool(napi_env env, bool value) { napi_value result; napi_get_boolean(env, value, &result); return result; }
static napi_value Connect(napi_env env, napi_callback_info info) {
    size_t count = 2; napi_value args[2]; napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    std::string host; double port = 0;
    if (count != 2 || !String(env, args[0], host, 128) || napi_get_value_double(env, args[1], &port) != napi_ok ||
        !(port >= 1 && port <= 65535) || port != static_cast<int>(port)) return Bool(env, false);
    return Bool(env, client.Connect(host, static_cast<int>(port)));
}
static napi_value Authenticate(napi_env env, napi_callback_info info) {
    size_t count = 3; napi_value args[3]; napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    std::string user, password, fingerprint;
    bool valid = count == 3 && String(env, args[0], user, 256) && String(env, args[1], password, 4096) && String(env, args[2], fingerprint, 128);
    bool result = valid && client.Authenticate(user, password, fingerprint);
    if (!password.empty()) { volatile char *p = &password[0]; for (size_t i = 0; i < password.size(); ++i) p[i] = 0; }
    return Bool(env, result);
}
static napi_value Disconnect(napi_env env, napi_callback_info info) { client.Disconnect(); napi_value value; napi_get_undefined(env, &value); return value; }
static napi_value Status(napi_env env, napi_callback_info info) {
    auto status = client.Status(); napi_value result; napi_create_object(env, &result);
    auto set = [&](const char *key, const std::string &text) { napi_value value; napi_create_string_utf8(env, text.c_str(), text.size(), &value); napi_set_named_property(env, result, key, value); };
    napi_value available; napi_get_boolean(env, true, &available);
    napi_set_named_property(env, result, "nativeAvailable", available);
    set("state", status.state); set("message", status.message); set("fingerprint", status.fingerprint); return result;
}
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"connect", nullptr, Connect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"authenticate", nullptr, Authenticate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"disconnect", nullptr, Disconnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc); return exports;
}
static napi_module module = {1, 0, nullptr, Init, "entry", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterEntryModule() { napi_module_register(&module); }
