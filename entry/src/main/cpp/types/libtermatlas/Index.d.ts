export const submitFrame: (
  width: number,
  height: number,
  cols: number,
  rows: number,
  cellW: number,
  cellH: number,
  fontPx: number,
  fontFamily: string,
  clearRgb: number,
  cells: ArrayBuffer,
  extra: ArrayBuffer,
  cursorCol: number,
  cursorRow: number,
  cursorShape: number,
  cursorRgb: number,
  accentRgb: number,
  barX: number,
  barY: number,
  barW: number,
  barH: number,
  barTrackA: number,
  barThumbA: number
) => void;

export const measureCellWidth: (fontPx: number, fontFamily: string) => number;

export const surfaceWidth: () => number;

export const surfaceHeight: () => number;
