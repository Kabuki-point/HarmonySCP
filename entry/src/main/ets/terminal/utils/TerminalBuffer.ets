import {
  TerminalState, CursorState,
  ATTR_BOLD, ATTR_DIM, ATTR_ITALIC, ATTR_UNDERLINE,
  ATTR_BLINK, ATTR_INVERSE, ATTR_HIDDEN, ATTR_STRIKETHROUGH,
  COLOR_DEFAULT_FG, COLOR_DEFAULT_BG,
  createDefaultTerminalState,
} from '../models/TerminalState';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MAX_SCROLLBACK: number = 10000;
const WRAP_LOG_DOMAIN: number = 0x0000;
const WRAP_LOG_TAG: string = 'TermArkWrap';
const TAB_STOP: number = 8;
const KITTY_STACK_CAP: number = 16;

export const DEC_APP_CURSOR: number = 1;
export const DEC_AUTOWRAP: number = 7;
export const DEC_CURSOR_BLINK: number = 12;
export const DEC_CURSOR_VISIBLE: number = 25;
export const DEC_MOUSE_BTN: number = 1000;
export const DEC_MOUSE_DRAG: number = 1002;
export const DEC_MOUSE_SGR: number = 1006;
export const DEC_ALT_SCREEN: number = 1049;
export const DEC_BRACKETED_PASTE: number = 2004;
export const DEC_SYNC_OUTPUT: number = 2026;

const KNOWN_DEC_MODES: number[] = [
  DEC_APP_CURSOR, DEC_AUTOWRAP, DEC_CURSOR_BLINK, DEC_CURSOR_VISIBLE,
  DEC_MOUSE_BTN, DEC_MOUSE_DRAG, DEC_MOUSE_SGR, DEC_ALT_SCREEN,
  DEC_BRACKETED_PASTE, DEC_SYNC_OUTPUT
];

const WIDTH_SHIFT: number = 0;
const WIDTH_MASK: number = 0x3;
const IS_COMBINED_SHIFT: number = 2;
const IS_COMBINED_MASK: number = 0x1 << IS_COMBINED_SHIFT;
const CODEPOINT_SHIFT: number = 3;
const CODEPOINT_MASK: number = 0x7FFFFF;
const FG_FLAGS_SHIFT: number = 24;
const BG_FLAGS_SHIFT: number = 24;
const ATTR_FLAGS_MASK: number = 0xFF;

export class BufferLine {
  content: Uint32Array;
  combinedIdx: number[] = [];
  combinedStr: string[] = [];
  isWrapped: boolean = false;
  /** Uncommitted prompt/input — excluded from reflow; remote may redraw after resize. */
  isEphemeral: boolean = false;

  constructor(cols: number) {
    this.content = new Uint32Array(cols * 3);
    const defFg = COLOR_DEFAULT_FG & 0xFFFFFF;
    const defBg = COLOR_DEFAULT_BG & 0xFFFFFF;
    for (let c = 0; c < cols; c++) {
      const idx = c * 3;
      this.content[idx + 1] = defFg;
      this.content[idx + 2] = defBg;
    }
  }

  get length(): number {
    return this.content.length / 3;
  }

  getChar(col: number): string {
    const idx = col * 3;
    const contentVal = this.content[idx];
    if ((contentVal & IS_COMBINED_MASK) !== 0) {
      for (let i = 0; i < this.combinedIdx.length; i++) {
        if (this.combinedIdx[i] === col) {
          return this.combinedStr[i];
        }
      }
      return ' ';
    }
    const cp = (contentVal >> CODEPOINT_SHIFT) & CODEPOINT_MASK;
    if (cp === 0) return ' ';
    return String.fromCodePoint(cp);
  }

  getFg(col: number): number {
    return this.content[col * 3 + 1] & 0xFFFFFF;
  }

  getBg(col: number): number {
    return this.content[col * 3 + 2] & 0xFFFFFF;
  }

  getAttrFlags(col: number): number {
    return (this.content[col * 3 + 1] >> FG_FLAGS_SHIFT) & ATTR_FLAGS_MASK;
  }

  getWidth(col: number): number {
    return (this.content[col * 3] >> WIDTH_SHIFT) & WIDTH_MASK;
  }

  setCell(col: number, ch: string, fg: number, bg: number, attrs: number, width: number): void {
    const idx = col * 3;
    let cp = 0;
    let isSurrogatePair = false;
    if (ch.length === 1) {
      cp = ch.charCodeAt(0);
    } else if (ch.length >= 2) {
      const high = ch.charCodeAt(0);
      const low = ch.charCodeAt(1);
      if (high >= 0xD800 && high <= 0xDBFF && low >= 0xDC00 && low <= 0xDFFF) {
        cp = ((high - 0xD800) << 10) + (low - 0xDC00) + 0x10000;
        isSurrogatePair = true;
      } else {
        cp = high;
      }
    }
    const needCombined = ch.length > 1 && !isSurrogatePair;
    this.content[idx] = ((cp & CODEPOINT_MASK) << CODEPOINT_SHIFT) |
                        ((width & WIDTH_MASK) << WIDTH_SHIFT) |
                        (needCombined ? IS_COMBINED_MASK : 0);
    if (needCombined) {
      let found = false;
      for (let i = 0; i < this.combinedIdx.length; i++) {
        if (this.combinedIdx[i] === col) {
          this.combinedStr[i] = ch;
          found = true;
          break;
        }
      }
      if (!found) {
        this.combinedIdx.push(col);
        this.combinedStr.push(ch);
      }
    }
    this.content[idx + 1] = ((attrs & ATTR_FLAGS_MASK) << FG_FLAGS_SHIFT) | (fg & 0xFFFFFF);
    this.content[idx + 2] = ((0) << BG_FLAGS_SHIFT) | (bg & 0xFFFFFF);
  }

  clearCell(col: number): void {
    this.blankCell(col, COLOR_DEFAULT_FG, COLOR_DEFAULT_BG, 0);
  }

  /** Space cell with an explicit rendition. Used by erase (BCE) so the current background fills the span. */
  blankCell(col: number, fg: number, bg: number, attrs: number): void {
    const idx = col * 3;
    this.content[idx] = ((0x20 & CODEPOINT_MASK) << CODEPOINT_SHIFT) | (1 << WIDTH_SHIFT);
    this.content[idx + 1] = ((attrs & ATTR_FLAGS_MASK) << FG_FLAGS_SHIFT) | (fg & 0xFFFFFF);
    this.content[idx + 2] = (bg & 0xFFFFFF);
    for (let i = this.combinedIdx.length - 1; i >= 0; i--) {
      if (this.combinedIdx[i] === col) {
        this.combinedIdx.splice(i, 1);
        this.combinedStr.splice(i, 1);
      }
    }
  }

  setWidePlaceholder(col: number): void {
    const idx = col * 3;
    this.content[idx] = (0 << CODEPOINT_SHIFT) | (0 << WIDTH_SHIFT);
    this.content[idx + 1] = ((0) << FG_FLAGS_SHIFT) | (COLOR_DEFAULT_FG & 0xFFFFFF);
    this.content[idx + 2] = ((0) << BG_FLAGS_SHIFT) | (COLOR_DEFAULT_BG & 0xFFFFFF);
  }

  resize(newCols: number): BufferLine {
    const newLine = new BufferLine(newCols);
    const copyLen = Math.min(this.content.length / 3, newCols);
    for (let c = 0; c < copyLen; c++) {
      newLine.content[c * 3] = this.content[c * 3];
      newLine.content[c * 3 + 1] = this.content[c * 3 + 1];
      newLine.content[c * 3 + 2] = this.content[c * 3 + 2];
    }
    for (let i = 0; i < this.combinedIdx.length; i++) {
      if (this.combinedIdx[i] < newCols) {
        newLine.combinedIdx.push(this.combinedIdx[i]);
        newLine.combinedStr.push(this.combinedStr[i]);
      }
    }
    newLine.isWrapped = this.isWrapped;
    newLine.isEphemeral = this.isEphemeral;
    return newLine;
  }
}

function makeLine(cols: number, ephemeral: boolean = false): BufferLine {
  const line = new BufferLine(cols);
  line.isEphemeral = ephemeral;
  return line;
}

class ReflowCell {
  ch: string = ' ';
  fg: number = COLOR_DEFAULT_FG & 0xFFFFFF;
  bg: number = COLOR_DEFAULT_BG & 0xFFFFFF;
  attrs: number = 0;
  width: number = 1;
}

/** One hard-\n-delimited content line (display soft-wraps this to cols). */
class LogicalLine {
  cells: ReflowCell[] = [];
}

function copyCursorState(src: CursorState): CursorState {
  return {
    col: src.col,
    row: src.row,
    visible: src.visible,
    blinking: src.blinking,
    shape: src.shape,
  };
}

export class DirtySnapshot {
  all: boolean = false;
  rows: number[] = [];
}

export class TerminalBuffer {
  private state: TerminalState;
  private lines: BufferLine[];
  private altLines: BufferLine[];
  private sb: BufferLine[] = [];
  private sbStart: number = 0;
  private sbCount: number = 0;
  private ydisp: number = 0;
  private savedCursor: CursorState;
  private savedAltCursor: CursorState;
  /** Main-screen companion to savedCursor (logicInput index). */
  private savedLogicInputCursor: number = 0;
  private currentFg: number = COLOR_DEFAULT_FG;
  private currentBg: number = COLOR_DEFAULT_BG;
  private currentAttrs: number = 0;
  /** Last graphic character, for ECMA-48 REP (CSI b). Empty when repeat is not valid. */
  private repeatCh: string = '';
  private repeatWidth: number = 0;
  private autoWrap: boolean = true;
  private decOn: number[] = [DEC_AUTOWRAP, DEC_CURSOR_BLINK, DEC_CURSOR_VISIBLE];
  private kittyFlagsMain: number = 0;
  private kittyFlagsAlt: number = 0;
  private kittyStackMain: number[] = [];
  private kittyStackAlt: number[] = [];
  private wrapPending: boolean = false;
  private dirtyFlags: Uint8Array = new Uint8Array(0);
  private dirtyAll: boolean = true;
  private _titleListeners: Array<(title: string) => void> = [];
  /** Committed main-screen content, split on hard \\n (not soft-wrap). */
  private logicHistory: LogicalLine[] = [];
  /** Current input zone (PS1 + typed text until hard \\n). Not part of history. */
  private logicInput: LogicalLine = new LogicalLine();
  /** Cell offset into logicInput for the logical cursor (main screen). */
  private logicInputCursor: number = 0;
  /**
   * Armed after SSH window-change while readline redisplays the edit line.
   * Hard LF in this window is display continuation, not Enter-to-commit.
   */
  private expectResizeRedraw: boolean = false;
  /** Deadline (ms) for the current resize-redraw burst; extended on activity. */
  private resizeRedrawUntil: number = 0;
  /**
   * After a resize-redraw LF: later CR must not jump to column 0, so the
   * remainder of the line appends after the prompt instead of overwriting it.
   */
  private resizeJoinContinuation: boolean = false;
  private static readonly RESIZE_REDRAW_IDLE_MS: number = 350;
  /** True after viewport-only wrap; full wrap still pending for off-screen history. */
  private viewportReflowIncomplete: boolean = false;
  /** Physical line count of logicHistory from the last refreshMainDisplay wrap. */
  private histPhysCount: number = 0;
  /** Cached wrap of logicHistory — avoid rewrapping all history on every print. */
  private histPhysCache: BufferLine[] = [];
  /** Physical row count of the current logicInput zone. */
  private inputPhysCount: number = 1;
  /**
   * Set by CSI cursor/erase on the main screen. Readline uses a following
   * hard LF as "cursor down one visual row" (clear leftover wrap), not Enter.
   */
  private mainCsiMotion: boolean = false;
  /**
   * Extra blank visual row after a display-only LF (or an EL that collapsed
   * a wrap row). Cursor sits on that row so leftover EL/CUU stay in-input.
   */
  private displayLfPending: boolean = false;
  /** True when the blank tail came from LF (commit on next graphic); false after EL collapse. */
  private displayLfFromFeed: boolean = false;

  constructor(cols: number, rows: number) {
    this.state = createDefaultTerminalState(cols, rows);
    this.lines = this.allocateScreen(cols, rows);
    this.altLines = this.allocateScreen(cols, rows);
    this.savedCursor = copyCursorState(this.state.cursorState);
    this.savedAltCursor = copyCursorState(this.state.cursorState);
  }

  getState(): TerminalState { return this.state; }
  /** Call before SSH window-change so redraw LF/CR are treated as line join. */
  markExpectResizeRedraw(): void {
    this.expectResizeRedraw = true;
    this.resizeJoinContinuation = false;
    this.extendResizeRedrawWindow();
  }

  /** @return true if still inside the post-window-change redraw window. */
  private noteResizeRedrawActivity(): boolean {
    if (!this.expectResizeRedraw) {
      return false;
    }
    if (Date.now() > this.resizeRedrawUntil) {
      this.clearResizeRedraw();
      return false;
    }
    this.extendResizeRedrawWindow();
    return true;
  }

  private extendResizeRedrawWindow(): void {
    this.resizeRedrawUntil = Date.now() + TerminalBuffer.RESIZE_REDRAW_IDLE_MS;
  }

  private clearResizeRedraw(): void {
    this.expectResizeRedraw = false;
    this.resizeRedrawUntil = 0;
    this.resizeJoinContinuation = false;
  }

  getRows(): number { return this.state.rows; }
  getCols(): number { return this.state.cols; }
  getYbase(): number { return this.sbCount; }
  getYdisp(): number { return this.ydisp; }

  setYdisp(val: number): void {
    const max = this.sbCount;
    const next = Math.max(0, Math.min(val, max));
    if (next === this.ydisp) {
      return;
    }
    this.ydisp = next;
    this.ensureViewportReflowed();
    this.markAllDirty();
  }

  /** Map viewport row (0..rows-1) to buffer line (scrollback + screen). */
  getLine(viewportRow: number): BufferLine | null {
    if (this.state.useAltScreen) {
      if (viewportRow >= 0 && viewportRow < this.altLines.length) {
        return this.altLines[viewportRow];
      }
      return null;
    }
    const absRow = this.ydisp + viewportRow;
    if (absRow < this.sbCount) {
      return this.sbAt(absRow);
    }
    const screenRow = absRow - this.sbCount;
    if (screenRow >= 0 && screenRow < this.lines.length) {
      return this.lines[screenRow];
    }
    return null;
  }

  /** Active-screen row for cursor (not viewport-adjusted). */
  getScreenLine(row: number): BufferLine | null {
    const screen = this.state.useAltScreen ? this.altLines : this.lines;
    if (row >= 0 && row < screen.length) {
      return screen[row];
    }
    return null;
  }

  /** Viewport row for cursor, or -1 if off-screen. */
  getCursorViewportRow(): number {
    if (this.state.useAltScreen) {
      return this.state.cursorState.row;
    }
    const absRow = this.sbCount + this.state.cursorState.row;
    const vp = absRow - this.ydisp;
    if (vp < 0 || vp >= this.state.rows) {
      return -1;
    }
    return vp;
  }

  getCursorAbsRow(): number {
    if (this.state.useAltScreen) {
      return this.state.cursorState.row;
    }
    return this.sbCount + this.state.cursorState.row;
  }

  absRowFromViewport(viewportRow: number): number {
    if (this.state.useAltScreen) {
      return viewportRow;
    }
    return this.ydisp + viewportRow;
  }

  viewportRowFromAbs(absRow: number): number {
    if (this.state.useAltScreen) {
      return absRow;
    }
    return absRow - this.ydisp;
  }

  getLineAbsolute(absRow: number): BufferLine | null {
    if (this.state.useAltScreen) {
      if (absRow >= 0 && absRow < this.altLines.length) {
        return this.altLines[absRow];
      }
      return null;
    }
    if (absRow < 0) {
      return null;
    }
    if (absRow < this.sbCount) {
      return this.sbAt(absRow);
    }
    const screenRow = absRow - this.sbCount;
    if (screenRow >= 0 && screenRow < this.lines.length) {
      return this.lines[screenRow];
    }
    return null;
  }

  consumeDirty(): DirtySnapshot {
    this.syncDirtySize();
    const snap = new DirtySnapshot();
    if (this.dirtyAll) {
      snap.all = true;
      this.dirtyAll = false;
      return snap;
    }
    const rows: number[] = [];
    for (let r = 0; r < this.dirtyFlags.length; r++) {
      if (this.dirtyFlags[r] !== 0) {
        rows.push(r);
        this.dirtyFlags[r] = 0;
      }
    }
    snap.rows = rows;
    return snap;
  }

  onTitleChange(cb: (title: string) => void): void {
    this._titleListeners.push(cb);
  }

  setTitle(title: string): void {
    this.state.title = title;
    for (const cb of this._titleListeners) cb(title);
  }

  resize(cols: number, rows: number, viewportOnly: boolean = false): void {
    const oldCols = this.state.cols;
    if (cols === oldCols && rows === this.state.rows) return;

    if (!this.state.useAltScreen) {
      // Main: logic is sole truth; physical sb/screen are always a projection.
      this.state.cols = cols;
      this.state.rows = rows;
      this.state.scrollTop = 0;
      this.state.scrollBottom = rows - 1;
      this.refreshMainDisplay(cols !== oldCols, viewportOnly);
      this.altLines = cols !== oldCols
        ? this.padLines(this.reflowLines(this.altLines, cols), cols, rows)
        : this.resizeScreen(this.altLines, cols, rows);
      this.markAllDirty();
      return;
    }

    this.lines = this.resizeScreen(this.lines, cols, rows);
    this.altLines = cols !== oldCols
      ? this.padLines(this.reflowLines(this.altLines, cols), cols, rows)
      : this.resizeScreen(this.altLines, cols, rows);

    this.state.cols = cols;
    this.state.rows = rows;
    this.state.scrollTop = 0;
    this.state.scrollBottom = rows - 1;
    this.clampCursor();
    this.markAllDirty();
  }

  /**
   * Project logicHistory + logicInput onto physical sb/screen.
   * clearInput drops the input zone (zoom when size actually changes).
   */
  rebuildFromLogic(clearInput: boolean = false): void {
    if (this.state.useAltScreen) {
      return;
    }
    this.refreshMainDisplay(clearInput, false);
  }

  /**
   * Rebuild main UI (physical) from logical history + input.
   * Physical sb/lines are a derived cache — never a second history source.
   * Full history wrap runs here (resize / clear) — not on every printChar.
   */
  private refreshMainDisplay(clearInput: boolean, viewportOnly: boolean): void {
    if (clearInput) {
      this.logicInput = new LogicalLine();
      this.logicInputCursor = 0;
    }
    const cols = this.state.cols;
    if (viewportOnly) {
      this.viewportReflowIncomplete = true;
      const hist = this.wrapLogicTail(this.logicHistory, cols, this.state.rows);
      this.histPhysCount = hist.length;
      this.applyMainPhysical(hist, this.wrapMainInputPart(cols));
      return;
    }
    this.viewportReflowIncomplete = false;
    this.histPhysCache = this.wrapLogicAll(this.logicHistory, cols);
    this.histPhysCount = this.histPhysCache.length;
    this.paintMainInput();
  }

  /** Wrap only the current input zone (ephemeral). */
  private wrapMainInputPart(cols: number): BufferLine[] {
    let inputPart = this.wrapCells(this.logicInput.cells, cols);
    for (let i = 0; i < inputPart.length; i++) {
      inputPart[i].isEphemeral = true;
      inputPart[i].isWrapped = i > 0;
    }
    if (inputPart.length === 0) {
      inputPart = [makeLine(cols, true)];
    } else {
      inputPart[0].isWrapped = false;
    }
    if (this.displayLfPending) {
      const extra = makeLine(cols, true);
      extra.isWrapped = true;
      inputPart.push(extra);
    }
    this.inputPhysCount = inputPart.length;
    return inputPart;
  }

  /**
   * Project cached history + current input onto sb/screen.
   * Does not rewrap logicHistory.
   */
  private paintMainInput(): void {
    this.histPhysCount = this.histPhysCache.length;
    this.applyMainPhysical(this.histPhysCache, this.wrapMainInputPart(this.state.cols));
  }

  private applyMainPhysical(hist: BufferLine[], inputPart: BufferLine[]): void {
    const cols = this.state.cols;
    const rows = this.state.rows;
    const total = hist.length + inputPart.length;
    if (total <= rows) {
      this.sbClear();
      const merged: BufferLine[] = [];
      for (let i = 0; i < hist.length; i++) {
        merged.push(hist[i]);
      }
      for (let i = 0; i < inputPart.length; i++) {
        merged.push(inputPart[i]);
      }
      this.lines = this.padLinesTop(merged, cols, rows);
    } else {
      const start = total - rows;
      this.syncScrollbackPrefix(hist, start, inputPart);
      const screenLines: BufferLine[] = [];
      if (start <= hist.length) {
        for (let i = start; i < hist.length; i++) {
          screenLines.push(hist[i]);
        }
        for (let i = 0; i < inputPart.length; i++) {
          screenLines.push(inputPart[i]);
        }
      } else {
        const inputStart = start - hist.length;
        for (let i = inputStart; i < inputPart.length; i++) {
          screenLines.push(inputPart[i]);
        }
      }
      this.lines = screenLines;
    }
    this.placeCursorFromLogicInput();
    this.ydisp = this.sbCount;
    this.markAllDirty();
  }

  /**
   * Keep sb as hist[0..start) (or hist+input head when input overflows).
   * Growing start by a few rows pushes instead of rebuilding the whole prefix.
   */
  private syncScrollbackPrefix(
    hist: BufferLine[],
    start: number,
    inputPart: BufferLine[]
  ): void {
    if (start <= hist.length) {
      if (this.sbStart === 0 && this.sbCount <= start && this.sbCount <= hist.length) {
        let same = true;
        for (let i = 0; i < this.sbCount; i++) {
          if (this.sb[i] !== hist[i]) {
            same = false;
            break;
          }
        }
        if (same) {
          for (let i = this.sbCount; i < start; i++) {
            this.sbPush(hist[i]);
          }
          return;
        }
      }
      const kept: BufferLine[] = [];
      for (let i = 0; i < start; i++) {
        kept.push(hist[i]);
      }
      this.sbReplace(kept);
      return;
    }
    const need = start - hist.length;
    const kept: BufferLine[] = [];
    for (let i = 0; i < hist.length; i++) {
      kept.push(hist[i]);
    }
    for (let i = 0; i < need; i++) {
      kept.push(inputPart[i]);
    }
    this.sbReplace(kept);
  }

  private sbPush(line: BufferLine): void {
    line.isEphemeral = false;
    if (this.sbCount < MAX_SCROLLBACK) {
      if (this.sbStart === 0 && this.sb.length === this.sbCount) {
        this.sb.push(line);
      } else {
        const idx = (this.sbStart + this.sbCount) % MAX_SCROLLBACK;
        if (idx < this.sb.length) {
          this.sb[idx] = line;
        } else {
          this.sb.push(line);
        }
      }
      this.sbCount++;
      return;
    }
    this.sb[this.sbStart] = line;
    this.sbStart = (this.sbStart + 1) % MAX_SCROLLBACK;
  }

  /** Commit current input as one hard line, then show a fresh empty input row. */
  private commitMainLineFeed(): void {
    const cols = this.state.cols;
    let wrapped = this.wrapCells(this.logicInput.cells, cols);
    if (wrapped.length === 0) {
      wrapped = [makeLine(cols)];
    }
    wrapped[0].isWrapped = false;
    for (let i = 0; i < wrapped.length; i++) {
      wrapped[i].isEphemeral = false;
      if (i > 0) {
        wrapped[i].isWrapped = true;
      }
      this.histPhysCache.push(wrapped[i]);
    }
    this.commitLogicInput();
    this.trimLogicHistory();
    this.paintMainInput();
  }

  private markMainCsiMotion(): void {
    this.mainCsiMotion = true;
  }

  private clearMainDisplayMotion(): void {
    this.mainCsiMotion = false;
    this.displayLfPending = false;
    this.displayLfFromFeed = false;
  }

  private trimLogicHistory(): void {
    let trimmed = false;
    while (this.logicHistory.length > MAX_SCROLLBACK) {
      this.logicHistory.shift();
      trimmed = true;
    }
    if (trimmed) {
      this.histPhysCache = this.wrapLogicAll(this.logicHistory, this.state.cols);
    }
  }

  ensureViewportReflowed(): void {
    if (this.state.useAltScreen || !this.viewportReflowIncomplete) {
      return;
    }
    if (this.ydisp > 0) {
      this.refreshMainDisplay(false, false);
    }
  }

  private wrapLogicAll(history: LogicalLine[], cols: number): BufferLine[] {
    const out: BufferLine[] = [];
    for (let i = 0; i < history.length; i++) {
      const wrapped = this.wrapCells(history[i].cells, cols);
      for (let j = 0; j < wrapped.length; j++) {
        out.push(wrapped[j]);
      }
    }
    return out;
  }

  private wrapLogicTail(history: LogicalLine[], cols: number, rows: number): BufferLine[] {
    const chunks: BufferLine[][] = [];
    let count = 0;
    const need = rows + 2;
    for (let i = history.length - 1; i >= 0 && count < need; i--) {
      const wrapped = this.wrapCells(history[i].cells, cols);
      chunks.push(wrapped);
      count += wrapped.length;
    }
    const out: BufferLine[] = [];
    for (let i = chunks.length - 1; i >= 0; i--) {
      const wrapped = chunks[i];
      for (let j = 0; j < wrapped.length; j++) {
        out.push(wrapped[j]);
      }
    }
    return out;
  }

  private commitLogicInput(): void {
    const committed = new LogicalLine();
    for (let i = 0; i < this.logicInput.cells.length; i++) {
      committed.cells.push(this.logicInput.cells[i]);
    }
    this.logicHistory.push(committed);
    this.logicInput = new LogicalLine();
    this.logicInputCursor = 0;
    this.clearMainDisplayMotion();
  }

  private appendLogicInputCell(
    ch: string,
    fg: number,
    bg: number,
    attrs: number,
    width: number
  ): void {
    const cell = new ReflowCell();
    cell.ch = ch;
    cell.fg = fg;
    cell.bg = bg;
    cell.attrs = attrs;
    cell.width = width >= 1 ? width : 1;
    // VT default is replace mode (not IRM insert).
    if (this.logicInputCursor < this.logicInput.cells.length) {
      this.logicInput.cells[this.logicInputCursor] = cell;
    } else {
      this.logicInput.cells.push(cell);
    }
    this.logicInputCursor++;
  }

  /**
   * Map a screen cell to an offset in logicInput (main screen, keepBottom layout).
   */
  private logicCursorFromScreen(row: number, col: number): number {
    const cols = this.state.cols;
    const rows = this.state.rows;
    const cells = this.logicInput.cells;
    const histPhys = this.histPhysCount;
    const inputPhys = Math.max(1, this.inputPhysCount);
    const total = histPhys + inputPhys;
    let absRow: number;
    if (total > rows) {
      absRow = (total - rows) + row;
    } else {
      absRow = row - (rows - total);
    }
    if (absRow < histPhys) {
      return 0;
    }
    const targetRow = absRow - histPhys;
    if (this.displayLfPending && targetRow >= inputPhys - 1) {
      return cells.length;
    }
    const targetCol = Math.max(0, Math.min(col, cols - 1));
    let r = 0;
    let c = 0;
    for (let i = 0; i < cells.length; i++) {
      const w = cells[i].width >= 1 ? cells[i].width : 1;
      if (w === 2 && cols < 2) {
        continue;
      }
      if (c + w > cols) {
        r++;
        c = 0;
      }
      if (r > targetRow) {
        return i;
      }
      if (r === targetRow && c >= targetCol) {
        return i;
      }
      c += w;
    }
    return cells.length;
  }

  private moveMainLogicCursorToScreen(row: number, col: number): void {
    const oldRow = this.state.cursorState.row;
    this.logicInputCursor = this.logicCursorFromScreen(row, col);
    this.placeCursorFromLogicInput();
    this.markDirty(oldRow);
    this.markDirty(this.state.cursorState.row);
  }

  private wrapLogCh(ch: string): string {
    if (ch === ' ') {
      return 'SP';
    }
    if (ch.length === 1) {
      const cp = ch.charCodeAt(0);
      if (cp >= 0x21 && cp <= 0x7e) {
        return ch;
      }
      return `U+${cp.toString(16)}`;
    }
    return 'U';
  }

  private wrapLogTail(): string {
    const cells = this.logicInput.cells;
    const n = Math.min(8, cells.length);
    let s = '';
    for (let i = cells.length - n; i < cells.length; i++) {
      s += this.wrapLogCh(cells[i].ch);
    }
    return s;
  }

  private wrapLog(op: string, extra: string): void {
    if (this.state.useAltScreen) {
      return;
    }
    hilog.info(WRAP_LOG_DOMAIN, WRAP_LOG_TAG,
      '%{public}s r=%{public}d c=%{public}d wp=%{public}d cur=%{public}d len=%{public}d cols=%{public}d phys=%{public}d d=%{public}d tail=%{public}s %{public}s',
      op,
      this.state.cursorState.row,
      this.state.cursorState.col,
      this.wrapPending ? 1 : 0,
      this.logicInputCursor,
      this.logicInput.cells.length,
      this.state.cols,
      this.inputPhysCount,
      this.displayLfPending ? 1 : 0,
      this.wrapLogTail(),
      extra);
  }

  private placeCursorFromLogicInput(): void {
    const cols = this.state.cols;
    const rows = this.state.rows;
    const cells = this.logicInput.cells;
    const histPhys = this.histPhysCount;
    const inputPhys = Math.max(1, this.inputPhysCount);
    if (this.displayLfPending) {
      const total = histPhys + inputPhys;
      let row: number;
      if (total > rows) {
        row = (histPhys + inputPhys - 1) - (total - rows);
      } else {
        row = (rows - total) + (histPhys + inputPhys - 1);
      }
      this.wrapPending = false;
      this.state.cursorState.row = Math.max(0, Math.min(row, rows - 1));
      this.state.cursorState.col = 0;
      return;
    }
    let absRow = histPhys;
    let col = 0;
    const limit = Math.min(this.logicInputCursor, cells.length);
    for (let i = 0; i < limit; i++) {
      const w = cells[i].width >= 1 ? cells[i].width : 1;
      if (w === 2 && cols < 2) {
        continue;
      }
      if (col + w > cols) {
        absRow++;
        col = 0;
      }
      col += w;
    }
    if (col >= cols && this.autoWrap) {
      if (limit < cells.length) {
        // The next cell already sits on the following row. Land on it.
        // Treating this as a pending wrap makes the next backspace's
        // erase-space start a new line.
        absRow++;
        col = 0;
        this.wrapPending = false;
      } else {
        // Cursor is past the last cell, which filled this row (xenl).
        this.wrapPending = true;
        col = cols - 1;
      }
    } else {
      this.wrapPending = false;
    }
    const total = histPhys + inputPhys;
    // Must match applyMainPhysical(keepBottom): overflow → clip top; short → padLinesTop.
    let row: number;
    if (total > rows) {
      row = absRow - (total - rows);
    } else {
      row = (rows - total) + absRow;
    }
    this.state.cursorState.row = Math.max(0, Math.min(row, rows - 1));
    this.state.cursorState.col = Math.max(0, Math.min(col, cols - 1));
  }

  private padLinesTop(lines: BufferLine[], cols: number, rows: number): BufferLine[] {
    const out: BufferLine[] = [];
    const n = Math.min(lines.length, rows);
    const pad = rows - n;
    for (let i = 0; i < pad; i++) {
      // Decorative pads are ephemeral so they never enter committed reflow history.
      out.push(makeLine(cols, true));
    }
    for (let i = 0; i < n; i++) {
      out.push(lines[i]);
    }
    return out;
  }

  setCursorPos(row: number, col: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('CUP', `to=${row},${col}`);
      this.moveMainLogicCursorToScreen(row, col);
      this.wrapLog('CUP.', '');
      return;
    }
    const oldRow = this.state.cursorState.row;
    this.wrapPending = false;
    this.state.cursorState.row = Math.max(0, Math.min(row, this.state.rows - 1));
    this.state.cursorState.col = Math.max(0, Math.min(col, this.state.cols - 1));
    this.markDirty(oldRow);
    this.markDirty(this.state.cursorState.row);
  }

  cursorUp(n: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('CUU', `n=${n}`);
      if (this.displayLfPending) {
        const col = this.state.cursorState.col;
        this.displayLfPending = false;
        this.displayLfFromFeed = false;
        this.paintMainInput();
        this.moveMainLogicCursorToScreen(this.state.cursorState.row, col);
        if (n > 1) {
          this.moveMainLogicCursorToScreen(this.state.cursorState.row - (n - 1), col);
        }
        this.wrapLog('CUU.tail', '');
        return;
      }
      this.moveMainLogicCursorToScreen(this.state.cursorState.row - n, this.state.cursorState.col);
      this.wrapLog('CUU.', '');
      return;
    }
    this.wrapPending = false;
    const oldRow = this.state.cursorState.row;
    const top = this.state.scrollTop;
    this.state.cursorState.row = Math.max(top, this.state.cursorState.row - n);
    this.markDirty(oldRow);
    this.markDirty(this.state.cursorState.row);
  }

  cursorDown(n: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('CUD', `n=${n}`);
      this.moveMainLogicCursorToScreen(this.state.cursorState.row + n, this.state.cursorState.col);
      this.wrapLog('CUD.', '');
      return;
    }
    this.wrapPending = false;
    const oldRow = this.state.cursorState.row;
    const bot = this.state.scrollBottom;
    this.state.cursorState.row = Math.min(bot, this.state.cursorState.row + n);
    this.markDirty(oldRow);
    this.markDirty(this.state.cursorState.row);
  }

  cursorForward(n: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('CUF', `n=${n}`);
      this.wrapPending = false;
      const oldRow = this.state.cursorState.row;
      const max = this.logicInput.cells.length;
      this.logicInputCursor = Math.min(max, this.logicInputCursor + n);
      this.placeCursorFromLogicInput();
      this.markDirty(oldRow);
      this.markDirty(this.state.cursorState.row);
      this.wrapLog('CUF.', '');
      return;
    }
    this.wrapPending = false;
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    this.markDirty(row);
    let col = this.state.cursorState.col;

    for (let i = 0; i < n; i++) {
      if (col >= this.state.cols) break;
      if (row >= 0 && row < screen.length) {
        const line = screen[row];
        const width = line.getWidth(col);
        col += (width === 2 ? 2 : 1);
      } else {
        col++;
      }
    }

    this.state.cursorState.col = Math.min(this.state.cols - 1, col);
  }

  cursorBack(n: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('BS', `n=${n}`);
      const oldRow = this.state.cursorState.row;
      for (let i = 0; i < n; i++) {
        if (this.wrapPending) {
          // xenl: cursor is past the last cell of this visual row. Land on it.
          this.wrapPending = false;
          if (this.logicInputCursor > 0) {
            this.logicInputCursor--;
          }
          this.placeCursorFromLogicInput();
          this.wrapLog('BS.xenl', `i=${i}`);
          continue;
        }
        if (this.logicInputCursor <= 0 || this.state.cursorState.col === 0) {
          // xterm: BS at column 0 does not reverse-wrap onto the previous row.
          this.wrapLog('BS.col0', `i=${i}`);
          break;
        }
        this.logicInputCursor--;
        this.placeCursorFromLogicInput();
      }
      this.markDirty(oldRow);
      this.markDirty(this.state.cursorState.row);
      this.wrapLog('BS.', '');
      return;
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    this.markDirty(row);
    let col = this.state.cursorState.col;

    for (let i = 0; i < n; i++) {
      // After writing the last column, wrapPending means the cursor is logically
      // past the last cell (xterm x === cols). One BS must land ON that cell so
      // the following EL (\x1b[K) only clears input, not the prompt behind it.
      if (this.wrapPending) {
        this.wrapPending = false;
        continue;
      }
      if (col <= 0) {
        break;
      }
      col--;
      if (row >= 0 && row < screen.length) {
        const line = screen[row];
        if (col > 0 && line.getWidth(col - 1) === 2) {
          col--;
        }
      }
    }

    this.state.cursorState.col = Math.max(0, col);
  }

  cursorNextLine(n: number): void {
    this.wrapPending = false;
    this.cursorDown(n);
    if (!this.state.useAltScreen) {
      this.moveMainLogicCursorToScreen(this.state.cursorState.row, 0);
      return;
    }
    this.state.cursorState.col = 0;
  }

  cursorPrevLine(n: number): void {
    this.wrapPending = false;
    this.cursorUp(n);
    if (!this.state.useAltScreen) {
      this.moveMainLogicCursorToScreen(this.state.cursorState.row, 0);
      return;
    }
    this.state.cursorState.col = 0;
  }

  cursorAbsoluteCol(col: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('CHA', `col=${col}`);
      this.moveMainLogicCursorToScreen(this.state.cursorState.row, col);
      this.wrapLog('CHA.', '');
      return;
    }
    this.wrapPending = false;
    this.state.cursorState.col = Math.max(0, Math.min(col, this.state.cols - 1));
  }

  cursorAbsoluteRow(row: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('VPA', `row=${row}`);
      this.moveMainLogicCursorToScreen(row, this.state.cursorState.col);
      this.wrapLog('VPA.', '');
      return;
    }
    this.wrapPending = false;
    this.state.cursorState.row = Math.max(0, Math.min(row, this.state.rows - 1));
  }

  tab(): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      const col = this.state.cursorState.col;
      const next = Math.min((Math.floor(col / TAB_STOP) + 1) * TAB_STOP, this.state.cols - 1);
      this.mainMoveToColOnRow(this.state.cursorState.row, next);
      return;
    }
    const col = this.state.cursorState.col;
    const next = (Math.floor(col / TAB_STOP) + 1) * TAB_STOP;
    this.state.cursorState.col = Math.min(next, this.state.cols - 1);
  }

  cursorBackTab(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      for (let i = 0; i < n; i++) {
        const col = this.state.cursorState.col;
        const prev = Math.max(0, (Math.ceil(col / TAB_STOP) - 1) * TAB_STOP);
        this.mainMoveToColOnRow(this.state.cursorState.row, prev);
      }
      return;
    }
    for (let i = 0; i < n; i++) {
      const col = this.state.cursorState.col;
      const prev = (Math.ceil(col / TAB_STOP) - 1) * TAB_STOP;
      this.state.cursorState.col = Math.max(0, prev);
    }
  }

  /**
   * Move main-screen logic cursor to (row, targetCol), padding with spaces
   * when the target sits past the end of current input on that row.
   */
  private mainMoveToColOnRow(row: number, targetCol: number): void {
    const cols = this.state.cols;
    const target = Math.max(0, Math.min(targetCol, cols - 1));
    for (let guard = 0; guard < cols + 2; guard++) {
      this.moveMainLogicCursorToScreen(row, target);
      if (this.state.cursorState.row === row && this.state.cursorState.col === target) {
        return;
      }
      // Target past end of content — extend input with spaces.
      this.logicInputCursor = this.logicInput.cells.length;
      this.appendLogicInputCell(' ', this.currentFg, this.currentBg, this.currentAttrs, 1);
      this.paintMainInput();
    }
    this.moveMainLogicCursorToScreen(row, target);
  }

  carriageReturn(): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      this.wrapLog('CR', '');
      this.noteResizeRedrawActivity();
      // Mid redraw-continuation: keep cursor at end so remaining input appends.
      if (this.resizeJoinContinuation) {
        this.wrapLog('CR.join', '');
        return;
      }
      // Column 0 of this visual row. A soft-wrapped prompt is several rows;
      // CR must not jump back to the start of the logical line and overwrite it.
      const row = this.state.cursorState.row;
      this.moveMainLogicCursorToScreen(row, 0);
      this.wrapLog('CR.', '');
      return;
    }
    this.state.cursorState.col = 0;
  }

  lineFeed(): void {
    this.lineFeedImpl(false);
  }

  private lineFeedImpl(fromAutoWrap: boolean): void {
    if (this.state.useAltScreen) {
      this.wrapPending = false;
      const row = this.state.cursorState.row;
      if (row === this.state.scrollBottom) {
        this.scrollUp(1);
      } else {
        this.state.cursorState.row = Math.min(this.state.rows - 1, row + 1);
      }
      return;
    }
    // Soft wrap is display-only — main screen never scrolls ephemeral into sb.
    if (fromAutoWrap) {
      this.wrapLog('LF.soft', '');
      return;
    }
    // Resize redraw LF: physical-row advance only — do not commit to history.
    // Park cursor at end and ignore following CRs so the rest of the line joins.
    if (this.noteResizeRedrawActivity()) {
      this.resizeJoinContinuation = true;
      this.logicInputCursor = this.logicInput.cells.length;
      this.placeCursorFromLogicInput();
      this.wrapLog('LF.resize', '');
      return;
    }
    // Readline wrap redisplay: CSI then LF means "down one visual row", not Enter.
    if (this.mainCsiMotion && this.logicInput.cells.length > 0) {
      this.displayLfPending = true;
      this.displayLfFromFeed = true;
      this.paintMainInput();
      this.wrapLog('LF.disp', '');
      return;
    }
    // Hard \\n from user Enter (or normal app output): commit into history.
    this.wrapLog('LF.commit', '');
    this.commitMainLineFeed();
    this.wrapLog('LF.', '');
  }

  index(): void { this.lineFeed(); }

  nextLine(): void {
    this.lineFeed();
    this.carriageReturn();
  }

  reverseIndex(): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      const row = this.state.cursorState.row;
      if (row <= this.state.scrollTop) {
        // Main screen has no physical scrollback push; ignore RI at top.
        return;
      }
      this.moveMainLogicCursorToScreen(row - 1, this.state.cursorState.col);
      return;
    }
    const row = this.state.cursorState.row;
    if (row === this.state.scrollTop) {
      this.scrollDown(1);
    } else {
      this.state.cursorState.row = Math.max(0, row - 1);
    }
  }

  /**
   * DEC auto-wrap (DECAWM): after writing into the last column, the next
   * graphic character wraps to the start of the following line.
   */
  printChar(ch: string, width: number): void {
    this.repeatCh = ch;
    this.repeatWidth = width >= 1 ? width : 1;
    if (!this.state.useAltScreen) {
      this.noteResizeRedrawActivity();
      if (this.displayLfPending) {
        const commitTail = this.displayLfFromFeed;
        this.displayLfPending = false;
        this.displayLfFromFeed = false;
        if (commitTail) {
          this.commitMainLineFeed();
        } else {
          this.paintMainInput();
        }
      }
      this.mainCsiMotion = false;
      const cellWidth = width >= 1 ? width : 1;
      const atEnd = this.logicInputCursor >= this.logicInput.cells.length;
      const c0 = this.state.cursorState.col;
      const wp0 = this.wrapPending ? 1 : 0;
      const nearEdge = c0 + cellWidth >= this.state.cols - 1;
      this.appendLogicInputCell(
        ch,
        this.currentFg,
        this.currentBg,
        this.currentAttrs,
        cellWidth
      );
      // Mid-line replace or soft-wrap: reflow input zone only (history stays cached).
      if (!atEnd || (this.wrapPending && this.autoWrap) ||
        this.state.cursorState.col + cellWidth > this.state.cols ||
        (cellWidth === 2 && this.state.cursorState.col >= this.state.cols - 1)) {
        this.paintMainInput();
        if (wp0 === 1 || this.wrapPending || !atEnd || ch === ' ' || nearEdge || this.inputPhysCount > 1) {
          this.wrapLog('PR.paint', `ch=${this.wrapLogCh(ch)} atEnd=${atEnd ? 1 : 0} c0=${c0} wp0=${wp0}`);
        }
        return;
      }
      // Hot path: append into the current cell without touching history wrap.
      const row = this.state.cursorState.row;
      const col = this.state.cursorState.col;
      const line = this.lines[row];
      if (!line || row < 0 || row >= this.lines.length) {
        this.paintMainInput();
        this.wrapLog('PR.miss', `ch=${this.wrapLogCh(ch)}`);
        return;
      }
      line.setCell(col, ch, this.currentFg, this.currentBg, this.currentAttrs, cellWidth);
      if (cellWidth === 2 && col + 1 < this.state.cols) {
        line.setWidePlaceholder(col + 1);
      }
      this.markDirty(row);
      const nextCol = col + cellWidth;
      if (nextCol >= this.state.cols) {
        this.state.cursorState.col = this.state.cols - 1;
        this.wrapPending = this.autoWrap;
      } else {
        this.state.cursorState.col = nextCol;
        this.wrapPending = false;
      }
      this.ydisp = this.sbCount;
      if (wp0 === 1 || this.wrapPending || !atEnd || ch === ' ' || nearEdge || this.inputPhysCount > 1) {
        this.wrapLog('PR.hot', `ch=${this.wrapLogCh(ch)} atEnd=${atEnd ? 1 : 0} c0=${c0} wp0=${wp0}`);
      }
      return;
    }

    const screen = this.currentScreen();
    const cellWidth = width >= 1 ? width : 1;
    let col = this.state.cursorState.col;
    let row = this.state.cursorState.row;

    if (this.wrapPending && this.autoWrap) {
      this.wrapPending = false;
      this.state.cursorState.col = 0;
      this.lineFeedImpl(true);
      col = this.state.cursorState.col;
      row = this.state.cursorState.row;
      if (row >= 0 && row < screen.length) {
        screen[row].isWrapped = true;
      }
    }

    if (cellWidth === 2 && col >= this.state.cols - 1) {
      if (this.autoWrap) {
        if (row >= 0 && row < screen.length && col < this.state.cols) {
          screen[row].setCell(col, ' ', this.currentFg, this.currentBg, this.currentAttrs, 1);
          this.markDirty(row);
        }
        this.state.cursorState.col = 0;
        this.lineFeedImpl(true);
        col = this.state.cursorState.col;
        row = this.state.cursorState.row;
        if (row >= 0 && row < screen.length) {
          screen[row].isWrapped = true;
        }
      } else if (this.state.cols >= 2) {
        col = this.state.cols - 2;
      }
    }

    if (row < 0 || row >= screen.length || col < 0 || col >= this.state.cols) {
      return;
    }

    screen[row].setCell(col, ch, this.currentFg, this.currentBg, this.currentAttrs, cellWidth);
    if (cellWidth === 2 && col + 1 < this.state.cols) {
      screen[row].setWidePlaceholder(col + 1);
    }
    this.markDirty(row);

    const nextCol = col + cellWidth;
    if (nextCol >= this.state.cols) {
      this.state.cursorState.col = this.state.cols - 1;
      this.wrapPending = this.autoWrap;
    } else {
      this.state.cursorState.col = nextCol;
      this.wrapPending = false;
    }
  }

  /** CSI b — repeat the preceding graphic character. ncurses uses this to fill htop header and selection bars. */
  repeatChar(count: number): void {
    if (this.repeatCh.length === 0 || count <= 0) {
      return;
    }
    const ch = this.repeatCh;
    const width = this.repeatWidth;
    const cap = this.state.cols * this.state.rows;
    const n = count > cap ? cap : count;
    for (let i = 0; i < n; i++) {
      this.printChar(ch, width);
    }
  }

  clearRepeat(): void {
    this.repeatCh = '';
  }

  eraseDisplay(mode: number): void {
    if (!this.state.useAltScreen && (mode === 2 || mode === 3)) {
      this.logicHistory = [];
      this.histPhysCache = [];
      this.histPhysCount = 0;
      this.logicInput = new LogicalLine();
      this.logicInputCursor = 0;
      this.paintMainInput();
      return;
    }
    if (!this.state.useAltScreen) {
      // ED 0/1 on main: operate on the input zone (shell clear-to-end / to-start).
      if (mode === 0) {
        if (this.logicInputCursor < this.logicInput.cells.length) {
          this.logicInput.cells.splice(this.logicInputCursor);
        }
        this.paintMainInput();
        return;
      }
      if (mode === 1) {
        if (this.logicInputCursor > 0) {
          this.logicInput.cells.splice(0, this.logicInputCursor);
          this.logicInputCursor = 0;
        }
        this.paintMainInput();
        return;
      }
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const col = this.eraseCol();
    const rows = this.state.rows;
    const cols = this.state.cols;

    switch (mode) {
      case 0:
        this.eraseCells(screen, row, col, cols);
        for (let r = row + 1; r < rows; r++) {
          screen[r] = makeLine(cols);
          this.markDirty(r);
        }
        break;
      case 1:
        for (let r = 0; r < row; r++) {
          screen[r] = makeLine(cols);
          this.markDirty(r);
        }
        this.eraseCells(screen, row, 0, Math.min(col + 1, cols));
        break;
      case 2:
      case 3:
        for (let r = 0; r < rows; r++) {
          screen[r] = makeLine(cols);
          this.markDirty(r);
        }
        break;
    }
  }

  eraseLine(mode: number): void {
    if (!this.state.useAltScreen) {
      this.markMainCsiMotion();
      this.wrapLog('EL', `mode=${mode}`);
      // Fresh redraw pass starts with erase — cancel join-continuation.
      if (this.noteResizeRedrawActivity() || this.resizeJoinContinuation) {
        this.resizeJoinContinuation = false;
      }
      if (mode === 2) {
        this.logicInput = new LogicalLine();
        this.logicInputCursor = 0;
        this.clearMainDisplayMotion();
        this.paintMainInput();
        this.wrapLog('EL.2', '');
        return;
      }
      if (mode === 0) {
        if (this.displayLfPending) {
          this.paintMainInput();
          this.wrapLog('EL.0.tail', '');
          return;
        }
        const physBefore = this.inputPhysCount;
        if (this.logicInputCursor < this.logicInput.cells.length) {
          this.logicInput.cells.splice(this.logicInputCursor);
        }
        this.paintMainInput();
        if (physBefore > this.inputPhysCount && this.logicInput.cells.length > 0) {
          this.displayLfPending = true;
          this.displayLfFromFeed = false;
          this.paintMainInput();
        }
        this.wrapLog('EL.0', '');
        return;
      }
      if (mode === 1) {
        if (this.logicInputCursor > 0) {
          this.logicInput.cells.splice(0, this.logicInputCursor);
          this.logicInputCursor = 0;
        }
        this.paintMainInput();
        this.wrapLog('EL.1', '');
        return;
      }
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const col = this.eraseCol();
    const cols = this.state.cols;
    switch (mode) {
      case 0: this.eraseCells(screen, row, col, cols); break;
      case 1: this.eraseCells(screen, row, 0, Math.min(col + 1, cols)); break;
      case 2: this.eraseCells(screen, row, 0, cols); break;
    }
    this.markDirty(row);
  }

  /**
   * Erase column with the pending-wrap state applied: after the last column is
   * written the cursor logically sits at `cols`, so "erase to end of line"
   * must not eat that last cell.
   */
  private eraseCol(): number {
    return this.wrapPending ? this.state.cols : this.state.cursorState.col;
  }

  eraseChars(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      const space = new ReflowCell();
      space.ch = ' ';
      space.fg = this.currentFg;
      space.bg = this.currentBg;
      space.attrs = this.currentAttrs;
      space.width = 1;
      for (let i = 0; i < n; i++) {
        const idx = this.logicInputCursor + i;
        if (idx >= this.logicInput.cells.length) {
          break;
        }
        this.logicInput.cells[idx] = space;
      }
      this.paintMainInput();
      return;
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const col = this.state.cursorState.col;
    this.eraseCells(screen, row, col, Math.min(col + n, this.state.cols));
    this.markDirty(row);
  }

  insertChars(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      for (let i = 0; i < n; i++) {
        const space = new ReflowCell();
        space.ch = ' ';
        space.fg = this.currentFg;
        space.bg = this.currentBg;
        space.attrs = this.currentAttrs;
        space.width = 1;
        this.logicInput.cells.splice(this.logicInputCursor, 0, space);
      }
      this.paintMainInput();
      return;
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const col = this.state.cursorState.col;
    const cols = this.state.cols;
    const line = screen[row];
    if (!line) return;
    const oldLine = line.resize(cols);
    for (let c = 0; c < cols; c++) {
      line.clearCell(c);
    }
    for (let c = 0; c < col; c++) {
      line.content[c * 3] = oldLine.content[c * 3];
      line.content[c * 3 + 1] = oldLine.content[c * 3 + 1];
      line.content[c * 3 + 2] = oldLine.content[c * 3 + 2];
    }
    for (let c = col + n; c < cols; c++) {
      const src = c - n;
      if (src >= col && src < cols) {
        line.content[c * 3] = oldLine.content[src * 3];
        line.content[c * 3 + 1] = oldLine.content[src * 3 + 1];
        line.content[c * 3 + 2] = oldLine.content[src * 3 + 2];
      }
    }
    for (let c = col; c < Math.min(col + n, cols); c++) {
      line.clearCell(c);
    }
    this.markDirty(row);
  }

  deleteChars(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      const max = this.logicInput.cells.length - this.logicInputCursor;
      const count = Math.min(n, Math.max(0, max));
      if (count > 0) {
        this.logicInput.cells.splice(this.logicInputCursor, count);
      }
      this.paintMainInput();
      return;
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const col = this.state.cursorState.col;
    const cols = this.state.cols;
    const line = screen[row];
    if (!line) return;
    const oldLine = line.resize(cols);
    for (let c = 0; c < cols; c++) {
      line.clearCell(c);
    }
    for (let c = 0; c < col; c++) {
      line.content[c * 3] = oldLine.content[c * 3];
      line.content[c * 3 + 1] = oldLine.content[c * 3 + 1];
      line.content[c * 3 + 2] = oldLine.content[c * 3 + 2];
    }
    for (let c = col; c < cols - n; c++) {
      const src = c + n;
      line.content[c * 3] = oldLine.content[src * 3];
      line.content[c * 3 + 1] = oldLine.content[src * 3 + 1];
      line.content[c * 3 + 2] = oldLine.content[src * 3 + 2];
    }
    for (let c = cols - n; c < cols; c++) {
      line.clearCell(c);
    }
    this.markDirty(row);
  }

  insertLines(n: number): void {
    this.wrapPending = false;
    // Main screen is logic-backed; IL would desync physical lines from logicHistory.
    if (!this.state.useAltScreen) {
      return;
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const bot = this.state.scrollBottom;
    const cols = this.state.cols;
    for (let i = 0; i < n; i++) {
      if (row <= bot && bot < screen.length) {
        screen.splice(bot, 1);
        screen.splice(row, 0, makeLine(cols));
      }
    }
    this.markRangeDirty(row, bot);
  }

  deleteLines(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      return;
    }
    const screen = this.currentScreen();
    const row = this.state.cursorState.row;
    const bot = this.state.scrollBottom;
    const cols = this.state.cols;
    for (let i = 0; i < n; i++) {
      if (row <= bot && row < screen.length) {
        screen.splice(row, 1);
        screen.splice(bot, 0, makeLine(cols));
      }
    }
    this.markRangeDirty(row, bot);
  }

  scrollUp(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      return;
    }
    const screen = this.currentScreen();
    const top = this.state.scrollTop;
    const bot = this.state.scrollBottom;
    const cols = this.state.cols;
    for (let i = 0; i < n; i++) {
      if (top < screen.length) {
        screen.splice(top, 1);
        if (bot <= screen.length) {
          screen.splice(bot, 0, makeLine(cols));
        }
      }
    }
    this.markRangeDirty(top, bot);
  }

  scrollDown(n: number): void {
    this.wrapPending = false;
    if (!this.state.useAltScreen) {
      return;
    }
    const screen = this.currentScreen();
    const top = this.state.scrollTop;
    const bot = this.state.scrollBottom;
    const cols = this.state.cols;
    for (let i = 0; i < n; i++) {
      if (bot < screen.length) {
        screen.splice(bot, 1);
      }
      screen.splice(top, 0, makeLine(cols));
    }
    this.markRangeDirty(top, bot);
  }

  setScrollRegion(top: number, bottom: number): void {
    this.state.scrollTop = Math.max(0, Math.min(top, this.state.rows - 1));
    this.state.scrollBottom = Math.max(0, Math.min(bottom, this.state.rows - 1));
    if (!this.state.useAltScreen) {
      this.moveMainLogicCursorToScreen(0, 0);
      return;
    }
    this.state.cursorState.row = 0;
    this.state.cursorState.col = 0;
  }

  resetAttributes(): void {
    this.currentFg = COLOR_DEFAULT_FG;
    this.currentBg = COLOR_DEFAULT_BG;
    this.currentAttrs = 0;
  }

  setAttribute(name: string, value: boolean): void {
    const flag = this.attrFlag(name);
    if (flag === 0) return;
    if (value) this.currentAttrs |= flag;
    else this.currentAttrs &= ~flag;
  }

  setFgColor(color: number): void { this.currentFg = color; }
  setBgColor(color: number): void { this.currentBg = color; }

  saveCursor(): void {
    if (this.state.useAltScreen) {
      this.savedAltCursor = copyCursorState(this.state.cursorState);
    } else {
      this.savedCursor = copyCursorState(this.state.cursorState);
      this.savedLogicInputCursor = this.logicInputCursor;
    }
  }

  restoreCursor(): void {
    if (this.state.useAltScreen) {
      const src = this.savedAltCursor;
      this.state.cursorState.col = src.col;
      this.state.cursorState.row = src.row;
      this.state.cursorState.visible = src.visible;
      this.state.cursorState.blinking = src.blinking;
      this.state.cursorState.shape = src.shape;
      this.clampCursor();
      return;
    }
    const src = this.savedCursor;
    this.state.cursorState.visible = src.visible;
    this.state.cursorState.blinking = src.blinking;
    this.state.cursorState.shape = src.shape;
    this.logicInputCursor = Math.max(0, Math.min(this.savedLogicInputCursor, this.logicInput.cells.length));
    this.placeCursorFromLogicInput();
  }

  useAltScreen(enable: boolean): void {
    if (enable === this.state.useAltScreen) return;
    if (enable) {
      this.saveCursor();
      this.state.useAltScreen = true;
      this.wrapPending = false;
      this.eraseDisplay(2);
    } else {
      this.state.useAltScreen = false;
      this.restoreCursor();
    }
    this.storeDec(DEC_ALT_SCREEN, enable);
    this.markAllDirty();
  }

  setAutoWrap(on: boolean): void {
    this.autoWrap = on;
    this.storeDec(DEC_AUTOWRAP, on);
    if (!on) {
      this.wrapPending = false;
    }
  }
  setCursorVisible(visible: boolean): void {
    this.state.cursorState.visible = visible;
    this.storeDec(DEC_CURSOR_VISIBLE, visible);
  }
  setCursorBlinking(blinking: boolean): void {
    this.state.cursorState.blinking = blinking;
    this.storeDec(DEC_CURSOR_BLINK, blinking);
  }

  isDecMode(id: number): boolean {
    for (let i = 0; i < this.decOn.length; i++) {
      if (this.decOn[i] === id) {
        return true;
      }
    }
    return false;
  }

  /** DECRQM: 0 unknown, 1 set, 2 reset. */
  queryDecMode(id: number): number {
    if (!this.knownDec(id)) {
      return 0;
    }
    return this.isDecMode(id) ? 1 : 2;
  }

  setDecMode(id: number, on: boolean): void {
    if (!this.knownDec(id)) {
      return;
    }
    if (id === DEC_AUTOWRAP) {
      this.setAutoWrap(on);
      return;
    }
    if (id === DEC_CURSOR_BLINK) {
      this.setCursorBlinking(on);
      return;
    }
    if (id === DEC_CURSOR_VISIBLE) {
      this.setCursorVisible(on);
      return;
    }
    if (id === DEC_ALT_SCREEN) {
      this.useAltScreen(on);
      return;
    }
    this.storeDec(id, on);
  }

  mouseReports(): boolean {
    return this.isDecMode(DEC_MOUSE_SGR) &&
      (this.isDecMode(DEC_MOUSE_BTN) || this.isDecMode(DEC_MOUSE_DRAG));
  }

  mouseDrag(): boolean {
    return this.mouseReports() && this.isDecMode(DEC_MOUSE_DRAG);
  }

  getKittyFlags(): number {
    return this.state.useAltScreen ? this.kittyFlagsAlt : this.kittyFlagsMain;
  }

  setKittyFlags(flags: number, mode: number): void {
    let next = this.getKittyFlags();
    if (mode === 2) {
      next = next | flags;
    } else if (mode === 3) {
      next = next & (~flags);
    } else {
      next = flags;
    }
    this.setActiveKittyFlags(next);
  }

  pushKittyFlags(flags: number): void {
    const stack = this.activeKittyStack();
    if (stack.length >= KITTY_STACK_CAP) {
      stack.shift();
    }
    stack.push(this.getKittyFlags());
    this.setActiveKittyFlags(flags);
  }

  popKittyFlags(count: number): void {
    const n = count < 1 ? 1 : count;
    const stack = this.activeKittyStack();
    if (n > stack.length) {
      while (stack.length > 0) {
        stack.pop();
      }
      this.setActiveKittyFlags(0);
      return;
    }
    let next = 0;
    for (let i = 0; i < n; i++) {
      if (stack.length === 0) {
        next = 0;
        break;
      }
      next = stack.pop() as number;
    }
    this.setActiveKittyFlags(next);
  }
  setCursorShape(shape: number): void { this.state.cursorState.shape = shape; }
  reset(): void {
    this.state = createDefaultTerminalState(this.state.cols, this.state.rows);
    this.lines = this.allocateScreen(this.state.cols, this.state.rows);
    this.altLines = this.allocateScreen(this.state.cols, this.state.rows);
    this.sbClear();
    this.logicHistory = [];
    this.logicInput = new LogicalLine();
    this.logicInputCursor = 0;
    this.savedLogicInputCursor = 0;
    this.histPhysCache = [];
    this.histPhysCount = 0;
    this.inputPhysCount = 1;
    this.viewportReflowIncomplete = false;
    this.mainCsiMotion = false;
    this.displayLfPending = false;
    this.displayLfFromFeed = false;
    this.expectResizeRedraw = false;
    this.resizeRedrawUntil = 0;
    this.resizeJoinContinuation = false;
    this.ydisp = 0;
    this.resetAttributes();
    this.autoWrap = true;
    this.wrapPending = false;
    this.decOn = [DEC_AUTOWRAP, DEC_CURSOR_BLINK, DEC_CURSOR_VISIBLE];
    this.kittyFlagsMain = 0;
    this.kittyFlagsAlt = 0;
    this.kittyStackMain = [];
    this.kittyStackAlt = [];
    this.markAllDirty();
  }

  private knownDec(id: number): boolean {
    for (let i = 0; i < KNOWN_DEC_MODES.length; i++) {
      if (KNOWN_DEC_MODES[i] === id) {
        return true;
      }
    }
    return false;
  }

  private storeDec(id: number, on: boolean): void {
    let idx = -1;
    for (let i = 0; i < this.decOn.length; i++) {
      if (this.decOn[i] === id) {
        idx = i;
        break;
      }
    }
    if (on) {
      if (idx < 0) {
        this.decOn.push(id);
      }
      return;
    }
    if (idx >= 0) {
      this.decOn.splice(idx, 1);
    }
  }

  private setActiveKittyFlags(flags: number): void {
    if (this.state.useAltScreen) {
      this.kittyFlagsAlt = flags;
    } else {
      this.kittyFlagsMain = flags;
    }
  }

  private activeKittyStack(): number[] {
    return this.state.useAltScreen ? this.kittyStackAlt : this.kittyStackMain;
  }

  private currentScreen(): BufferLine[] {
    return this.state.useAltScreen ? this.altLines : this.lines;
  }

  private allocateScreen(cols: number, rows: number): BufferLine[] {
    const screen: BufferLine[] = [];
    for (let r = 0; r < rows; r++) screen.push(makeLine(cols));
    return screen;
  }

  private resizeScreen(screen: BufferLine[], cols: number, rows: number): BufferLine[] {
    const newScreen: BufferLine[] = [];
    for (let r = 0; r < rows; r++) {
      if (r < screen.length) {
        newScreen.push(screen[r].resize(cols));
      } else {
        newScreen.push(makeLine(cols));
      }
    }
    return newScreen;
  }

  private padLines(lines: BufferLine[], cols: number, rows: number): BufferLine[] {
    const out: BufferLine[] = [];
    const n = Math.min(lines.length, rows);
    for (let i = 0; i < n; i++) {
      out.push(lines[i]);
    }
    while (out.length < rows) {
      out.push(makeLine(cols));
    }
    return out;
  }

  /** Join hard lines / soft-wraps, then wrap to newCols (edge auto-wrap on resize). */
  private reflowLines(source: BufferLine[], newCols: number): BufferLine[] {
    const out: BufferLine[] = [];
    let pending: ReflowCell[] = [];
    let started: boolean = false;
    let groupEphemeral: boolean = false;

    const flush = (): void => {
      const wrapped = this.wrapCells(pending, newCols);
      for (let i = 0; i < wrapped.length; i++) {
        wrapped[i].isEphemeral = groupEphemeral;
        out.push(wrapped[i]);
      }
      pending = [];
      started = false;
      groupEphemeral = false;
    };

    for (let r = 0; r < source.length; r++) {
      const line = source[r];
      if (!line.isWrapped) {
        if (started) {
          flush();
        }
        started = true;
        groupEphemeral = line.isEphemeral;
      } else if (!started) {
        // Scrollback may start mid soft-wrap after the head was discarded.
        started = true;
        groupEphemeral = line.isEphemeral;
      } else if (line.isEphemeral) {
        groupEphemeral = true;
      }
      const nextIsWrapped = r + 1 < source.length && source[r + 1].isWrapped;
      this.appendLineCells(line, pending, nextIsWrapped);
    }
    if (started || pending.length > 0) {
      flush();
    }
    return out;
  }

  private appendLineCells(
    line: BufferLine,
    pending: ReflowCell[],
    preserveFullWidth: boolean = false
  ): void {
    const last = preserveFullWidth ? line.length - 1 : this.lastSignificantCol(line);
    if (last < 0) {
      return;
    }
    let i = 0;
    while (i <= last) {
      const w = line.getWidth(i);
      if (w === 2) {
        const cell = new ReflowCell();
        cell.ch = line.getChar(i);
        cell.fg = line.getFg(i);
        cell.bg = line.getBg(i);
        cell.attrs = line.getAttrFlags(i);
        cell.width = 2;
        pending.push(cell);
        i += 2;
      } else if (w === 1) {
        const cell = new ReflowCell();
        cell.ch = line.getChar(i);
        cell.fg = line.getFg(i);
        cell.bg = line.getBg(i);
        cell.attrs = line.getAttrFlags(i);
        cell.width = 1;
        pending.push(cell);
        i += 1;
      } else {
        const cell = new ReflowCell();
        cell.ch = ' ';
        cell.fg = COLOR_DEFAULT_FG & 0xFFFFFF;
        cell.bg = COLOR_DEFAULT_BG & 0xFFFFFF;
        cell.attrs = 0;
        cell.width = 1;
        pending.push(cell);
        i += 1;
      }
    }
  }

  private lastSignificantCol(line: BufferLine): number {
    for (let i = line.length - 1; i >= 0; i--) {
      const cp = (line.content[i * 3] >> CODEPOINT_SHIFT) & CODEPOINT_MASK;
      const w = line.getWidth(i);
      if (cp !== 0 || w === 2) {
        return i;
      }
    }
    return -1;
  }

  private wrapCells(cells: ReflowCell[], newCols: number): BufferLine[] {
    if (cells.length === 0) {
      return [makeLine(newCols)];
    }
    const out: BufferLine[] = [];
    let cur = makeLine(newCols);
    let col = 0;

    for (let i = 0; i < cells.length; i++) {
      const cell = cells[i];
      const w = cell.width >= 1 ? cell.width : 1;
      if (w === 2 && newCols < 2) {
        continue;
      }
      if (col + w > newCols) {
        out.push(cur);
        cur = makeLine(newCols);
        cur.isWrapped = true;
        col = 0;
      }
      cur.setCell(col, cell.ch, cell.fg, cell.bg, cell.attrs, w);
      if (w === 2 && col + 1 < newCols) {
        cur.setWidePlaceholder(col + 1);
      }
      col += w;
    }
    out.push(cur);
    return out;
  }

  isWrapPending(): boolean {
    return this.wrapPending;
  }

  private eraseCells(screen: BufferLine[], row: number, fromCol: number, toCol: number): void {
    const line = screen[row];
    if (!line) return;
    for (let c = fromCol; c < toCol && c < this.state.cols; c++) {
      line.blankCell(c, this.currentFg, this.currentBg, this.currentAttrs);
    }
    if (fromCol <= 0 && toCol >= this.state.cols) {
      line.isWrapped = false;
    }
    this.markDirty(row);
  }

  private clampCursor(): void {
    this.wrapPending = false;
    const cs = this.state.cursorState;
    cs.row = Math.max(0, Math.min(cs.row, this.state.rows - 1));
    cs.col = Math.max(0, Math.min(cs.col, this.state.cols - 1));
  }

  private syncDirtySize(): void {
    if (this.dirtyFlags.length !== this.state.rows) {
      this.dirtyFlags = new Uint8Array(this.state.rows);
      this.dirtyAll = true;
    }
  }

  private markDirty(row: number): void {
    this.syncDirtySize();
    if (this.dirtyAll || row < 0 || row >= this.dirtyFlags.length) {
      return;
    }
    this.dirtyFlags[row] = 1;
  }

  private markAllDirty(): void {
    this.syncDirtySize();
    this.dirtyAll = true;
    this.dirtyFlags.fill(0);
  }

  private markRangeDirty(top: number, bottom: number): void {
    if (this.dirtyAll) {
      return;
    }
    const last = Math.min(bottom, this.state.rows - 1);
    for (let r = Math.max(0, top); r <= last; r++) {
      this.markDirty(r);
    }
  }

  /** Mark viewport rows dirty (e.g. selection highlight changed). */
  markRowsDirty(top: number, bottom: number): void {
    this.markRangeDirty(top, bottom);
  }

  private sbAt(index: number): BufferLine {
    return this.sb[(this.sbStart + index) % MAX_SCROLLBACK];
  }

  private sbClear(): void {
    this.sb = [];
    this.sbStart = 0;
    this.sbCount = 0;
  }

  private sbReplace(lines: BufferLine[]): void {
    let start = 0;
    if (lines.length > MAX_SCROLLBACK) {
      start = lines.length - MAX_SCROLLBACK;
    }
    const kept: BufferLine[] = [];
    for (let i = start; i < lines.length; i++) {
      // Scrollback is committed history only.
      lines[i].isEphemeral = false;
      kept.push(lines[i]);
    }
    this.sb = kept;
    this.sbStart = 0;
    this.sbCount = kept.length;
  }

  private attrFlag(name: string): number {
    switch (name) {
      case 'bold': return ATTR_BOLD;
      case 'dim': return ATTR_DIM;
      case 'italic': return ATTR_ITALIC;
      case 'underline': return ATTR_UNDERLINE;
      case 'blink': return ATTR_BLINK;
      case 'inverse': return ATTR_INVERSE;
      case 'hidden': return ATTR_HIDDEN;
      case 'strikethrough': return ATTR_STRIKETHROUGH;
      default: return 0;
    }
  }
}
