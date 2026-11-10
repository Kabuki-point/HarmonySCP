import { encodeKey } from '../utils/KeyboardEncoder';
import { DEC_APP_CURSOR, TerminalBuffer } from '../utils/TerminalBuffer';
import { TerminalOptions } from '../models/TerminalOptions';
import { SelectionManager, CellPos, SELECTION_MODE_CELL, SELECTION_MODE_WORD } from '../utils/SelectionManager';
import { TerminalAtlas } from './TerminalAtlas';
import { TerminalKeyboard } from './TerminalKeyboard';
import {
  SelectionUI,
  HANDLE_WIDTH,
  HANDLE_KNOB,
  MENU_HEIGHT,
  MENU_BTN_MIN_W,
  MENU_HANDLE_PAD
} from './SelectionUI';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';

const SCROLLBAR_HIDE_DELAY_MS: number = 1000;
const SCROLLBAR_FADE_MS: number = 250;
const SEL_RELEASE_GUARD_MS: number = 350;
const LOG_DOMAIN: number = 0x0000;
const LOG_SEL: string = 'TermArkSel';
const FONT_SIZE_MIN: number = 8;
const FONT_SIZE_MAX: number = 48;

/**
 * ArkUI KeyEvent.metaKey is ONLY the Meta/Win/Command key (0|1), not a Ctrl bitfield.
 * Use getModifierKeyState for Ctrl/Alt/Shift.
 */
function keyMod(event: KeyEvent, name: string): boolean {
  if (event.getModifierKeyState !== undefined) {
    try {
      return event.getModifierKeyState([name]);
    } catch (_e) {
    }
  }
  return false;
}

/** True when the event came from a mouse (phone/tablet/2in1; incl. mouse→touch conversion). */
function isMouseSource(source: SourceType): boolean {
  return source === SourceType.Mouse;
}

/** Strip C0/DEL from paste; keep TAB/LF/CR, then normalize newlines to CR. */
export function sanitizePasteText(raw: string): string {
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    const code = raw.charCodeAt(i);
    if (code === 0x09 || code === 0x0A || code === 0x0D) {
      out += raw.charAt(i);
      continue;
    }
    if (code < 0x20 || (code >= 0x7F && code <= 0x9F)) {
      continue;
    }
    out += raw.charAt(i);
  }
  return out.replace(/\r\n/g, '\r').replace(/\n/g, '\r');
}

@Component
export struct TerminalViewport {
  buffer: TerminalBuffer | null = null;
  selection: SelectionManager | null = null;
  @Prop @Watch('onRenderTickChange') renderTick: number = 0;
  @Prop @Watch('onOptionsPropChange') options: TerminalOptions = TerminalOptions.create();
  @Prop imeHostId: string = 'termImeHost';
  @Prop showKeyBar: boolean = true;
  @State private selUiTick: number = 0;
  @State private menuHasText: boolean = false;
  @State private uiMode: string = '';
  @State private handleH: number = 36;
  @State private cellWPx: number = 0;
  @State private cellHPx: number = 0;
  @State private viewW: number = 0;
  @State private leftHandleX: number = 0;
  @State private leftHandleY: number = 0;
  @State private rightHandleX: number = 0;
  @State private rightHandleY: number = 0;
  @State private leftHandleVisible: boolean = false;
  @State private rightHandleVisible: boolean = false;
  @State private menuPosX: number = 0;
  @State private menuPosY: number = 0;
  @State private scrollbarOpacity: number = 0;
  @State private selectionOpacity: number = 0;
  @State private selUiPresentSeq: number = 0;
  @State private selUiDismissSeq: number = 0;
  @State private selUiMenuHideSeq: number = 0;
  @State private selUiMenuShowSeq: number = 0;

  @Prop inputEnabled: boolean = false;
  @State private draft: string = '';
  private alive: boolean = false;
  onInput: (data: string) => boolean = () => false;
  onResize: (cols: number, rows: number) => void = () => {};
  onOptionsChange: (options: TerminalOptions) => void = () => {};
  onViewportChange: () => void = () => {};
  onPaste: (text: string) => void = (_text: string) => {};
  onReport: (data: string) => void = () => {};

  private startFontSize: number = 14;
  private pendingPinchFontSize: number = 14;
  /** True while pinching: viewport-only reflow; SSH window-change deferred. */
  private pinching: boolean = false;
  private pendingRemoteCols: number = -1;
  private pendingRemoteRows: number = -1;
  /** PTY size at pinch start — end is a no-op when still equal (e.g. already at min/max). */
  private pinchStartCols: number = -1;
  private pinchStartRows: number = -1;
  /**
   * Pinch ended and final font was applied; wait for measure, then one discard +
   * one window-change (avoids late font step causing a second SIGWINCH).
   */
  private pinchCommitPending: boolean = false;
  private isSelecting: boolean = false;
  private ignoreNextTap: boolean = false;
  private stackX: number = 0;
  private stackY: number = 0;
  private pressX: number = 0;
  private pressY: number = 0;
  private scrollBaseYdisp: number = 0;
  private isScrolling: boolean = false;
  private scrollbarHideTimer: number = -1;
  private mouseHeld: boolean = false;
  /** Local CELL select via mouse drag (when DEC mouse reports are off). */
  private mouseSelecting: boolean = false;
  /** Previous mouse-selection viewport row span for dirty marking. */
  private mouseSelVpTop: number = -1;
  private mouseSelVpBottom: number = -1;
  /** Swallow the synthetic click/tap that follows mouse select release. */
  private swallowMouseClick: boolean = false;
  private mouseCol: number = 1;
  private mouseRow: number = 1;
  private lastMotionCol: number = -1;
  private lastMotionRow: number = -1;
  private wheelAccum: number = 0;
  private lastWheelOffset: number = 0;
  /** DEC mouse: touch may become a click (short tap) or scroll/drag. */
  private pendingMouseClick: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  /** Trackpad pinch via AxisEvent (parallel to touch PinchGesture). */
  private axisPinching: boolean = false;
  /** Swallow synthetic click/tap after long-press until this time. */
  private releaseGuardUntil: number = 0;
  /** A long-press selection gesture is still holding the finger down. */
  private selGestureHeld: boolean = false;
  private selUiDismissing: boolean = false;
  /** Physical modifiers — fallback when getModifierKeyState is unset on tablet/2in1. */
  private ctrlKeyHeld: boolean = false;
  private altKeyHeld: boolean = false;
  private shiftKeyHeld: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.startFontSize = this.options.fontSize;
    this.syncCursorToBuffer();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.draft = '';
    this.clearScrollbarHideTimer();
    this.selUiDismissing = false;
    this.finishDismissSelection();
  }

  onRenderTickChange(): void {
    this.syncHandleLayout();
  }

  onOptionsPropChange(): void {
    // Do not reset startFontSize here — pinch scale is relative to gesture start.
    this.syncCursorToBuffer();
  }

  private syncCursorToBuffer(): void {
    if (!this.buffer) {
      return;
    }
    this.buffer.setCursorShape(this.options.cursorShapeCode());
    this.buffer.setCursorBlinking(this.options.cursorBlink);
  }

  private handleInput(text: string): void {
    if (text.length === 0) {
      return;
    }
    this.onInput(text);
  }

  private trackModifierKeys(event: KeyEvent): boolean {
    const down = event.type === KeyType.Down;
    const code = event.keyCode;
    if (code === KeyCode.KEYCODE_CTRL_LEFT || code === KeyCode.KEYCODE_CTRL_RIGHT) {
      this.ctrlKeyHeld = down;
      return true;
    }
    if (code === KeyCode.KEYCODE_ALT_LEFT || code === KeyCode.KEYCODE_ALT_RIGHT) {
      this.altKeyHeld = down;
      return true;
    }
    if (code === KeyCode.KEYCODE_SHIFT_LEFT || code === KeyCode.KEYCODE_SHIFT_RIGHT) {
      this.shiftKeyHeld = down;
      return true;
    }
    return false;
  }

  private handleHardwareKey(event: KeyEvent): boolean {
    if (this.trackModifierKeys(event) || event.type !== KeyType.Down) {
      return false;
    }
    const kitty = this.buffer ? this.buffer.getKittyFlags() : 0;
    const ctrl = keyMod(event, 'Ctrl') || this.ctrlKeyHeld;
    const alt = keyMod(event, 'Alt') || this.altKeyHeld;
    const shift = keyMod(event, 'Shift') || this.shiftKeyHeld;
    const keyC = event.keyCode === KeyCode.KEYCODE_C ||
      event.keyText === 'C' || event.keyText === 'c';

    // Native editing and the IME own printable keys, paste, and submit.
    if (event.keyCode === KeyCode.KEYCODE_PASTE ||
      (ctrl && !alt && event.keyCode === KeyCode.KEYCODE_V)) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_COPY ||
      (ctrl && !alt && keyC && this.selection !== null && this.selection.hasSelection())) {
      this.handleCopySelection();
      return true;
    }

    if (!ctrl && !alt) {
      switch (event.keyCode) {
        case KeyCode.KEYCODE_DPAD_UP:
        case KeyCode.KEYCODE_DPAD_DOWN:
        case KeyCode.KEYCODE_DPAD_LEFT:
        case KeyCode.KEYCODE_DPAD_RIGHT:
        case KeyCode.KEYCODE_MOVE_HOME:
        case KeyCode.KEYCODE_MOVE_END:
          if (this.draft.length === 0) {
            break;
          }
          return false;
        case KeyCode.KEYCODE_ESCAPE:
        case KeyCode.KEYCODE_TAB:
        case KeyCode.KEYCODE_PAGE_UP:
        case KeyCode.KEYCODE_PAGE_DOWN:
          break;
        default:
          if (event.keyCode < KeyCode.KEYCODE_F1 || event.keyCode > KeyCode.KEYCODE_F12) {
            return false;
          }
      }
    }

    // Always pass real modifiers; encodeKey chooses legacy CSI mods vs kitty CSI-u.
    switch (event.keyCode) {
      case KeyCode.KEYCODE_DPAD_UP:
        this.sendNamed('up', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_DPAD_DOWN:
        this.sendNamed('down', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_DPAD_LEFT:
        this.sendNamed('left', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        this.sendNamed('right', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_ESCAPE:
        this.sendNamed('esc', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_TAB:
        this.sendNamed('tab', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_SPACE:
        this.sendNamed('space', ' ', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_DEL:
        this.sendNamed('backspace', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        this.sendNamed('enter', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_PAGE_UP:
        this.sendNamed('pgup', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_PAGE_DOWN:
        this.sendNamed('pgdn', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_MOVE_HOME:
        this.sendNamed('home', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_MOVE_END:
        this.sendNamed('end', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_FORWARD_DEL:
        this.sendNamed('delete', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F1:
        this.sendNamed('f1', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F2:
        this.sendNamed('f2', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F3:
        this.sendNamed('f3', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F4:
        this.sendNamed('f4', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F5:
        this.sendNamed('f5', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F6:
        this.sendNamed('f6', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F7:
        this.sendNamed('f7', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F8:
        this.sendNamed('f8', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F9:
        this.sendNamed('f9', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F10:
        this.sendNamed('f10', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F11:
        this.sendNamed('f11', '', ctrl, alt, shift);
        return true;
      case KeyCode.KEYCODE_F12:
        this.sendNamed('f12', '', ctrl, alt, shift);
        return true;
      default:
        if (event.unicode !== undefined && event.unicode >= 1 && event.unicode <= 26) {
          const letter = String.fromCharCode(0x60 + event.unicode);
          this.sendNamed('char', letter, true, alt, shift);
          return true;
        }
        if (event.unicode !== undefined && event.unicode >= 32) {
          if (kitty !== 0 || ctrl || alt) {
            this.sendNamed('char', String.fromCodePoint(event.unicode), ctrl, alt, shift);
          } else {
            this.handleInput(String.fromCodePoint(event.unicode));
          }
          return true;
        }
        return false;
    }
  }

  private sendNamed(name: string, text: string, ctrl: boolean, alt: boolean, shift: boolean): void {
    if (!this.buffer) {
      return;
    }
    const seq = encodeKey(
      name,
      text,
      ctrl,
      alt,
      shift,
      this.buffer.isDecMode(DEC_APP_CURSOR),
      this.buffer.getKittyFlags()
    );
    this.handleInput(seq);
  }

  private submitDraft(text: string): void {
    if (this.inputEnabled && this.onInput(text + '\r')) {
      this.draft = '';
    }
  }

  private handlePinchStart(): void {
    this.pinching = true;
    this.pinchCommitPending = false;
    this.pendingRemoteCols = -1;
    this.pendingRemoteRows = -1;
    this.startFontSize = this.options.fontSize;
    this.pendingPinchFontSize = this.startFontSize;
    this.pinchStartCols = this.buffer ? this.buffer.getCols() : -1;
    this.pinchStartRows = this.buffer ? this.buffer.getRows() : -1;
  }

  private handlePinchUpdate(scale: number): void {
    if (!this.pinching) {
      return;
    }
    const newFontSize = Math.round(this.startFontSize * scale);
    const clamped = Math.max(FONT_SIZE_MIN, Math.min(FONT_SIZE_MAX, newFontSize));
    this.pendingPinchFontSize = clamped;
    // Live font; buffer uses viewport-only reflow while pinching (see onResize).
    if (clamped !== this.options.fontSize) {
      this.onOptionsChange(this.options.withFontSize(clamped));
    }
  }

  private handlePinchEnd(): void {
    if (!this.pinching) {
      return;
    }
    const finalFont = this.pendingPinchFontSize;
    this.pinching = false;
    this.pendingRemoteCols = -1;
    this.pendingRemoteRows = -1;

    // Apply final font once; discard + one window-change run after measure settles.
    if (finalFont !== this.options.fontSize) {
      this.pinchCommitPending = true;
      this.onOptionsChange(this.options.withFontSize(finalFont));
      return;
    }
    this.finishPinchCommit();
  }

  /** After final pinch font has been measured (or font already final). */
  private finishPinchCommit(): void {
    this.pinchCommitPending = false;
    const curCols = this.buffer ? this.buffer.getCols() : -1;
    const curRows = this.buffer ? this.buffer.getRows() : -1;
    const sizeChanged =
      curCols > 0 &&
      curRows > 0 &&
      (curCols !== this.pinchStartCols || curRows !== this.pinchStartRows);
    if (!sizeChanged) {
      this.rebuildMainDisplay(false);
      return;
    }
    this.rebuildMainDisplay(true);
    if (this.buffer) {
      this.buffer.markExpectResizeRedraw();
    }
    this.onResize(curCols, curRows);
  }

  private rebuildMainDisplay(clearInput: boolean): void {
    if (!this.buffer) {
      return;
    }
    this.buffer.rebuildFromLogic(clearInput);
    this.onViewportChange();
  }

  private handlePinchCancel(): void {
    this.pinching = false;
    this.pinchCommitPending = false;
    this.axisPinching = false;
    this.pendingRemoteCols = -1;
    this.pendingRemoteRows = -1;
    this.pendingPinchFontSize = this.options.fontSize;
    this.pinchStartCols = -1;
    this.pinchStartRows = -1;
    this.rebuildMainDisplay(false);
  }

  private emitRemoteResize(cols: number, rows: number): void {
    if (this.pinching) {
      this.pendingRemoteCols = cols;
      this.pendingRemoteRows = rows;
      return;
    }
    if (this.pinchCommitPending) {
      // Final font measure produced a new grid — one discard + one WC.
      this.finishPinchCommit();
      return;
    }
    if (this.buffer) {
      this.buffer.markExpectResizeRedraw();
    }
    this.onResize(cols, rows);
  }

  private handleTapForSelection(x: number, y: number, count: number): void {
    // When DEC mouse is on, press/release already go through onTouch / onMouse.
    if (this.mouseReports()) {
      return;
    }
    if (count === 1 && this.uiMode.length > 0) {
      this.dismissSelection();
      return;
    }
    if (!this.buffer || !this.selection) {
      return;
    }
    const cell = this.pointToCell(x, y);
    if (!cell) {
      this.dismissSelection();
      return;
    }
    if (count === 2) {
      this.beginWordSelection(cell);
      return;
    }
    this.dismissSelection();
  }

  private armSelectionGesture(): void {
    // Swallow finger-up click/tap noise after long-press; real exit is the next tap.
    // The window restarts on finger-up, so holding longer than it does not exit.
    this.selGestureHeld = true;
    this.releaseGuardUntil = Date.now() + SEL_RELEASE_GUARD_MS;
  }

  /** Swallow the synthetic click/tap that follows long-press finger-up. */
  private consumeSelectionRelease(): boolean {
    // Mouse drag: Touch Up + onClick often fire BEFORE MouseAction.Release.
    // While the button gesture is still open, never treat click as "dismiss".
    if (this.mouseSelecting) {
      hilog.info(LOG_DOMAIN, LOG_SEL, 'consumeRelease SWALLOW mouseSelecting ui=%{public}s', this.uiMode);
      return true;
    }
    // After mouse release: swallow synthetic click/tap for the guard window.
    if (this.swallowMouseClick) {
      if (Date.now() < this.releaseGuardUntil) {
        hilog.info(LOG_DOMAIN, LOG_SEL,
          'consumeRelease SWALLOW post-release remain=%{public}d',
          this.releaseGuardUntil - Date.now());
        return true;
      }
      hilog.info(LOG_DOMAIN, LOG_SEL, 'consumeRelease post-release guard done → allow dismiss');
      this.swallowMouseClick = false;
      return false;
    }
    if (Date.now() >= this.releaseGuardUntil) {
      return false;
    }
    hilog.info(LOG_DOMAIN, LOG_SEL, 'consumeRelease SWALLOW touch-guard ui=%{public}s', this.uiMode);
    this.isSelecting = false;
    this.ignoreNextTap = false;
    return true;
  }

  private handleLongPress(x: number, y: number): void {
    // DEC mouse: long-press starts a drag (htop process select); not local selection.
    if (this.mouseReports()) {
      this.pendingMouseClick = false;
      this.pressMouse(x, y);
      return;
    }
    if (!this.buffer || !this.selection) {
      return;
    }
    this.pressX = x;
    this.pressY = y;
    this.armSelectionGesture();
    const cell = this.pointToCell(x, y);
    if (!cell) {
      this.showPasteUi();
      return;
    }
    const absRow = this.buffer.absRowFromViewport(cell.row);
    if (this.selection.isCursorCell(cell.col, absRow) || !this.selection.cellHasText(cell.col, absRow)) {
      this.showPasteUi();
      return;
    }
    this.beginWordSelection(cell);
    // Keep dragging arm so Sequence(LongPress→Pan) can still extend the range.
    this.isSelecting = true;
  }

  private beginWordSelection(cell: CellPos): void {
    if (!this.selection) {
      return;
    }
    this.selection.startSelection(cell.col, cell.row, SELECTION_MODE_WORD);
    if (!this.selection.hasSelection()) {
      this.showPasteUi();
      return;
    }
    this.uiMode = 'select';
    this.menuHasText = true;
    this.isSelecting = false;
    this.presentSelectionUi();
  }

  /**
   * Mouse-only actions (not touch): left-drag CELL select without handles/menu,
   * copy on release, right-click paste into the PTY.
   */
  private handleMouse(event: MouseEvent): void {
    if (this.mouseReports()) {
      const x = event.x;
      const y = event.y;
      if (event.action === MouseAction.Press && event.button === MouseButton.Left) {
        this.pressMouse(x, y);
      } else if (event.action === MouseAction.Move) {
        if (this.mouseHeld) {
          this.moveMouse(x, y);
        }
      } else if (event.action === MouseAction.Release && event.button === MouseButton.Left) {
        this.releaseMouse();
      }
      return;
    }
    this.handleMouseAction(event);
  }

  private handleMouseAction(event: MouseEvent): void {
    const x = event.x;
    const y = event.y;
    if (event.action === MouseAction.Press) {
      if (event.button === MouseButton.Right) {
        hilog.info(LOG_DOMAIN, LOG_SEL, 'mouse RIGHT press');
        this.handleMouseRightPaste();
        return;
      }
      if (event.button !== MouseButton.Left || !this.buffer || !this.selection) {
        return;
      }
      const cell = this.pointToCell(x, y);
      if (!cell) {
        return;
      }
      this.pressX = x;
      this.pressY = y;
      hilog.info(LOG_DOMAIN, LOG_SEL, 'mouse LEFT press cell=%{public}d,%{public}d', cell.col, cell.row);
      this.beginMouseSelection(cell);
      return;
    }
    if (event.action === MouseAction.Move) {
      if (this.mouseSelecting) {
        this.updateMouseSelection(x, y);
      }
      return;
    }
    if (event.action === MouseAction.Release && event.button === MouseButton.Left) {
      hilog.info(LOG_DOMAIN, LOG_SEL,
        'mouse LEFT release selecting=%{public}s ui=%{public}s hasSel=%{public}s',
        String(this.mouseSelecting), this.uiMode,
        String(this.selection !== null && this.selection.hasSelection()));
      if (!this.mouseSelecting) {
        return;
      }
      this.endMouseSelection();
    }
  }

  private beginMouseSelection(cell: CellPos): void {
    if (!this.selection) {
      return;
    }
    this.selection.startSelection(cell.col, cell.row, SELECTION_MODE_CELL);
    this.uiMode = 'mouse';
    this.menuHasText = false;
    this.isSelecting = true;
    this.mouseSelecting = true;
    // Do not arm a short time-guard on Press: drag often exceeds it, and
    // onClick/TouchUp arrive before Mouse Release while mouseSelecting is still true.
    this.swallowMouseClick = false;
    this.leftHandleVisible = false;
    this.rightHandleVisible = false;
    // Single-cell press must not paint a selection; wait until span >= 2.
    this.selectionOpacity = 0;
    this.mouseSelVpTop = -1;
    this.mouseSelVpBottom = -1;
    hilog.info(LOG_DOMAIN, LOG_SEL,
      'beginMouse sel active=%{public}s opacity=%{public}s',
      String(this.selection.hasSelection()), String(this.selectionOpacity));
  }

  private mouseSelectionCellCount(): number {
    if (!this.selection || !this.buffer || !this.selection.hasSelection()) {
      return 0;
    }
    const range = this.selection.getNormalizedSelection();
    if (!range) {
      return 0;
    }
    const cols = this.buffer.getCols();
    const lo = range.start.row * cols + range.start.col;
    const hi = range.end.row * cols + range.end.col;
    return hi - lo + 1;
  }

  /** Visible viewport rows covered by the current selection, or null if none on screen. */
  private selectionViewportRowSpan(): number[] | null {
    if (!this.selection || !this.buffer || !this.selection.hasSelection()) {
      return null;
    }
    const range = this.selection.getNormalizedSelection();
    if (!range) {
      return null;
    }
    const rows = this.buffer.getRows();
    let top = this.buffer.viewportRowFromAbs(range.start.row);
    let bottom = this.buffer.viewportRowFromAbs(range.end.row);
    if (bottom < top) {
      const tmp = top;
      top = bottom;
      bottom = tmp;
    }
    if (bottom < 0 || top >= rows) {
      return null;
    }
    return [Math.max(0, top), Math.min(rows - 1, bottom)];
  }

  private markMouseSelectionDirty(): void {
    if (!this.buffer) {
      return;
    }
    if (this.mouseSelVpTop >= 0 && this.mouseSelVpBottom >= this.mouseSelVpTop) {
      this.buffer.markRowsDirty(this.mouseSelVpTop, this.mouseSelVpBottom);
    }
    const span = this.selectionViewportRowSpan();
    if (span) {
      this.buffer.markRowsDirty(span[0], span[1]);
      this.mouseSelVpTop = span[0];
      this.mouseSelVpBottom = span[1];
    } else {
      this.mouseSelVpTop = -1;
      this.mouseSelVpBottom = -1;
    }
  }

  private syncMouseSelectionVisibility(): void {
    const count = this.mouseSelectionCellCount();
    const show = count >= 2;
    this.selectionOpacity = show ? 1 : 0;
    this.leftHandleVisible = false;
    this.rightHandleVisible = false;
  }

  /** Selection-only repaint: mark dirty rows + frame bump, skip handle/menu layout. */
  private bumpMouseSelectionRender(): void {
    this.markMouseSelectionDirty();
    this.onViewportChange();
  }

  private updateMouseSelection(x: number, y: number): void {
    if (!this.selection || !this.mouseSelecting) {
      return;
    }
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    this.selection.updateSelection(cell.col, cell.row);
    this.syncMouseSelectionVisibility();
    this.bumpMouseSelectionRender();
  }

  private endMouseSelection(): void {
    this.mouseSelecting = false;
    this.isSelecting = false;
    // Arm after Release so the late onClick/Tap (already seen before Release in
    // some orders, or still pending) cannot dismiss the kept selection.
    this.swallowMouseClick = true;
    this.releaseGuardUntil = Date.now() + SEL_RELEASE_GUARD_MS;
    const count = this.mouseSelectionCellCount();
    const has = this.selection !== null && this.selection.hasSelection();
    const textLen = has && this.selection ? this.selection.getSelectedText().length : 0;
    hilog.info(LOG_DOMAIN, LOG_SEL,
      'endMouse cells=%{public}d hasSel=%{public}s textLen=%{public}d ui=%{public}s',
      count, String(has), textLen, this.uiMode);
    // Click or one-cell drag: no visible selection, clear tracking.
    if (count < 2) {
      this.swallowMouseClick = false;
      hilog.info(LOG_DOMAIN, LOG_SEL, 'endMouse DISMISS reason=span-lt-2');
      this.finishDismissSelection();
      return;
    }
    const text = this.selection!.getSelectedText();
    if (text.length === 0) {
      hilog.info(LOG_DOMAIN, LOG_SEL, 'endMouse keep empty-text multi-cell');
      return;
    }
    this.writePasteboard(text, () => {
      hilog.info(LOG_DOMAIN, LOG_SEL, 'endMouse copy done keep selection');
    });
  }

  private handleMouseRightPaste(): void {
    if (this.mouseSelecting || this.uiMode === 'mouse') {
      this.finishDismissSelection();
    }
    this.showPasteUi();
  }

  private showPasteUi(): void {
    hilog.info(LOG_DOMAIN, LOG_SEL, 'showPasteUi from ui=%{public}s', this.uiMode);
    if (this.selection) {
      this.selection.clearSelection();
    }
    this.uiMode = 'paste';
    this.menuHasText = false;
    this.isSelecting = false;
    this.leftHandleVisible = false;
    this.rightHandleVisible = false;
    this.presentSelectionUi();
  }

  private presentSelectionUi(): void {
    this.selUiDismissing = false;
    this.bumpSelectionUi();
    this.selUiPresentSeq = this.selUiPresentSeq + 1;
  }

  private fadeSelectionMenuIn(): void {
    this.selUiMenuShowSeq = this.selUiMenuShowSeq + 1;
  }

  private fadeSelectionMenuOut(): void {
    this.selUiMenuHideSeq = this.selUiMenuHideSeq + 1;
  }

  private handleSelectionPan(x: number, y: number): void {
    if (this.mouseHeld) {
      this.moveMouse(x, y);
      return;
    }
    if ((!this.isSelecting && this.uiMode !== 'select') || !this.selection) {
      return;
    }
    if (this.uiMode === 'mouse' || this.mouseSelecting) {
      hilog.info(LOG_DOMAIN, LOG_SEL,
        'selectionPan ui=%{public}s isSelecting=%{public}s mouseSel=%{public}s',
        this.uiMode, String(this.isSelecting), String(this.mouseSelecting));
    }
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    this.selection.updateSelection(cell.col, cell.row);
    if (!this.selection.hasSelection()) {
      hilog.info(LOG_DOMAIN, LOG_SEL, 'selectionPan → showPasteUi (no sel after update)');
      this.showPasteUi();
      return;
    }
    if (this.uiMode === 'mouse') {
      hilog.info(LOG_DOMAIN, LOG_SEL, 'selectionPan OVERWRITE ui mouse→select');
    }
    this.uiMode = 'select';
    this.fadeSelectionMenuOut();
    this.bumpSelectionUi();
  }

  private handleSelectionPanEnd(): void {
    if (this.mouseHeld) {
      this.releaseMouse();
    }
    this.isSelecting = false;
    if (this.uiMode === 'select' && this.selection && this.selection.hasSelection()) {
      this.menuHasText = this.selection.getSelectedText().length > 0;
      this.fadeSelectionMenuIn();
    }
    this.bumpSelectionUi();
  }

  private writePasteboard(text: string, after: () => void): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      after();
    }).catch((_err: BusinessError) => {
    });
  }

  private handleCopySelection(): void {
    if (!this.selection || !this.selection.hasSelection()) {
      return;
    }
    const text = this.selection.getSelectedText();
    if (text.length === 0) {
      return;
    }
    this.writePasteboard(text, () => {
      this.dismissSelection();
    });
  }

  private handleCutSelection(): void {
    if (!this.selection || !this.selection.hasSelection() || !this.buffer) {
      return;
    }
    const text = this.selection.getSelectedText();
    if (text.length === 0) {
      return;
    }
    const range = this.selection.getNormalizedSelection();
    const cursorAbs = this.buffer.getCursorAbsRow();
    const onCursorLine = range !== null &&
      range.start.row <= cursorAbs &&
      range.end.row >= cursorAbs;
    let del = '';
    if (onCursorLine) {
      for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i);
        if (ch !== '\n' && ch !== '\r') {
          del += '\x7f';
        }
      }
    }
    this.writePasteboard(text, () => {
      if (del.length > 0) {
        this.handleInput(del);
      }
      this.dismissSelection();
    });
  }

  private dismissSelection(): void {
    hilog.info(LOG_DOMAIN, LOG_SEL,
      'dismissSelection ui=%{public}s opacity=%{public}f dismissing=%{public}s',
      this.uiMode, this.selectionOpacity, String(this.selUiDismissing));
    if (this.selUiDismissing) {
      return;
    }
    if (this.uiMode.length === 0 && this.selectionOpacity <= 0) {
      this.finishDismissSelection();
      return;
    }
    this.selUiDismissing = true;
    this.releaseGuardUntil = 0;
    this.ignoreNextTap = false;
    this.isSelecting = false;
    this.mouseSelecting = false;
    this.swallowMouseClick = false;
    if (this.selectionOpacity <= 0.01) {
      this.finishDismissSelection();
      return;
    }
    this.selUiDismissSeq = this.selUiDismissSeq + 1;
  }

  private finishDismissSelection(): void {
    hilog.info(LOG_DOMAIN, LOG_SEL, 'finishDismissSelection was ui=%{public}s', this.uiMode);
    if (this.buffer && this.mouseSelVpTop >= 0 && this.mouseSelVpBottom >= this.mouseSelVpTop) {
      this.buffer.markRowsDirty(this.mouseSelVpTop, this.mouseSelVpBottom);
    }
    this.selUiDismissing = false;
    if (this.selection) {
      this.selection.clearSelection();
    }
    this.uiMode = '';
    this.isSelecting = false;
    this.mouseSelecting = false;
    this.swallowMouseClick = false;
    this.mouseSelVpTop = -1;
    this.mouseSelVpBottom = -1;
    this.releaseGuardUntil = 0;
    this.ignoreNextTap = false;
    this.leftHandleVisible = false;
    this.rightHandleVisible = false;
    this.selectionOpacity = 0;
    this.bumpSelectionUi();
  }

  private bumpSelectionUi(): void {
    this.selUiTick = this.selUiTick + 1;
    this.syncHandleLayout();
    this.onViewportChange();
  }

  private syncHandleLayout(): void {
    this.leftHandleVisible = false;
    this.rightHandleVisible = false;
    this.handleH = this.cellHVp() + HANDLE_KNOB;
    if (this.uiMode === 'select') {
      const range = this.selection ? this.selection.getNormalizedSelection() : null;
      if (range) {
        const start = this.viewportCellTop(range.start.col, range.start.row);
        if (start) {
          // Knob sits above the start cell (top-left).
          this.leftHandleX = start.col - HANDLE_WIDTH / 2;
          this.leftHandleY = start.row - HANDLE_KNOB;
          this.leftHandleVisible = true;
        }
        const end = this.viewportCellTop(range.end.col, range.end.row);
        if (end) {
          // Knob sits below the end cell (bottom-right).
          this.rightHandleX = end.col + this.cellWVp() - HANDLE_WIDTH / 2;
          this.rightHandleY = end.row;
          this.rightHandleVisible = true;
        }
      }
    }
    this.syncMenuLayout();
  }

  private syncMenuLayout(): void {
    let x = this.pressX;
    let y = this.pressY + 24;
    const btnCount = this.uiMode === 'select' && this.menuHasText ? 3 : 1;
    const width = btnCount * MENU_BTN_MIN_W + (btnCount - 1) * 8 + 24;
    const cellH = this.cellHVp();
    if (this.uiMode === 'paste') {
      const cursor = this.cursorCellTop();
      if (cursor) {
        x = cursor.col + this.cellWVp() / 2 - width / 2;
        y = cursor.row - MENU_HEIGHT - MENU_HANDLE_PAD;
        if (y < 8) {
          y = cursor.row + cellH + MENU_HANDLE_PAD;
        }
      }
    } else {
      const range = this.selection ? this.selection.getNormalizedSelection() : null;
      if (range) {
        const start = this.viewportCellTop(range.start.col, range.start.row);
        const end = this.viewportCellTop(range.end.col, range.end.row);
        if (start && end) {
          const left = Math.min(start.col, end.col);
          const right = Math.max(start.col + this.cellWVp(), end.col + this.cellWVp());
          x = (left + right) / 2 - width / 2;
          // Keep clear of the top-left handle knob above the selection.
          const handleTop = Math.min(start.row, end.row) - HANDLE_KNOB;
          y = handleTop - MENU_HEIGHT - MENU_HANDLE_PAD;
          if (y < 8) {
            // Fall below the bottom-right handle knob.
            const handleBottom = Math.max(start.row, end.row) + cellH + HANDLE_KNOB;
            y = handleBottom + MENU_HANDLE_PAD;
          }
        }
      }
    }
    if (this.viewW > 0) {
      x = Math.max(8, Math.min(x, this.viewW - width - 8));
    }
    if (y < 8) {
      y = 8;
    }
    this.menuPosX = x;
    this.menuPosY = y;
  }

  private pointToCell(x: number, y: number): CellPos | null {
    if (!this.buffer || this.cellWPx <= 0 || this.cellHPx <= 0) {
      return null;
    }
    const xPx = this.getUIContext().vp2px(x);
    const yPx = this.getUIContext().vp2px(y);
    if (xPx < 0 || yPx < 0) {
      return null;
    }
    const cols = this.buffer.getCols();
    const rows = this.buffer.getRows();
    const col = Math.floor(xPx / this.cellWPx);
    const row = Math.floor(yPx / this.cellHPx);
    if (col < 0 || row < 0 || col >= cols || row >= rows) {
      return null;
    }
    return new CellPos(col, row);
  }

  private viewportCellTop(col: number, absRow: number): CellPos | null {
    if (!this.buffer || this.cellWPx <= 0 || this.cellHPx <= 0) {
      return null;
    }
    const vpRow = this.buffer.viewportRowFromAbs(absRow);
    const rows = this.buffer.getRows();
    if (vpRow < 0 || vpRow >= rows) {
      return null;
    }
    const xPx = col * this.cellWPx;
    const yPx = vpRow * this.cellHPx;
    return new CellPos(this.getUIContext().px2vp(xPx), this.getUIContext().px2vp(yPx));
  }

  private cursorCellTop(): CellPos | null {
    if (!this.buffer) {
      return null;
    }
    const vpRow = this.buffer.getCursorViewportRow();
    if (vpRow < 0) {
      return null;
    }
    return this.viewportCellTop(this.buffer.getState().cursorState.col, this.buffer.getCursorAbsRow());
  }

  private handleStartMoved(event: GestureEvent): void {
    if (!this.selection || event.fingerList.length === 0) {
      return;
    }
    const x = event.fingerList[0].globalX - this.stackX;
    const y = event.fingerList[0].globalY - this.stackY;
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    this.selection.moveStartHandle(cell.col, cell.row);
    if (!this.selection.hasSelection()) {
      this.showPasteUi();
      return;
    }
    this.uiMode = 'select';
    this.fadeSelectionMenuOut();
    this.bumpSelectionUi();
  }

  private handleEndMoved(event: GestureEvent): void {
    if (!this.selection || event.fingerList.length === 0) {
      return;
    }
    const x = event.fingerList[0].globalX - this.stackX;
    const y = event.fingerList[0].globalY - this.stackY;
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    this.selection.moveEndHandle(cell.col, cell.row);
    if (!this.selection.hasSelection()) {
      this.showPasteUi();
      return;
    }
    this.uiMode = 'select';
    this.fadeSelectionMenuOut();
    this.bumpSelectionUi();
  }

  private handleHandlePanEnd(): void {
    if (this.selection && this.selection.hasSelection()) {
      this.menuHasText = this.selection.getSelectedText().length > 0;
      this.fadeSelectionMenuIn();
    }
    this.bumpSelectionUi();
  }

  private cellHVp(): number {
    if (this.cellHPx <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(this.cellHPx);
  }

  private cellWVp(): number {
    if (this.cellWPx <= 0) {
      return 0;
    }
    return this.getUIContext().px2vp(this.cellWPx);
  }

  private handleScrollPanStart(): void {
    if (this.mouseReports()) {
      this.pendingMouseClick = false;
      this.wheelAccum = 0;
      this.lastWheelOffset = 0;
      return;
    }
    hilog.info(LOG_DOMAIN, LOG_SEL,
      'scrollPanStart ui=%{public}s isSelecting=%{public}s mouseSel=%{public}s',
      this.uiMode, String(this.isSelecting), String(this.mouseSelecting));
    if (this.uiMode === 'select') {
      this.isSelecting = true;
      this.fadeSelectionMenuOut();
      return;
    }
    if (!this.buffer || this.isSelecting) {
      return;
    }
    this.isScrolling = true;
    this.scrollBaseYdisp = this.buffer.getYdisp();
    this.showScrollbar();
  }

  private handleScrollPan(offsetY: number, x: number, y: number): void {
    if (this.mouseReports()) {
      this.handleWheel(offsetY, x, y);
      return;
    }
    if (this.uiMode === 'select' || this.isSelecting) {
      if (this.uiMode === 'mouse' || this.mouseSelecting) {
        hilog.info(LOG_DOMAIN, LOG_SEL,
          'scrollPan→selectionPan ui=%{public}s isSelecting=%{public}s',
          this.uiMode, String(this.isSelecting));
      }
      this.handleSelectionPan(x, y);
      return;
    }
    if (!this.buffer || !this.isScrolling) {
      return;
    }
    const cellH = this.cellHVp();
    if (cellH <= 0) {
      return;
    }
    // Finger down → reveal older lines → decrease ydisp.
    const rowsDelta = Math.round(offsetY / cellH);
    this.buffer.setYdisp(this.scrollBaseYdisp - rowsDelta);
    this.showScrollbar();
    this.onViewportChange();
  }

  private handleScrollPanEnd(): void {
    hilog.info(LOG_DOMAIN, LOG_SEL,
      'scrollPanEnd ui=%{public}s isSelecting=%{public}s mouseSel=%{public}s',
      this.uiMode, String(this.isSelecting), String(this.mouseSelecting));
    if (this.uiMode === 'select' || this.isSelecting) {
      this.handleSelectionPanEnd();
      return;
    }
    this.isScrolling = false;
    this.scheduleHideScrollbar();
  }

  private mouseReports(): boolean {
    return this.buffer !== null && this.buffer.mouseReports();
  }

  private sendClick(x: number, y: number): void {
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    this.sendSgr(0, cell.col, cell.row, false);
    this.sendSgr(0, cell.col, cell.row, true);
  }

  private pressMouse(x: number, y: number): void {
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    this.mouseHeld = true;
    this.mouseCol = cell.col;
    this.mouseRow = cell.row;
    this.lastMotionCol = cell.col;
    this.lastMotionRow = cell.row;
    this.sendSgr(0, cell.col, cell.row, false);
  }

  private moveMouse(x: number, y: number): void {
    if (!this.buffer || !this.buffer.mouseDrag()) {
      return;
    }
    const cell = this.pointToCell(x, y);
    if (!cell) {
      return;
    }
    if (cell.col === this.lastMotionCol && cell.row === this.lastMotionRow) {
      return;
    }
    this.mouseCol = cell.col;
    this.mouseRow = cell.row;
    this.lastMotionCol = cell.col;
    this.lastMotionRow = cell.row;
    this.sendSgr(32, cell.col, cell.row, false);
  }

  private releaseMouse(): void {
    if (!this.mouseHeld) {
      return;
    }
    this.mouseHeld = false;
    this.sendSgr(0, this.mouseCol, this.mouseRow, true);
  }

  /**
   * Mouse wheel / trackpad: scroll history (or DEC mouse wheel), Ctrl+wheel or
   * trackpad pinch → font zoom (same path as PinchGesture).
   */
  private handleAxis(event: AxisEvent): void {
    if (!this.buffer) {
      return;
    }
    if (event.action === AxisAction.END || event.action === AxisAction.CANCEL) {
      this.wheelAccum = 0;
      if (this.axisPinching) {
        if (event.action === AxisAction.CANCEL) {
          this.handlePinchCancel();
        } else {
          this.handlePinchEnd();
        }
        this.axisPinching = false;
      }
      return;
    }

    let pinchScale = 0;
    try {
      pinchScale = event.getPinchAxisScaleValue();
    } catch (_e) {
      pinchScale = 0;
    }
    if (pinchScale > 0) {
      if (!this.axisPinching) {
        this.axisPinching = true;
        this.handlePinchStart();
      }
      this.handlePinchUpdate(pinchScale);
      return;
    }

    const delta = event.getVerticalAxisValue();
    if (delta === 0) {
      return;
    }
    const cellH = this.cellHVp();
    if (cellH <= 0) {
      return;
    }

    // Ctrl+wheel → zoom font (2in1 / trackpad with mouse).
    if (this.ctrlKeyHeld) {
      const steps = delta > 0 ? -1 : 1;
      const next = Math.max(FONT_SIZE_MIN, Math.min(FONT_SIZE_MAX, this.options.fontSize + steps));
      if (next !== this.options.fontSize) {
        this.handlePinchStart();
        this.pendingPinchFontSize = next;
        this.onOptionsChange(this.options.withFontSize(next));
        this.handlePinchEnd();
      }
      return;
    }

    if (this.mouseReports()) {
      const cell = this.pointToCell(event.x, event.y);
      const col = cell ? cell.col : 0;
      const row = cell ? cell.row : 0;
      this.wheelAccum += delta;
      while (this.wheelAccum >= cellH) {
        this.wheelAccum -= cellH;
        this.sendSgr(65, col, row, false);
      }
      while (this.wheelAccum <= -cellH) {
        this.wheelAccum += cellH;
        this.sendSgr(64, col, row, false);
      }
      return;
    }

    let rows = Math.round(delta / cellH);
    if (rows === 0) {
      rows = delta > 0 ? 1 : -1;
    }
    this.buffer.setYdisp(this.buffer.getYdisp() + rows);
    this.showScrollbar();
    this.onViewportChange();
    this.scheduleHideScrollbar();
  }

  private handleWheel(offsetY: number, x: number, y: number): void {
    const cellH = this.cellHVp();
    if (cellH <= 0) {
      return;
    }
    const delta = offsetY - this.lastWheelOffset;
    this.lastWheelOffset = offsetY;
    this.wheelAccum += delta;
    const cell = this.pointToCell(x, y);
    const col = cell ? cell.col : 0;
    const row = cell ? cell.row : 0;
    while (this.wheelAccum >= cellH) {
      this.wheelAccum -= cellH;
      this.sendSgr(64, col, row, false);
    }
    while (this.wheelAccum <= -cellH) {
      this.wheelAccum += cellH;
      this.sendSgr(65, col, row, false);
    }
  }

  private sendSgr(button: number, col: number, row: number, release: boolean): void {
    const final = release ? 'm' : 'M';
    this.onReport(`\x1b[<${button};${col + 1};${row + 1}${final}`);
  }

  private showScrollbar(): void {
    if (!this.buffer || this.buffer.getYbase() === 0) {
      return;
    }
    this.clearScrollbarHideTimer();
    this.scrollbarOpacity = 1;
  }

  private scheduleHideScrollbar(): void {
    this.clearScrollbarHideTimer();
    if (this.scrollbarOpacity <= 0) {
      return;
    }
    this.scrollbarHideTimer = setTimeout(() => {
      this.scrollbarHideTimer = -1;
      this.getUIContext().animateTo({ duration: SCROLLBAR_FADE_MS, curve: Curve.EaseOut }, () => {
        this.scrollbarOpacity = 0;
      });
    }, SCROLLBAR_HIDE_DELAY_MS) as number;
  }

  private clearScrollbarHideTimer(): void {
    if (this.scrollbarHideTimer !== -1) {
      clearTimeout(this.scrollbarHideTimer);
      this.scrollbarHideTimer = -1;
    }
  }

  // Called only after a system PasteButton grants temporary read access.
  private pasteFromClipboard(): void {
    pasteboard.getSystemPasteboard().getData().then((data: pasteboard.PasteData) => {
      if (this.alive && this.inputEnabled) {
        this.onPaste(sanitizePasteText(data.getPrimaryText()));
        this.dismissSelection();
      }
    }).catch((_err: BusinessError) => {});
  }

  build() {
    Column() {
      Stack() {
        TerminalAtlas({
          buffer: this.buffer,
          selection: this.selection,
          renderTick: this.renderTick,
          fontSize: this.options.fontSize,
          fontFamily: this.options.fontFamily,
          lineHeight: this.options.lineHeight,
          theme: this.options.theme,
          cursorStyle: this.options.cursorStyle,
          cursorBlink: this.options.cursorBlink,
          scrollbarOpacity: this.scrollbarOpacity,
          selectionOpacity: this.selectionOpacity,
          onResize: (cols: number, rows: number) => {
            if (this.buffer) {
              // Pinch: viewport-tail wrap from logical history; always clear input.
              this.buffer.resize(cols, rows, this.pinching);
            }
            this.emitRemoteResize(cols, rows);
          },
          onMeasureSettled: (_cols: number, _rows: number) => {
            if (this.pinchCommitPending) {
              this.finishPinchCommit();
            }
          },
          onCellMetrics: (cellWPx: number, cellHPx: number) => {
            if (this.cellWPx !== cellWPx || this.cellHPx !== cellHPx) {
              this.cellWPx = cellWPx;
              this.cellHPx = cellHPx;
              this.syncHandleLayout();
            }
          }
        })
          .width('100%')
          .height('100%');

        SelectionUI({
          presentSeq: this.selUiPresentSeq,
          dismissSeq: this.selUiDismissSeq,
          menuHideSeq: this.selUiMenuHideSeq,
          menuShowSeq: this.selUiMenuShowSeq,
          uiMode: this.uiMode,
          menuHasText: this.menuHasText,
          leftHandleVisible: this.leftHandleVisible,
          rightHandleVisible: this.rightHandleVisible,
          handleH: this.handleH,
          leftHandleX: this.leftHandleX,
          leftHandleY: this.leftHandleY,
          rightHandleX: this.rightHandleX,
          rightHandleY: this.rightHandleY,
          menuPosX: this.menuPosX,
          menuPosY: this.menuPosY,
          selectionOpacity: $selectionOpacity,
          onCut: () => {
            this.handleCutSelection();
          },
          onCopy: () => {
            this.handleCopySelection();
          },
          onPaste: () => {
            this.pasteFromClipboard();
          },
          onStartHandleMoved: (event: GestureEvent) => {
            this.handleStartMoved(event);
          },
          onEndHandleMoved: (event: GestureEvent) => {
            this.handleEndMoved(event);
          },
          onHandlePanEnd: () => {
            this.handleHandlePanEnd();
          },
          onDismissed: () => {
            this.finishDismissSelection();
          }
        })
          .width('100%')
          .height('100%');
      }
      .layoutWeight(1)
      .width('100%')
      .clip(true)
      .backgroundColor(this.options.theme.background)
      .onClick(() => {
        const swallowed = this.consumeSelectionRelease();
        hilog.info(LOG_DOMAIN, LOG_SEL,
          'onClick swallow=%{public}s ui=%{public}s', String(swallowed), this.uiMode);
        if (swallowed) {
          return;
        }
        if (this.uiMode.length > 0) {
          hilog.info(LOG_DOMAIN, LOG_SEL, 'onClick → dismissSelection');
          this.dismissSelection();
          return;
        }
      })
      .onTouch((event: TouchEvent) => {
        // htop / DEC mouse: short tap → click; pan → wheel (existing PanGesture);
        // long-press hold → drag via pressMouse + moveMouse.
        if (this.mouseReports()) {
          const t = event.touches.length > 0 ? event.touches[0] :
            (event.changedTouches.length > 0 ? event.changedTouches[0] : null);
          if (t === null) {
            return;
          }
          if (event.type === TouchType.Down) {
            this.pendingMouseClick = true;
            this.touchStartX = t.x;
            this.touchStartY = t.y;
            return;
          }
          if (event.type === TouchType.Move) {
            if (this.mouseHeld) {
              this.moveMouse(t.x, t.y);
              return;
            }
            if (this.pendingMouseClick) {
              const dx = t.x - this.touchStartX;
              const dy = t.y - this.touchStartY;
              if (dx * dx + dy * dy > 64) {
                this.pendingMouseClick = false;
              }
            }
            return;
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            if (this.pendingMouseClick) {
              this.pendingMouseClick = false;
              this.sendClick(this.touchStartX, this.touchStartY);
            } else if (this.mouseHeld) {
              this.releaseMouse();
            }
            return;
          }
          return;
        }
        if (event.type !== TouchType.Up && event.type !== TouchType.Cancel) {
          return;
        }
        hilog.info(LOG_DOMAIN, LOG_SEL,
          'onTouch Up/Cancel ui=%{public}s mouseSel=%{public}s',
          this.uiMode, String(this.mouseSelecting));
        if (this.selGestureHeld) {
          this.selGestureHeld = false;
          this.releaseGuardUntil = Date.now() + SEL_RELEASE_GUARD_MS;
        }
        if (this.mouseHeld) {
          this.releaseMouse();
        }
      })
      .onMouse((event: MouseEvent) => {
        this.handleMouse(event);
      })
      .onAxisEvent((event: AxisEvent) => {
        this.handleAxis(event);
      })
      .onAreaChange((_oldVal: Area, newVal: Area) => {
        this.viewW = newVal.width as number;
        this.stackX = newVal.globalPosition.x as number;
        this.stackY = newVal.globalPosition.y as number;
      })
      // On phone/tablet/2in1, mouse left-click/drag may be converted to touch, but
      // SourceType stays Mouse. Reject touch gestures so only onMouse handles select/paste.
      .onGestureJudgeBegin((_gestureInfo: GestureInfo, event: BaseGestureEvent) => {
        if (isMouseSource(event.source)) {
          hilog.info(LOG_DOMAIN, LOG_SEL, 'gestureJudge REJECT mouse');
          return GestureJudgeResult.REJECT;
        }
        return GestureJudgeResult.CONTINUE;
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2 })
            .onActionStart((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              this.handlePinchStart();
            })
            .onActionUpdate((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              this.handlePinchUpdate(event.scale);
            })
            .onActionEnd((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              this.handlePinchEnd();
            })
            .onActionCancel((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              this.handlePinchCancel();
            }),
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false })
              .onAction((event: GestureEvent) => {
                if (isMouseSource(event.source)) {
                  hilog.info(LOG_DOMAIN, LOG_SEL, 'longPress IGNORED mouse');
                  return;
                }
                if (event.fingerList.length > 0) {
                  this.handleLongPress(event.fingerList[0].localX, event.fingerList[0].localY);
                }
              }),
            PanGesture()
              .onActionUpdate((event: GestureEvent) => {
                if (isMouseSource(event.source)) {
                  return;
                }
                if (event.fingerList.length === 0) {
                  return;
                }
                const lx = event.fingerList[0].localX;
                const ly = event.fingerList[0].localY;
                if (this.mouseReports()) {
                  this.moveMouse(lx, ly);
                  return;
                }
                this.handleSelectionPan(lx, ly);
              })
              .onActionEnd((event: GestureEvent) => {
                if (isMouseSource(event.source)) {
                  return;
                }
                if (this.mouseReports()) {
                  return;
                }
                this.handleSelectionPanEnd();
              })
          ),
          PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionStart((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              this.handleScrollPanStart();
            })
            .onActionUpdate((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              const x = event.fingerList.length > 0 ? event.fingerList[0].localX : 0;
              const y = event.fingerList.length > 0 ? event.fingerList[0].localY : 0;
              this.handleScrollPan(event.offsetY, x, y);
            })
            .onActionEnd((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              this.handleScrollPanEnd();
            }),
          TapGesture({ count: 2 })
            .onAction((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                return;
              }
              if (event.fingerList.length > 0) {
                this.handleTapForSelection(event.fingerList[0].localX, event.fingerList[0].localY, 2);
              }
            }),
          TapGesture({ count: 1 })
            .onAction((event: GestureEvent) => {
              if (isMouseSource(event.source)) {
                hilog.info(LOG_DOMAIN, LOG_SEL, 'tap1 IGNORED mouse');
                return;
              }
              const swallowed = this.consumeSelectionRelease();
              hilog.info(LOG_DOMAIN, LOG_SEL,
                'tap1 swallow=%{public}s ui=%{public}s', String(swallowed), this.uiMode);
              if (swallowed) {
                return;
              }
              if (this.uiMode.length > 0) {
                hilog.info(LOG_DOMAIN, LOG_SEL, 'tap1 → dismissSelection');
                this.dismissSelection();
                return;
              }
              if (event.fingerList.length > 0) {
                this.handleTapForSelection(event.fingerList[0].localX, event.fingerList[0].localY, 1);
              }
            })
        )
      );

      if (this.showKeyBar) {
        TerminalKeyboard({
          onSend: (data: string) => {
            this.handleInput(data);
          },
          onKey: (name: string, text: string, ctrl: boolean, alt: boolean, shift: boolean) => {
            this.sendNamed(name, text, ctrl, alt, shift);
          }
        })
      }
      Row({ space: 8 }) {
        TextInput({ text: this.draft, placeholder: '输入文本或命令' })
          .id(this.imeHostId)
          .layoutWeight(1)
          .maxLength(4095)
          .enterKeyType(EnterKeyType.Send)
          .enabled(this.inputEnabled)
          .onChange((value: string) => { this.draft = value; })
          .onSubmit((_key: EnterKeyType, event: SubmitEvent) => {
            event.keepEditableState();
            this.submitDraft(event.text);
          })
          .onKeyEvent((event: KeyEvent) => {
            const handled = this.handleHardwareKey(event);
            if (handled) {
              event.stopPropagation();
            }
            return handled;
          })
          .onBlur(() => {
            this.ctrlKeyHeld = false;
            this.altKeyHeld = false;
            this.shiftKeyHeld = false;
          })
        Button('发送')
          .enabled(this.inputEnabled)
          .onClick(() => this.submitDraft(this.draft))
        PasteButton()
          .enabled(this.inputEnabled)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result === PasteButtonOnClickResult.SUCCESS) {
              this.pasteFromClipboard();
            }
          })
      }
      .width('100%')
      .padding(8)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'));
  }
}
