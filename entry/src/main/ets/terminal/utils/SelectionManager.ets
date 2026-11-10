import { TerminalBuffer } from './TerminalBuffer';

export class CellPos {
  col: number = 0;
  row: number = 0;

  constructor(col: number, row: number) {
    this.col = col;
    this.row = row;
  }
}

export class SelectionRange {
  start: CellPos = new CellPos(0, 0);
  end: CellPos = new CellPos(0, 0);
}

export class SelectionManager {
  private buffer: TerminalBuffer;
  selectionStartCol: number = -1;
  selectionStartRow: number = -1;
  selectionEndCol: number = -1;
  selectionEndRow: number = -1;
  active: boolean = false;
  mode: number = SELECTION_MODE_NONE;

  constructor(buffer: TerminalBuffer) {
    this.buffer = buffer;
  }

  startSelection(col: number, viewportRow: number, mode: number): void {
    const snapped = this.snapCell(col, this.buffer.absRowFromViewport(viewportRow));
    this.mode = mode;
    this.selectionStartCol = snapped.col;
    this.selectionStartRow = snapped.row;
    this.selectionEndCol = snapped.col;
    this.selectionEndRow = snapped.row;
    this.active = true;
    if (mode === SELECTION_MODE_WORD) {
      this.selectWordAt(snapped.col, snapped.row);
    } else if (mode === SELECTION_MODE_LINE) {
      this.selectLineAt(snapped.row);
    }
    this.trimCursor();
  }

  updateSelection(col: number, viewportRow: number): void {
    if (!this.active) {
      return;
    }
    const snapped = this.snapCell(col, this.buffer.absRowFromViewport(viewportRow));
    this.selectionEndCol = snapped.col;
    this.selectionEndRow = snapped.row;
    this.trimCursor();
  }

  moveStartHandle(col: number, viewportRow: number): void {
    if (!this.active) {
      return;
    }
    const current = this.getNormalizedSelection();
    if (!current) {
      return;
    }
    const snapped = this.snapCell(col, this.buffer.absRowFromViewport(viewportRow));
    this.selectionStartCol = snapped.col;
    this.selectionStartRow = snapped.row;
    this.selectionEndCol = current.end.col;
    this.selectionEndRow = current.end.row;
    this.trimCursor();
  }

  moveEndHandle(col: number, viewportRow: number): void {
    if (!this.active) {
      return;
    }
    const current = this.getNormalizedSelection();
    if (!current) {
      return;
    }
    const snapped = this.snapCell(col, this.buffer.absRowFromViewport(viewportRow));
    this.selectionStartCol = current.start.col;
    this.selectionStartRow = current.start.row;
    this.selectionEndCol = snapped.col;
    this.selectionEndRow = snapped.row;
    this.trimCursor();
  }

  clearSelection(): void {
    this.selectionStartCol = -1;
    this.selectionStartRow = -1;
    this.selectionEndCol = -1;
    this.selectionEndRow = -1;
    this.active = false;
    this.mode = SELECTION_MODE_NONE;
  }

  hasSelection(): boolean {
    return this.active && this.selectionStartCol >= 0 && this.selectionStartRow >= 0;
  }

  getNormalizedSelection(): SelectionRange | null {
    if (!this.hasSelection()) {
      return null;
    }
    const start = this.getSelectionStart();
    const end = this.getSelectionEnd();
    const range = new SelectionRange();
    range.start = start;
    range.end = end;
    return range;
  }

  getSelectionStart(): CellPos {
    if (this.selectionStartRow < this.selectionEndRow ||
      (this.selectionStartRow === this.selectionEndRow && this.selectionStartCol <= this.selectionEndCol)) {
      return new CellPos(this.selectionStartCol, this.selectionStartRow);
    }
    return new CellPos(this.selectionEndCol, this.selectionEndRow);
  }

  getSelectionEnd(): CellPos {
    if (this.selectionStartRow < this.selectionEndRow ||
      (this.selectionStartRow === this.selectionEndRow && this.selectionStartCol <= this.selectionEndCol)) {
      return new CellPos(this.selectionEndCol, this.selectionEndRow);
    }
    return new CellPos(this.selectionStartCol, this.selectionStartRow);
  }

  getSelectedText(): string {
    const range = this.getNormalizedSelection();
    if (!range) {
      return '';
    }
    const result: string[] = [];
    for (let r = range.start.row; r <= range.end.row; r++) {
      const line = this.buffer.getLineAbsolute(r);
      if (!line) {
        continue;
      }
      const sc = r === range.start.row ? range.start.col : 0;
      const ec = r === range.end.row ? range.end.col : this.buffer.getCols() - 1;
      let lineText = '';
      for (let c = sc; c <= ec; c++) {
        if (c < line.length) {
          const ch = line.getChar(c);
          const w = line.getWidth(c);
          lineText += ch;
          if (w === 2) {
            c++;
          }
        }
      }
      result.push(lineText.replace(/ +$/, ''));
      if (r < range.end.row) {
        const next = this.buffer.getLineAbsolute(r + 1);
        if (!next || !next.isWrapped) {
          result.push('\n');
        }
      }
    }
    return result.join('');
  }

  isCursorCell(col: number, absRow: number): boolean {
    return absRow === this.buffer.getCursorAbsRow() &&
      col === this.buffer.getState().cursorState.col;
  }

  cellHasText(col: number, absRow: number): boolean {
    const line = this.buffer.getLineAbsolute(absRow);
    if (!line || col >= line.length) {
      return false;
    }
    const ch = line.getChar(col);
    return ch.length > 0 && ch !== ' ' && ch !== '\0';
  }

  /** Drop the cursor cell from the range. Returns false if nothing remains. */
  trimCursor(): boolean {
    const range = this.getNormalizedSelection();
    if (!range) {
      return false;
    }
    const cols = this.buffer.getCols();
    const lo = range.start.row * cols + range.start.col;
    const hi = range.end.row * cols + range.end.col;
    const cIdx = this.buffer.getCursorAbsRow() * cols + this.buffer.getState().cursorState.col;
    if (cIdx < lo || cIdx > hi) {
      return true;
    }
    if (cIdx === hi && hi > lo) {
      this.selectionStartCol = range.start.col;
      this.selectionStartRow = range.start.row;
      this.selectionEndCol = (hi - 1) % cols;
      this.selectionEndRow = Math.floor((hi - 1) / cols);
      return true;
    }
    if (cIdx === lo && hi > lo) {
      this.selectionStartCol = (lo + 1) % cols;
      this.selectionStartRow = Math.floor((lo + 1) / cols);
      this.selectionEndCol = range.end.col;
      this.selectionEndRow = range.end.row;
      return true;
    }
    if (cIdx > lo && cIdx < hi) {
      this.selectionStartCol = range.start.col;
      this.selectionStartRow = range.start.row;
      this.selectionEndCol = (cIdx - 1) % cols;
      this.selectionEndRow = Math.floor((cIdx - 1) / cols);
      return true;
    }
    this.clearSelection();
    return false;
  }

  private selectWordAt(col: number, absRow: number): void {
    const line = this.buffer.getLineAbsolute(absRow);
    if (!line) {
      return;
    }
    let startCol = col;
    let startRow = absRow;
    let endCol = col;
    let endRow = absRow;
    if (this.isWordChar(line.getChar(col))) {
      let prev = this.prevCell(startCol, startRow);
      while (prev !== null) {
        const prevLine = this.buffer.getLineAbsolute(prev.row);
        if (!prevLine || !this.isWordChar(prevLine.getChar(prev.col)) ||
          this.isCursorCell(prev.col, prev.row)) {
          break;
        }
        startCol = prev.col;
        startRow = prev.row;
        prev = this.prevCell(startCol, startRow);
      }
      let next = this.nextCell(endCol, endRow);
      while (next !== null) {
        const nextLine = this.buffer.getLineAbsolute(next.row);
        if (!nextLine || !this.isWordChar(nextLine.getChar(next.col)) ||
          this.isCursorCell(next.col, next.row)) {
          break;
        }
        endCol = next.col;
        endRow = next.row;
        next = this.nextCell(endCol, endRow);
      }
    }
    this.selectionStartCol = startCol;
    this.selectionStartRow = startRow;
    this.selectionEndCol = endCol;
    this.selectionEndRow = endRow;
  }

  private prevCell(col: number, absRow: number): CellPos | null {
    if (col > 0) {
      return new CellPos(col - 1, absRow);
    }
    if (absRow <= 0) {
      return null;
    }
    const line = this.buffer.getLineAbsolute(absRow);
    if (!line || !line.isWrapped) {
      return null;
    }
    return new CellPos(this.buffer.getCols() - 1, absRow - 1);
  }

  private nextCell(col: number, absRow: number): CellPos | null {
    const cols = this.buffer.getCols();
    if (col < cols - 1) {
      return new CellPos(col + 1, absRow);
    }
    const next = this.buffer.getLineAbsolute(absRow + 1);
    if (!next || !next.isWrapped) {
      return null;
    }
    return new CellPos(0, absRow + 1);
  }

  private selectLineAt(absRow: number): void {
    const cols = this.buffer.getCols();
    this.selectionStartCol = 0;
    this.selectionStartRow = absRow;
    this.selectionEndCol = cols - 1;
    this.selectionEndRow = absRow;
  }

  private isWordChar(ch: string): boolean {
    if (ch.length !== 1) {
      return false;
    }
    const code = ch.charCodeAt(0);
    const isDigit = code >= 48 && code <= 57;
    const isUpper = code >= 65 && code <= 90;
    const isLower = code >= 97 && code <= 122;
    return isDigit || isUpper || isLower;
  }

  private snapCell(col: number, absRow: number): CellPos {
    const cols = this.buffer.getCols();
    const rows = this.buffer.getRows();
    let nextCol = Math.max(0, Math.min(col, cols - 1));
    let nextRow = absRow;
    if (this.buffer.getState().useAltScreen) {
      nextRow = Math.max(0, Math.min(nextRow, rows - 1));
    } else {
      const maxAbs = this.buffer.getYbase() + rows - 1;
      nextRow = Math.max(0, Math.min(nextRow, maxAbs));
    }
    const line = this.buffer.getLineAbsolute(nextRow);
    if (line && nextCol < line.length && line.getWidth(nextCol) === 0 && nextCol > 0) {
      nextCol = nextCol - 1;
    }
    return new CellPos(nextCol, nextRow);
  }
}

export const SELECTION_MODE_NONE: number = 0;
export const SELECTION_MODE_CELL: number = 1;
export const SELECTION_MODE_WORD: number = 2;
export const SELECTION_MODE_LINE: number = 3;
