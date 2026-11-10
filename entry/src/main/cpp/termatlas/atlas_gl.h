#ifndef TERMARK_ATLAS_GL_H
#define TERMARK_ATLAS_GL_H

#include <cstddef>
#include <cstdint>
#include <string>

struct AtlasFrame {
    int width = 0;
    int height = 0;
    int cols = 0;
    int rows = 0;
    int cellW = 0;
    int cellH = 0;
    float fontPx = 0;
    std::string fontFamily;
    uint32_t clearRgb = 0;
    std::string cells;
    std::string extra;
    int cursorCol = -1;
    int cursorRow = -1;
    int cursorShape = -1;
    uint32_t cursorRgb = 0;
    uint32_t accentRgb = 0;
    float barX = 0;
    float barY = 0;
    float barW = 0;
    float barH = 0;
    float barTrackA = 0;
    float barThumbA = 0;
};

void AtlasSetSurface(void* window, uint64_t width, uint64_t height);
void AtlasClearSurface();
void AtlasSubmit(const AtlasFrame& frame);
void AtlasDraw();
/** Drawable size of the XComponent, in px. 0 before the surface exists. */
int AtlasSurfaceWidth();
int AtlasSurfaceHeight();
/** Fixed cell width: ink width of "~" at this font, in px. */
int AtlasMeasureCell(float fontPx, const std::string& family);

#endif
