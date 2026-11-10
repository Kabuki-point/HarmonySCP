import { TerminalTheme } from './TerminalTheme';
import { CURSOR_BLOCK, CURSOR_UNDERLINE, CURSOR_BAR } from './TerminalState';

export const CURSOR_STYLE_BLOCK: string = 'block';
export const CURSOR_STYLE_UNDERLINE: string = 'underline';
export const CURSOR_STYLE_BAR: string = 'bar';

/** Live-updatable terminal appearance. Replace the object so @Prop @Watch redraws. */
export class TerminalOptions {
  fontSize: number = 14;
  fontFamily: string = 'monospace';
  lineHeight: number = 1.6;
  theme: TerminalTheme = new TerminalTheme();
  cursorStyle: string = CURSOR_STYLE_BLOCK;
  cursorBlink: boolean = true;

  static create(): TerminalOptions {
    return new TerminalOptions();
  }

  clone(): TerminalOptions {
    const o = new TerminalOptions();
    o.fontSize = this.fontSize;
    o.fontFamily = this.fontFamily;
    o.lineHeight = this.lineHeight;
    o.cursorStyle = this.cursorStyle;
    o.cursorBlink = this.cursorBlink;
    o.theme = cloneTheme(this.theme);
    return o;
  }

  /** New instance with patches — for realtime UI updates. */
  withFontSize(size: number): TerminalOptions {
    const o = this.clone();
    o.fontSize = Math.max(8, Math.min(48, size));
    return o;
  }

  withFontFamily(family: string): TerminalOptions {
    const o = this.clone();
    o.fontFamily = family;
    return o;
  }

  withLineHeight(h: number): TerminalOptions {
    const o = this.clone();
    o.lineHeight = Math.max(1.0, Math.min(2.5, h));
    return o;
  }

  withTheme(theme: TerminalTheme): TerminalOptions {
    const o = this.clone();
    o.theme = cloneTheme(theme);
    return o;
  }

  withCursorStyle(style: string): TerminalOptions {
    const o = this.clone();
    o.cursorStyle = style;
    return o;
  }

  withCursorBlink(blink: boolean): TerminalOptions {
    const o = this.clone();
    o.cursorBlink = blink;
    return o;
  }

  cursorShapeCode(): number {
    if (this.cursorStyle === CURSOR_STYLE_UNDERLINE) {
      return CURSOR_UNDERLINE;
    }
    if (this.cursorStyle === CURSOR_STYLE_BAR) {
      return CURSOR_BAR;
    }
    return CURSOR_BLOCK;
  }
}

export function cloneTheme(src: TerminalTheme): TerminalTheme {
  const t = new TerminalTheme();
  t.background = src.background;
  t.foreground = src.foreground;
  t.cursor = src.cursor;
  t.cursorAccent = src.cursorAccent;
  t.selectionBackground = src.selectionBackground;
  t.selectionForeground = src.selectionForeground;
  t.black = src.black;
  t.red = src.red;
  t.green = src.green;
  t.yellow = src.yellow;
  t.blue = src.blue;
  t.magenta = src.magenta;
  t.cyan = src.cyan;
  t.white = src.white;
  t.brightBlack = src.brightBlack;
  t.brightRed = src.brightRed;
  t.brightGreen = src.brightGreen;
  t.brightYellow = src.brightYellow;
  t.brightBlue = src.brightBlue;
  t.brightMagenta = src.brightMagenta;
  t.brightCyan = src.brightCyan;
  t.brightWhite = src.brightWhite;
  t.extendedAnsi = src.extendedAnsi.slice();
  return t;
}
