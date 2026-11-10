export interface CursorState {
  col: number;
  row: number;
  visible: boolean;
  blinking: boolean;
  shape: number;
}

export const CURSOR_BLOCK: number = 0;
export const CURSOR_UNDERLINE: number = 1;
export const CURSOR_BAR: number = 2;

export const ATTR_BOLD: number = 1 << 0;
export const ATTR_DIM: number = 1 << 1;
export const ATTR_ITALIC: number = 1 << 2;
export const ATTR_UNDERLINE: number = 1 << 3;
export const ATTR_BLINK: number = 1 << 4;
export const ATTR_INVERSE: number = 1 << 5;
export const ATTR_HIDDEN: number = 1 << 6;
export const ATTR_STRIKETHROUGH: number = 1 << 7;

export const COLOR_DEFAULT_FG: number = -1;
export const COLOR_DEFAULT_BG: number = -2;

export interface TerminalState {
  cols: number;
  rows: number;
  cursorState: CursorState;
  scrollTop: number;
  scrollBottom: number;
  useAltScreen: boolean;
  title: string;
}

export function createDefaultTerminalState(cols: number, rows: number): TerminalState {
  return {
    cols: cols,
    rows: rows,
    cursorState: {
      col: 0,
      row: 0,
      visible: true,
      blinking: true,
      shape: CURSOR_BLOCK,
    },
    scrollTop: 0,
    scrollBottom: rows - 1,
    useAltScreen: false,
    title: 'TermArk',
  };
}
