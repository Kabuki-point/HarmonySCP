import { DEC_BRACKETED_PASTE } from '../utils/TerminalBuffer';
import { SelectionManager } from '../utils/SelectionManager';
import { TerminalOptions } from '../models/TerminalOptions';
import { TerminalController, TerminalUIHooks } from './TerminalController';
import { TerminalViewport } from './TerminalViewport';
import { FrameCallback } from '@kit.ArkUI';

class RenderFrame extends FrameCallback {
  run: () => void = (): void => {};

  onFrame(_frameTimeInNano: number): void {
    this.run();
  }

  onIdle(_timeLeftInNano: number): void {
  }
}

let terminalInstanceCounter: number = 0;

@Component
export struct Terminal {
  controller: TerminalController = new TerminalController();
  @Prop @Watch('onOptionsPropChange') options: TerminalOptions = TerminalOptions.create();
  @Prop showKeyBar: boolean = true;
  @State renderTick: number = 0;

  @Prop inputEnabled: boolean = false;
  onData: (data: string) => boolean = () => false;
  onResize: (cols: number, rows: number) => void = () => {};
  onTitleChange: (title: string) => void = () => {};
  onOptionsChange: (options: TerminalOptions) => void = () => {};

  private selection: SelectionManager | null = null;
  private imeHostId: string = 'termImeHost';

  private frameQueued: boolean = false;
  private alive: boolean = true;
  private frame: RenderFrame = new RenderFrame();

  aboutToAppear(): void {
    this.alive = true;
    terminalInstanceCounter++;
    this.imeHostId = `termIme-${terminalInstanceCounter}`;
    this.selection = new SelectionManager(this.controller.getBuffer());
    this.frame.run = (): void => {
      this.frameQueued = false;
      if (!this.alive) {
        return;
      }
      this.renderTick = this.renderTick + 1;
    };
    this.applyOptionsToBuffer(this.options);
    this.attachControllerUI();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.controller.setReply(() => {});
    this.controller.detachUI();
  }

  onOptionsPropChange(): void {
    this.applyOptionsToBuffer(this.options);
  }

  /**
   * Same pattern as the old TerminalPage.handleInput: a method on the
   * @Component that owns @State renderTick. ArkUI will not reliably refresh
   * @State when it is mutated from a lambda stored on TerminalController.
   */
  private bumpRender(): void {
    if (!this.alive || this.frameQueued) {
      return;
    }
    this.frameQueued = true;
    this.getUIContext().postFrameCallback(this.frame);
  }

  private attachControllerUI(): void {
    const hooks = new TerminalUIHooks();
    hooks.notifyRender = () => {
      this.bumpRender();
    };
    hooks.focus = () => {
      focusControl.requestFocus(this.imeHostId);
    };
    hooks.onTitleChange = (title: string) => {
      this.onTitleChange(title);
    };
    this.controller.attachUI(hooks);
    this.controller.setReply((data: string) => {
      this.onData(data);
    });
  }

  private applyOptionsToBuffer(opts: TerminalOptions): void {
    const buffer = this.controller.getBuffer();
    buffer.setCursorShape(opts.cursorShapeCode());
    buffer.setCursorBlinking(opts.cursorBlink);
  }

  private handleUserInput(data: string): boolean {
    if (!this.inputEnabled || data.length === 0 || !this.onData(data)) {
      return false;
    }
    const buffer = this.controller.getBuffer();
    buffer.setYdisp(buffer.getYbase());
    this.bumpRender();
    return true;
  }

  private emitPasteText(text: string): void {
    if (text.length === 0) {
      return;
    }
    const buffer = this.controller.getBuffer();
    if (buffer.isDecMode(DEC_BRACKETED_PASTE)) {
      this.handleUserInput(`\x1b[200~${text}\x1b[201~`);
    } else {
      this.handleUserInput(text);
    }
  }

  private handleResize(cols: number, rows: number): void {
    this.onResize(cols, rows);
    this.bumpRender();
  }

  build() {
    TerminalViewport({
      buffer: this.controller.getBuffer(),
      selection: this.selection,
      renderTick: this.renderTick,
      options: this.options,
      imeHostId: this.imeHostId,
      showKeyBar: this.showKeyBar,
      inputEnabled: this.inputEnabled,
      onInput: (data: string) => this.handleUserInput(data),
      onResize: (cols: number, rows: number) => {
        this.handleResize(cols, rows);
      },
      onOptionsChange: (next: TerminalOptions) => {
        this.onOptionsChange(next);
      },
      onPaste: (text: string) => {
        this.emitPasteText(text);
      },
      onReport: (data: string) => {
        if (data.length > 0) {
          this.onData(data);
        }
      },
      onViewportChange: () => {
        this.bumpRender();
      }
    })
      .width('100%')
      .height('100%');
  }
}
