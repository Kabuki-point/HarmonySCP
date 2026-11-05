#include "napi/native_api.h"
#include "ssh_client.h"
#include <cmath>
#include <limits>
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
static void SetString(napi_env env, napi_value object, const char *key, const std::string &text) {
    napi_value value;
    napi_create_string_utf8(env, text.c_str(), text.size(), &value);
    napi_set_named_property(env, object, key, value);
}

static void SetNumber(napi_env env, napi_value object, const char *key, double number) {
    napi_value value;
    napi_create_double(env, number, &value);
    napi_set_named_property(env, object, key, value);
}
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
    napi_value available; napi_get_boolean(env, true, &available);
    napi_set_named_property(env, result, "nativeAvailable", available);
    SetString(env, result, "state", status.state);
    SetString(env, result, "message", status.message);
    SetString(env, result, "fingerprint", status.fingerprint);
    SetNumber(env, result, "connectionId", status.connectionId);
    return result;
}

static bool ConnectionId(napi_env env, napi_value value, uint32_t &out) {
    double number;
    if (napi_get_value_double(env, value, &number) != napi_ok ||
        !(number >= 0 && number <= std::numeric_limits<uint32_t>::max()) ||
        number != std::trunc(number)) return false;
    out = static_cast<uint32_t>(number);
    return true;
}

static napi_value StartTransfer(napi_env env, napi_callback_info info) {
    size_t count = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    bool upload;
    double fd;
    uint32_t connectionId;
    std::string path;
    if (count != 4 || napi_get_value_bool(env, args[0], &upload) != napi_ok ||
        napi_get_value_double(env, args[1], &fd) != napi_ok ||
        !(fd >= 0 && fd <= std::numeric_limits<int>::max()) || fd != std::trunc(fd) ||
        !String(env, args[2], path, 4096) ||
        !ConnectionId(env, args[3], connectionId)) return Bool(env, false);
    return Bool(env, client.StartTransfer(upload, static_cast<int>(fd), path, connectionId));
}

static napi_value CancelTransfer(napi_env env, napi_callback_info info) {
    client.CancelTransfer();
    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

static napi_value GetTransferStatus(napi_env env, napi_callback_info info) {
    const auto status = client.GetTransferStatus();
    napi_value result;
    napi_create_object(env, &result);
    SetString(env, result, "state", status.state);
    SetString(env, result, "message", status.message);
    SetNumber(env, result, "bytes", status.bytes);
    SetNumber(env, result, "total", status.total);
    return result;
}
static napi_value StartRemote(napi_env env, napi_callback_info info) {
    size_t count = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    RemoteRequest request{};
    std::string action;
    uint32_t connectionId;
    if (count != 4 || !String(env, args[0], action, 12) || !String(env, args[1], request.path, 4096) ||
        !String(env, args[2], request.newName, 4096) || !ConnectionId(env, args[3], connectionId)) {
        return Bool(env, false);
    }
    if (action == "list") request.action = RemoteAction::List;
    else if (action == "mkdir") request.action = RemoteAction::MakeDirectory;
    else if (action == "rename") request.action = RemoteAction::Rename;
    else if (action == "unlink") request.action = RemoteAction::RemoveFile;
    else if (action == "rmdir") request.action = RemoteAction::RemoveDirectory;
    else return Bool(env, false);
    return Bool(env, client.StartRemote(std::move(request), connectionId));
}

static napi_value GetRemoteStatus(napi_env env, napi_callback_info info) {
    const auto status = client.GetRemoteStatus();
    napi_value result, entries;
    napi_create_object(env, &result);
    napi_create_array_with_length(env, status.entries.size(), &entries);
    for (size_t i = 0; i < status.entries.size(); ++i) {
        const auto &entry = status.entries[i];
        napi_value object;
        napi_create_object(env, &object);
        SetString(env, object, "name", entry.name);
        SetString(env, object, "kind", entry.kind);
        SetNumber(env, object, "size", entry.size);
        SetNumber(env, object, "modified", entry.modified);
        napi_set_element(env, entries, i, object);
    }
    SetString(env, result, "state", status.state);
    SetString(env, result, "message", status.message);
    SetString(env, result, "path", status.path);
    napi_set_named_property(env, result, "entries", entries);
    return result;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"connect", nullptr, Connect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"authenticate", nullptr, Authenticate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"disconnect", nullptr, Disconnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTransfer", nullptr, StartTransfer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelTransfer", nullptr, CancelTransfer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"transferStatus", nullptr, GetTransferStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startRemote", nullptr, StartRemote, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"remoteStatus", nullptr, GetRemoteStatus, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc); return exports;
}
static napi_module module = {1, 0, nullptr, Init, "entry", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterEntryModule() { napi_module_register(&module); }
