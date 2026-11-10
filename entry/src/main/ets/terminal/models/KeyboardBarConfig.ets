import { preferences } from '@kit.ArkData';

export const SETTINGS_PREFS_NAME: string = 'termark_settings';
export const KEYBOARD_BAR_PREFS_KEY: string = 'keyboardBarKeys';
export const LETTER_ALTS_PREFS_KEY: string = 'keyboardLetterAlts';
export const KEYBOARD_CTRL_SLOT_PREFS_KEY: string = 'keyboardCtrlSlot';
export const KEYBOARD_DOT_SLOT_PREFS_KEY: string = 'keyboardDotSlot';
export const KEYBOARD_PIPE_SLOT_PREFS_KEY: string = 'keyboardPipeSlot';
export const KEYBOARD_COMMA_SLOT_PREFS_KEY: string = 'keyboardCommaSlot';
export const DEFAULT_DOT_SLOT_ID: string = 'dot';
export const DEFAULT_PIPE_SLOT_ID: string = 'pipe';
export const DEFAULT_COMMA_SLOT_ID: string = 'comma';

export const LETTER_ROW1: string[] = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
export const LETTER_ROW2: string[] = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
export const LETTER_ROW3: string[] = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

/** 自定义栏按键定义：点击后写入终端的原始序列。 */
export interface KeyboardBarKey {
  id: string;
  label: string;
  /** 写入 SSH/PTY 的字符串；修饰键用空串，靠 sticky 逻辑处理 */
  sequence: string;
  /** ctrl / alt / shift 为粘滞修饰键 */
  sticky?: string;
}

export const DEFAULT_KEYBOARD_BAR_KEYS: KeyboardBarKey[] = [
  { id: 'interrupt', label: 'Ctrl+C', sequence: '\u0003' },
  { id: 'esc', label: 'Esc', sequence: '\u001b' },
  { id: 'tab', label: 'Tab', sequence: '\t' },
  { id: 'alt', label: 'Alt', sequence: '', sticky: 'alt' },
  { id: 'dash', label: '-', sequence: '-' },
  { id: 'pipe', label: '|', sequence: '|' },
  { id: 'slash', label: '/', sequence: '/' },
  { id: 'tilde', label: '~', sequence: '~' },
  { id: 'up', label: '↑', sequence: '\u001b[A' },
  { id: 'down', label: '↓', sequence: '\u001b[B' },
  { id: 'left', label: '←', sequence: '\u001b[D' },
  { id: 'right', label: '→', sequence: '\u001b[C' }
];

/** 设置页可选的快捷键池（含默认项以外的命令行常用键） */
export const KEYBOARD_BAR_CATALOG: KeyboardBarKey[] = [
  ...DEFAULT_KEYBOARD_BAR_KEYS,
  { id: 'ctrl', label: 'Ctrl', sequence: '', sticky: 'ctrl' },
  { id: 'shift', label: 'Shift', sequence: '', sticky: 'shift' },
  { id: 'dot', label: '.', sequence: '.' },
  { id: 'comma', label: ',', sequence: ',' },
  { id: 'home', label: 'Home', sequence: '\u001b[H' },
  { id: 'end', label: 'End', sequence: '\u001b[F' },
  { id: 'pgup', label: 'PgUp', sequence: '\u001b[5~' },
  { id: 'pgdn', label: 'PgDn', sequence: '\u001b[6~' },
  { id: 'del', label: 'Del', sequence: '\u001b[3~' },
  { id: 'ins', label: 'Ins', sequence: '\u001b[2~' },
  { id: 'f1', label: 'F1', sequence: '\u001bOP' },
  { id: 'f2', label: 'F2', sequence: '\u001bOQ' },
  { id: 'f3', label: 'F3', sequence: '\u001bOR' },
  { id: 'f4', label: 'F4', sequence: '\u001bOS' },
  { id: 'f5', label: 'F5', sequence: '\u001b[15~' },
  { id: 'f6', label: 'F6', sequence: '\u001b[17~' },
  { id: 'f7', label: 'F7', sequence: '\u001b[18~' },
  { id: 'f8', label: 'F8', sequence: '\u001b[19~' },
  { id: 'f9', label: 'F9', sequence: '\u001b[20~' },
  { id: 'f10', label: 'F10', sequence: '\u001b[21~' },
  { id: 'f11', label: 'F11', sequence: '\u001b[23~' },
  { id: 'f12', label: 'F12', sequence: '\u001b[24~' },
  { id: 'underscore', label: '_', sequence: '_' },
  { id: 'amp', label: '&', sequence: '&' },
  { id: 'semi', label: ';', sequence: ';' },
  { id: 'colon', label: ':', sequence: ':' },
  { id: 'dollar', label: '$', sequence: '$' },
  { id: 'hash', label: '#', sequence: '#' },
  { id: 'at', label: '@', sequence: '@' },
  { id: 'star', label: '*', sequence: '*' },
  { id: 'bang', label: '!', sequence: '!' },
  { id: 'question', label: '?', sequence: '?' },
  { id: 'backslash', label: '\\', sequence: '\\' },
  { id: 'backtick', label: '`', sequence: '`' },
  { id: 'gt', label: '>', sequence: '>' },
  { id: 'lt', label: '<', sequence: '<' },
  { id: 'lbrace', label: '{', sequence: '{' },
  { id: 'rbrace', label: '}', sequence: '}' },
  { id: 'lbracket', label: '[', sequence: '[' },
  { id: 'rbracket', label: ']', sequence: ']' },
  { id: 'lparen', label: '(', sequence: '(' },
  { id: 'rparen', label: ')', sequence: ')' },
  { id: 'equal', label: '=', sequence: '=' },
  { id: 'plus', label: '+', sequence: '+' },
  { id: 'percent', label: '%', sequence: '%' },
  { id: 'caret', label: '^', sequence: '^' },
  { id: 'quote', label: "'", sequence: "'" },
  { id: 'dquote', label: '"', sequence: '"' }
];

function cloneKey(key: KeyboardBarKey): KeyboardBarKey {
  return {
    id: key.id,
    label: key.label,
    sequence: key.sequence,
    sticky: key.sticky
  };
}

export function cloneKeyboardBarKeys(keys: KeyboardBarKey[]): KeyboardBarKey[] {
  const out: KeyboardBarKey[] = [];
  for (let i = 0; i < keys.length; i++) {
    out.push(cloneKey(keys[i]));
  }
  return out;
}

export function defaultKeyboardBarKeys(): KeyboardBarKey[] {
  return cloneKeyboardBarKeys(DEFAULT_KEYBOARD_BAR_KEYS);
}

export interface LetterAltPair {
  ch: string;
  alt: string;
}

export function defaultLetterAltPairs(): LetterAltPair[] {
  return [
    { ch: 'q', alt: '1' },
    { ch: 'w', alt: '2' },
    { ch: 'e', alt: '3' },
    { ch: 'r', alt: '4' },
    { ch: 't', alt: '5' },
    { ch: 'y', alt: '6' },
    { ch: 'u', alt: '7' },
    { ch: 'i', alt: '8' },
    { ch: 'o', alt: '9' },
    { ch: 'p', alt: '0' },
    { ch: 'a', alt: '@' },
    { ch: 's', alt: '#' },
    { ch: 'd', alt: '$' },
    { ch: 'f', alt: '%' },
    { ch: 'g', alt: '&' },
    { ch: 'h', alt: '*' },
    { ch: 'j', alt: '<' },
    { ch: 'k', alt: '>' },
    { ch: 'l', alt: '_' },
    { ch: 'z', alt: '~' },
    { ch: 'x', alt: '-' },
    { ch: 'c', alt: '/' },
    { ch: 'v', alt: ':' },
    { ch: 'b', alt: ';' },
    { ch: 'n', alt: '!' },
    { ch: 'm', alt: '?' }
  ];
}

export function letterAltOf(pairs: LetterAltPair[], ch: string): string {
  for (let i = 0; i < pairs.length; i++) {
    if (pairs[i].ch === ch) {
      return pairs[i].alt;
    }
  }
  return '';
}

export async function loadLetterAlts(ctx: Context): Promise<LetterAltPair[]> {
  try {
    const prefs = await preferences.getPreferences(ctx, SETTINGS_PREFS_NAME);
    const raw = (await prefs.get(LETTER_ALTS_PREFS_KEY, '')) as string;
    if (!raw || raw.length === 0) {
      return defaultLetterAltPairs();
    }
    const parsed = JSON.parse(raw) as LetterAltPair[];
    if (!parsed || parsed.length === 0) {
      return defaultLetterAltPairs();
    }
    return parsed;
  } catch (err) {
    throw new Error(`Failed to load letter alts: ${String(err)}`);
  }
}

export function resolveBarKey(id: string): KeyboardBarKey | undefined {
  const found = findCatalogKey(id);
  if (found) {
    return found;
  }
  if (id.length > 6 && id.substring(0, 6) === 'empty:') {
    return emptySlotKey(id.substring(6));
  }
  if (id === DEFAULT_DOT_SLOT_ID) {
    return defaultDotSlotKey();
  }
  if (id === DEFAULT_COMMA_SLOT_ID) {
    return defaultCommaSlotKey();
  }
  if (id.length > 4 && id.substring(0, 4) === 'lit:') {
    const ch = id.substring(4);
    if (ch.length > 0) {
      return { id: id, label: ch, sequence: ch };
    }
  }
  return undefined;
}

export function findCatalogKey(id: string): KeyboardBarKey | undefined {
  for (let i = 0; i < KEYBOARD_BAR_CATALOG.length; i++) {
    if (KEYBOARD_BAR_CATALOG[i].id === id) {
      return cloneKey(KEYBOARD_BAR_CATALOG[i]);
    }
  }
  return undefined;
}

export function emptySlotKey(slot: string): KeyboardBarKey {
  return { id: `empty:${slot}`, label: '', sequence: '' };
}

export function isEmptySlotKey(key: KeyboardBarKey): boolean {
  return key.id.length > 6 && key.id.substring(0, 6) === 'empty:';
}

export function defaultCtrlSlotKey(): KeyboardBarKey {
  return { id: 'ctrl', label: 'Ctrl', sequence: '', sticky: 'ctrl' };
}

export function defaultDotSlotKey(): KeyboardBarKey {
  return { id: DEFAULT_DOT_SLOT_ID, label: '.', sequence: '.' };
}

export function defaultPipeSlotKey(): KeyboardBarKey {
  const found = findCatalogKey(DEFAULT_PIPE_SLOT_ID);
  if (found) {
    return found;
  }
  return { id: DEFAULT_PIPE_SLOT_ID, label: '|', sequence: '|' };
}

export function defaultCommaSlotKey(): KeyboardBarKey {
  return { id: DEFAULT_COMMA_SLOT_ID, label: ',', sequence: ',' };
}

async function loadSlotKey(ctx: Context, prefsKey: string, fallback: KeyboardBarKey): Promise<KeyboardBarKey> {
  try {
    const prefs = await preferences.getPreferences(ctx, SETTINGS_PREFS_NAME);
    const id = (await prefs.get(prefsKey, fallback.id)) as string;
    if (!id) {
      return fallback;
    }
    const found = resolveBarKey(id);
    if (!found) {
      return fallback;
    }
    return found;
  } catch (err) {
    throw new Error(`Failed to load slot ${prefsKey}: ${String(err)}`);
  }
}

export async function loadCtrlSlotKey(ctx: Context): Promise<KeyboardBarKey> {
  return loadSlotKey(ctx, KEYBOARD_CTRL_SLOT_PREFS_KEY, defaultCtrlSlotKey());
}

export async function loadDotSlotKey(ctx: Context): Promise<KeyboardBarKey> {
  return loadSlotKey(ctx, KEYBOARD_DOT_SLOT_PREFS_KEY, defaultDotSlotKey());
}

export async function loadPipeSlotKey(ctx: Context): Promise<KeyboardBarKey> {
  return loadSlotKey(ctx, KEYBOARD_PIPE_SLOT_PREFS_KEY, defaultPipeSlotKey());
}

export async function loadCommaSlotKey(ctx: Context): Promise<KeyboardBarKey> {
  return loadSlotKey(ctx, KEYBOARD_COMMA_SLOT_PREFS_KEY, defaultCommaSlotKey());
}

export async function loadKeyboardBarKeys(ctx: Context): Promise<KeyboardBarKey[]> {
  try {
    const prefs = await preferences.getPreferences(ctx, SETTINGS_PREFS_NAME);
    const raw = (await prefs.get(KEYBOARD_BAR_PREFS_KEY, '')) as string;
    if (!raw || raw.length === 0) {
      return defaultKeyboardBarKeys();
    }
    const ids = JSON.parse(raw) as string[];
    const keys: KeyboardBarKey[] = [];
    for (let i = 0; i < ids.length; i++) {
      const found = resolveBarKey(ids[i]);
      if (found) {
        keys.push(found);
      }
    }
    return keys.length > 0 ? keys : defaultKeyboardBarKeys();
  } catch (err) {
    throw new Error(`Failed to load keyboard bar keys: ${String(err)}`);
  }
}

export function cloneLetterAltPairs(pairs: LetterAltPair[]): LetterAltPair[] {
  const out: LetterAltPair[] = [];
  for (let i = 0; i < pairs.length; i++) {
    out.push({ ch: pairs[i].ch, alt: pairs[i].alt });
  }
  return out;
}

export interface KeyboardBarLiveState {
  keys: KeyboardBarKey[];
  letterAlts: LetterAltPair[];
  ctrlSlot: KeyboardBarKey;
  dotSlot: KeyboardBarKey;
  pipeSlot: KeyboardBarKey;
  commaSlot: KeyboardBarKey;
}

let liveKeys: KeyboardBarKey[] = defaultKeyboardBarKeys();
let liveAlts: LetterAltPair[] = defaultLetterAltPairs();
let liveCtrl: KeyboardBarKey = defaultCtrlSlotKey();
let liveDot: KeyboardBarKey = defaultDotSlotKey();
let livePipe: KeyboardBarKey = defaultPipeSlotKey();
let liveComma: KeyboardBarKey = defaultCommaSlotKey();
let liveReady: boolean = false;
let liveListener: () => void = () => {};

export function setKeyboardBarLiveListener(fn: () => void): void {
  liveListener = fn;
}

export function isKeyboardBarLiveReady(): boolean {
  return liveReady;
}

export function getKeyboardBarLive(): KeyboardBarLiveState {
  return {
    keys: cloneKeyboardBarKeys(liveKeys),
    letterAlts: cloneLetterAltPairs(liveAlts),
    ctrlSlot: cloneKey(liveCtrl),
    dotSlot: cloneKey(liveDot),
    pipeSlot: cloneKey(livePipe),
    commaSlot: cloneKey(liveComma)
  };
}

function assignKeyboardBarLive(state: KeyboardBarLiveState): void {
  liveKeys = cloneKeyboardBarKeys(state.keys);
  liveAlts = cloneLetterAltPairs(state.letterAlts);
  liveCtrl = cloneKey(state.ctrlSlot);
  liveDot = cloneKey(state.dotSlot);
  livePipe = cloneKey(state.pipeSlot);
  liveComma = cloneKey(state.commaSlot);
  liveReady = true;
}

export async function hydrateKeyboardBarLive(ctx: Context): Promise<void> {
  if (liveReady) {
    liveListener();
    return;
  }
  const keys = await loadKeyboardBarKeys(ctx);
  const letterAlts = await loadLetterAlts(ctx);
  const ctrlSlot = await loadCtrlSlotKey(ctx);
  const dotSlot = await loadDotSlotKey(ctx);
  const pipeSlot = await loadPipeSlotKey(ctx);
  const commaSlot = await loadCommaSlotKey(ctx);
  if (liveReady) {
    liveListener();
    return;
  }
  assignKeyboardBarLive({
    keys: keys,
    letterAlts: letterAlts,
    ctrlSlot: ctrlSlot,
    dotSlot: dotSlot,
    pipeSlot: pipeSlot,
    commaSlot: commaSlot
  });
  liveListener();
}

/** Ctrl/Alt 修饰后生成要写入的序列。 */
export function applyModifiers(ch: string, ctrl: boolean, alt: boolean): string {
  if (ch.length === 0) {
    return '';
  }
  let out = ch;
  if (ctrl && out.length === 1) {
    const code = out.toLowerCase().charCodeAt(0);
    if (code >= 97 && code <= 122) {
      out = String.fromCharCode(code - 96);
    }
  }
  if (alt) {
    out = `\u001b${out}`;
  }
  return out;
}
