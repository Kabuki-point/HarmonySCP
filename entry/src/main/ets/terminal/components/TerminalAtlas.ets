import { BufferLine, DEC_SYNC_OUTPUT, TerminalBuffer } from '../utils/TerminalBuffer';
import { TerminalTheme, resolveColorRgb, parseCssColor, isDefaultBg } from '../models/TerminalTheme';
import { SelectionManager } from '../utils/SelectionManager';
import {
  ATTR_UNDERLINE, ATTR_INVERSE,
  ATTR_DIM, ATTR_BLINK, ATTR_HIDDEN, ATTR_STRIKETHROUGH,
  CURSOR_UNDERLINE, CURSOR_BAR
} from '../models/TerminalState';
import { CURSOR_STYLE_BLOCK, CURSOR_STYLE_UNDERLINE, CURSOR_STYLE_BAR } from '../models/TerminalOptions';
import { LengthMetricsUnit } from '@kit.ArkUI';
import atlas from 'libtermatlas.so';

const BLINK_INTERVAL_MS: number = 500;
const SCROLLBAR_WIDTH_PX: number = 16;
const SCROLLBAR_MIN_THUMB_PX: number = 40;
const CELL_BYTES: number = 16;
const FLAG_GLYPH: number = 1;
const FLAG_EXTRA: number = 2;
const DIM_COVER: number = 0.6;

let atlasIdCounter: number = 0;

@Component
export struct TerminalAtlas {
  buffer: TerminalBuffer | null = null;
  selection: SelectionManager | null = null;
  @Prop @Watch('onRenderTickChange') renderTick: number = 0;
  @Prop @Watch('onFontSizeChange') fontSize: number = 14;
  @Prop @Watch('onFontFamilyChange') fontFamily: string = 'monospace';
  @Prop @Watch('onLineHeightChange') lineHeight: number = 1.6;
  @Prop @Watch('onThemeChange') theme: TerminalTheme = new TerminalTheme();
  @Prop @Watch('onCursorStyleChange') cursorStyle: string = CURSOR_STYLE_BLOCK;
  @Prop @Watch('onCursorBlinkChange') cursorBlink: boolean = true;
  @Prop @Watch('onScrollbarOpacityChange') scrollbarOpacity: number = 0;
  @Prop @Watch('onSelectionOpacityChange') selectionOpacity: number = 0;

  onResize: (cols: number, rows: number) => void = () => {};
  /** Fired after measure when cols/rows did not change (font settled, grid same). */
  onMeasureSettled: (cols: number, rows: number) => void = () => {};
  onCellMetrics: (cellWPx: number, cellHPx: number) => void = () => {};

  private xcId: string = 'termAtlas';
  private settings: RenderingContextSettings = new RenderingContextSettings(false);
  private measureCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private areaW: number = 0;
  private areaH: number = 0;
  private cellW: number = 0;
  private cellH: number = 0;
  private cols: number = 80;
  private rows: number = 24;
  private cursorOn: boolean = true;
  private textBlinkOn: boolean = true;
  private blinkTimer: number = -1;
  private measureReady: boolean = false;
  private reportedSize: boolean = false;
  private fontPx: number = 0;
  private fontKey: string = '';
  /** Last submitted cell grid; reused when only dirty rows need rebuild. */
  private cachedCells: ArrayBuffer | null = null;
  private cachedExtra: ArrayBuffer | null = null;
  private cachedCols: number = 0;
  private cachedRows: number = 0;

  aboutToAppear(): void {
    atlasIdCounter++;
    this.xcId = `termAtlas-${atlasIdCounter}`;
  }

  aboutToDisappear(): void {
    this.stopBlink();
  }

  private startBlink(): void {
    this.stopBlink();
    this.blinkTimer = setInterval(() => {
      if (this.cursorBlink) {
        this.cursorOn = !this.cursorOn;
      }
      this.textBlinkOn = !this.textBlinkOn;
      this.submit(false);
    }, BLINK_INTERVAL_MS) as number;
  }

  private stopBlink(): void {
    if (this.blinkTimer !== -1) {
      clearInterval(this.blinkTimer);
      this.blinkTimer = -1;
    }
  }

  private vpToPx(vp: number): number {
    return this.getUIContext().vp2px(vp);
  }

  private syncSize(widthVp: number, heightVp: number): boolean {
    const width = this.vpToPx(widthVp);
    const height = this.vpToPx(heightVp);
    if (width <= 0 || height <= 0) {
      return false;
    }
    const areaChanged = width !== this.areaW || height !== this.areaH;
    this.areaW = width;
    this.areaH = height;
    return this.applyDrawable() || areaChanged;
  }

  /** Columns follow the pixels that are actually drawn, not a larger layout box. */
  private applyDrawable(): boolean {
    let w = this.areaW;
    let h = this.areaH;
    const sw = atlas.surfaceWidth();
    const sh = atlas.surfaceHeight();
    if (sw > 0 && (w <= 0 || sw < w)) {
      w = sw;
    }
    if (sh > 0 && (h <= 0 || sh < h)) {
      h = sh;
    }
    if (w === this.canvasWidth && h === this.canvasHeight) {
      return false;
    }
    this.canvasWidth = w;
    this.canvasHeight = h;
    return true;
  }

  private ensureFontPx(): void {
    const px = this.getUIContext().vp2px(this.fontSize);
    const key = `${px}|${this.fontFamily}|${this.lineHeight}`;
    if (key === this.fontKey) {
      return;
    }
    this.fontKey = key;
    this.fontPx = px;
  }

  private measureCell(): void {
    if (!this.measureReady) {
      return;
    }
    this.ensureFontPx();
    // Cell width is the ink of "~". Wider glyphs are narrowed to this width.
    const drawn = atlas.measureCellWidth(this.fontPx, this.fontFamily);
    if (drawn <= 0) {
      return;
    }
    this.cellW = drawn;
    // Keep room for ascent+descent so Raster vertical center does not clip.
    const lh = this.lineHeight > 0 ? this.lineHeight : 1.6;
    this.cellH = Math.max(1, Math.ceil(this.fontPx * Math.max(lh, 1.4)));
    this.onCellMetrics(this.cellW, this.cellH);
    if (this.canvasWidth > 0 && this.canvasHeight > 0) {
      const newCols = Math.max(1, Math.floor(this.canvasWidth / this.cellW));
      const newRows = Math.max(1, Math.floor(this.canvasHeight / this.cellH));
      if (!this.reportedSize || newCols !== this.cols || newRows !== this.rows) {
        this.reportedSize = true;
        this.cols = newCols;
        this.rows = newRows;
        this.onResize(newCols, newRows);
      } else {
        this.onMeasureSettled(newCols, newRows);
      }
    }
    this.submit(true);
  }

  private blend(dst: number, src: number, alpha: number): number {
    const inv = 1 - alpha;
    const dr = (dst >> 16) & 0xFF;
    const dg = (dst >> 8) & 0xFF;
    const db = dst & 0xFF;
    const sr = (src >> 16) & 0xFF;
    const sg = (src >> 8) & 0xFF;
    const sb = src & 0xFF;
    const r = Math.round(sr * alpha + dr * inv);
    const g = Math.round(sg * alpha + dg * inv);
    const b = Math.round(sb * alpha + db * inv);
    return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
  }

  private paintColors(fgCode: number, bgCode: number, attrs: number, selected: boolean): number[] {
    const clear = parseCssColor(this.theme.background);
    const inverse = (attrs & ATTR_INVERSE) !== 0;
    let bg = inverse ? resolveColorRgb(fgCode, this.theme) : resolveColorRgb(bgCode, this.theme);
    if (!inverse && isDefaultBg(bgCode)) {
      bg = clear;
    }
    let fg = inverse ? resolveColorRgb(bgCode, this.theme) : resolveColorRgb(fgCode, this.theme);
    if (fg === bg) {
      fg = parseCssColor(this.theme.foreground);
    }
    if (selected && this.selectionOpacity > 0.01) {
      bg = this.blend(bg, parseCssColor(this.theme.selectionBackground), 0.35 * this.selectionOpacity);
    }
    if ((attrs & ATTR_DIM) !== 0) {
      fg = this.blend(bg, fg, DIM_COVER);
    }
    return [fg, bg];
  }

  private submit(force: boolean): void {
    if (!this.buffer || this.cellW <= 0 || this.cellH <= 0) {
      return;
    }
    if (this.applyDrawable()) {
      this.measureCell();
      return;
    }
    if (this.canvasWidth <= 0) {
      return;
    }
    if (!force && this.buffer.isDecMode(DEC_SYNC_OUTPUT)) {
      return;
    }
    const dirty = this.buffer.consumeDirty();
    const cols = this.buffer.getCols();
    const rows = this.buffer.getRows();
    const cacheOk = this.cachedCells !== null &&
      this.cachedCols === cols &&
      this.cachedRows === rows &&
      this.cachedCells.byteLength === rows * cols * CELL_BYTES;
    // Partial pack only when specific rows are dirty (selection drag / small edits).
    // Empty dirty (cursor blink) still needs a full rebuild for ATTR_BLINK cells.
    if (!dirty.all && cacheOk && dirty.rows.length > 0) {
      this.rebuildDirtyRows(dirty.rows, cols, rows);
    } else {
      this.rebuildAllRows(cols, rows);
    }
    this.emitFrame();
  }

  private rebuildAllRows(cols: number, rows: number): void {
    const cells = new ArrayBuffer(rows * cols * CELL_BYTES);
    const view = new DataView(cells);
    const extraBytes: number[] = [];
    for (let r = 0; r < rows; r++) {
      this.writeRow(view, r, cols, extraBytes);
    }
    this.cachedCells = cells;
    this.cachedExtra = this.extraToBuffer(extraBytes);
    this.cachedCols = cols;
    this.cachedRows = rows;
  }

  private rebuildDirtyRows(dirtyRows: number[], cols: number, rows: number): void {
    const cells = this.cachedCells as ArrayBuffer;
    const view = new DataView(cells);
    const extraBytes: number[] = [];
    if (this.cachedExtra !== null && this.cachedExtra.byteLength > 0) {
      const prev = new Uint8Array(this.cachedExtra);
      for (let i = 0; i < prev.length; i++) {
        extraBytes.push(prev[i]);
      }
    }
    for (let i = 0; i < dirtyRows.length; i++) {
      const r = dirtyRows[i];
      if (r < 0 || r >= rows) {
        continue;
      }
      this.writeRow(view, r, cols, extraBytes);
    }
    this.cachedExtra = this.extraToBuffer(extraBytes);
  }

  private writeRow(view: DataView, r: number, cols: number, extraBytes: number[]): void {
    if (!this.buffer) {
      return;
    }
    const line = this.buffer.getLine(r);
    const sel = this.rowSelection(r, cols);
    const clear = parseCssColor(this.theme.background);
    for (let c = 0; c < cols; c++) {
      const off = (r * cols + c) * CELL_BYTES;
      if (!line || c >= line.length) {
        view.setUint32(off, 0, true);
        view.setUint32(off + 4, 0, true);
        view.setUint32(off + 8, clear, true);
        view.setUint16(off + 12, 0, true);
        view.setUint8(off + 14, 0);
        view.setUint8(off + 15, 0);
        continue;
      }
      const width = line.getWidth(c);
      let attrs = line.getAttrFlags(c);
      const selected = c >= sel[0] && c < sel[1];
      const painted = this.paintColors(line.getFg(c), line.getBg(c), attrs, selected);
      const hidden = (attrs & ATTR_HIDDEN) !== 0;
      const blinkOff = (attrs & ATTR_BLINK) !== 0 && !this.textBlinkOn;
      let flags = 0;
      let cp = 0;
      if (width > 0 && !hidden && !blinkOff) {
        const packed = this.packGlyph(line, c, extraBytes);
        cp = packed[0];
        flags = packed[1];
      }
      if (hidden || blinkOff) {
        attrs = attrs & ~(ATTR_UNDERLINE | ATTR_STRIKETHROUGH);
      }
      view.setUint32(off, cp, true);
      view.setUint32(off + 4, painted[0], true);
      view.setUint32(off + 8, painted[1], true);
      view.setUint16(off + 12, attrs & 0xFFFF, true);
      view.setUint8(off + 14, width & 0xFF);
      view.setUint8(off + 15, flags);
    }
  }

  private extraToBuffer(extraBytes: number[]): ArrayBuffer {
    const extra = new ArrayBuffer(extraBytes.length);
    const extraView = new Uint8Array(extra);
    for (let i = 0; i < extraBytes.length; i++) {
      extraView[i] = extraBytes[i];
    }
    return extra;
  }

  private emitFrame(): void {
    if (!this.cachedCells || !this.buffer) {
      return;
    }
    const clear = parseCssColor(this.theme.background);
    const cursor = this.cursorPack();
    const bar = this.barPack();
    const extra = this.cachedExtra !== null ? this.cachedExtra : new ArrayBuffer(0);
    atlas.submitFrame(
      this.canvasWidth,
      this.canvasHeight,
      this.cachedCols,
      this.cachedRows,
      this.cellW,
      this.cellH,
      this.fontPx,
      this.fontFamily,
      clear,
      this.cachedCells,
      extra,
      cursor[0],
      cursor[1],
      cursor[2],
      cursor[3],
      cursor[4],
      bar[0],
      bar[1],
      bar[2],
      bar[3],
      bar[4],
      bar[5]
    );
  }

  private packGlyph(line: BufferLine, col: number, extraBytes: number[]): number[] {
    const ch = line.getChar(col);
    if (ch.length === 0 || ch === ' ') {
      return [0, 0];
    }
    const cp = ch.codePointAt(0);
    if (cp === undefined) {
      return [0, 0];
    }
    const units = cp > 0xFFFF ? 2 : 1;
    if (ch.length === units) {
      return [cp, FLAG_GLYPH];
    }
    const offset = extraBytes.length;
    const bytes = this.utf8(ch);
    extraBytes.push(bytes.length & 0xFF);
    extraBytes.push((bytes.length >> 8) & 0xFF);
    for (let i = 0; i < bytes.length; i++) {
      extraBytes.push(bytes[i]);
    }
    return [offset, FLAG_EXTRA];
  }

  private utf8(text: string): number[] {
    const out: number[] = [];
    let i = 0;
    while (i < text.length) {
      const cp = text.codePointAt(i);
      if (cp === undefined) {
        break;
      }
      if (cp < 0x80) {
        out.push(cp);
      } else if (cp < 0x800) {
        out.push(0xC0 | (cp >> 6));
        out.push(0x80 | (cp & 0x3F));
      } else if (cp < 0x10000) {
        out.push(0xE0 | (cp >> 12));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      } else {
        out.push(0xF0 | (cp >> 18));
        out.push(0x80 | ((cp >> 12) & 0x3F));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      }
      i += cp > 0xFFFF ? 2 : 1;
    }
    return out;
  }

  private rowSelection(viewportRow: number, cols: number): number[] {
    if (!this.buffer || !this.selection) {
      return [-1, -1];
    }
    const sel = this.selection.getNormalizedSelection();
    if (!sel) {
      return [-1, -1];
    }
    const absR = this.buffer.absRowFromViewport(viewportRow);
    if (absR < sel.start.row || absR > sel.end.row) {
      return [-1, -1];
    }
    const start = absR === sel.start.row ? sel.start.col : 0;
    const end = (absR === sel.end.row ? sel.end.col : cols - 1) + 1;
    return [start, end];
  }

  private cursorPack(): number[] {
    if (!this.buffer) {
      return [-1, -1, -1, 0, 0];
    }
    const cs = this.buffer.getState().cursorState;
    if (!cs.visible || !this.cursorOn) {
      return [-1, -1, -1, 0, 0];
    }
    const vpRow = this.buffer.getCursorViewportRow();
    if (vpRow < 0) {
      return [-1, -1, -1, 0, 0];
    }
    let col = cs.col;
    const line = this.buffer.getScreenLine(cs.row);
    if (line && col > 0 && col < line.length && line.getWidth(col - 1) === 2) {
      col = col - 1;
    }
    const cursorRgb = parseCssColor(this.theme.cursor);
    let accent = parseCssColor(this.theme.cursorAccent);
    if (accent === cursorRgb) {
      accent = parseCssColor(this.theme.foreground);
    }
    return [col, vpRow, this.cursorShapeValue(), cursorRgb, accent];
  }

  private cursorShapeValue(): number {
    const style = this.resolveCursorStyle();
    if (style === CURSOR_STYLE_UNDERLINE) {
      return 1;
    }
    if (style === CURSOR_STYLE_BAR) {
      return 2;
    }
    return 0;
  }

  private resolveCursorStyle(): string {
    if (this.cursorStyle === CURSOR_STYLE_UNDERLINE || this.cursorStyle === CURSOR_STYLE_BAR ||
      this.cursorStyle === CURSOR_STYLE_BLOCK) {
      return this.cursorStyle;
    }
    if (!this.buffer) {
      return CURSOR_STYLE_BLOCK;
    }
    const shape = this.buffer.getState().cursorState.shape;
    if (shape === CURSOR_UNDERLINE) {
      return CURSOR_STYLE_UNDERLINE;
    }
    if (shape === CURSOR_BAR) {
      return CURSOR_STYLE_BAR;
    }
    return CURSOR_STYLE_BLOCK;
  }

  private barPack(): number[] {
    if (!this.buffer || this.scrollbarOpacity <= 0.01) {
      return [0, 0, 0, 0, 0, 0];
    }
    const yBase = this.buffer.getYbase();
    if (yBase === 0) {
      return [0, 0, 0, 0, 0, 0];
    }
    const yDisplay = this.buffer.getYdisp();
    const totalLines = yBase + this.buffer.getRows();
    const thumbH = Math.max(SCROLLBAR_MIN_THUMB_PX, (this.buffer.getRows() / totalLines) * this.canvasHeight);
    const thumbY = (yDisplay / yBase) * (this.canvasHeight - thumbH);
    return [
      this.canvasWidth - SCROLLBAR_WIDTH_PX,
      thumbY,
      SCROLLBAR_WIDTH_PX,
      thumbH,
      0.1 * this.scrollbarOpacity,
      0.3 * this.scrollbarOpacity
    ];
  }

  onRenderTickChange(): void {
    this.submit(true);
  }

  onScrollbarOpacityChange(): void {
    this.submit(false);
  }

  onSelectionOpacityChange(): void {
    // Tint changed across whatever was selected; drop cache so colors rebuild.
    this.cachedCells = null;
    this.submit(true);
  }

  onFontSizeChange(): void {
    this.cachedCells = null;
    this.measureCell();
  }

  onFontFamilyChange(): void {
    this.cachedCells = null;
    this.measureCell();
  }

  onLineHeightChange(): void {
    this.cachedCells = null;
    this.measureCell();
  }

  onThemeChange(): void {
    this.cachedCells = null;
    this.submit(true);
  }

  onCursorStyleChange(): void {
    this.submit(true);
  }

  onCursorBlinkChange(): void {
    this.cursorOn = true;
    this.startBlink();
    this.submit(true);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({
        id: this.xcId,
        type: XComponentType.TEXTURE,
        libraryname: 'termatlas'
      })
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .backgroundColor(this.theme.background)
        .onAreaChange((_oldVal: Area, newVal: Area) => {
          const changed = this.syncSize(newVal.width as number, newVal.height as number);
          if (changed && this.measureReady) {
            this.measureCell();
          }
        });
      Canvas(this.measureCtx)
        .width(1)
        .height(1)
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.measureReady = true;
          this.measureCell();
          this.startBlink();
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background);
  }
}
