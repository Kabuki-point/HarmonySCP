/**
 * Imperative handle for Terminal component (xterm-style write/focus/clear).
 * Host keeps one instance and passes it to Terminal({ controller }).
 *
 * Buffer/parser live on the controller so write() always parses.
 * The Terminal view registers a render callback; write() does not depend on it.
 */
import { DEC_SYNC_OUTPUT, TerminalBuffer } from '../utils/TerminalBuffer';
import { EscapeSequenceParser } from '../utils/EscapeSequenceParser';
import { InputHandler } from '../utils/InputHandler';

const SYNC_TIMEOUT_MS: number = 100;

export class TerminalUIHooks {
  notifyRender: () => void = () => {};
  focus: () => void = () => {};
  paste: () => void = () => {};
  onTitleChange: (title: string) => void = (_title: string) => {};
}

export class TerminalController {
  private buffer: TerminalBuffer = new TerminalBuffer(80, 24);
  private parser: EscapeSequenceParser = new EscapeSequenceParser();
  private handler: InputHandler;
  private replyFn: (data: string) => void = () => {};
  private notifyRender: (() => void) | null = null;
  private focusFn: (() => void) | null = null;
  private pasteFn: (() => void) | null = null;
  private titleFn: ((title: string) => void) | null = null;
  private titleBridgeInstalled: boolean = false;
  private syncTimer: number = -1;

  constructor() {
    this.handler = new InputHandler(this.buffer, this.parser);
  }

  setReply(fn: (data: string) => void): void {
    this.replyFn = fn;
    this.handler.onReply = fn;
  }

  getBuffer(): TerminalBuffer {
    return this.buffer;
  }

  attachUI(hooks: TerminalUIHooks): void {
    this.notifyRender = hooks.notifyRender;
    this.focusFn = hooks.focus;
    this.pasteFn = hooks.paste;
    this.titleFn = hooks.onTitleChange;
    if (!this.titleBridgeInstalled) {
      this.buffer.onTitleChange((title: string) => {
        if (this.titleFn) {
          this.titleFn(title);
        }
      });
      this.titleBridgeInstalled = true;
    }
  }

  detachUI(): void {
    this.clearSyncTimeout();
    this.notifyRender = null;
    this.focusFn = null;
    this.pasteFn = null;
    this.titleFn = null;
  }

  /** Push host/PTY output into the terminal parser. */
  write(data: string): void {
    if (data.length === 0) {
      return;
    }
    this.parser.parse(data);
    if (this.buffer.isDecMode(DEC_SYNC_OUTPUT)) {
      this.armSyncTimeout();
      return;
    }
    this.clearSyncTimeout();
    this.renderNow();
  }

  private armSyncTimeout(): void {
    this.clearSyncTimeout();
    this.syncTimer = setTimeout(() => {
      this.syncTimer = -1;
      this.renderNow();
    }, SYNC_TIMEOUT_MS) as number;
  }

  private clearSyncTimeout(): void {
    if (this.syncTimer !== -1) {
      clearTimeout(this.syncTimer);
      this.syncTimer = -1;
    }
  }

  private renderNow(): void {
    if (this.notifyRender) {
      this.notifyRender();
    }
  }

  focus(): void {
    if (this.focusFn) {
      this.focusFn();
    }
  }

  clear(): void {
    this.clearSyncTimeout();
    this.buffer.reset();
    if (this.notifyRender) {
      this.notifyRender();
    }
  }

  reset(): void {
    this.clearSyncTimeout();
    this.buffer.reset();
    this.parser = new EscapeSequenceParser();
    this.handler = new InputHandler(this.buffer, this.parser);
    this.handler.onReply = this.replyFn;
    if (this.notifyRender) {
      this.notifyRender();
    }
  }

  paste(): void {
    if (this.pasteFn) {
      this.pasteFn();
    }
  }

  getCols(): number {
    return this.buffer.getCols();
  }

  getRows(): number {
    return this.buffer.getRows();
  }
}
