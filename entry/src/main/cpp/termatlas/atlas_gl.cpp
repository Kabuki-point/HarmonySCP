#include "atlas_gl.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <cmath>
#include <cstring>
#include <hilog/log.h>
#include <mutex>
#include <native_drawing/drawing_bitmap.h>
#include <native_drawing/drawing_canvas.h>
#include <native_drawing/drawing_font_collection.h>
#include <native_drawing/drawing_text_typography.h>
#include <native_window/external_window.h>
#include <unordered_map>
#include <vector>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "TermAtlas"

namespace {

constexpr int ATLAS = 2048;
constexpr int CELL_BYTES = 16;
constexpr uint32_t ATTR_BOLD = 1u << 0;
constexpr uint32_t ATTR_ITALIC = 1u << 2;
constexpr uint32_t ATTR_UNDERLINE = 1u << 3;
constexpr uint32_t ATTR_STRIKETHROUGH = 1u << 7;
constexpr uint8_t FLAG_GLYPH = 1;
constexpr uint8_t FLAG_EXTRA = 2;

int CellGap(float fontPx) {
    int gap = static_cast<int>(fontPx * 0.15f);
    if (gap < 2) {
        gap = 2;
    }
    return gap;
}

struct Glyph {
    int x = 0;
    int y = 0;
    int w = 0;
    int h = 0;
};

struct Vert {
    float x;
    float y;
    float u;
    float v;
    float r;
    float g;
    float b;
    float a;
};

struct Renderer {
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext context = EGL_NO_CONTEXT;
    EGLConfig config = nullptr;
    void* window = nullptr;
    bool glReady = false;
    GLuint program = 0;
    GLuint atlasTex = 0;
    GLuint vbo = 0;
    int atlasX = 1;
    int atlasY = 0;
    int atlasRowH = 0;
    int fontGen = 1;
    float cachedFontPx = -1;
    std::string cachedFamily;
    OH_Drawing_FontCollection* fonts = nullptr;
    std::unordered_map<std::string, Glyph> glyphs;
    std::mutex mu;
    AtlasFrame pending;
    bool dirty = false;
    bool hasFrame = false;
    int surfaceW = 0;
    int surfaceH = 0;
};

Renderer g;

const char* kVs = R"(#version 300 es
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 2) in vec4 aColor;
uniform vec2 uViewport;
out vec2 vUv;
out vec4 vColor;
void main() {
  vec2 clip = (aPos / uViewport) * 2.0 - 1.0;
  clip.y = -clip.y;
  gl_Position = vec4(clip, 0.0, 1.0);
  vUv = aUv;
  vColor = aColor;
}
)";

const char* kFs = R"(#version 300 es
precision mediump float;
uniform sampler2D uAtlas;
in vec2 vUv;
in vec4 vColor;
out vec4 frag;
void main() {
  float cover = texture(uAtlas, vUv).r;
  frag = vec4(vColor.rgb, vColor.a * cover);
}
)";

void LogEgl(const char* what) {
    OH_LOG_ERROR(LOG_APP, "%{public}s egl=%{public}d", what, eglGetError());
}

GLuint Compile(GLenum type, const char* src) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        OH_LOG_ERROR(LOG_APP, "shader compile failed");
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

bool InitGl() {
    if (g.glReady) {
        return true;
    }
    GLuint vs = Compile(GL_VERTEX_SHADER, kVs);
    GLuint fs = Compile(GL_FRAGMENT_SHADER, kFs);
    if (vs == 0 || fs == 0) {
        return false;
    }
    g.program = glCreateProgram();
    glAttachShader(g.program, vs);
    glAttachShader(g.program, fs);
    glLinkProgram(g.program);
    glDeleteShader(vs);
    glDeleteShader(fs);
    GLint linked = 0;
    glGetProgramiv(g.program, GL_LINK_STATUS, &linked);
    if (!linked) {
        OH_LOG_ERROR(LOG_APP, "program link failed");
        return false;
    }
    glGenTextures(1, &g.atlasTex);
    glBindTexture(GL_TEXTURE_2D, g.atlasTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    std::vector<uint8_t> blank(static_cast<size_t>(ATLAS) * ATLAS, 0);
    blank[0] = 255;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, ATLAS, ATLAS, 0, GL_RED, GL_UNSIGNED_BYTE, blank.data());
    glGenBuffers(1, &g.vbo);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    if (g.fonts == nullptr) {
        g.fonts = OH_Drawing_CreateSharedFontCollection();
    }
    g.glReady = true;
    return true;
}

void ResetAtlas() {
    g.atlasX = 1;
    g.atlasY = 0;
    g.atlasRowH = 0;
    g.glyphs.clear();
    g.fontGen++;
    if (g.atlasTex == 0) {
        return;
    }
    std::vector<uint8_t> blank(static_cast<size_t>(ATLAS) * ATLAS, 0);
    blank[0] = 255;
    glBindTexture(GL_TEXTURE_2D, g.atlasTex);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, ATLAS, ATLAS, GL_RED, GL_UNSIGNED_BYTE, blank.data());
}

std::string Utf8Of(uint32_t cp) {
    std::string out;
    if (cp < 0x80) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
    return out;
}

bool Raster(const std::string& text, int style, int pxW, int pxH, float fontPx,
    const std::string& family, std::vector<uint8_t>& alpha) {
    if (pxW <= 0 || pxH <= 0 || text.empty() || g.fonts == nullptr) {
        return false;
    }
    OH_Drawing_BitmapFormat fmt{COLOR_FORMAT_RGBA_8888, ALPHA_FORMAT_PREMUL};
    OH_Drawing_TypographyStyle* ty = OH_Drawing_CreateTypographyStyle();
    // Left + unconstrained layout, then center via paint origin (see below).
    OH_Drawing_SetTypographyTextAlign(ty, TEXT_ALIGN_LEFT);
    OH_Drawing_TextStyle* ts = OH_Drawing_CreateTextStyle();
    OH_Drawing_SetTextStyleColor(ts, 0xFFFFFFFF);
    OH_Drawing_SetTextStyleFontSize(ts, fontPx);
    OH_Drawing_SetTextStyleFontWeight(ts, (style & 1) ? FONT_WEIGHT_700 : FONT_WEIGHT_400);
    OH_Drawing_SetTextStyleFontStyle(ts, (style & 2) ? FONT_STYLE_ITALIC : FONT_STYLE_NORMAL);
    if (!family.empty()) {
        const char* fams[] = {family.c_str()};
        OH_Drawing_SetTextStyleFontFamilies(ts, 1, fams);
    }
    OH_Drawing_TypographyCreate* handler = OH_Drawing_CreateTypographyHandler(ty, g.fonts);
    OH_Drawing_TypographyHandlerPushTextStyle(handler, ts);
    OH_Drawing_TypographyHandlerAddText(handler, text.c_str());
    OH_Drawing_Typography* typo = OH_Drawing_CreateTypography(handler);
    // Layout unconstrained so a wide glyph is not wrapped or squeezed into the cell.
    OH_Drawing_TypographyLayout(typo, 10000.0);
    // Canvas measureText and this drawer disagree. @ / W ink is wider than the
    // cell, so a cell-sized bitmap clips both sides. Draw into a padded scratch
    // bitmap, then fit the real ink into the cell.
    const int pad = std::max(4, static_cast<int>(fontPx));
    const int scratchW = std::max(pxW + pad * 2, static_cast<int>(fontPx * 4.0f));
    const int scratchH = std::max(pxH + pad * 2, static_cast<int>(fontPx * 4.0f));
    OH_Drawing_Bitmap* scratch = OH_Drawing_BitmapCreate();
    OH_Drawing_BitmapBuild(scratch, static_cast<uint32_t>(scratchW), static_cast<uint32_t>(scratchH), &fmt);
    OH_Drawing_Canvas* scratchCanvas = OH_Drawing_CanvasCreate();
    OH_Drawing_CanvasBind(scratchCanvas, scratch);
    OH_Drawing_CanvasClear(scratchCanvas, 0);
    OH_Drawing_TypographyPaint(typo, scratchCanvas, static_cast<float>(pad), static_cast<float>(pad));
    void* scratchPx = OH_Drawing_BitmapGetPixels(scratch);
    alpha.assign(static_cast<size_t>(pxW) * pxH, 0);
    if (scratchPx != nullptr) {
        const auto* src = static_cast<const uint8_t*>(scratchPx);
        auto coverAt = [&](int x, int y) -> uint8_t {
            const uint8_t* px = src + (static_cast<size_t>(y) * scratchW + x) * 4;
            uint8_t cover = px[0];
            if (px[1] > cover) {
                cover = px[1];
            }
            if (px[2] > cover) {
                cover = px[2];
            }
            if (px[3] > cover) {
                cover = px[3];
            }
            return cover;
        };
        int minX = scratchW;
        int minY = scratchH;
        int maxX = -1;
        int maxY = -1;
        for (int y = 0; y < scratchH; y++) {
            for (int x = 0; x < scratchW; x++) {
                if (coverAt(x, y) == 0) {
                    continue;
                }
                if (x < minX) {
                    minX = x;
                }
                if (y < minY) {
                    minY = y;
                }
                if (x > maxX) {
                    maxX = x;
                }
                if (y > maxY) {
                    maxY = y;
                }
            }
        }
        if (maxX >= minX && maxY >= minY) {
            const int inkW = maxX - minX + 1;
            // Fit into the "~" ink width. The extra cell pixels are the gap between glyphs.
            int limit = pxW - CellGap(fontPx);
            if (limit < 1) {
                limit = pxW;
            }
            float scaleX = 1.0f;
            if (inkW > limit) {
                scaleX = static_cast<float>(limit) / static_cast<float>(inkW);
            }
            const float inkCenter = (static_cast<float>(minX) + static_cast<float>(maxX)) * 0.5f;
            const double baseline = OH_Drawing_TypographyGetAlphabeticBaseline(typo);
            const double lineH = OH_Drawing_TypographyGetHeight(typo);
            const float scratchBaseline = static_cast<float>(pad) + static_cast<float>(baseline);
            float cellBaseline = static_cast<float>(pxH - 1);
            if (lineH > 0.0 && baseline > 0.0) {
                cellBaseline = static_cast<float>(pxH) - (static_cast<float>(lineH) - static_cast<float>(baseline));
            }
            if (cellBaseline < 0.0f) {
                cellBaseline = 0.0f;
            }
            for (int y = minY; y <= maxY; y++) {
                for (int x = minX; x <= maxX; x++) {
                    const uint8_t cover = coverAt(x, y);
                    if (cover == 0) {
                        continue;
                    }
                    const float dx = (static_cast<float>(x) + 0.5f - inkCenter) * scaleX + static_cast<float>(pxW) * 0.5f;
                    const float dy = (static_cast<float>(y) + 0.5f - scratchBaseline) + cellBaseline;
                    const int ix = static_cast<int>(dx);
                    const int iy = static_cast<int>(dy);
                    if (ix < 0 || iy < 0 || ix >= pxW || iy >= pxH) {
                        continue;
                    }
                    uint8_t& dst = alpha[static_cast<size_t>(iy) * pxW + ix];
                    if (cover > dst) {
                        dst = cover;
                    }
                }
            }
        }
    }
    OH_Drawing_CanvasDestroy(scratchCanvas);
    OH_Drawing_BitmapDestroy(scratch);
    OH_Drawing_DestroyTypography(typo);
    OH_Drawing_DestroyTypographyHandler(handler);
    OH_Drawing_DestroyTextStyle(ts);
    OH_Drawing_DestroyTypographyStyle(ty);
    return true;
}

const Glyph* Place(const std::string& text, int style, int span, const AtlasFrame& frame) {
    std::string key = std::to_string(g.fontGen) + "|" + std::to_string(style) + "|" + text;
    auto found = g.glyphs.find(key);
    if (found != g.glyphs.end()) {
        return &found->second;
    }
    const int pxW = frame.cellW * span;
    const int pxH = frame.cellH;
    if (g.atlasX + pxW > ATLAS) {
        g.atlasX = 1;
        g.atlasY += g.atlasRowH;
        g.atlasRowH = 0;
    }
    if (g.atlasY + pxH > ATLAS) {
        return nullptr;
    }
    std::vector<uint8_t> alpha;
    if (!Raster(text, style, pxW, pxH, frame.fontPx, frame.fontFamily, alpha)) {
        return nullptr;
    }
    glBindTexture(GL_TEXTURE_2D, g.atlasTex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexSubImage2D(GL_TEXTURE_2D, 0, g.atlasX, g.atlasY, pxW, pxH, GL_RED, GL_UNSIGNED_BYTE, alpha.data());
    Glyph slot;
    slot.x = g.atlasX;
    slot.y = g.atlasY;
    slot.w = pxW;
    slot.h = pxH;
    g.atlasX += pxW;
    if (pxH > g.atlasRowH) {
        g.atlasRowH = pxH;
    }
    auto inserted = g.glyphs.emplace(key, slot);
    return &inserted.first->second;
}

void PushQuad(std::vector<Vert>& out, float x0, float y0, float x1, float y1,
    float u0, float v0, float u1, float v1, uint32_t rgb, float alpha) {
    const float r = static_cast<float>((rgb >> 16) & 0xFF) / 255.0f;
    const float gch = static_cast<float>((rgb >> 8) & 0xFF) / 255.0f;
    const float b = static_cast<float>(rgb & 0xFF) / 255.0f;
    Vert q[6] = {
        {x0, y0, u0, v0, r, gch, b, alpha},
        {x1, y0, u1, v0, r, gch, b, alpha},
        {x0, y1, u0, v1, r, gch, b, alpha},
        {x1, y0, u1, v0, r, gch, b, alpha},
        {x1, y1, u1, v1, r, gch, b, alpha},
        {x0, y1, u0, v1, r, gch, b, alpha},
    };
    for (int i = 0; i < 6; i++) {
        out.push_back(q[i]);
    }
}

void PushSolid(std::vector<Vert>& out, float x0, float y0, float x1, float y1, uint32_t rgb, float alpha) {
    const float u = 0.5f / ATLAS;
    PushQuad(out, x0, y0, x1, y1, u, u, u, u, rgb, alpha);
}

/** Unicode box drawing / block separators (tmux borders, etc.). */
bool IsBoxDrawing(uint32_t cp) {
    return (cp >= 0x2500 && cp <= 0x259F);
}

/**
 * Draw box-drawing as cell-filling geometry so adjacent cells form continuous lines.
 * Returns false if the codepoint should fall back to glyph atlas.
 */
bool PushBoxDrawing(std::vector<Vert>& out, uint32_t cp,
    float x0, float y0, float x1, float y1, uint32_t fg) {
    const float cellW = x1 - x0;
    const float cellH = y1 - y0;
    if (cellW <= 0.0f || cellH <= 0.0f) {
        return false;
    }
    const float cx = (x0 + x1) * 0.5f;
    const float cy = (y0 + y1) * 0.5f;
    // Keep stroke thick enough to meet at cell edges without gaps.
    float t = std::max(1.0f, std::floor(std::min(cellW, cellH) * 0.12f + 0.5f));
    if (static_cast<int>(t) % 2 == 0) {
        t += 1.0f;
    }
    const float t2 = t * 0.5f;

    auto hline = [&](float xa, float xb, float y) {
        PushSolid(out, xa, y - t2, xb, y + t2, fg, 1.0f);
    };
    auto vline = [&](float x, float ya, float yb) {
        PushSolid(out, x - t2, ya, x + t2, yb, fg, 1.0f);
    };
    // Connection bits from cell center: N S W E
    constexpr int N = 1;
    constexpr int S = 2;
    constexpr int W = 4;
    constexpr int E = 8;

    auto stroke = [&](int mask) {
        if ((mask & W) != 0) {
            hline(x0, cx + t2, cy);
        }
        if ((mask & E) != 0) {
            hline(cx - t2, x1, cy);
        }
        if ((mask & N) != 0) {
            vline(cx, y0, cy + t2);
        }
        if ((mask & S) != 0) {
            vline(cx, cy - t2, y1);
        }
    };

    // Light / heavy share the same topology; heavy just uses the same stroke.
    switch (cp) {
        case 0x2500: case 0x2501: stroke(W | E); return true; // ─ ━
        case 0x2502: case 0x2503: stroke(N | S); return true; // │ ┃
        case 0x250C: case 0x250F: stroke(S | E); return true; // ┌ ┏
        case 0x2510: case 0x2513: stroke(S | W); return true; // ┐ ┓
        case 0x2514: case 0x2517: stroke(N | E); return true; // └ ┗
        case 0x2518: case 0x251B: stroke(N | W); return true; // ┘ ┛
        case 0x251C: case 0x2523: stroke(N | S | E); return true; // ├ ┣
        case 0x2524: case 0x252B: stroke(N | S | W); return true; // ┤ ┫
        case 0x252C: case 0x2533: stroke(S | W | E); return true; // ┬ ┳
        case 0x2534: case 0x253B: stroke(N | W | E); return true; // ┴ ┻
        case 0x253C: case 0x254B: stroke(N | S | W | E); return true; // ┼ ╋
        case 0x2574: stroke(W); return true; // ╴
        case 0x2575: stroke(N); return true; // ╵
        case 0x2576: stroke(E); return true; // ╶
        case 0x2577: stroke(S); return true; // ╷
        case 0x2578: stroke(W); return true;
        case 0x2579: stroke(N); return true;
        case 0x257A: stroke(E); return true;
        case 0x257B: stroke(S); return true;
        // Double-line: two parallel strokes.
        case 0x2550: { // ═
            const float o = std::max(t, cellH * 0.15f);
            hline(x0, x1, cy - o);
            hline(x0, x1, cy + o);
            return true;
        }
        case 0x2551: { // ║
            const float o = std::max(t, cellW * 0.15f);
            vline(cx - o, y0, y1);
            vline(cx + o, y0, y1);
            return true;
        }
        case 0x2552: case 0x2553: case 0x2554: // ╒ ╓ ╔
            stroke(S | E);
            return true;
        case 0x2555: case 0x2556: case 0x2557:
            stroke(S | W);
            return true;
        case 0x2558: case 0x2559: case 0x255A:
            stroke(N | E);
            return true;
        case 0x255B: case 0x255C: case 0x255D:
            stroke(N | W);
            return true;
        case 0x255E: case 0x255F: case 0x2560:
            stroke(N | S | E);
            return true;
        case 0x2561: case 0x2562: case 0x2563:
            stroke(N | S | W);
            return true;
        case 0x2564: case 0x2565: case 0x2566:
            stroke(S | W | E);
            return true;
        case 0x2567: case 0x2568: case 0x2569:
            stroke(N | W | E);
            return true;
        case 0x256A: case 0x256B: case 0x256C:
            stroke(N | S | W | E);
            return true;
        // Block elements used as solid separators.
        case 0x2588: // █ full block
            PushSolid(out, x0, y0, x1, y1, fg, 1.0f);
            return true;
        case 0x258C: // ▌ left half
            PushSolid(out, x0, y0, cx, y1, fg, 1.0f);
            return true;
        case 0x2590: // ▐ right half
            PushSolid(out, cx, y0, x1, y1, fg, 1.0f);
            return true;
        case 0x2580: // ▀ upper half
            PushSolid(out, x0, y0, x1, cy, fg, 1.0f);
            return true;
        case 0x2584: // ▄ lower half
            PushSolid(out, x0, cy, x1, y1, fg, 1.0f);
            return true;
        default:
            return false;
    }
}

void ReadCell(const std::string& cells, int index, uint32_t& cp, uint32_t& fg, uint32_t& bg,
    uint16_t& attrs, uint8_t& width, uint8_t& flags) {
    const size_t off = static_cast<size_t>(index) * CELL_BYTES;
    const auto* p = reinterpret_cast<const uint8_t*>(cells.data() + off);
    auto u32 = [&](int o) {
        return static_cast<uint32_t>(p[o]) | (static_cast<uint32_t>(p[o + 1]) << 8) |
            (static_cast<uint32_t>(p[o + 2]) << 16) | (static_cast<uint32_t>(p[o + 3]) << 24);
    };
    cp = u32(0);
    fg = u32(4);
    bg = u32(8);
    attrs = static_cast<uint16_t>(p[12] | (p[13] << 8));
    width = p[14];
    flags = p[15];
}

std::string ExtraText(const std::string& extra, uint32_t offset) {
    if (offset + 2 > extra.size()) {
        return "";
    }
    const auto* p = reinterpret_cast<const uint8_t*>(extra.data() + offset);
    const uint16_t len = static_cast<uint16_t>(p[0] | (p[1] << 8));
    if (offset + 2 + len > extra.size()) {
        return "";
    }
    return extra.substr(offset + 2, len);
}

void Build(const AtlasFrame& frame, std::vector<Vert>& verts) {
    if (frame.fontPx != g.cachedFontPx || frame.fontFamily != g.cachedFamily) {
        g.cachedFontPx = frame.fontPx;
        g.cachedFamily = frame.fontFamily;
        ResetAtlas();
    }
    const int cols = frame.cols;
    const int rows = frame.rows;
    const size_t need = static_cast<size_t>(cols) * rows * CELL_BYTES;
    if (frame.cells.size() < need || frame.cellW <= 0 || frame.cellH <= 0) {
        return;
    }
    for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols;) {
            uint32_t cp = 0;
            uint32_t fg = 0;
            uint32_t bg = 0;
            uint16_t attrs = 0;
            uint8_t width = 0;
            uint8_t flags = 0;
            ReadCell(frame.cells, row * cols + col, cp, fg, bg, attrs, width, flags);
            const int span = width == 2 ? 2 : 1;
            const float x0 = static_cast<float>(col * frame.cellW);
            const float y0 = static_cast<float>(row * frame.cellH);
            const float x1 = x0 + static_cast<float>(span * frame.cellW);
            const float y1 = y0 + static_cast<float>(frame.cellH);
            if (bg != frame.clearRgb) {
                PushSolid(verts, x0, y0, x1, y1, bg, 1.0f);
            }
            // Prefer geometric box-drawing so tmux borders form continuous lines.
            if (width != 0 && (flags & FLAG_GLYPH) != 0 &&
                IsBoxDrawing(cp) && PushBoxDrawing(verts, cp, x0, y0, x1, y1, fg)) {
                col += span;
                continue;
            }
            if (width != 0 && (flags & (FLAG_GLYPH | FLAG_EXTRA)) != 0) {
                std::string text = (flags & FLAG_EXTRA) ? ExtraText(frame.extra, cp) : Utf8Of(cp);
                if (!text.empty() && text != " ") {
                    int style = 0;
                    if ((attrs & ATTR_BOLD) != 0) {
                        style |= 1;
                    }
                    if ((attrs & ATTR_ITALIC) != 0) {
                        style |= 2;
                    }
                    const Glyph* slot = Place(text, style, span, frame);
                    if (slot != nullptr && slot->w > 0) {
                        const float u0 = static_cast<float>(slot->x) / ATLAS;
                        const float v0 = static_cast<float>(slot->y) / ATLAS;
                        const float u1 = static_cast<float>(slot->x + slot->w) / ATLAS;
                        const float v1 = static_cast<float>(slot->y + slot->h) / ATLAS;
                        PushQuad(verts, x0, y0, x1, y1, u0, v0, u1, v1, fg, 1.0f);
                    }
                }
            }
            if ((attrs & ATTR_UNDERLINE) != 0) {
                const float uy = y1 - 2.0f;
                PushSolid(verts, x0, uy, x1, uy + 1.0f, fg, 1.0f);
            }
            if ((attrs & ATTR_STRIKETHROUGH) != 0) {
                const float sy = y0 + static_cast<float>(frame.cellH) * 0.55f;
                PushSolid(verts, x0, sy, x1, sy + 1.0f, fg, 1.0f);
            }
            col += span;
        }
    }
    if (frame.cursorShape >= 0 && frame.cursorRow >= 0 && frame.cursorRow < rows &&
        frame.cursorCol >= 0 && frame.cursorCol < cols) {
        const float x0 = static_cast<float>(frame.cursorCol * frame.cellW);
        const float y0 = static_cast<float>(frame.cursorRow * frame.cellH);
        float span = 1.0f;
        uint32_t cp = 0;
        uint32_t fg = 0;
        uint32_t bg = 0;
        uint16_t attrs = 0;
        uint8_t width = 0;
        uint8_t flags = 0;
        ReadCell(frame.cells, frame.cursorRow * cols + frame.cursorCol, cp, fg, bg, attrs, width, flags);
        if (width == 2) {
            span = 2.0f;
        }
        const float x1 = x0 + span * frame.cellW;
        const float y1 = y0 + frame.cellH;
        if (frame.cursorShape == 1) {
            PushSolid(verts, x0, y1 - 2.0f, x1, y1, frame.cursorRgb, 1.0f);
        } else if (frame.cursorShape == 2) {
            PushSolid(verts, x0, y0, x0 + 2.0f, y1, frame.cursorRgb, 1.0f);
        } else {
            PushSolid(verts, x0, y0, x1, y1, frame.cursorRgb, 1.0f);
            if ((flags & (FLAG_GLYPH | FLAG_EXTRA)) != 0) {
                std::string text = (flags & FLAG_EXTRA) ? ExtraText(frame.extra, cp) : Utf8Of(cp);
                if (!text.empty() && text != " ") {
                    int style = ((attrs & ATTR_BOLD) != 0 ? 1 : 0) | ((attrs & ATTR_ITALIC) != 0 ? 2 : 0);
                    const Glyph* slot = Place(text, style, width == 2 ? 2 : 1, frame);
                    if (slot != nullptr) {
                        const float u0 = static_cast<float>(slot->x) / ATLAS;
                        const float v0 = static_cast<float>(slot->y) / ATLAS;
                        const float u1 = static_cast<float>(slot->x + slot->w) / ATLAS;
                        const float v1 = static_cast<float>(slot->y + slot->h) / ATLAS;
                        PushQuad(verts, x0, y0, x1, y1, u0, v0, u1, v1, frame.accentRgb, 1.0f);
                    }
                }
            }
        }
    }
    if (frame.barH > 1.0f && frame.barW > 1.0f) {
        PushSolid(verts, frame.barX, 0, frame.barX + frame.barW, static_cast<float>(frame.height), 0xFFFFFF, frame.barTrackA);
        PushSolid(verts, frame.barX, frame.barY, frame.barX + frame.barW, frame.barY + frame.barH, 0xFFFFFF, frame.barThumbA);
    }
}

void DrawFrame(const AtlasFrame& frame, int surfaceW, int surfaceH) {
    if (!InitGl() || frame.width <= 0 || frame.height <= 0) {
        return;
    }
    int viewW = frame.width;
    int viewH = frame.height;
    if (surfaceW > 0 && surfaceW < viewW) {
        viewW = surfaceW;
    }
    if (surfaceH > 0 && surfaceH < viewH) {
        viewH = surfaceH;
    }
    if (g.window != nullptr) {
        OH_NativeWindow_NativeWindowHandleOpt(static_cast<OHNativeWindow*>(g.window), SET_BUFFER_GEOMETRY,
            viewW, viewH);
    }
    glViewport(0, 0, viewW, viewH);
    const float cr = static_cast<float>((frame.clearRgb >> 16) & 0xFF) / 255.0f;
    const float cg = static_cast<float>((frame.clearRgb >> 8) & 0xFF) / 255.0f;
    const float cb = static_cast<float>(frame.clearRgb & 0xFF) / 255.0f;
    glClearColor(cr, cg, cb, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    std::vector<Vert> verts;
    verts.reserve(static_cast<size_t>(frame.cols) * frame.rows * 6);
    Build(frame, verts);
    if (!verts.empty()) {
        glUseProgram(g.program);
        glUniform2f(glGetUniformLocation(g.program, "uViewport"),
            static_cast<float>(viewW), static_cast<float>(viewH));
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, g.atlasTex);
        glUniform1i(glGetUniformLocation(g.program, "uAtlas"), 0);
        glBindBuffer(GL_ARRAY_BUFFER, g.vbo);
        glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(verts.size() * sizeof(Vert)), verts.data(), GL_STREAM_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(Vert), reinterpret_cast<void*>(0));
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vert), reinterpret_cast<void*>(8));
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vert), reinterpret_cast<void*>(16));
        glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(verts.size()));
    }
    eglSwapBuffers(g.display, g.surface);
}

int DrawnInkWidth(const std::string& text, int style, float fontPx, const std::string& family) {
    if (text.empty() || fontPx <= 0.0f || g.fonts == nullptr) {
        return 0;
    }
    OH_Drawing_TypographyStyle* ty = OH_Drawing_CreateTypographyStyle();
    OH_Drawing_SetTypographyTextAlign(ty, TEXT_ALIGN_LEFT);
    OH_Drawing_TextStyle* ts = OH_Drawing_CreateTextStyle();
    OH_Drawing_SetTextStyleColor(ts, 0xFFFFFFFF);
    OH_Drawing_SetTextStyleFontSize(ts, fontPx);
    OH_Drawing_SetTextStyleFontWeight(ts, (style & 1) ? FONT_WEIGHT_700 : FONT_WEIGHT_400);
    if (!family.empty()) {
        const char* fams[] = {family.c_str()};
        OH_Drawing_SetTextStyleFontFamilies(ts, 1, fams);
    }
    OH_Drawing_TypographyCreate* handler = OH_Drawing_CreateTypographyHandler(ty, g.fonts);
    OH_Drawing_TypographyHandlerPushTextStyle(handler, ts);
    OH_Drawing_TypographyHandlerAddText(handler, text.c_str());
    OH_Drawing_Typography* typo = OH_Drawing_CreateTypography(handler);
    OH_Drawing_TypographyLayout(typo, 10000.0);
    const int pad = std::max(4, static_cast<int>(fontPx));
    const int scratchW = std::max(pad * 2, static_cast<int>(fontPx * 4.0f));
    const int scratchH = scratchW;
    OH_Drawing_Bitmap* scratch = OH_Drawing_BitmapCreate();
    OH_Drawing_BitmapFormat fmt{COLOR_FORMAT_RGBA_8888, ALPHA_FORMAT_PREMUL};
    OH_Drawing_BitmapBuild(scratch, static_cast<uint32_t>(scratchW), static_cast<uint32_t>(scratchH), &fmt);
    OH_Drawing_Canvas* canvas = OH_Drawing_CanvasCreate();
    OH_Drawing_CanvasBind(canvas, scratch);
    OH_Drawing_CanvasClear(canvas, 0);
    OH_Drawing_TypographyPaint(typo, canvas, static_cast<float>(pad), static_cast<float>(pad));
    int width = 0;
    void* pixels = OH_Drawing_BitmapGetPixels(scratch);
    if (pixels != nullptr) {
        const auto* src = static_cast<const uint8_t*>(pixels);
        int minX = scratchW;
        int maxX = -1;
        for (int i = 0; i < scratchW * scratchH; i++) {
            const uint8_t* px = src + static_cast<size_t>(i) * 4;
            const uint8_t cover = std::max(std::max(px[0], px[1]), std::max(px[2], px[3]));
            if (cover == 0) {
                continue;
            }
            const int x = i % scratchW;
            if (x < minX) {
                minX = x;
            }
            if (x > maxX) {
                maxX = x;
            }
        }
        if (maxX >= minX) {
            width = maxX - minX + 1;
        }
    }
    OH_Drawing_CanvasDestroy(canvas);
    OH_Drawing_BitmapDestroy(scratch);
    OH_Drawing_DestroyTypography(typo);
    OH_Drawing_DestroyTypographyHandler(handler);
    OH_Drawing_DestroyTextStyle(ts);
    OH_Drawing_DestroyTypographyStyle(ty);
    return width;
}

} // namespace

int AtlasMeasureCell(float fontPx, const std::string& family) {
    std::lock_guard<std::mutex> lock(g.mu);
    if (g.fonts == nullptr) {
        g.fonts = OH_Drawing_CreateSharedFontCollection();
    }
    const int ink = DrawnInkWidth("~", 0, fontPx, family);
    if (ink <= 0) {
        return 0;
    }
    return ink + CellGap(fontPx);
}

void AtlasSetSurface(void* window, uint64_t width, uint64_t height) {
    std::lock_guard<std::mutex> lock(g.mu);
    if (g.display == EGL_NO_DISPLAY) {
        g.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (g.display == EGL_NO_DISPLAY || !eglInitialize(g.display, nullptr, nullptr)) {
            LogEgl("init");
            return;
        }
        const EGLint attribs[] = {
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
            EGL_RED_SIZE, 8,
            EGL_GREEN_SIZE, 8,
            EGL_BLUE_SIZE, 8,
            EGL_ALPHA_SIZE, 8,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_NONE
        };
        EGLint count = 0;
        if (!eglChooseConfig(g.display, attribs, &g.config, 1, &count) || count < 1) {
            LogEgl("config");
            return;
        }
        const EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
        g.context = eglCreateContext(g.display, g.config, EGL_NO_CONTEXT, ctxAttribs);
        if (g.context == EGL_NO_CONTEXT) {
            LogEgl("context");
            return;
        }
    }
    if (g.surface != EGL_NO_SURFACE) {
        eglMakeCurrent(g.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(g.display, g.surface);
        g.surface = EGL_NO_SURFACE;
    }
    g.window = window;
    if (width > 0 && height > 0) {
        OH_NativeWindow_NativeWindowHandleOpt(static_cast<OHNativeWindow*>(window), SET_BUFFER_GEOMETRY,
            static_cast<int>(width), static_cast<int>(height));
    }
    g.surface = eglCreateWindowSurface(g.display, g.config,
        static_cast<EGLNativeWindowType>(reinterpret_cast<uintptr_t>(window)), nullptr);
    if (g.surface == EGL_NO_SURFACE) {
        LogEgl("surface");
        return;
    }
    g.surfaceW = static_cast<int>(width);
    g.surfaceH = static_cast<int>(height);
    if (eglMakeCurrent(g.display, g.surface, g.surface, g.context)) {
        EGLint ew = 0;
        EGLint eh = 0;
        eglQuerySurface(g.display, g.surface, EGL_WIDTH, &ew);
        eglQuerySurface(g.display, g.surface, EGL_HEIGHT, &eh);
        if (ew > 0 && eh > 0) {
            g.surfaceW = ew;
            g.surfaceH = eh;
        }
        eglMakeCurrent(g.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    g.dirty = g.hasFrame;
}

int AtlasSurfaceWidth() {
    std::lock_guard<std::mutex> lock(g.mu);
    return g.surfaceW;
}

int AtlasSurfaceHeight() {
    std::lock_guard<std::mutex> lock(g.mu);
    return g.surfaceH;
}

void AtlasClearSurface() {
    std::lock_guard<std::mutex> lock(g.mu);
    if (g.display != EGL_NO_DISPLAY) {
        eglMakeCurrent(g.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (g.surface != EGL_NO_SURFACE) {
            eglDestroySurface(g.display, g.surface);
            g.surface = EGL_NO_SURFACE;
        }
    }
    g.window = nullptr;
}

void AtlasSubmit(const AtlasFrame& frame) {
    std::lock_guard<std::mutex> lock(g.mu);
    g.pending = frame;
    g.hasFrame = true;
    g.dirty = true;
}

void AtlasDraw() {
    AtlasFrame frame;
    int surfaceW = 0;
    int surfaceH = 0;
    {
        std::lock_guard<std::mutex> lock(g.mu);
        if (!g.dirty || !g.hasFrame || g.surface == EGL_NO_SURFACE || g.context == EGL_NO_CONTEXT) {
            return;
        }
        frame = g.pending;
        surfaceW = g.surfaceW;
        surfaceH = g.surfaceH;
        g.dirty = false;
    }
    if (!eglMakeCurrent(g.display, g.surface, g.surface, g.context)) {
        LogEgl("makeCurrent");
        return;
    }
    DrawFrame(frame, surfaceW, surfaceH);
}
