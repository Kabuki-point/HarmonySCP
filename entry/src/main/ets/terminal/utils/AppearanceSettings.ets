import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { TerminalTheme } from '../models/TerminalTheme';
import {
  TerminalOptions,
  CURSOR_STYLE_BLOCK,
  CURSOR_STYLE_UNDERLINE,
  CURSOR_STYLE_BAR,
  cloneTheme
} from '../models/TerminalOptions';
import { SETTINGS_PREFS_NAME } from '../models/KeyboardBarConfig';
import { SYSTEM_FONT_FAMILY, atlasFontFamily, normalizeSystemFontFamily } from './SystemFonts';

export const APPEARANCE_REVISION_KEY: string = 'appearance.revision';
export const DEFAULT_THEME_NAME: string = 'Catppuccin Mocha';
export const CUSTOM_THEME_NAME: string = 'Custom';

const KEY_JSON: string = 'appearancePrefsJson';

export class ThemePresetInfo {
  name: string = '';
  bg: string = '';
  fg: string = '';
  accent: string = '';
}

export class AppearancePrefs {
  fontFamily: string = SYSTEM_FONT_FAMILY;
  fontSize: number = 14;
  lineHeight: number = 1.6;
  cursorStyle: string = CURSOR_STYLE_BLOCK;
  cursorBlink: boolean = true;
  themeName: string = DEFAULT_THEME_NAME;
  accent: string = '#CBA6F7';
  accentMode: boolean = false;
  theme: TerminalTheme = buildThemeFromPreset(DEFAULT_THEME_NAME);
}

function createPreset(name: string, bg: string, fg: string, accent: string): ThemePresetInfo {
  const p = new ThemePresetInfo();
  p.name = name;
  p.bg = bg;
  p.fg = fg;
  p.accent = accent;
  return p;
}

export function listThemePresets(): ThemePresetInfo[] {
  return [
    createPreset('Catppuccin Mocha', '#1E1E2E', '#CDD6F4', '#CBA6F7'),
    createPreset('Tokyo Night', '#1A1B26', '#C0CAF5', '#7AA2F7'),
    createPreset('Gruvbox', '#282828', '#EBDBB2', '#FE8019'),
    createPreset('Nord', '#2E3440', '#D8DEE9', '#88C0D0'),
    createPreset('Solarized Dark', '#002B36', '#839496', '#2AA198'),
    createPreset('Rosé Pine', '#191724', '#E0DEF4', '#EBBCBA'),
    createPreset('Catppuccin Latte', '#EFF1F5', '#4C4F69', '#8839EF'),
    createPreset('Gruvbox Light', '#FBF1C7', '#3C3836', '#AF3A03')
  ];
}

export function resolveThemeName(name: string): string {
  if (name === CUSTOM_THEME_NAME) {
    return CUSTOM_THEME_NAME;
  }
  if (name === 'Solarized') {
    return 'Solarized Dark';
  }
  const presets = listThemePresets();
  for (let i = 0; i < presets.length; i++) {
    if (presets[i].name === name) {
      return name;
    }
  }
  return DEFAULT_THEME_NAME;
}

function fillAnsi(
  theme: TerminalTheme,
  cursor: string,
  black: string, red: string, green: string, yellow: string,
  blue: string, magenta: string, cyan: string, white: string,
  brightBlack: string, brightRed: string, brightGreen: string, brightYellow: string,
  brightBlue: string, brightMagenta: string, brightCyan: string, brightWhite: string
): void {
  theme.cursor = cursor;
  theme.black = black;
  theme.red = red;
  theme.green = green;
  theme.yellow = yellow;
  theme.blue = blue;
  theme.magenta = magenta;
  theme.cyan = cyan;
  theme.white = white;
  theme.brightBlack = brightBlack;
  theme.brightRed = brightRed;
  theme.brightGreen = brightGreen;
  theme.brightYellow = brightYellow;
  theme.brightBlue = brightBlue;
  theme.brightMagenta = brightMagenta;
  theme.brightCyan = brightCyan;
  theme.brightWhite = brightWhite;
}

export function buildThemeFromPreset(themeName: string): TerminalTheme {
  const name = resolveThemeName(themeName);
  let info = createPreset(DEFAULT_THEME_NAME, '#1E1E2E', '#CDD6F4', '#CBA6F7');
  const presets = listThemePresets();
  for (let i = 0; i < presets.length; i++) {
    if (presets[i].name === name) {
      info = presets[i];
      break;
    }
  }
  const theme = new TerminalTheme();
  theme.background = info.bg;
  theme.foreground = info.fg;
  theme.cursorAccent = info.bg;
  theme.selectionBackground = info.accent;
  theme.selectionForeground = info.bg;
  switch (name) {
    case 'Tokyo Night':
      fillAnsi(theme, '#C0CAF5',
        '#15161E', '#F7768E', '#9ECE6A', '#E0AF68', '#7AA2F7', '#BB9AF7', '#7DCFFF', '#A9B1D6',
        '#414868', '#FF899D', '#9FE044', '#FABA4A', '#8DB0FF', '#C7A9FF', '#A4DAFF', '#C0CAF5');
      break;
    case 'Gruvbox':
      fillAnsi(theme, '#EBDBB2',
        '#282828', '#CC241D', '#98971A', '#D79921', '#458588', '#B16286', '#689D6A', '#A89984',
        '#928374', '#FB4934', '#B8BB26', '#FABD2F', '#83A598', '#D3869B', '#8EC07C', '#EBDBB2');
      break;
    case 'Nord':
      fillAnsi(theme, '#D8DEE9',
        '#3B4252', '#BF616A', '#A3BE8C', '#EBCB8B', '#81A1C1', '#B48EAD', '#88C0D0', '#E5E9F0',
        '#4C566A', '#BF616A', '#A3BE8C', '#EBCB8B', '#81A1C1', '#B48EAD', '#8FBCBB', '#ECEFF4');
      break;
    case 'Solarized Dark':
      fillAnsi(theme, '#839496',
        '#073642', '#DC322F', '#859900', '#B58900', '#268BD2', '#D33682', '#2AA198', '#EEE8D5',
        '#586E75', '#CB4B16', '#859900', '#B58900', '#268BD2', '#6C71C4', '#2AA198', '#FDF6E3');
      break;
    case 'Rosé Pine':
      fillAnsi(theme, '#E0DEF4',
        '#26233A', '#EB6F92', '#31748F', '#F6C177', '#9CCFD8', '#C4A7E7', '#EBBCBA', '#E0DEF4',
        '#6E6A86', '#EB6F92', '#31748F', '#F6C177', '#9CCFD8', '#C4A7E7', '#EBBCBA', '#E0DEF4');
      break;
    case 'Catppuccin Latte':
      fillAnsi(theme, '#DC8A78',
        '#BCC0CC', '#D20F39', '#40A02B', '#DF8E1D', '#1E66F5', '#EA76CB', '#179299', '#5C5F77',
        '#ACB0BE', '#D20F39', '#40A02B', '#DF8E1D', '#1E66F5', '#EA76CB', '#179299', '#6C6F85');
      break;
    case 'Gruvbox Light':
      fillAnsi(theme, '#3C3836',
        '#FBF1C7', '#CC241D', '#98971A', '#D79921', '#458588', '#B16286', '#689D6A', '#7C6F64',
        '#928374', '#9D0006', '#79740E', '#B57614', '#076678', '#8F3F71', '#427B58', '#3C3836');
      break;
    case 'Catppuccin Mocha':
    default:
      fillAnsi(theme, '#F5E0DC',
        '#45475A', '#F38BA8', '#A6E3A1', '#F9E2AF', '#89B4FA', '#F5C2E7', '#94E2D5', '#BAC2DE',
        '#585B70', '#F38BA8', '#A6E3A1', '#F9E2AF', '#89B4FA', '#F5C2E7', '#94E2D5', '#A6ADC8');
      break;
  }
  return theme;
}

/** Apply simplified accent: cursor + selection + blue emphasis. */
export function applyAccentMode(theme: TerminalTheme, accent: string): TerminalTheme {
  const t = cloneTheme(theme);
  t.cursor = accent;
  t.selectionBackground = accent;
  t.blue = accent;
  t.brightBlue = accent;
  return t;
}

export function cloneAppearance(src: AppearancePrefs): AppearancePrefs {
  const o = new AppearancePrefs();
  o.fontFamily = src.fontFamily;
  o.fontSize = src.fontSize;
  o.lineHeight = src.lineHeight;
  o.cursorStyle = src.cursorStyle;
  o.cursorBlink = src.cursorBlink;
  o.themeName = src.themeName;
  o.accent = src.accent;
  o.accentMode = src.accentMode;
  o.theme = cloneTheme(src.theme);
  return o;
}

function themeToRecord(t: TerminalTheme): Record<string, string> {
  return {
    'background': t.background,
    'foreground': t.foreground,
    'cursor': t.cursor,
    'cursorAccent': t.cursorAccent,
    'selectionBackground': t.selectionBackground,
    'selectionForeground': t.selectionForeground,
    'black': t.black,
    'red': t.red,
    'green': t.green,
    'yellow': t.yellow,
    'blue': t.blue,
    'magenta': t.magenta,
    'cyan': t.cyan,
    'white': t.white,
    'brightBlack': t.brightBlack,
    'brightRed': t.brightRed,
    'brightGreen': t.brightGreen,
    'brightYellow': t.brightYellow,
    'brightBlue': t.brightBlue,
    'brightMagenta': t.brightMagenta,
    'brightCyan': t.brightCyan,
    'brightWhite': t.brightWhite
  };
}

function themeFromRecord(r: Record<string, Object>): TerminalTheme {
  const t = new TerminalTheme();
  const get = (k: string, d: string): string => {
    const v = r[k];
    return typeof v === 'string' && v.length > 0 ? v : d;
  };
  const base = buildThemeFromPreset(DEFAULT_THEME_NAME);
  t.background = get('background', base.background);
  t.foreground = get('foreground', base.foreground);
  t.cursor = get('cursor', base.cursor);
  t.cursorAccent = get('cursorAccent', base.cursorAccent);
  t.selectionBackground = get('selectionBackground', base.selectionBackground);
  t.selectionForeground = get('selectionForeground', base.selectionForeground);
  t.black = get('black', base.black);
  t.red = get('red', base.red);
  t.green = get('green', base.green);
  t.yellow = get('yellow', base.yellow);
  t.blue = get('blue', base.blue);
  t.magenta = get('magenta', base.magenta);
  t.cyan = get('cyan', base.cyan);
  t.white = get('white', base.white);
  t.brightBlack = get('brightBlack', base.brightBlack);
  t.brightRed = get('brightRed', base.brightRed);
  t.brightGreen = get('brightGreen', base.brightGreen);
  t.brightYellow = get('brightYellow', base.brightYellow);
  t.brightBlue = get('brightBlue', base.brightBlue);
  t.brightMagenta = get('brightMagenta', base.brightMagenta);
  t.brightCyan = get('brightCyan', base.brightCyan);
  t.brightWhite = get('brightWhite', base.brightWhite);
  return t;
}

function prefsToRecord(p: AppearancePrefs): Record<string, Object> {
  return {
    'fontFamily': p.fontFamily,
    'fontSize': p.fontSize,
    'lineHeight': p.lineHeight,
    'cursorStyle': p.cursorStyle,
    'cursorBlink': p.cursorBlink,
    'themeName': p.themeName,
    'accent': p.accent,
    'accentMode': p.accentMode,
    'theme': themeToRecord(p.theme)
  };
}

function prefsFromRecord(r: Record<string, Object>): AppearancePrefs {
  const p = new AppearancePrefs();
  const fontFamily = r['fontFamily'];
  if (typeof fontFamily === 'string') {
    p.fontFamily = normalizeSystemFontFamily(fontFamily);
  }
  const fontSize = r['fontSize'];
  if (typeof fontSize === 'number' && Number.isFinite(fontSize)) {
    p.fontSize = Math.max(8, Math.min(48, Math.round(fontSize)));
  }
  const lineHeight = r['lineHeight'];
  if (typeof lineHeight === 'number' && Number.isFinite(lineHeight)) {
    p.lineHeight = Math.max(1.0, Math.min(2.5, lineHeight));
  }
  const cursorStyle = r['cursorStyle'];
  if (typeof cursorStyle === 'string' &&
    (cursorStyle === CURSOR_STYLE_BLOCK || cursorStyle === CURSOR_STYLE_UNDERLINE ||
      cursorStyle === CURSOR_STYLE_BAR)) {
    p.cursorStyle = cursorStyle;
  }
  const cursorBlink = r['cursorBlink'];
  if (typeof cursorBlink === 'boolean') {
    p.cursorBlink = cursorBlink;
  }
  const themeName = r['themeName'];
  if (typeof themeName === 'string') {
    p.themeName = resolveThemeName(themeName);
  }
  const accent = r['accent'];
  if (typeof accent === 'string' && accent.length > 0) {
    p.accent = accent;
  }
  const accentMode = r['accentMode'];
  if (typeof accentMode === 'boolean') {
    p.accentMode = accentMode;
  }
  const themeObj = r['theme'];
  if (themeObj !== undefined && typeof themeObj === 'object') {
    p.theme = themeFromRecord(themeObj as Record<string, Object>);
  } else if (p.themeName !== CUSTOM_THEME_NAME) {
    p.theme = buildThemeFromPreset(p.themeName);
  }
  if (p.accentMode) {
    p.theme = applyAccentMode(p.theme, p.accent);
  }
  return p;
}

export function bumpAppearanceRevision(): void {
  const cur = AppStorage.get<number>(APPEARANCE_REVISION_KEY) ?? 0;
  AppStorage.setOrCreate<number>(APPEARANCE_REVISION_KEY, cur + 1);
}

export async function loadAppearancePrefs(ctx: Context): Promise<AppearancePrefs> {
  try {
    const store = await preferences.getPreferences(ctx, SETTINGS_PREFS_NAME);
    const raw = (await store.get(KEY_JSON, '')) as string;
    if (raw.length === 0) {
      return new AppearancePrefs();
    }
    const parsed = JSON.parse(raw) as Object;
    if (parsed === null || typeof parsed !== 'object') {
      return new AppearancePrefs();
    }
    return prefsFromRecord(parsed as Record<string, Object>);
  } catch (e) {
    const err = e as BusinessError;
    console.error(`loadAppearancePrefs failed. code=${err.code}, message=${err.message}`);
    return new AppearancePrefs();
  }
}

export async function saveAppearancePrefs(ctx: Context, prefs: AppearancePrefs): Promise<void> {
  try {
    const store = await preferences.getPreferences(ctx, SETTINGS_PREFS_NAME);
    await store.put(KEY_JSON, JSON.stringify(prefsToRecord(prefs)));
    await store.flush();
    bumpAppearanceRevision();
  } catch (e) {
    const err = e as BusinessError;
    console.error(`saveAppearancePrefs failed. code=${err.code}, message=${err.message}`);
  }
}

/** Map saved appearance → live TerminalOptions (atlas-ready font family). */
export function appearanceToOptions(prefs: AppearancePrefs): TerminalOptions {
  const o = TerminalOptions.create();
  o.fontFamily = atlasFontFamily(prefs.fontFamily);
  o.fontSize = prefs.fontSize;
  o.lineHeight = prefs.lineHeight;
  o.cursorStyle = prefs.cursorStyle;
  o.cursorBlink = prefs.cursorBlink;
  let theme = cloneTheme(prefs.theme);
  if (prefs.accentMode) {
    theme = applyAccentMode(theme, prefs.accent);
  }
  o.theme = theme;
  return o;
}

/** Normalize #RGB / #RRGGBB; empty → ''. */
export function normalizeHexColor(raw: string): string {
  let s = raw.trim();
  if (s.length === 0) {
    return '';
  }
  if (s.charAt(0) !== '#') {
    s = `#${s}`;
  }
  if (s.length === 4) {
    const r = s.charAt(1);
    const g = s.charAt(2);
    const b = s.charAt(3);
    s = `#${r}${r}${g}${g}${b}${b}`;
  }
  if (s.length !== 7) {
    return '';
  }
  const body = s.substring(1);
  for (let i = 0; i < body.length; i++) {
    const c = body.charAt(i).toLowerCase();
    const ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    if (!ok) {
      return '';
    }
  }
  return `#${body.toUpperCase()}`;
}
