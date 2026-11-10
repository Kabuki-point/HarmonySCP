#include "atlas_gl.h"

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <napi/native_api.h>
#include <string>
#include <vector>

namespace {

void OnSurfaceCreated(OH_NativeXComponent* component, void* window) {
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    OH_NativeXComponent_ExpectedRateRange range = {30, 60, 60};
    OH_NativeXComponent_SetExpectedFrameRateRange(component, &range);
    AtlasSetSurface(window, width, height);
    AtlasDraw();
}

void OnSurfaceChanged(OH_NativeXComponent* component, void* window) {
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    AtlasSetSurface(window, width, height);
    AtlasDraw();
}

void OnSurfaceDestroyed(OH_NativeXComponent* component, void* window) {
    (void)component;
    (void)window;
    AtlasClearSurface();
}

void OnDispatchTouch(OH_NativeXComponent* component, void* window) {
    (void)component;
    (void)window;
}

OH_NativeXComponent_Callback g_callback = {
    OnSurfaceCreated,
    OnSurfaceChanged,
    OnSurfaceDestroyed,
    OnDispatchTouch,
};

void OnFrame(OH_NativeXComponent* component, uint64_t timestamp, uint64_t targetTimestamp) {
    (void)component;
    (void)timestamp;
    (void)targetTimestamp;
    AtlasDraw();
}

bool ReadDouble(napi_env env, napi_value value, double& out) {
    return napi_get_value_double(env, value, &out) == napi_ok;
}

bool ReadString(napi_env env, napi_value value, std::string& out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    std::vector<char> buf(len + 1, '\0');
    size_t written = 0;
    if (napi_get_value_string_utf8(env, value, buf.data(), buf.size(), &written) != napi_ok) {
        return false;
    }
    out.assign(buf.data(), written);
    return true;
}

bool ReadBuffer(napi_env env, napi_value value, std::string& out) {
    void* data = nullptr;
    size_t len = 0;
    if (napi_get_arraybuffer_info(env, value, &data, &len) != napi_ok || data == nullptr) {
        out.clear();
        return false;
    }
    out.assign(static_cast<const char*>(data), len);
    return true;
}

napi_value Num(napi_env env, napi_value value, double& out) {
    if (!ReadDouble(env, value, out)) {
        return nullptr;
    }
    return reinterpret_cast<napi_value>(1);
}

napi_value SubmitFrame(napi_env env, napi_callback_info info) {
    size_t argc = 22;
    napi_value argv[22];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 22) {
        return nullptr;
    }
    double width = 0;
    double height = 0;
    double cols = 0;
    double rows = 0;
    double cellW = 0;
    double cellH = 0;
    double fontPx = 0;
    double clearRgb = 0;
    double cursorCol = 0;
    double cursorRow = 0;
    double cursorShape = 0;
    double cursorRgb = 0;
    double accentRgb = 0;
    double barX = 0;
    double barY = 0;
    double barW = 0;
    double barH = 0;
    double barTrackA = 0;
    double barThumbA = 0;
    if (!ReadDouble(env, argv[0], width) || !ReadDouble(env, argv[1], height) ||
        !ReadDouble(env, argv[2], cols) || !ReadDouble(env, argv[3], rows) ||
        !ReadDouble(env, argv[4], cellW) || !ReadDouble(env, argv[5], cellH) ||
        !ReadDouble(env, argv[6], fontPx) || !ReadDouble(env, argv[8], clearRgb) ||
        !ReadDouble(env, argv[11], cursorCol) || !ReadDouble(env, argv[12], cursorRow) ||
        !ReadDouble(env, argv[13], cursorShape) || !ReadDouble(env, argv[14], cursorRgb) ||
        !ReadDouble(env, argv[15], accentRgb) || !ReadDouble(env, argv[16], barX) ||
        !ReadDouble(env, argv[17], barY) || !ReadDouble(env, argv[18], barW) ||
        !ReadDouble(env, argv[19], barH) || !ReadDouble(env, argv[20], barTrackA) ||
        !ReadDouble(env, argv[21], barThumbA)) {
        return nullptr;
    }
    AtlasFrame frame;
    frame.width = static_cast<int>(width);
    frame.height = static_cast<int>(height);
    frame.cols = static_cast<int>(cols);
    frame.rows = static_cast<int>(rows);
    frame.cellW = static_cast<int>(cellW);
    frame.cellH = static_cast<int>(cellH);
    frame.fontPx = static_cast<float>(fontPx);
    frame.clearRgb = static_cast<uint32_t>(clearRgb);
    ReadString(env, argv[7], frame.fontFamily);
    ReadBuffer(env, argv[9], frame.cells);
    ReadBuffer(env, argv[10], frame.extra);
    frame.cursorCol = static_cast<int>(cursorCol);
    frame.cursorRow = static_cast<int>(cursorRow);
    frame.cursorShape = static_cast<int>(cursorShape);
    frame.cursorRgb = static_cast<uint32_t>(cursorRgb);
    frame.accentRgb = static_cast<uint32_t>(accentRgb);
    frame.barX = static_cast<float>(barX);
    frame.barY = static_cast<float>(barY);
    frame.barW = static_cast<float>(barW);
    frame.barH = static_cast<float>(barH);
    frame.barTrackA = static_cast<float>(barTrackA);
    frame.barThumbA = static_cast<float>(barThumbA);
    AtlasSubmit(frame);
    return nullptr;
}

napi_value MeasureCellWidth(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double fontPx = 0;
    std::string family;
    napi_value out = nullptr;
    if (argc < 2 || !ReadDouble(env, argv[0], fontPx) || !ReadString(env, argv[1], family)) {
        napi_create_int32(env, 0, &out);
        return out;
    }
    napi_create_int32(env, AtlasMeasureCell(static_cast<float>(fontPx), family), &out);
    return out;
}

napi_value SurfaceWidth(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out = nullptr;
    napi_create_int32(env, AtlasSurfaceWidth(), &out);
    return out;
}

napi_value SurfaceHeight(napi_env env, napi_callback_info info) {
    (void)info;
    napi_value out = nullptr;
    napi_create_int32(env, AtlasSurfaceHeight(), &out);
    return out;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"submitFrame", nullptr, SubmitFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"measureCellWidth", nullptr, MeasureCellWidth, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"surfaceWidth", nullptr, SurfaceWidth, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"surfaceHeight", nullptr, SurfaceHeight, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) == napi_ok) {
        OH_NativeXComponent* component = nullptr;
        if (napi_unwrap(env, exportInstance, reinterpret_cast<void**>(&component)) == napi_ok && component != nullptr) {
            OH_NativeXComponent_RegisterCallback(component, &g_callback);
            OH_NativeXComponent_RegisterOnFrameCallback(component, OnFrame);
        }
    }
    return exports;
}

} // namespace

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "termatlas",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterTermAtlas(void) {
    napi_module_register(&g_module);
}
