export class TerminalTheme {
  background: string = '#1E1E1E';
  foreground: string = '#D4D4D4';
  cursor: string = '#AEAFAD';
  cursorAccent: string = '#000000';
  selectionBackground: string = '#0A59F7';
  selectionForeground: string = '';
  black: string = '#000000';
  red: string = '#CC0000';
  green: string = '#4E9A06';
  yellow: string = '#C4A000';
  blue: string = '#3465A4';
  magenta: string = '#75507B';
  cyan: string = '#06989A';
  white: string = '#D3D7CF';
  brightBlack: string = '#555753';
  brightRed: string = '#EF2929';
  brightGreen: string = '#8AE234';
  brightYellow: string = '#FCE94F';
  brightBlue: string = '#729FCF';
  brightMagenta: string = '#AD7FA8';
  brightCyan: string = '#34E2E2';
  brightWhite: string = '#EEEEEC';
  extendedAnsi: string[] = [];
}

export function resolveColorRgb(code: number, theme: TerminalTheme): number {
  if (code === -1 || code === 0xFFFFFF) {
    return parseCssColor(theme.foreground);
  }
  if (code === -2 || code === 0xFFFFFE) {
    return parseCssColor(theme.background);
  }
  if (code >= 0 && code < 16) {
    const palette: string[] = [
      theme.black, theme.red, theme.green, theme.yellow,
      theme.blue, theme.magenta, theme.cyan, theme.white,
      theme.brightBlack, theme.brightRed, theme.brightGreen, theme.brightYellow,
      theme.brightBlue, theme.brightMagenta, theme.brightCyan, theme.brightWhite,
    ];
    return parseCssColor(palette[code]);
  }
  if (code >= 16 && code <= 231) {
    const idx = code - 16;
    const b = idx % 6;
    const g = Math.floor(idx / 6) % 6;
    const r = Math.floor(idx / 36);
    const v = (n: number): number => n === 0 ? 0 : 55 + n * 40;
    return (v(r) << 16) | (v(g) << 8) | v(b);
  }
  if (code >= 232 && code <= 255) {
    const gray = 8 + (code - 232) * 10;
    return (gray << 16) | (gray << 8) | gray;
  }
  if ((code & 0x1000000) !== 0) {
    return code & 0xFFFFFF;
  }
  return parseCssColor(theme.foreground);
}

export function parseCssColor(css: string): number {
  if (css.length >= 7 && css.charAt(0) === '#') {
    const n = parseInt(css.substring(1, 7), 16);
    return n >= 0 ? n : 0;
  }
  if (css.length > 4 && css.substring(0, 4) === 'rgb(') {
    const body = css.substring(4, css.length - 1);
    const parts = body.split(',');
    if (parts.length >= 3) {
      const r = parseInt(parts[0], 10);
      const g = parseInt(parts[1], 10);
      const b = parseInt(parts[2], 10);
      return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
    }
  }
  return 0;
}

export function isDefaultBg(code: number): boolean {
  return code === -2 || code === 0xFFFFFE;
}

export function resolveColor(code: number, theme: TerminalTheme): string {
  // Buffer stores defaults as signed -1/-2 masked into 24-bit: 0xFFFFFF / 0xFFFFFE.
  if (code === -1 || code === 0xFFFFFF) {
    return theme.foreground;
  }
  if (code === -2 || code === 0xFFFFFE) {
    return theme.background;
  }
  if (code >= 0 && code < 16) {
    const palette: string[] = [
      theme.black, theme.red, theme.green, theme.yellow,
      theme.blue, theme.magenta, theme.cyan, theme.white,
      theme.brightBlack, theme.brightRed, theme.brightGreen, theme.brightYellow,
      theme.brightBlue, theme.brightMagenta, theme.brightCyan, theme.brightWhite,
    ];
    return palette[code];
  }
  if (code >= 16 && code <= 231) {
    const idx = code - 16;
    const b = idx % 6;
    const g = Math.floor(idx / 6) % 6;
    const r = Math.floor(idx / 36);
    const v = (n: number): number => n === 0 ? 0 : 55 + n * 40;
    return `rgb(${v(r)},${v(g)},${v(b)})`;
  }
  if (code >= 232 && code <= 255) {
    const gray = 8 + (code - 232) * 10;
    return `rgb(${gray},${gray},${gray})`;
  }
  if ((code & 0x1000000) !== 0) {
    const r = (code >> 16) & 0xFF;
    const g = (code >> 8) & 0xFF;
    const b = code & 0xFF;
    return `rgb(${r},${g},${b})`;
  }
  return theme.foreground;
}
