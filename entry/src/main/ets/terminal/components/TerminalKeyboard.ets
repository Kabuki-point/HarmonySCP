import { classifySequence } from '../utils/KeyboardEncoder';
import {
  KeyboardBarKey,
  LETTER_ROW1,
  LETTER_ROW2,
  LETTER_ROW3,
  LetterAltPair,
  defaultCtrlSlotKey,
  defaultDotSlotKey,
  defaultKeyboardBarKeys,
  defaultLetterAltPairs,
  defaultPipeSlotKey,
  defaultCommaSlotKey,
  getKeyboardBarLive,
  hydrateKeyboardBarLive,
  isEmptySlotKey,
  isKeyboardBarLiveReady,
  letterAltOf,
  setKeyboardBarLiveListener
} from '../models/KeyboardBarConfig';
import { LengthMetrics, display } from '@kit.ArkUI';

const KEY_BG: Resource = $r('sys.color.comp_background_tertiary');
const KEY_BG_MOD: Resource = $r('sys.color.comp_background_secondary');
const KEY_BG_ON: Resource = $r('sys.color.brand');
const KEY_TEXT: Resource = $r('sys.color.font_primary');
const KBD_BG: Resource = $r('sys.color.background_primary');
const KEY_H: number = 42;
const BAR_H: number = 42;
const BAR_KEY_H: number = 32;
const BAR_KEY_W: number = 36;
const TAB_KEY_W: number = 52;
const TAB_MOD_W: number = 66;
const TAB_SPACE_W: number = 110;
const PHONE_KEYS_H: number = 200;
const SPLIT_KEYS_H: number = 248;
const FOLD_ANIM_MS: number = 220;
const PHONE_KEY_INSET: number = 4;
const TAB_KEY_INSET: number = 20;
const TABLET_MIN_VP: number = 840;

class KeyboardActions {
  emitChar: (ch: string) => void = (_ch: string) => {};
  emitSeq: (seq: string) => void = (_seq: string) => {};
  toggleShift: () => void = () => {};
  toggleCtrl: () => void = () => {};
  toggleAlt: () => void = () => {};
  backspace: () => void = () => {};
  enter: () => void = () => {};
  space: () => void = () => {};
  barKey: (id: string) => void = (_id: string) => {};
  toggleFold: () => void = () => {};
}

@Component
struct TermKeyCap {
  @Prop label: string = '';
  @Prop capId: string = '';
  @Prop kind: string = 'char';
  @Prop keyWeight: number = 1;
  @Prop emphasize: boolean = false;
  @Prop active: boolean = false;
  @Prop symbolName: string = '';
  @Prop capHeight: number = KEY_H;
  @Prop capWidth: number = 0;
  @Prop hintText: string = '';
  @State popupOn: boolean = false;
  @State hoverAlt: boolean = false;
  actions: KeyboardActions = new KeyboardActions();
  private longPressed: boolean = false;
  private pressedByTouch: boolean = false;

  private capBg(): ResourceColor {
    if (this.kind === 'fold') {
      return Color.Transparent;
    }
    if (this.active) {
      return KEY_BG_ON;
    }
    return this.emphasize ? KEY_BG_MOD : KEY_BG;
  }

  private glyphSize(): number {
    return this.capHeight <= BAR_KEY_H ? 15 : 18;
  }

  private labelSize(): number {
    if (this.capHeight <= BAR_KEY_H) {
      return this.label.length > 1 ? 11 : 14;
    }
    return this.label.length > 1 ? 13 : 18;
  }

  private hintSize(): number {
    return this.capHeight <= BAR_KEY_H ? 7 : 9;
  }

  private hint(): string {
    return this.hintText;
  }

  private alts(): string[] {
    if (this.hintText.length === 0) {
      return [];
    }
    return [this.hintText];
  }

  private pickAlt(ch: string): void {
    this.popupOn = false;
    this.hoverAlt = false;
    this.longPressed = false;
    this.actions.emitChar(ch);
  }

  private touchY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return event.touches[0].y;
    }
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0].y;
    }
    return 0;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedByTouch = false;
      return;
    }
    if (event.type === TouchType.Move && this.popupOn) {
      const over = this.touchY(event) < 0;
      if (over !== this.hoverAlt) {
        this.hoverAlt = over;
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.popupOn && this.hoverAlt && this.hint().length > 0) {
        this.pickAlt(this.hint());
        this.pressedByTouch = true;
        return;
      }
      const tapped = event.type === TouchType.Up && !this.longPressed;
      this.popupOn = false;
      this.hoverAlt = false;
      this.longPressed = false;
      if (tapped) {
        this.pressedByTouch = true;
        this.pressKey();
      }
    }
  }

  private pressKey(): void {
    if (this.longPressed) {
      return;
    }
    if (this.kind === 'empty') {
      return;
    }
    if (this.kind === 'char') {
      this.actions.emitChar(this.capId);
    } else if (this.kind === 'seq') {
      this.actions.emitSeq(this.capId);
    } else if (this.kind === 'shift') {
      this.actions.toggleShift();
    } else if (this.kind === 'backspace') {
      this.actions.backspace();
    } else if (this.kind === 'enter') {
      this.actions.enter();
    } else if (this.kind === 'space') {
      this.actions.space();
    } else if (this.kind === 'ctrl') {
      this.actions.toggleCtrl();
    } else if (this.kind === 'alt') {
      this.actions.toggleAlt();
    } else if (this.kind === 'bar') {
      this.actions.barKey(this.capId);
    } else if (this.kind === 'fold') {
      this.actions.toggleFold();
    }
  }

  @Builder
  AltPopup() {
    Row({ space: 4 }) {
      ForEach(this.alts(), (ch: string) => {
        Text(ch)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(KEY_TEXT)
          .textAlign(TextAlign.Center)
          .width(36)
          .height(40)
          .backgroundColor(this.hoverAlt ? KEY_BG_ON : KEY_BG)
          .borderRadius(6)
      }, (ch: string) => ch)
    }
    .padding(6)
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.symbolName === 'arrowshape_up_frame_fill') {
          SymbolGlyph($r('sys.symbol.arrowshape_up_frame_fill'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrowshape_up_fill') {
          SymbolGlyph($r('sys.symbol.arrowshape_up_fill'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrowshape_up') {
          SymbolGlyph($r('sys.symbol.arrowshape_up'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'delete_left') {
          SymbolGlyph($r('sys.symbol.delete_left'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'checkmark') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrowshape_down_to_line_fill') {
          SymbolGlyph($r('sys.symbol.arrowshape_down_to_line_fill'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrow_up') {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrow_down') {
          SymbolGlyph($r('sys.symbol.arrow_down'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrow_left') {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'arrow_right') {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.symbolName === 'space_1') {
          SymbolGlyph($r('sys.symbol.space_1'))
            .fontSize(this.glyphSize())
            .fontColor([KEY_TEXT])
        } else if (this.hint().length > 0) {
          Column() {
            Text(this.hint())
              .fontSize(this.hintSize())
              .fontColor($r('sys.color.font_secondary'))
              .height(this.capHeight <= BAR_KEY_H ? 10 : 12)
            Text(this.label)
              .fontSize(this.capHeight <= BAR_KEY_H ? 13 : 16)
              .fontWeight(FontWeight.Medium)
              .fontColor(KEY_TEXT)
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
        } else {
          Text(this.label)
            .fontSize(this.labelSize())
            .fontWeight(FontWeight.Medium)
            .fontColor(KEY_TEXT)
        }
      }
      .width('100%')
      .height('100%')
    }
      .height(this.capHeight)
      .width(this.capWidth > 0 ? this.capWidth : 'auto')
      .layoutWeight(this.capWidth > 0 ? 0 : this.keyWeight)
      .flexShrink(0)
      .backgroundColor(this.capBg())
      .borderRadius(this.kind === 'fold' ? 0 : 6)
      .padding(0)
      .margin(this.kind === 'fold' ? { left: 0, right: 3 } : { left: 3, right: 3 })
      .stateEffect(this.kind !== 'fold')
      .focusable(false)
      .onClick(() => {
        if (this.pressedByTouch) {
          return;
        }
        this.pressKey();
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            if (this.alts().length > 0) {
              this.longPressed = true;
              this.hoverAlt = false;
              this.popupOn = true;
            }
          })
      )
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
      })
      .responseRegion(this.popupOn ?
        { x: 0, y: -52, width: '100%', height: 94 } :
        { x: 0, y: 0, width: '100%', height: '100%' })
      .bindPopup(this.popupOn, {
        builder: this.AltPopup(),
        placement: Placement.Top,
        popupColor: $r('sys.color.comp_background_list_card'),
        backgroundBlurStyle: BlurStyle.NONE,
        enableArrow: true,
        autoCancel: true,
        radius: 10,
        onStateChange: (event) => {
          this.popupOn = event.isVisible;
          if (!event.isVisible) {
            this.hoverAlt = false;
          }
        }
      })
  }
}

@Component
export struct TerminalKeyboard {
  onSend: (data: string) => void = () => {};
  onKey: (name: string, text: string, ctrl: boolean, alt: boolean, shift: boolean) => void = () => {};
  @State barKeys: KeyboardBarKey[] = defaultKeyboardBarKeys();
  @State shiftOn: boolean = false;
  @State capsLock: boolean = false;
  @State ctrlOn: boolean = false;
  @State altOn: boolean = false;
  @State keysExpanded: boolean = false;
  @State keysVisible: boolean = false;
  @State keysPanelH: number = 0;
  @State splitKeys: boolean = false;
  @State letterAlts: LetterAltPair[] = defaultLetterAltPairs();
  @State ctrlSlot: KeyboardBarKey = defaultCtrlSlotKey();
  @State dotSlot: KeyboardBarKey = defaultDotSlotKey();
  @State pipeSlot: KeyboardBarKey = defaultPipeSlotKey();
  @State commaSlot: KeyboardBarKey = defaultCommaSlotKey();
  private actions: KeyboardActions = new KeyboardActions();
  private viewWidth: number = 0;
  private foldStatusCallback = (_status: display.FoldStatus): void => {
    this.refreshSplitKeys();
  };

  aboutToAppear(): void {
    this.actions.emitChar = (ch: string) => {
      this.emitChar(ch);
    };
    this.actions.emitSeq = (seq: string) => {
      const name = classifySequence('', seq);
      const text = name === 'text' ? seq : '';
      this.emitNamed(name, text, true);
    };
    this.actions.toggleShift = () => {
      this.toggleShift();
    };
    this.actions.toggleCtrl = () => {
      this.ctrlOn = !this.ctrlOn;
    };
    this.actions.toggleAlt = () => {
      this.altOn = !this.altOn;
    };
    this.actions.backspace = () => {
      this.emitNamed('backspace', '', true);
    };
    this.actions.enter = () => {
      this.emitNamed('enter', '', true);
    };
    this.actions.space = () => {
      this.emitNamed('space', ' ', true);
    };
    this.actions.barKey = (id: string) => {
      this.handleBarKey(id);
    };
    this.actions.toggleFold = () => {
      this.toggleKeysFold();
    };
    setKeyboardBarLiveListener(() => {
      this.applyLiveSnapshot();
    });
    this.reloadBarKeys();
    this.refreshSplitKeys();
    try {
      display.on('foldStatusChange', this.foldStatusCallback);
    } catch (_e) {
    }
  }

  aboutToDisappear(): void {
    setKeyboardBarLiveListener(() => {});
    try {
      display.off('foldStatusChange', this.foldStatusCallback);
    } catch (_e) {
    }
  }

  private refreshSplitKeys(): void {
    let foldOpen = false;
    try {
      foldOpen = display.isFoldable() &&
        display.getFoldStatus() === display.FoldStatus.FOLD_STATUS_EXPANDED;
    } catch (_e) {
    }
    this.splitKeys = this.viewWidth >= TABLET_MIN_VP || foldOpen;
    if (this.keysExpanded) {
      this.keysPanelH = this.expandedKeysHeight();
    }
  }

  private expandedKeysHeight(): number {
    return this.splitKeys ? SPLIT_KEYS_H : PHONE_KEYS_H;
  }

  private toggleKeysFold(): void {
    if (this.keysExpanded) {
      this.keysVisible = false;
      this.getUIContext().animateTo({ duration: FOLD_ANIM_MS, curve: Curve.EaseOut }, () => {
        this.keysExpanded = false;
        this.keysPanelH = 0;
      });
      return;
    }
    this.keysVisible = false;
    this.getUIContext().animateTo({
      duration: FOLD_ANIM_MS,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (this.keysExpanded) {
          this.keysVisible = true;
        }
      }
    }, () => {
      this.keysExpanded = true;
      this.keysPanelH = this.expandedKeysHeight();
    });
  }

  private applyLiveSnapshot(): void {
    const snap = getKeyboardBarLive();
    this.barKeys = snap.keys;
    this.letterAlts = snap.letterAlts;
    this.ctrlSlot = snap.ctrlSlot;
    this.dotSlot = snap.dotSlot;
    this.pipeSlot = snap.pipeSlot;
    this.commaSlot = snap.commaSlot;
  }

  private async reloadBarKeys(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined && !isKeyboardBarLiveReady()) {
      await hydrateKeyboardBarLive(ctx);
    }
    this.applyLiveSnapshot();
  }

  private letterHint(ch: string): string {
    return letterAltOf(this.letterAlts, ch);
  }

  private letterLabel(ch: string): string {
    if (this.shiftOn || this.capsLock) {
      return ch.toUpperCase();
    }
    return ch;
  }

  private emitRaw(seq: string): void {
    if (seq.length === 0) {
      return;
    }
    this.onSend(seq);
  }

  private emitNamed(name: string, text: string, clearMods: boolean): void {
    this.onKey(name, text, this.ctrlOn, this.altOn, this.shiftOn || this.capsLock);
    if (!clearMods) {
      return;
    }
    this.ctrlOn = false;
    this.altOn = false;
    if (!this.capsLock) {
      this.shiftOn = false;
    }
  }

  private emitChar(ch: string): void {
    this.emitNamed('char', ch, true);
  }

  private toggleShift(): void {
    if (this.shiftOn && !this.capsLock) {
      this.capsLock = true;
      this.shiftOn = true;
      return;
    }
    if (this.capsLock) {
      this.capsLock = false;
      this.shiftOn = false;
      return;
    }
    this.shiftOn = true;
  }

  private findBarKey(id: string): KeyboardBarKey | undefined {
    for (let i = 0; i < this.barKeys.length; i++) {
      if (this.barKeys[i].id === id) {
        return this.barKeys[i];
      }
    }
    return undefined;
  }

  private handleBarKey(id: string): void {
    let key = this.findBarKey(id);
    if (!key && this.ctrlSlot.id === id) {
      key = this.ctrlSlot;
    }
    if (!key && this.dotSlot.id === id) {
      key = this.dotSlot;
    }
    if (!key && this.pipeSlot.id === id) {
      key = this.pipeSlot;
    }
    if (!key && this.commaSlot.id === id) {
      key = this.commaSlot;
    }
    if (!key || isEmptySlotKey(key)) {
      return;
    }
    if (key.sticky === 'ctrl') {
      this.ctrlOn = !this.ctrlOn;
      return;
    }
    if (key.sticky === 'alt') {
      this.altOn = !this.altOn;
      return;
    }
    if (key.sticky === 'shift') {
      this.toggleShift();
      return;
    }
    if (key.id === 'interrupt') {
      this.emitRaw(key.sequence);
      return;
    }
    const name = classifySequence(key.id, key.sequence);
    const text = name === 'text' ? key.sequence : '';
    this.emitNamed(name, text, true);
  }

  private barActive(key: KeyboardBarKey): boolean {
    if (key.sticky === 'ctrl') {
      return this.ctrlOn;
    }
    if (key.sticky === 'alt') {
      return this.altOn;
    }
    if (key.sticky === 'shift') {
      return this.shiftOn || this.capsLock;
    }
    return false;
  }

  private barSymbolName(key: KeyboardBarKey): string {
    if (key.id === 'up') {
      return 'arrow_up';
    }
    if (key.id === 'down') {
      return 'arrow_down';
    }
    if (key.id === 'left') {
      return 'arrow_left';
    }
    if (key.id === 'right') {
      return 'arrow_right';
    }
    return '';
  }

  private slotKind(key: KeyboardBarKey): string {
    if (isEmptySlotKey(key)) {
      return 'empty';
    }
    if (key.sticky === 'ctrl') {
      return 'ctrl';
    }
    if (key.sticky === 'alt') {
      return 'alt';
    }
    if (key.sticky === 'shift') {
      return 'shift';
    }
    if (key.sequence.length === 1) {
      return 'char';
    }
    if (key.sequence.length > 0) {
      return 'seq';
    }
    return 'bar';
  }

  private slotCapId(key: KeyboardBarKey): string {
    const kind = this.slotKind(key);
    if (kind === 'char' || kind === 'seq') {
      return key.sequence;
    }
    return key.id;
  }

  private slotLabel(key: KeyboardBarKey): string {
    if (isEmptySlotKey(key)) {
      return '';
    }
    return key.label;
  }

  private slotActive(key: KeyboardBarKey): boolean {
    return this.barActive(key);
  }

  private slotEmphasize(key: KeyboardBarKey, base: boolean): boolean {
    if (base) {
      return true;
    }
    const sticky = key.sticky;
    if (!sticky) {
      return false;
    }
    return sticky.length > 0;
  }

  private shiftSymbolName(): string {
    if (this.capsLock) {
      return 'arrowshape_up_frame_fill';
    }
    if (this.shiftOn) {
      return 'arrowshape_up_fill';
    }
    return 'arrowshape_up';
  }

  private keyInset(): number {
    return this.splitKeys ? TAB_KEY_INSET : PHONE_KEY_INSET;
  }

  private foldSymbolName(): string {
    if (this.keysExpanded) {
      return 'arrowshape_down_to_line_fill';
    }
    return 'arrowshape_up';
  }

  @Builder
  LetterRow(chars: string[], prefix: string) {
    Row() {
      ForEach(chars, (ch: string) => {
        TermKeyCap({
          label: this.letterLabel(ch),
          capId: ch,
          kind: 'char',
          capHeight: KEY_H,
          capWidth: TAB_KEY_W,
          hintText: this.letterHint(ch),
          actions: this.actions
        })
      }, (ch: string) => `${prefix}-${ch}`)
    }
    .padding({ top: 6 })
  }

  @Builder
  PhoneKeys() {
    Column() {
      Row() {
        ForEach(LETTER_ROW1, (ch: string) => {
          TermKeyCap({
            label: this.letterLabel(ch),
            capId: ch,
            kind: 'char',
            hintText: this.letterHint(ch),
            actions: this.actions
          })
        }, (ch: string) => `r1-${ch}`)
      }
      .width('100%')
      .padding({ left: PHONE_KEY_INSET, right: PHONE_KEY_INSET, top: 4 })

      Row() {
        Blank().width(10)
        ForEach(LETTER_ROW2, (ch: string) => {
          TermKeyCap({
            label: this.letterLabel(ch),
            capId: ch,
            kind: 'char',
            hintText: this.letterHint(ch),
            actions: this.actions
          })
        }, (ch: string) => `r2-${ch}`)
        Blank().width(10)
      }
      .width('100%')
      .padding({ left: PHONE_KEY_INSET, right: PHONE_KEY_INSET, top: 6 })

      Row() {
        TermKeyCap({
          kind: 'shift',
          keyWeight: 1.25,
          emphasize: true,
          active: this.shiftOn || this.capsLock,
          symbolName: this.shiftSymbolName(),
          actions: this.actions
        })
        ForEach(LETTER_ROW3, (ch: string) => {
          TermKeyCap({
            label: this.letterLabel(ch),
            capId: ch,
            kind: 'char',
            hintText: this.letterHint(ch),
            actions: this.actions
          })
        }, (ch: string) => `r3-${ch}`)
        TermKeyCap({
          kind: 'backspace',
          keyWeight: 1.25,
          emphasize: true,
          symbolName: 'delete_left',
          actions: this.actions
        })
      }
      .width('100%')
      .padding({ left: PHONE_KEY_INSET, right: PHONE_KEY_INSET, top: 6 })

      Row() {
        TermKeyCap({
          label: this.slotLabel(this.ctrlSlot),
          capId: this.slotCapId(this.ctrlSlot),
          kind: this.slotKind(this.ctrlSlot),
          keyWeight: 1.3,
          emphasize: true,
          active: this.slotActive(this.ctrlSlot),
          symbolName: this.barSymbolName(this.ctrlSlot),
          hintText: this.letterHint('ctrl'),
          actions: this.actions
        })
        TermKeyCap({
          label: this.slotLabel(this.dotSlot),
          capId: this.slotCapId(this.dotSlot),
          kind: this.slotKind(this.dotSlot),
          keyWeight: 1.0,
          emphasize: this.slotEmphasize(this.dotSlot, false),
          active: this.slotActive(this.dotSlot),
          symbolName: this.barSymbolName(this.dotSlot),
          hintText: this.letterHint('.'),
          actions: this.actions
        })
        TermKeyCap({
          kind: 'space',
          keyWeight: 3.2,
          symbolName: 'space_1',
          actions: this.actions
        })
        TermKeyCap({
          label: this.slotLabel(this.pipeSlot),
          capId: this.slotCapId(this.pipeSlot),
          kind: this.slotKind(this.pipeSlot),
          keyWeight: 1.0,
          emphasize: this.slotEmphasize(this.pipeSlot, false),
          active: this.slotActive(this.pipeSlot),
          symbolName: this.barSymbolName(this.pipeSlot),
          hintText: this.letterHint('|'),
          actions: this.actions
        })
        TermKeyCap({
          kind: 'enter',
          keyWeight: 1.4,
          emphasize: true,
          symbolName: 'checkmark',
          actions: this.actions
        })
      }
      .width('100%')
      .padding({ left: PHONE_KEY_INSET, right: PHONE_KEY_INSET, top: 6, bottom: 10 })
    }
    .width('100%')
  }

  @Builder
  SplitKeys() {
    Row() {
      Column() {
        this.LetterRow(['q', 'w', 'e', 'r', 't'], 'sl1')
        this.LetterRow(['a', 's', 'd', 'f', 'g'], 'sl2')
        Row() {
          TermKeyCap({
            kind: 'shift',
            keyWeight: 0,
            emphasize: true,
            active: this.shiftOn || this.capsLock,
            symbolName: this.shiftSymbolName(),
            capHeight: KEY_H,
            capWidth: TAB_MOD_W,
            actions: this.actions
          })
          ForEach(['z', 'x', 'c', 'v'], (ch: string) => {
            TermKeyCap({
              label: this.letterLabel(ch),
              capId: ch,
              kind: 'char',
              capHeight: KEY_H,
              capWidth: TAB_KEY_W,
              hintText: this.letterHint(ch),
              actions: this.actions
            })
          }, (ch: string) => `sl3-${ch}`)
        }
        .padding({ top: 6 })
        Row() {
          TermKeyCap({
            label: this.slotLabel(this.ctrlSlot),
            capId: this.slotCapId(this.ctrlSlot),
            kind: this.slotKind(this.ctrlSlot),
            keyWeight: 0,
            emphasize: true,
            active: this.slotActive(this.ctrlSlot),
            symbolName: this.barSymbolName(this.ctrlSlot),
            hintText: this.letterHint('ctrl'),
            capHeight: KEY_H,
            capWidth: TAB_MOD_W,
            actions: this.actions
          })
          TermKeyCap({
            label: this.slotLabel(this.commaSlot),
            capId: this.slotCapId(this.commaSlot),
            kind: this.slotKind(this.commaSlot),
            keyWeight: 0,
            emphasize: this.slotEmphasize(this.commaSlot, false),
            active: this.slotActive(this.commaSlot),
            symbolName: this.barSymbolName(this.commaSlot),
            hintText: this.letterHint(','),
            capHeight: KEY_H,
            capWidth: TAB_KEY_W,
            actions: this.actions
          })
          TermKeyCap({
            kind: 'space',
            keyWeight: 0,
            symbolName: 'space_1',
            capHeight: KEY_H,
            capWidth: TAB_SPACE_W,
            actions: this.actions
          })
        }
        .padding({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()
        .layoutWeight(1)

      Column() {
        this.LetterRow(['y', 'u', 'i', 'o', 'p'], 'sr1')
        this.LetterRow(['g', 'h', 'j', 'k', 'l'], 'sr2')
        Row() {
          ForEach(['v', 'b', 'n', 'm'], (ch: string) => {
            TermKeyCap({
              label: this.letterLabel(ch),
              capId: ch,
              kind: 'char',
              capHeight: KEY_H,
              capWidth: TAB_KEY_W,
              hintText: this.letterHint(ch),
              actions: this.actions
            })
          }, (ch: string) => `sr3-${ch}`)
          TermKeyCap({
            kind: 'backspace',
            keyWeight: 0,
            emphasize: true,
            symbolName: 'delete_left',
            capHeight: KEY_H,
            capWidth: TAB_MOD_W,
            actions: this.actions
          })
        }
        .padding({ top: 6 })
        Row() {
          TermKeyCap({
            kind: 'space',
            keyWeight: 0,
            symbolName: 'space_1',
            capHeight: KEY_H,
            capWidth: TAB_SPACE_W,
            actions: this.actions
          })
          TermKeyCap({
            label: this.slotLabel(this.dotSlot),
            capId: this.slotCapId(this.dotSlot),
            kind: this.slotKind(this.dotSlot),
            keyWeight: 0,
            emphasize: this.slotEmphasize(this.dotSlot, false),
            active: this.slotActive(this.dotSlot),
            symbolName: this.barSymbolName(this.dotSlot),
            hintText: this.letterHint('.'),
            capHeight: KEY_H,
            capWidth: TAB_KEY_W,
            actions: this.actions
          })
          TermKeyCap({
            kind: 'enter',
            keyWeight: 0,
            emphasize: true,
            symbolName: 'checkmark',
            capHeight: KEY_H,
            capWidth: TAB_MOD_W,
            actions: this.actions
          })
        }
        .padding({ top: 6 })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: TAB_KEY_INSET, right: TAB_KEY_INSET, top: 4, bottom: 10 })
  }

  build() {
    Column() {
      Row() {
        List({ space: 6 }) {
          ForEach(this.barKeys, (key: KeyboardBarKey) => {
            ListItem() {
              TermKeyCap({
                label: key.label,
                capId: key.id,
                kind: 'bar',
                keyWeight: 0,
                emphasize: true,
                active: this.barActive(key),
                symbolName: this.barSymbolName(key),
                capHeight: BAR_KEY_H,
                capWidth: BAR_KEY_W,
                actions: this.actions
              })
            }
            .width(BAR_KEY_W)
            .height(BAR_H)
          }, (key: KeyboardBarKey) => key.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(20) })
        .layoutWeight(1)
        .height(BAR_H)
        .width('100%')
        .alignListItem(ListItemAlign.Center)

        TermKeyCap({
          kind: 'fold',
          keyWeight: 0,
          symbolName: this.foldSymbolName(),
          capHeight: BAR_H,
          capWidth: BAR_H,
          actions: this.actions
        })
      }
      .width('100%')
      .height(BAR_H)
      .padding({ left: this.keyInset(), right: this.keyInset() })
      .alignItems(VerticalAlign.Center)

      Column() {
        if (this.keysVisible) {
          if (this.splitKeys) {
            this.SplitKeys()
          } else {
            this.PhoneKeys()
          }
        }
      }
      .width('100%')
      .height(this.keysPanelH)
      .clip(false)
    }
    .width('100%')
    .clip(false)
    .focusable(false)
    .backgroundColor(KBD_BG)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      if (w !== this.viewWidth) {
        this.viewWidth = w;
        this.refreshSplitKeys();
      }
    })
  }
}
