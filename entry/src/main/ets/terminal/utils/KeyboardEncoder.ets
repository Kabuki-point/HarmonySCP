import { applyModifiers } from '../models/KeyboardBarConfig';

const KITTY_DISAMBIGUATE: number = 1;
const KITTY_ALT_KEYS: number = 4;
const KITTY_ALL_KEYS: number = 8;
const KITTY_TEXT: number = 16;

export function classifySequence(id: string, sequence: string): string {
  if (sequence === '\u001b' || id === 'esc') {
    return 'esc';
  }
  if (sequence === '\t' || id === 'tab') {
    return 'tab';
  }
  if (sequence === '\u001b[A' || id === 'up') {
    return 'up';
  }
  if (sequence === '\u001b[B' || id === 'down') {
    return 'down';
  }
  if (sequence === '\u001b[C' || id === 'right') {
    return 'right';
  }
  if (sequence === '\u001b[D' || id === 'left') {
    return 'left';
  }
  if (sequence === '\u001b[H' || id === 'home') {
    return 'home';
  }
  if (sequence === '\u001b[F' || id === 'end') {
    return 'end';
  }
  if (sequence === '\u001b[5~' || id === 'pgup') {
    return 'pgup';
  }
  if (sequence === '\u001b[6~' || id === 'pgdn') {
    return 'pgdn';
  }
  if (sequence === '\u001b[3~' || id === 'del') {
    return 'delete';
  }
  if (sequence === '\u001b[2~' || id === 'ins') {
    return 'insert';
  }
  if (sequence === '\u001bOP' || id === 'f1') {
    return 'f1';
  }
  if (sequence === '\u001bOQ' || id === 'f2') {
    return 'f2';
  }
  if (sequence === '\u001bOR' || id === 'f3') {
    return 'f3';
  }
  if (sequence === '\u001bOS' || id === 'f4') {
    return 'f4';
  }
  if (sequence === '\u001b[15~' || id === 'f5') {
    return 'f5';
  }
  if (sequence === '\u001b[17~' || id === 'f6') {
    return 'f6';
  }
  if (sequence === '\u001b[18~' || id === 'f7') {
    return 'f7';
  }
  if (sequence === '\u001b[19~' || id === 'f8') {
    return 'f8';
  }
  if (sequence === '\u001b[20~' || id === 'f9') {
    return 'f9';
  }
  if (sequence === '\u001b[21~' || id === 'f10') {
    return 'f10';
  }
  if (sequence === '\u001b[23~' || id === 'f11') {
    return 'f11';
  }
  if (sequence === '\u001b[24~' || id === 'f12') {
    return 'f12';
  }
  if (sequence === '\r' || id === 'enter') {
    return 'enter';
  }
  if (sequence === '\u007f' || id === 'backspace') {
    return 'backspace';
  }
  if (sequence === ' ' || id === 'space') {
    return 'space';
  }
  return 'text';
}

export function encodeKey(
  name: string,
  text: string,
  ctrl: boolean,
  alt: boolean,
  shift: boolean,
  appCursor: boolean,
  kittyFlags: number
): string {
  if (kittyFlags === 0) {
    return encodeLegacy(name, text, ctrl, alt, shift, appCursor);
  }
  const keyName = name === 'space' ? 'char' : name;
  const keyText = name === 'space' ? ' ' : text;
  return encodeKitty(keyName, keyText, ctrl, alt, shift, kittyFlags);
}

function encodeLegacy(
  name: string,
  text: string,
  ctrl: boolean,
  alt: boolean,
  shift: boolean,
  appCursor: boolean
): string {
  const mods = legacyMods(ctrl, alt, shift);
  // 与 Ctrl+字母同一套路：有修饰键时，导航/F 键带上 xterm mods 参数发给远端
  if (mods > 1 && needsCsiMods(name)) {
    return encodeLegacyModified(name, mods);
  }
  const bare = legacyBare(name, text, shift, appCursor);
  return applyModifiers(bare, ctrl, alt);
}

function legacyMods(ctrl: boolean, alt: boolean, shift: boolean): number {
  let bits = 0;
  if (shift) {
    bits |= 1;
  }
  if (alt) {
    bits |= 2;
  }
  if (ctrl) {
    bits |= 4;
  }
  return 1 + bits;
}

function needsCsiMods(name: string): boolean {
  return name === 'up' || name === 'down' || name === 'left' || name === 'right' ||
    name === 'home' || name === 'end' || name === 'pgup' || name === 'pgdn' ||
    name === 'insert' || name === 'delete' ||
    name === 'f1' || name === 'f2' || name === 'f3' || name === 'f4' ||
    name === 'f5' || name === 'f6' || name === 'f7' || name === 'f8' ||
    name === 'f9' || name === 'f10' || name === 'f11' || name === 'f12';
}

/** Shift/Ctrl/Alt + 方向键、Home/End、PgUp/PgDn、F 键等 → CSI 带 mods。 */
function encodeLegacyModified(name: string, mods: number): string {
  // F1–F4：xterm terminfo 为 kF1=\E[1;2P … kF3=\E[1;2R（不是 13;2~）
  if (name === 'f1') {
    return `\x1b[1;${mods}P`;
  }
  if (name === 'f2') {
    return `\x1b[1;${mods}Q`;
  }
  if (name === 'f3') {
    return `\x1b[1;${mods}R`;
  }
  if (name === 'f4') {
    return `\x1b[1;${mods}S`;
  }
  const letter = cursorLetter(name);
  if (letter.length > 0) {
    return `\x1b[1;${mods}${letter}`;
  }
  const tilde = tildeNumber(name);
  if (tilde > 0) {
    return `\x1b[${tilde};${mods}~`;
  }
  return '';
}

function legacyBare(name: string, text: string, shift: boolean, appCursor: boolean): string {
  if (name === 'up') {
    return appCursor ? '\x1bOA' : '\x1b[A';
  }
  if (name === 'down') {
    return appCursor ? '\x1bOB' : '\x1b[B';
  }
  if (name === 'right') {
    return appCursor ? '\x1bOC' : '\x1b[C';
  }
  if (name === 'left') {
    return appCursor ? '\x1bOD' : '\x1b[D';
  }
  if (name === 'home') {
    return appCursor ? '\x1bOH' : '\x1b[H';
  }
  if (name === 'end') {
    return appCursor ? '\x1bOF' : '\x1b[F';
  }
  if (name === 'tab' && shift) {
    return '\x1b[Z';
  }
  if (name === 'tab') {
    return '\t';
  }
  if (name === 'enter') {
    return '\r';
  }
  if (name === 'backspace') {
    return '\u007f';
  }
  if (name === 'esc') {
    return '\u001b';
  }
  if (name === 'space') {
    return ' ';
  }
  if (name === 'insert') {
    return '\x1b[2~';
  }
  if (name === 'delete') {
    return '\x1b[3~';
  }
  if (name === 'pgup') {
    return '\x1b[5~';
  }
  if (name === 'pgdn') {
    return '\x1b[6~';
  }
  if (name === 'f1') {
    return '\x1bOP';
  }
  if (name === 'f2') {
    return '\x1bOQ';
  }
  if (name === 'f3') {
    return '\x1bOR';
  }
  if (name === 'f4') {
    return '\x1bOS';
  }
  if (name === 'f5') {
    return '\x1b[15~';
  }
  if (name === 'f6') {
    return '\x1b[17~';
  }
  if (name === 'f7') {
    return '\x1b[18~';
  }
  if (name === 'f8') {
    return '\x1b[19~';
  }
  if (name === 'f9') {
    return '\x1b[20~';
  }
  if (name === 'f10') {
    return '\x1b[21~';
  }
  if (name === 'f11') {
    return '\x1b[23~';
  }
  if (name === 'f12') {
    return '\x1b[24~';
  }
  if (shift && text.length === 1) {
    return text.toUpperCase();
  }
  return text;
}

function encodeKitty(
  name: string,
  text: string,
  ctrl: boolean,
  alt: boolean,
  shift: boolean,
  flags: number
): string {
  const all = (flags & KITTY_ALL_KEYS) !== 0;
  const disambiguate = all || (flags & KITTY_DISAMBIGUATE) !== 0;
  const mods = kittyMods(ctrl, alt, shift);
  if (isFunctional(name)) {
    if ((name === 'enter' || name === 'tab' || name === 'backspace') && !all) {
      return encodeLegacy(name, text, ctrl, alt, shift, false);
    }
    if (disambiguate) {
      return kittyFunctional(name, mods, all, shift, (flags & KITTY_TEXT) !== 0);
    }
    return encodeLegacy(name, text, ctrl, alt, shift, false);
  }
  const cp = unshifted(text, shift, ctrl);
  if (cp === 0) {
    return '';
  }
  if (all) {
    return kittyU(cp, shiftCode(text, shift), mods, flags, shiftedText(text, shift));
  }
  if (disambiguate && (ctrl || alt || (shift && alt))) {
    return kittyU(cp, shiftCode(text, shift), mods, flags, shiftedText(text, shift));
  }
  return encodeLegacy(name, text, ctrl, alt, shift, false);
}

function isFunctional(name: string): boolean {
  return name !== 'char' && name !== 'text';
}

function kittyMods(ctrl: boolean, alt: boolean, shift: boolean): number {
  let bits = 0;
  if (shift) {
    bits |= 1;
  }
  if (alt) {
    bits |= 2;
  }
  if (ctrl) {
    bits |= 4;
  }
  return 1 + bits;
}

function kittyFunctional(name: string, mods: number, all: boolean, shift: boolean, textFlag: boolean): string {
  if (all && name === 'esc') {
    return kittyU(27, 0, mods, textFlag ? KITTY_TEXT | KITTY_ALL_KEYS : KITTY_ALL_KEYS, '');
  }
  if (all && name === 'enter') {
    return kittyU(13, 0, mods, textFlag ? KITTY_TEXT | KITTY_ALL_KEYS : KITTY_ALL_KEYS, '');
  }
  if (all && name === 'tab') {
    return kittyU(9, 0, mods, textFlag ? KITTY_TEXT | KITTY_ALL_KEYS : KITTY_ALL_KEYS, '');
  }
  if (all && name === 'backspace') {
    return kittyU(127, 0, mods, textFlag ? KITTY_TEXT | KITTY_ALL_KEYS : KITTY_ALL_KEYS, '');
  }
  if (all && name === 'space') {
    return kittyU(32, shift ? 32 : 0, mods, textFlag ? KITTY_TEXT | KITTY_ALL_KEYS : KITTY_ALL_KEYS, ' ');
  }
  // F1–F4: bare = SS3 (\eOP…); modified = CSI 1;mods L. Never \e[P (that is DCH).
  const fLetter = fKeyLetter(name);
  if (fLetter.length > 0) {
    if (mods === 1) {
      return `\x1bO${fLetter}`;
    }
    return `\x1b[1;${mods}${fLetter}`;
  }
  const letter = cursorLetter(name);
  if (letter.length > 0) {
    return csiCursor(letter, mods);
  }
  const tilde = tildeNumber(name);
  if (tilde > 0) {
    return csiTilde(tilde, mods);
  }
  return '';
}

function fKeyLetter(name: string): string {
  if (name === 'f1') {
    return 'P';
  }
  if (name === 'f2') {
    return 'Q';
  }
  if (name === 'f3') {
    return 'R';
  }
  if (name === 'f4') {
    return 'S';
  }
  return '';
}

function cursorLetter(name: string): string {
  if (name === 'up') {
    return 'A';
  }
  if (name === 'down') {
    return 'B';
  }
  if (name === 'right') {
    return 'C';
  }
  if (name === 'left') {
    return 'D';
  }
  if (name === 'home') {
    return 'H';
  }
  if (name === 'end') {
    return 'F';
  }
  return '';
}

function tildeNumber(name: string): number {
  if (name === 'insert') {
    return 2;
  }
  if (name === 'delete') {
    return 3;
  }
  if (name === 'pgup') {
    return 5;
  }
  if (name === 'pgdn') {
    return 6;
  }
  if (name === 'f5') {
    return 15;
  }
  if (name === 'f6') {
    return 17;
  }
  if (name === 'f7') {
    return 18;
  }
  if (name === 'f8') {
    return 19;
  }
  if (name === 'f9') {
    return 20;
  }
  if (name === 'f10') {
    return 21;
  }
  if (name === 'f11') {
    return 23;
  }
  if (name === 'f12') {
    return 24;
  }
  return 0;
}

function csiCursor(letter: string, mods: number): string {
  if (mods === 1) {
    return `\x1b[${letter}`;
  }
  return `\x1b[1;${mods}${letter}`;
}

function csiTilde(num: number, mods: number): string {
  if (mods === 1) {
    return `\x1b[${num}~`;
  }
  return `\x1b[${num};${mods}~`;
}

function kittyU(cp: number, shifted: number, mods: number, flags: number, text: string): string {
  let key = `${cp}`;
  if ((flags & KITTY_ALT_KEYS) !== 0 && shifted > 0) {
    key = `${cp}:${shifted}`;
  }
  const wantText = (flags & KITTY_TEXT) !== 0 && (flags & KITTY_ALL_KEYS) !== 0 && text.length > 0;
  if (!wantText && mods === 1 && shifted === 0) {
    return `\x1b[${key}u`;
  }
  if (!wantText && ((flags & KITTY_ALT_KEYS) === 0 || shifted === 0) && mods === 1) {
    return `\x1b[${key}u`;
  }
  if (!wantText) {
    return `\x1b[${key};${mods}u`;
  }
  return `\x1b[${key};${mods};${textPoints(text)}u`;
}

function textPoints(text: string): string {
  let out = '';
  let i = 0;
  while (i < text.length) {
    const cp = text.codePointAt(i);
    if (cp === undefined) {
      break;
    }
    if (out.length > 0) {
      out += ':';
    }
    out += `${cp}`;
    i += cp > 0xFFFF ? 2 : 1;
  }
  return out;
}

function unshifted(text: string, shift: boolean, ctrl: boolean): number {
  if (text.length === 0) {
    return 0;
  }
  const cp = text.codePointAt(0);
  if (cp === undefined) {
    return 0;
  }
  if (ctrl && cp >= 1 && cp <= 26) {
    return cp + 96;
  }
  if (shift && cp >= 65 && cp <= 90) {
    return cp + 32;
  }
  return cp;
}

function shiftCode(text: string, shift: boolean): number {
  if (!shift || text.length === 0) {
    return 0;
  }
  const cp = text.codePointAt(0);
  if (cp === undefined) {
    return 0;
  }
  if (cp >= 97 && cp <= 122) {
    return cp - 32;
  }
  if (cp >= 65 && cp <= 90) {
    return cp;
  }
  return 0;
}

function shiftedText(text: string, shift: boolean): string {
  if (!shift || text.length !== 1) {
    return text;
  }
  return text.toUpperCase();
}
