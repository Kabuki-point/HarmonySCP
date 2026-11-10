export const STATE_GROUND: number = 0;
export const STATE_ESCAPE: number = 1;
export const STATE_ESCAPE_INTERMEDIATE: number = 2;
export const STATE_CSI_ENTRY: number = 3;
export const STATE_CSI_PARAM: number = 4;
export const STATE_CSI_INTERMEDIATE: number = 5;
export const STATE_CSI_IGNORE: number = 6;
export const STATE_DCS_ENTRY: number = 7;
export const STATE_DCS_PARAM: number = 8;
export const STATE_DCS_INTERMEDIATE: number = 9;
export const STATE_DCS_PASSTHROUGH: number = 10;
export const STATE_DCS_IGNORE: number = 11;
export const STATE_OSC_STRING: number = 12;
export const STATE_SOS_PM_APC_STRING: number = 13;

export const ACTION_NONE: number = 0;
export const ACTION_PRINT: number = 1;
export const ACTION_EXECUTE: number = 2;
export const ACTION_CLEAR: number = 3;
export const ACTION_COLLECT: number = 4;
export const ACTION_PARAM: number = 5;
export const ACTION_ESC_DISPATCH: number = 6;
export const ACTION_CSI_DISPATCH: number = 7;
export const ACTION_HOOK: number = 8;
export const ACTION_PUT: number = 9;
export const ACTION_UNHOOK: number = 10;
export const ACTION_OSC_START: number = 11;
export const ACTION_OSC_PUT: number = 12;
export const ACTION_OSC_END: number = 13;

const NUM_STATES: number = 14;
const TABLE_SIZE: number = NUM_STATES * 256;

function encode(action: number, state: number): number {
  return (action << 8) | state;
}

function buildTransitionTable(): Uint16Array {
  const table: Uint16Array = new Uint16Array(TABLE_SIZE);
  for (let s = 0; s < NUM_STATES; s++) {
    for (let b = 0; b < 256; b++) {
      table[s * 256 + b] = encode(ACTION_NONE, s);
    }
  }

  for (let s = 0; s < NUM_STATES; s++) {
    for (let b = 0; b < 256; b++) {
      if (b === 0x18 || b === 0x1A) {
        table[s * 256 + b] = encode(ACTION_EXECUTE, STATE_GROUND);
        continue;
      }
      if (b === 0x1B) {
        table[s * 256 + b] = encode(ACTION_NONE, STATE_ESCAPE);
        continue;
      }
      if (b >= 0x80 && b <= 0x8F) {
        table[s * 256 + b] = encode(ACTION_EXECUTE, STATE_GROUND);
        continue;
      }
      if (b >= 0x90 && b <= 0x97) {
        table[s * 256 + b] = encode(ACTION_NONE, STATE_DCS_ENTRY);
        continue;
      }
      if (b === 0x98 || b === 0x9E || b === 0x9F) {
        table[s * 256 + b] = encode(ACTION_NONE, STATE_SOS_PM_APC_STRING);
        continue;
      }
      if (b === 0x99 || b === 0x9A) {
        table[s * 256 + b] = encode(ACTION_EXECUTE, STATE_GROUND);
        continue;
      }
      if (b === 0x9B) {
        table[s * 256 + b] = encode(ACTION_NONE, STATE_CSI_ENTRY);
        continue;
      }
      if (b === 0x9C) {
        table[s * 256 + b] = encode(ACTION_NONE, STATE_GROUND);
        continue;
      }
      if (b === 0x9D) {
        table[s * 256 + b] = encode(ACTION_OSC_START, STATE_OSC_STRING);
        continue;
      }
    }
  }

  fillGround(table);
  fillEscape(table);
  fillEscapeIntermediate(table);
  fillCsiEntry(table);
  fillCsiParam(table);
  fillCsiIntermediate(table);
  fillCsiIgnore(table);
  fillDcsEntry(table);
  fillDcsParam(table);
  fillDcsIntermediate(table);
  fillDcsPassthrough(table);
  fillOscString(table);
  fillSosPmApcString(table);

  return table;
}

function fillGround(table: Uint16Array): void {
  const base = STATE_GROUND * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_GROUND);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_GROUND);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_GROUND);
  for (let b = 0x20; b <= 0x7E; b++) table[base + b] = encode(ACTION_PRINT, STATE_GROUND);
  table[base + 0x7F] = encode(ACTION_EXECUTE, STATE_GROUND);
  for (let b = 0xA0; b < 256; b++) table[base + b] = encode(ACTION_PRINT, STATE_GROUND);
}

function fillEscape(table: Uint16Array): void {
  const base = STATE_ESCAPE * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_ESCAPE);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_ESCAPE);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_ESCAPE);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_ESCAPE);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_ESCAPE_INTERMEDIATE);
  for (let b = 0x30; b <= 0x4F; b++) table[base + b] = encode(ACTION_ESC_DISPATCH, STATE_GROUND);
  table[base + 0x50] = encode(ACTION_NONE, STATE_DCS_ENTRY);
  for (let b = 0x51; b <= 0x57; b++) table[base + b] = encode(ACTION_ESC_DISPATCH, STATE_GROUND);
  table[base + 0x58] = encode(ACTION_NONE, STATE_SOS_PM_APC_STRING);
  table[base + 0x5E] = encode(ACTION_NONE, STATE_SOS_PM_APC_STRING);
  table[base + 0x5F] = encode(ACTION_NONE, STATE_SOS_PM_APC_STRING);
  table[base + 0x5B] = encode(ACTION_NONE, STATE_CSI_ENTRY);
  table[base + 0x5C] = encode(ACTION_ESC_DISPATCH, STATE_GROUND);
  table[base + 0x5D] = encode(ACTION_OSC_START, STATE_OSC_STRING);
  for (let b = 0x60; b <= 0x7E; b++) table[base + b] = encode(ACTION_ESC_DISPATCH, STATE_GROUND);
}

function fillEscapeIntermediate(table: Uint16Array): void {
  const base = STATE_ESCAPE_INTERMEDIATE * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_ESCAPE_INTERMEDIATE);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_ESCAPE_INTERMEDIATE);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_ESCAPE_INTERMEDIATE);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_ESCAPE_INTERMEDIATE);
  for (let b = 0x30; b <= 0x7E; b++) table[base + b] = encode(ACTION_ESC_DISPATCH, STATE_GROUND);
}

function fillCsiEntry(table: Uint16Array): void {
  const base = STATE_CSI_ENTRY * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_ENTRY);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_CSI_ENTRY);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_ENTRY);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_CSI_ENTRY);
  for (let b = 0x30; b <= 0x39; b++) table[base + b] = encode(ACTION_PARAM, STATE_CSI_PARAM);
  table[base + 0x3B] = encode(ACTION_PARAM, STATE_CSI_PARAM);
  for (let b = 0x3C; b <= 0x3F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_CSI_PARAM);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_CSI_DISPATCH, STATE_GROUND);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_CSI_INTERMEDIATE);
}

function fillCsiParam(table: Uint16Array): void {
  const base = STATE_CSI_PARAM * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_PARAM);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_CSI_PARAM);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_PARAM);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_CSI_PARAM);
  for (let b = 0x30; b <= 0x39; b++) table[base + b] = encode(ACTION_PARAM, STATE_CSI_PARAM);
  table[base + 0x3B] = encode(ACTION_PARAM, STATE_CSI_PARAM);
  for (let b = 0x3C; b <= 0x3F; b++) table[base + b] = encode(ACTION_NONE, STATE_CSI_IGNORE);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_CSI_DISPATCH, STATE_GROUND);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_CSI_INTERMEDIATE);
}

function fillCsiIntermediate(table: Uint16Array): void {
  const base = STATE_CSI_INTERMEDIATE * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_INTERMEDIATE);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_CSI_INTERMEDIATE);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_INTERMEDIATE);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_CSI_INTERMEDIATE);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_CSI_INTERMEDIATE);
  for (let b = 0x30; b <= 0x3F; b++) table[base + b] = encode(ACTION_NONE, STATE_CSI_IGNORE);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_CSI_DISPATCH, STATE_GROUND);
}

function fillCsiIgnore(table: Uint16Array): void {
  const base = STATE_CSI_IGNORE * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_IGNORE);
  table[base + 0x19] = encode(ACTION_EXECUTE, STATE_CSI_IGNORE);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_EXECUTE, STATE_CSI_IGNORE);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_NONE, STATE_GROUND);
}

function fillDcsEntry(table: Uint16Array): void {
  const base = STATE_DCS_ENTRY * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_ENTRY);
  table[base + 0x19] = encode(ACTION_NONE, STATE_DCS_ENTRY);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_ENTRY);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_DCS_ENTRY);
  for (let b = 0x30; b <= 0x39; b++) table[base + b] = encode(ACTION_PARAM, STATE_DCS_PARAM);
  table[base + 0x3B] = encode(ACTION_PARAM, STATE_DCS_PARAM);
  for (let b = 0x3C; b <= 0x3F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_DCS_PARAM);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_DCS_INTERMEDIATE);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_HOOK, STATE_DCS_PASSTHROUGH);
}

function fillDcsParam(table: Uint16Array): void {
  const base = STATE_DCS_PARAM * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_PARAM);
  table[base + 0x19] = encode(ACTION_NONE, STATE_DCS_PARAM);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_PARAM);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_DCS_PARAM);
  for (let b = 0x30; b <= 0x39; b++) table[base + b] = encode(ACTION_PARAM, STATE_DCS_PARAM);
  table[base + 0x3B] = encode(ACTION_PARAM, STATE_DCS_PARAM);
  for (let b = 0x3C; b <= 0x3F; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_IGNORE);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_DCS_INTERMEDIATE);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_HOOK, STATE_DCS_PASSTHROUGH);
}

function fillDcsIntermediate(table: Uint16Array): void {
  const base = STATE_DCS_INTERMEDIATE * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_INTERMEDIATE);
  table[base + 0x19] = encode(ACTION_NONE, STATE_DCS_INTERMEDIATE);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_INTERMEDIATE);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_DCS_INTERMEDIATE);
  for (let b = 0x20; b <= 0x2F; b++) table[base + b] = encode(ACTION_COLLECT, STATE_DCS_INTERMEDIATE);
  for (let b = 0x30; b <= 0x3F; b++) table[base + b] = encode(ACTION_NONE, STATE_DCS_IGNORE);
  for (let b = 0x40; b <= 0x7E; b++) table[base + b] = encode(ACTION_HOOK, STATE_DCS_PASSTHROUGH);
}

function fillDcsPassthrough(table: Uint16Array): void {
  const base = STATE_DCS_PASSTHROUGH * 256;
  for (let b = 0; b <= 0x17; b++) table[base + b] = encode(ACTION_PUT, STATE_DCS_PASSTHROUGH);
  table[base + 0x19] = encode(ACTION_PUT, STATE_DCS_PASSTHROUGH);
  for (let b = 0x1C; b <= 0x1F; b++) table[base + b] = encode(ACTION_PUT, STATE_DCS_PASSTHROUGH);
  for (let b = 0x20; b <= 0x7E; b++) table[base + b] = encode(ACTION_PUT, STATE_DCS_PASSTHROUGH);
  table[base + 0x7F] = encode(ACTION_NONE, STATE_DCS_PASSTHROUGH);
}

function fillOscString(table: Uint16Array): void {
  const base = STATE_OSC_STRING * 256;
  table[base + 0x07] = encode(ACTION_OSC_END, STATE_GROUND);
  table[base + 0x9C] = encode(ACTION_OSC_END, STATE_GROUND);
  table[base + 0x1B] = encode(ACTION_OSC_END, STATE_ESCAPE);
  for (let b = 0x20; b <= 0x7F; b++) table[base + b] = encode(ACTION_OSC_PUT, STATE_OSC_STRING);
  for (let b = 0xA0; b < 256; b++) table[base + b] = encode(ACTION_OSC_PUT, STATE_OSC_STRING);
}

function fillSosPmApcString(table: Uint16Array): void {
  const base = STATE_SOS_PM_APC_STRING * 256;
  table[base + 0x9C] = encode(ACTION_NONE, STATE_GROUND);
  table[base + 0x1B] = encode(ACTION_NONE, STATE_GROUND);
}

const MAX_PARAMS: number = 32;
const MAX_INTERMEDIATES: number = 2;

export class EscapeSequenceParser {
  private state: number = STATE_GROUND;
  private params: number[] = [];
  private intermediates: number[] = [];
  private table: Uint16Array;

  onPrint: (ch: string) => void = (_ch: string) => {};
  onExecute: (code: number) => void = (_code: number) => {};
  onCsiDispatch: (finalByte: number, params: number[], intermediates: number[]) => void =
    (_f: number, _p: number[], _i: number[]) => {};
  onEscDispatch: (finalByte: number, intermediates: number[]) => void =
    (_f: number, _i: number[]) => {};
  onOscStart: () => void = () => {};
  onOscPut: (data: string) => void = (_data: string) => {};
  onOscEnd: () => void = () => {};
  onHook: (params: number[], intermediates: number[]) => void =
    (_p: number[], _i: number[]) => {};
  onPut: (ch: string) => void = (_ch: string) => {};
  onUnhook: () => void = () => {};

  constructor() {
    this.table = buildTransitionTable();
  }

  parse(data: string): void {
    for (let i = 0; i < data.length; i++) {
      const code = data.charCodeAt(i);

      if (this.state === STATE_GROUND && code > 0x7F) {
        if (code >= 0xD800 && code <= 0xDBFF && i + 1 < data.length) {
          const low = data.charCodeAt(i + 1);
          if (low >= 0xDC00 && low <= 0xDFFF) {
            this.onPrint(data[i] + data[i + 1]);
            i++;
            continue;
          }
        }
        this.onPrint(data[i]);
        continue;
      }

      // The transition table is byte-sized. Keep non-ASCII title text in the OSC handler.
      if (code > 0xFF) {
        if (this.state === STATE_OSC_STRING) this.onOscPut(data[i]);
        continue;
      }

      const trans = this.table[this.state * 256 + code];
      const action = (trans >> 8) & 0xFF;
      const nextState = trans & 0xFF;

      if (nextState !== this.state) {
        this.performStateExit(this.state, nextState);
        this.state = nextState;
        this.performStateEntry(nextState, action, code, data[i]);
      } else {
        this.performAction(action, code, data[i]);
      }
    }
  }

  private performStateEntry(state: number, action: number, code: number, ch: string): void {
    switch (state) {
      case STATE_ESCAPE:
      case STATE_CSI_ENTRY:
      case STATE_DCS_ENTRY:
        this.params = [];
        this.intermediates = [];
        break;
      default:
        break;
    }
    this.performAction(action, code, ch);
  }

  private performStateExit(_oldState: number, _newState: number): void {}

  private performAction(action: number, code: number, ch: string): void {
    switch (action) {
      case ACTION_PRINT:
        this.onPrint(ch);
        break;
      case ACTION_EXECUTE:
        this.onExecute(code);
        break;
      case ACTION_CLEAR:
        this.params = [];
        this.intermediates = [];
        break;
      case ACTION_COLLECT:
        if (this.intermediates.length < MAX_INTERMEDIATES) {
          this.intermediates.push(code);
        }
        break;
      case ACTION_PARAM:
        if (code === 0x3B) {
          this.params.push(0);
        } else {
          if (this.params.length === 0) this.params.push(0);
          const last = this.params[this.params.length - 1];
          this.params[this.params.length - 1] = last * 10 + (code - 0x30);
        }
        if (this.params.length > MAX_PARAMS) this.params.length = MAX_PARAMS;
        break;
      case ACTION_ESC_DISPATCH:
        this.onEscDispatch(code, this.intermediates);
        break;
      case ACTION_CSI_DISPATCH:
        this.onCsiDispatch(code, this.params, this.intermediates);
        break;
      case ACTION_HOOK:
        this.onHook(this.params, this.intermediates);
        break;
      case ACTION_PUT:
        this.onPut(ch);
        break;
      case ACTION_UNHOOK:
        this.onUnhook();
        break;
      case ACTION_OSC_START:
        this.onOscStart();
        break;
      case ACTION_OSC_PUT:
        this.onOscPut(ch);
        break;
      case ACTION_OSC_END:
        this.onOscEnd();
        break;
      default:
        break;
    }
  }
}
