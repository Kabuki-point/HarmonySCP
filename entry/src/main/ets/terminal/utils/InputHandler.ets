import { COLOR_DEFAULT_FG, COLOR_DEFAULT_BG } from '../models/TerminalState';
import { TerminalBuffer } from './TerminalBuffer';
import { EscapeSequenceParser } from './EscapeSequenceParser';
import { wcwidth } from './UnicodeService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const WRAP_LOG_DOMAIN: number = 0x0000;
const WRAP_LOG_TAG: string = 'TermArkWrap';
const OSC_LIMIT: number = 4096;

export class InputHandler {
  private buffer: TerminalBuffer;
  private parser: EscapeSequenceParser;
  private oscData: string = '';
  onReply: (data: string) => void = () => {};

  constructor(buffer: TerminalBuffer, parser: EscapeSequenceParser) {
    this.buffer = buffer;
    this.parser = parser;
    this.installHandlers();
  }

  private installHandlers(): void {
    this.parser.onPrint = (ch: string) => { this.handlePrint(ch); };
    this.parser.onExecute = (code: number) => { this.handleExecute(code); };
    this.parser.onCsiDispatch = (finalByte: number, params: number[], intermediates: number[]) => {
      this.handleCsi(finalByte, params, intermediates);
    };
    this.parser.onEscDispatch = (finalByte: number, intermediates: number[]) => {
      this.handleEsc(finalByte, intermediates);
    };
    this.parser.onOscStart = () => { this.oscData = ''; };
    this.parser.onOscPut = (data: string) => {
      if (this.oscData.length < OSC_LIMIT) this.oscData += data;
    };
    this.parser.onOscEnd = () => { this.handleOsc(this.oscData); };
  }

  private handlePrint(ch: string): void {
    let codepoint: number = ch.charCodeAt(0);
    if (ch.length > 1) {
      const high: number = ch.charCodeAt(0);
      const low: number = ch.charCodeAt(1);
      if (high >= 0xD800 && high <= 0xDBFF && low >= 0xDC00 && low <= 0xDFFF) {
        codepoint = ((high - 0xD800) << 10) + (low - 0xDC00) + 0x10000;
      }
    }
    const width: number = wcwidth(codepoint);
    this.buffer.printChar(ch, width);
  }

  private logWrapIn(name: string, extra: string): void {
    if (this.buffer.getState().useAltScreen) {
      return;
    }
    hilog.info(WRAP_LOG_DOMAIN, WRAP_LOG_TAG, 'in %{public}s %{public}s', name, extra);
  }

  private handleExecute(code: number): void {
    this.buffer.clearRepeat();
    switch (code) {
      case 0x08:
        // BS only moves the cursor. Applications erase with "\b \b".
        this.logWrapIn('BS', '');
        this.buffer.cursorBack(1);
        break;
      case 0x7F:
        break;
      case 0x09:
        this.buffer.tab();
        break;
      case 0x0A:
      case 0x0B:
      case 0x0C:
        this.logWrapIn('LF', `code=${code}`);
        this.buffer.lineFeed();
        break;
      case 0x0D:
        this.logWrapIn('CR', '');
        this.buffer.carriageReturn();
        break;
      case 0x07:
      case 0x0E:
      case 0x0F:
        break;
      default:
        break;
    }
  }

  private handleEsc(finalByte: number, intermediates: number[]): void {
    this.buffer.clearRepeat();
    if (intermediates.length > 0) {
      if (intermediates[0] === 0x28 || intermediates[0] === 0x29) {
        return;
      }
    }
    switch (finalByte) {
      case 0x37:
        this.buffer.saveCursor();
        break;
      case 0x38:
        this.buffer.restoreCursor();
        break;
      case 0x44:
        this.buffer.index();
        break;
      case 0x45:
        this.buffer.nextLine();
        break;
      case 0x4D:
        this.buffer.reverseIndex();
        break;
      case 0x63:
        this.buffer.reset();
        break;
      default:
        break;
    }
  }

  private param(params: number[], idx: number, def: number): number {
    if (idx >= params.length) return def;
    const v: number = params[idx];
    return v === 0 ? def : v;
  }

  private handleCsi(finalByte: number, params: number[], intermediates: number[]): void {
    if (intermediates.length > 0) {
      this.buffer.clearRepeat();
      this.dispatchMarked(finalByte, params, intermediates);
      return;
    }
    if (finalByte !== 0x62) {
      this.buffer.clearRepeat();
    }
    switch (finalByte) {
      case 0x40:
        this.buffer.insertChars(this.param(params, 0, 1));
        break;
      case 0x41:
        this.logWrapIn('CUU', `n=${this.param(params, 0, 1)}`);
        this.buffer.cursorUp(this.param(params, 0, 1));
        break;
      case 0x42:
        this.logWrapIn('CUD', `n=${this.param(params, 0, 1)}`);
        this.buffer.cursorDown(this.param(params, 0, 1));
        break;
      case 0x43:
        this.logWrapIn('CUF', `n=${this.param(params, 0, 1)}`);
        this.buffer.cursorForward(this.param(params, 0, 1));
        break;
      case 0x44:
        this.logWrapIn('CUB', `n=${this.param(params, 0, 1)}`);
        this.buffer.cursorBack(this.param(params, 0, 1));
        break;
      case 0x45:
        this.buffer.cursorNextLine(this.param(params, 0, 1));
        break;
      case 0x46:
        this.buffer.cursorPrevLine(this.param(params, 0, 1));
        break;
      case 0x47:
        this.logWrapIn('CHA', `col=${this.param(params, 0, 1) - 1}`);
        this.buffer.cursorAbsoluteCol(this.param(params, 0, 1) - 1);
        break;
      case 0x48:
        this.logWrapIn('CUP', `r=${this.param(params, 0, 1) - 1} c=${this.param(params, 1, 1) - 1}`);
        this.buffer.setCursorPos(this.param(params, 0, 1) - 1, this.param(params, 1, 1) - 1);
        break;
      case 0x49: {
        const n: number = this.param(params, 0, 1);
        for (let j: number = 0; j < n; j++) {
          this.buffer.tab();
        }
        break;
      }
      case 0x4A:
        this.buffer.eraseDisplay(this.param(params, 0, 0));
        break;
      case 0x4B:
        this.logWrapIn('EL', `mode=${this.param(params, 0, 0)}`);
        this.buffer.eraseLine(this.param(params, 0, 0));
        break;
      case 0x4C:
        this.buffer.insertLines(this.param(params, 0, 1));
        break;
      case 0x4D:
        this.buffer.deleteLines(this.param(params, 0, 1));
        break;
      case 0x50:
        this.buffer.deleteChars(this.param(params, 0, 1));
        break;
      case 0x53:
        this.buffer.scrollUp(this.param(params, 0, 1));
        break;
      case 0x54:
        this.buffer.scrollDown(this.param(params, 0, 1));
        break;
      case 0x58:
        this.buffer.eraseChars(this.param(params, 0, 1));
        break;
      case 0x5A:
        this.buffer.cursorBackTab(this.param(params, 0, 1));
        break;
      case 0x60:
        this.logWrapIn('CHA', `col=${this.param(params, 0, 1) - 1}`);
        this.buffer.cursorAbsoluteCol(this.param(params, 0, 1) - 1);
        break;
      case 0x61:
        this.logWrapIn('CUF', `n=${this.param(params, 0, 1)}`);
        this.buffer.cursorForward(this.param(params, 0, 1));
        break;
      case 0x62:
        this.buffer.repeatChar(this.param(params, 0, 1));
        break;
      case 0x63:
        this.onReply('\x1b[?62;22c');
        break;
      case 0x64:
        this.buffer.cursorAbsoluteRow(this.param(params, 0, 1) - 1);
        break;
      case 0x66:
        this.buffer.setCursorPos(this.param(params, 0, 1) - 1, this.param(params, 1, 1) - 1);
        break;
      case 0x6D:
        this.handleSgr(params);
        break;
      case 0x6E:
        this.handleDsr(this.param(params, 0, 0));
        break;
      case 0x72:
        this.buffer.setScrollRegion(this.param(params, 0, 1) - 1, this.param(params, 1, this.buffer.getRows()) - 1);
        break;
      case 0x73:
        this.buffer.saveCursor();
        break;
      case 0x75:
        this.buffer.restoreCursor();
        break;
      default:
        break;
    }
  }

  private dispatchMarked(finalByte: number, params: number[], intermediates: number[]): void {
    const mark = intermediates[0];
    const second = intermediates.length > 1 ? intermediates[1] : 0;
    if (mark === 0x3F && second === 0x24 && finalByte === 0x70) {
      this.replyDecrqm(params);
      return;
    }
    if (mark === 0x3F && intermediates.length === 1 && finalByte === 0x75) {
      this.onReply(`\x1b[?${this.buffer.getKittyFlags()}u`);
      return;
    }
    if (mark === 0x3F && intermediates.length === 1 && (finalByte === 0x68 || finalByte === 0x6C)) {
      const on = finalByte === 0x68;
      const count = params.length === 0 ? 1 : params.length;
      for (let i = 0; i < count; i++) {
        const p = params.length === 0 ? 0 : params[i];
        this.buffer.setDecMode(p, on);
      }
      return;
    }
    if (mark === 0x3E && intermediates.length === 1 && finalByte === 0x63) {
      this.onReply('\x1b[>0;0;0c');
      return;
    }
    if (mark === 0x3E && intermediates.length === 1 && finalByte === 0x71) {
      const ps = params.length === 0 ? 0 : params[0];
      if (ps === 0) {
        this.onReply('\x1bP>|TermArk\x1b\\');
      }
      return;
    }
    if (mark === 0x3E && intermediates.length === 1 && finalByte === 0x75) {
      const flags = params.length === 0 ? 0 : params[0];
      this.buffer.pushKittyFlags(flags);
      return;
    }
    if (mark === 0x3D && intermediates.length === 1 && finalByte === 0x75) {
      const flags = params.length === 0 ? 0 : params[0];
      const mode = params.length < 2 || params[1] === 0 ? 1 : params[1];
      this.buffer.setKittyFlags(flags, mode);
      return;
    }
    if (mark === 0x3C && intermediates.length === 1 && finalByte === 0x75) {
      const n = params.length === 0 || params[0] === 0 ? 1 : params[0];
      this.buffer.popKittyFlags(n);
    }
  }

  private replyDecrqm(params: number[]): void {
    const count = params.length === 0 ? 1 : params.length;
    for (let i = 0; i < count; i++) {
      const ps = params.length === 0 ? 0 : params[i];
      const pm = this.buffer.queryDecMode(ps);
      this.onReply(`\x1b[?${ps};${pm}$y`);
    }
  }

  private handleDsr(kind: number): void {
    if (kind !== 6) {
      return;
    }
    const row = this.buffer.getState().cursorState.row + 1;
    let col = this.buffer.getState().cursorState.col + 1;
    if (this.buffer.isWrapPending()) {
      col = this.buffer.getCols() + 1;
    }
    this.onReply(`\x1b[${row};${col}R`);
  }

  private handleSgr(params: number[]): void {
    if (params.length === 0) {
      this.buffer.resetAttributes();
      return;
    }
    let i: number = 0;
    while (i < params.length) {
      const p: number = params[i];
      if (p === 0) {
        this.buffer.resetAttributes();
      } else if (p === 1) {
        this.buffer.setAttribute('bold', true);
      } else if (p === 2) {
        this.buffer.setAttribute('dim', true);
      } else if (p === 3) {
        this.buffer.setAttribute('italic', true);
      } else if (p === 4) {
        this.buffer.setAttribute('underline', true);
      } else if (p === 5) {
        this.buffer.setAttribute('blink', true);
      } else if (p === 7) {
        this.buffer.setAttribute('inverse', true);
      } else if (p === 8) {
        this.buffer.setAttribute('hidden', true);
      } else if (p === 9) {
        this.buffer.setAttribute('strikethrough', true);
      } else if (p === 22) {
        this.buffer.setAttribute('bold', false);
        this.buffer.setAttribute('dim', false);
      } else if (p === 23) {
        this.buffer.setAttribute('italic', false);
      } else if (p === 24) {
        this.buffer.setAttribute('underline', false);
      } else if (p === 25) {
        this.buffer.setAttribute('blink', false);
      } else if (p === 27) {
        this.buffer.setAttribute('inverse', false);
      } else if (p === 28) {
        this.buffer.setAttribute('hidden', false);
      } else if (p === 29) {
        this.buffer.setAttribute('strikethrough', false);
      } else if (p >= 30 && p <= 37) {
        this.buffer.setFgColor(p - 30);
      } else if (p === 38) {
        i = this.parseColor(params, i, true);
        continue;
      } else if (p === 39) {
        this.buffer.setFgColor(COLOR_DEFAULT_FG);
      } else if (p >= 40 && p <= 47) {
        this.buffer.setBgColor(p - 40);
      } else if (p === 48) {
        i = this.parseColor(params, i, false);
        continue;
      } else if (p === 49) {
        this.buffer.setBgColor(COLOR_DEFAULT_BG);
      } else if (p >= 90 && p <= 97) {
        this.buffer.setFgColor(p - 90 + 8);
      } else if (p >= 100 && p <= 107) {
        this.buffer.setBgColor(p - 100 + 8);
      }
      i++;
    }
  }

  private parseColor(params: number[], i: number, isFg: boolean): number {
    if (i + 1 >= params.length) return i + 1;
    const mode: number = params[i + 1];
    if (mode === 5 && i + 2 < params.length) {
      const idx: number = params[i + 2];
      const color: number = 0x100 | idx;
      if (isFg) {
        this.buffer.setFgColor(color);
      } else {
        this.buffer.setBgColor(color);
      }
      return i + 3;
    }
    if (mode === 2 && i + 4 < params.length) {
      const r: number = params[i + 2];
      const g: number = params[i + 3];
      const b: number = params[i + 4];
      const color: number = 0x1000000 | (r << 16) | (g << 8) | b;
      if (isFg) {
        this.buffer.setFgColor(color);
      } else {
        this.buffer.setBgColor(color);
      }
      return i + 5;
    }
    return i + 1;
  }

  private handleOsc(data: string): void {
    this.buffer.clearRepeat();
    const semiIdx: number = data.indexOf(';');
    if (semiIdx < 0) return;
    const codeStr: string = data.substring(0, semiIdx);
    const code: number = parseInt(codeStr);
    const text: string = data.substring(semiIdx + 1);
    if (code === 0 || code === 2) {
      this.buffer.setTitle(text);
    }
  }
}
